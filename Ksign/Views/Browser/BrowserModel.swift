//
//  BrowserModel.swift
//  Ksign
//
//  Part of the in-app browser module.
//  Owns the WKWebView (Safari's WebKit engine), tracks its state and hands
//  downloads over to the Library: IPAs are imported, other files end up in
//  the "Downloads" folder of the app files.
//

import SwiftUI
import WebKit

// MARK: - BrowserModel
final class BrowserModel: NSObject, ObservableObject {
	/// Shared so the page survives switching tabs
	static let shared = BrowserModel()

	let webView: WKWebView

	@Published private(set) var url: URL?
	@Published private(set) var title: String = ""
	@Published private(set) var canGoBack = false
	@Published private(set) var canGoForward = false
	@Published private(set) var isLoading = false
	@Published private(set) var progress: Double = 0
	/// True while the page is scrolled down: the address bar shrinks
	@Published private(set) var isCollapsed = false
	/// True while the home page is shown instead of the loaded page
	@Published private(set) var showHome = false
	/// Background colour of the current page, drawn behind the bars
	@Published private(set) var pageColor: UIColor?
	/// Short message at the bottom, e.g. "Download started"
	@Published private(set) var banner: String?
	@Published var desktopMode = false
	/// Blocks well-known ad and tracking servers (on by default)
	@Published var adBlockEnabled: Bool = (UserDefaults.standard.object(forKey: "ksign.browser.adblock") as? Bool) ?? true {
		didSet {
			UserDefaults.standard.set(adBlockEnabled, forKey: "ksign.browser.adblock")
			_applyAdBlock(reload: true)
		}
	}

	private var _observers: [NSKeyValueObservation] = []
	private var _bannerWork: DispatchWorkItem?
	private var _lastOffset: CGFloat = 0
	/// Scrolled distance in one direction, so tiny movements do not toggle the bar
	private var _scrollTravel: CGFloat = 0
	/// Resizing the page moves the scroll offset; ignore that for a moment
	private var _ignoreScrollUntil = Date.distantPast
	private var _ruleList: WKContentRuleList?

	/// Downloads that WebKit handles itself (for example from blob: addresses)
	private struct WebKitDownloadInfo {
		var row: Download
		var file: URL
		var observation: NSKeyValueObservation?
	}
	private var _webKitDownloads: [ObjectIdentifier: WebKitDownloadInfo] = [:]

	private override init() {
		let configuration = WKWebViewConfiguration()
		configuration.allowsInlineMediaPlayback = true
		webView = WKWebView(frame: .zero, configuration: configuration)
		super.init()

		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.allowsBackForwardNavigationGestures = true
		webView.scrollView.contentInsetAdjustmentBehavior = .never

		_applyAdBlock(reload: false)

		_observers = [
			webView.observe(\.url) { [weak self] view, _ in
				DispatchQueue.main.async {
					self?.url = view.url
					self?.showHome = false
				}
			},
			webView.observe(\.title) { [weak self] view, _ in
				DispatchQueue.main.async { self?.title = view.title ?? "" }
			},
			webView.observe(\.canGoBack) { [weak self] view, _ in
				DispatchQueue.main.async { self?.canGoBack = view.canGoBack }
			},
			webView.observe(\.canGoForward) { [weak self] view, _ in
				DispatchQueue.main.async { self?.canGoForward = view.canGoForward }
			},
			webView.observe(\.isLoading) { [weak self] view, _ in
				DispatchQueue.main.async { self?.isLoading = view.isLoading }
			},
			webView.observe(\.estimatedProgress) { [weak self] view, _ in
				DispatchQueue.main.async { self?.progress = view.estimatedProgress }
			},
			webView.observe(\.underPageBackgroundColor) { [weak self] view, _ in
				DispatchQueue.main.async { self?.pageColor = view.underPageBackgroundColor }
			},
			webView.scrollView.observe(\.contentOffset) { [weak self] scrollView, _ in
				self?._scrolled(scrollView)
			}
		]
	}

	private func _scrolled(_ scrollView: UIScrollView) {
		let offset = scrollView.contentOffset.y
		defer { _lastOffset = offset }
		guard Date() >= _ignoreScrollUntil else {
			_scrollTravel = 0
			return
		}
		// Only react to the user's own scrolling
		guard scrollView.isTracking || scrollView.isDecelerating else { return }

		let delta = offset - _lastOffset
		// A change of direction starts a new count
		if (delta > 0) != (_scrollTravel > 0) { _scrollTravel = 0 }
		_scrollTravel += delta

		var collapsed = isCollapsed
		if offset <= -scrollView.adjustedContentInset.top + 8 {
			collapsed = false
		} else if _scrollTravel > 28 {
			collapsed = true
		} else if _scrollTravel < -28 {
			collapsed = false
		}

		if collapsed != isCollapsed {
			_ignoreScrollUntil = Date().addingTimeInterval(0.6)
			_scrollTravel = 0
			DispatchQueue.main.async { self.isCollapsed = collapsed }
		}
	}

	func goHome() {
		isCollapsed = false
		showHome = true
	}

	func expandBar() {
		isCollapsed = false
	}

	// MARK: Actions
	func load(_ input: String) {
		let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return }
		showHome = false
		webView.load(URLRequest(url: Self.url(from: text)))
	}

	func goBack() { webView.goBack() }
	func goForward() { webView.goForward() }
	func reload() { webView.reload() }
	func stop() { webView.stopLoading() }

	func clearBrowsingData() {
		WKWebsiteDataStore.default().removeData(
			ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
			modifiedSince: .distantPast
		) { }
		showBanner(String.localized("Browsing data cleared"))
	}

	/// Address field input: a web address is opened, anything else is searched.
	static func url(from text: String) -> URL {
		if
			let url = URL(string: text),
			let scheme = url.scheme?.lowercased(),
			["http", "https"].contains(scheme),
			url.host != nil
		{
			return url
		}
		if !text.contains(" "), text.contains("."), let url = URL(string: "https://\(text)"), url.host != nil {
			return url
		}
		var allowed = CharacterSet.urlQueryAllowed
		allowed.remove(charactersIn: "&+=#")
		let query = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
		return URL(string: "https://www.google.com/search?q=\(query)")!
	}

	// MARK: Banner
	func showBanner(_ text: String) {
		DispatchQueue.main.async {
			self._bannerWork?.cancel()
			self.banner = text
			let work = DispatchWorkItem { [weak self] in self?.banner = nil }
			self._bannerWork = work
			DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
		}
	}

	// MARK: Ad blocker
	private static let _adBlockDomains = [
		"doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
		"adnxs.com", "taboola.com", "outbrain.com", "criteo.com", "criteo.net", "pubmatic.com",
		"rubiconproject.com", "openx.net", "amazon-adsystem.com", "moatads.com", "adsrvr.org",
		"advertising.com", "casalemedia.com", "smartadserver.com", "adform.net", "teads.tv",
		"zedo.com", "popads.net", "popcash.net", "propellerads.com", "exoclick.com",
		"juicyads.com", "trafficjunky.net", "mgid.com", "revcontent.com", "yieldmo.com",
		"33across.com", "sharethrough.com", "bidswitch.net", "contextweb.com", "lijit.com",
		"scorecardresearch.com", "quantserve.com"
	]

	private static let _adBlockRules: String = {
		var rules: [[String: Any]] = _adBlockDomains.map { domain -> [String: Any] in
			[
				"trigger": [
					"url-filter": domain.replacingOccurrences(of: ".", with: "\\."),
					"load-type": ["third-party"]
				],
				"action": ["type": "block"]
			]
		}
		// Empty ad containers disappear too
		rules.append([
			"trigger": ["url-filter": ".*"],
			"action": [
				"type": "css-display-none",
				"selector": ".adsbygoogle, ins.adsbygoogle, [id^='google_ads_iframe'], [id^='div-gpt-ad'], .ad-slot, .ad-container, .advertisement, .banner-ad, [data-ad-slot]"
			]
		])
		let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
		return String(data: data, encoding: .utf8) ?? "[]"
	}()

	private func _applyAdBlock(reload: Bool) {
		let controller = webView.configuration.userContentController
		if let list = _ruleList {
			controller.remove(list)
			_ruleList = nil
		}

		guard adBlockEnabled else {
			if reload { webView.reload() }
			return
		}

		WKContentRuleListStore.default().compileContentRuleList(
			forIdentifier: "ksign.adblock.v1",
			encodedContentRuleList: Self._adBlockRules
		) { [weak self] list, _ in
			DispatchQueue.main.async {
				guard let self, self.adBlockEnabled, let list else { return }
				self.webView.configuration.userContentController.add(list)
				self._ruleList = list
				if reload { self.webView.reload() }
			}
		}
	}

	// MARK: Downloads
	private static func _isWebAddress(_ url: URL) -> Bool {
		["http", "https"].contains(url.scheme?.lowercased() ?? "")
	}

	private static func _isIPAName(_ name: String) -> Bool {
		let lower = name.lowercased()
		return lower.hasSuffix(".ipa") || lower.hasSuffix(".tipa")
	}

	/// Starts the download through the app's download manager, so it shows up
	/// under "Downloads in progress" in the Library like every other download.
	private func _startDownload(_ url: URL) {
		// Hand over the browser's cookies so hosts that check a session keep working
		webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
			cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
			DispatchQueue.main.async {
				_ = DownloadManager.shared.startDownload(
					from: url,
					id: "\(BrowserFileSaver.idPrefix)\(UUID().uuidString)"
				)
				let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
				self.showBanner("\(String.localized("Download started")): \(name)")
			}
		}
	}
}

// MARK: - WKNavigationDelegate
extension BrowserModel: WKNavigationDelegate {
	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard let url = webView.url else { return }
		let title = webView.title ?? ""
		let script = """
		(function () {
			var d = document.querySelector('meta[name="description"],meta[property="og:description"]');
			var links = [].slice.call(document.querySelectorAll('link[rel~="icon"],link[rel="apple-touch-icon"],link[rel="apple-touch-icon-precomposed"]'));
			var apple = links.filter(function (l) { return /apple-touch/.test(l.rel); })[0];
			var plain = links.filter(function (l) { return !/\\.svg(\\?|$)/i.test(l.href); })[0];
			var icon = apple || plain || links[0];
			return { d: d ? d.content : '', i: icon ? icon.href : '' };
		})()
		"""
		webView.evaluateJavaScript(script) { result, _ in
			let info = result as? [String: Any]
			let summary = (info?["d"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
			let icon = (info?["i"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
			HistoryStore.shared.record(url: url, title: title, iconURL: icon, summary: summary)
		}
	}

	func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction,
		preferences: WKWebpagePreferences,
		decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
	) {
		if let url = navigationAction.request.url {
			if BrowserFileSaver.isIPA(url), Self._isWebAddress(url) {
				decisionHandler(.cancel, preferences)
				_startDownload(url)
				return
			}
			// Links with a download attribute, blob: addresses and similar
			if navigationAction.shouldPerformDownload {
				if Self._isWebAddress(url) {
					decisionHandler(.cancel, preferences)
					_startDownload(url)
				} else {
					decisionHandler(.download, preferences)
				}
				return
			}
		}
		preferences.preferredContentMode = desktopMode ? .desktop : .mobile
		decisionHandler(.allow, preferences)
	}

	func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationResponse: WKNavigationResponse,
		decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
	) {
		guard navigationResponse.isForMainFrame, let url = navigationResponse.response.url else {
			decisionHandler(.allow)
			return
		}

		let disposition = (navigationResponse.response as? HTTPURLResponse)?
			.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
		let suggested = navigationResponse.response.suggestedFilename ?? ""

		let isFile = BrowserFileSaver.isIPA(url)
			|| Self._isIPAName(suggested)
			|| disposition.contains("attachment")
			|| !navigationResponse.canShowMIMEType

		guard isFile else {
			decisionHandler(.allow)
			return
		}

		if Self._isWebAddress(url) {
			decisionHandler(.cancel)
			_startDownload(url)
		} else {
			decisionHandler(.download)
		}
	}

	func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
		download.delegate = self
	}

	func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
		download.delegate = self
	}
}

// MARK: - WKDownloadDelegate
extension BrowserModel: WKDownloadDelegate {
	func download(
		_ download: WKDownload,
		decideDestinationUsing response: URLResponse,
		suggestedFilename: String,
		completionHandler: @escaping (URL?) -> Void
	) {
		let folder = FileManager.default.temporaryDirectory
			.appendingPathComponent("BrowserDownloads", isDirectory: true)
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let file = folder.appendingPathComponent(suggestedFilename)

		// A row in "Downloads in progress" that follows WebKit's progress
		let row = DownloadManager.shared.startArchive(
			from: file,
			id: "\(BrowserFileSaver.idPrefix)\(UUID().uuidString)"
		)
		let observation = download.progress.observe(\.fractionCompleted) { [weak self, weak download] progress, _ in
			DispatchQueue.main.async {
				row.progress = progress.fractionCompleted
				row.unpackageProgress = progress.fractionCompleted
				// The row was cancelled in the Library
				if DownloadManager.shared.getDownload(by: row.id) == nil, let download {
					download.cancel { _ in }
					self?._webKitDownloads[ObjectIdentifier(download)] = nil
				}
			}
		}
		_webKitDownloads[ObjectIdentifier(download)] = WebKitDownloadInfo(
			row: row,
			file: file,
			observation: observation
		)
		completionHandler(file)
	}

	func downloadDidFinish(_ download: WKDownload) {
		guard let info = _webKitDownloads.removeValue(forKey: ObjectIdentifier(download)) else { return }

		if BrowserFileSaver.isIPA(info.file) {
			info.row.unpackageProgress = 0
			DownloadManager.shared.handlePachageFile(url: info.file, dl: info.row) { _ in }
		} else {
			BrowserFileSaver.save(info.file)
			DownloadManager.shared.cancelDownload(info.row)
			showBanner(String.localized("Saved to the Downloads folder"))
		}
	}

	func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
		if let info = _webKitDownloads.removeValue(forKey: ObjectIdentifier(download)) {
			DownloadManager.shared.cancelDownload(info.row)
			try? FileManager.default.removeItem(at: info.file)
		}
		showBanner(String.localized("Download failed"))
	}
}

// MARK: - WKUIDelegate
extension BrowserModel: WKUIDelegate {
	/// Links that want a new window open in the same view
	func webView(
		_ webView: WKWebView,
		createWebViewWith configuration: WKWebViewConfiguration,
		for navigationAction: WKNavigationAction,
		windowFeatures: WKWindowFeatures
	) -> WKWebView? {
		if navigationAction.targetFrame == nil {
			webView.load(navigationAction.request)
		}
		return nil
	}
}
