//
//  BrowserModel.swift
//  Ksign
//
//  Part of the in-app browser module.
//  Owns the WKWebView (Safari's WebKit engine), tracks its state and hands
//  IPA downloads over to the DownloadManager so they show up in the Library.
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
	/// Short message at the bottom, e.g. "Download started"
	@Published private(set) var banner: String?
	@Published var desktopMode = false

	private var _observers: [NSKeyValueObservation] = []
	private var _bannerWork: DispatchWorkItem?

	private override init() {
		let configuration = WKWebViewConfiguration()
		configuration.allowsInlineMediaPlayback = true
		webView = WKWebView(frame: .zero, configuration: configuration)
		super.init()

		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.allowsBackForwardNavigationGestures = true

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
			}
		]
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

	// MARK: IPA download
	private static func _isIPA(_ url: URL) -> Bool {
		["ipa", "tipa"].contains(url.pathExtension.lowercased())
	}

	private static func _isIPAName(_ name: String) -> Bool {
		let lower = name.lowercased()
		return lower.hasSuffix(".ipa") || lower.hasSuffix(".tipa")
	}

	/// Starts the download through the app's download manager, so it shows up
	/// under "Downloads in progress" in the Library like every other download.
	private func _startIPADownload(_ url: URL) {
		// Hand over the browser's cookies so hosts that check a session keep working
		webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
			cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
			DispatchQueue.main.async {
				_ = DownloadManager.shared.startDownload(
					from: url,
					id: "FeatherManualDownload_\(UUID().uuidString)"
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
		if let url = navigationAction.request.url, Self._isIPA(url) {
			decisionHandler(.cancel, preferences)
			_startIPADownload(url)
			return
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

		let suggested = navigationResponse.response.suggestedFilename ?? ""
		if Self._isIPA(url) || Self._isIPAName(suggested) {
			decisionHandler(.cancel)
			_startIPADownload(url)
			return
		}

		// Any other file would be a download; only IPAs are supported
		let disposition = (navigationResponse.response as? HTTPURLResponse)?
			.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
		if disposition.contains("attachment") || !navigationResponse.canShowMIMEType {
			decisionHandler(.cancel)
			showBanner(String.localized("Only IPA files can be downloaded."))
			return
		}

		decisionHandler(.allow)
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
