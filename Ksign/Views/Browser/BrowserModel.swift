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
	/// Short message at the bottom, e.g. "Download started"
	@Published private(set) var banner: String?
	@Published var desktopMode = false

	private var _observers: [NSKeyValueObservation] = []
	private var _bannerWork: DispatchWorkItem?
	private var _lastOffset: CGFloat = 0

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

		_observers = [
			webView.observe(\.url) { [weak self] view, _ in
				DispatchQueue.main.async { self?.url = view.url }
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
			webView.scrollView.observe(\.contentOffset) { [weak self] scrollView, _ in
				self?._scrolled(scrollView)
			}
		]
	}

	// MARK: Layout
	/// The page is drawn across the whole screen; the insets keep its content
	/// clear of the floating bars when it is not scrolled.
	func applyInsets(top: CGFloat, bottom: CGFloat) {
		let scrollView = webView.scrollView
		let old = scrollView.contentInset
		guard old.top != top || old.bottom != bottom else { return }

		let wasAtTop = scrollView.contentOffset.y <= -old.top + 2
		scrollView.contentInset = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
		scrollView.verticalScrollIndicatorInsets = scrollView.contentInset
		if wasAtTop {
			scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: -top)
		}
	}

	private func _scrolled(_ scrollView: UIScrollView) {
		let offset = scrollView.contentOffset.y
		defer { _lastOffset = offset }
		// Only react to the user's own scrolling
		guard scrollView.isTracking || scrollView.isDecelerating else { return }

		let delta = offset - _lastOffset
		var collapsed = isCollapsed
		if offset <= -scrollView.contentInset.top + 8 {
			collapsed = false
		} else if delta > 4 {
			collapsed = true
		} else if delta < -4 {
			collapsed = false
		}

		if collapsed != isCollapsed {
			DispatchQueue.main.async { self.isCollapsed = collapsed }
		}
	}

	func expandBar() {
		isCollapsed = false
	}

	// MARK: Actions
	func load(_ input: String) {
		let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return }
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
