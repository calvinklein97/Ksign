//
//  BrowserView.swift
//  Ksign
//
//  Part of the in-app browser module.
//  A small browser tab. IPA links are downloaded into the Library.
//

import SwiftUI
import WebKit
import NimbleExtensions

// MARK: - BrowserWebView
struct BrowserWebView: UIViewRepresentable {
	let webView: WKWebView

	func makeUIView(context: Context) -> WKWebView { webView }
	func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - BrowserView
struct BrowserView: View {
	@ObservedObject private var _model = BrowserModel.shared

	@State private var _input = ""
	@State private var _isBookmarksPresenting = false
	@FocusState private var _isEditing: Bool

	// MARK: Body
	var body: some View {
		VStack(spacing: 0) {
			_addressBar

			ProgressView(value: _model.progress)
				.progressViewStyle(.linear)
				.opacity(_model.isLoading ? 1 : 0)

			ZStack {
				if _model.url == nil {
					BrowserBookmarksList { bookmark in
						_model.load(bookmark.url.absoluteString)
					}
				} else {
					BrowserWebView(webView: _model.webView)
				}
			}
			.overlay(alignment: .bottom) {
				if let banner = _model.banner {
					Text(banner)
						.font(.subheadline)
						.padding(.horizontal, 16)
						.padding(.vertical, 10)
						.background(.regularMaterial)
						.clipShape(Capsule())
						.padding(.bottom, 12)
						.transition(.move(edge: .bottom).combined(with: .opacity))
				}
			}
			.animation(.easeInOut, value: _model.banner)

			Divider()
			_bottomBar
		}
		.onReceive(_model.$url) { url in
			if !_isEditing {
				_input = url?.absoluteString ?? ""
			}
		}
		.onChange(of: _model.desktopMode) { _ in
			_model.reload()
		}
		.sheet(isPresented: $_isBookmarksPresenting) {
			NavigationStack {
				BrowserBookmarksList { bookmark in
					_isBookmarksPresenting = false
					_model.load(bookmark.url.absoluteString)
				}
				.navigationTitle(.localized("Bookmarks"))
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .topBarTrailing) {
						Button(.localized("Done")) {
							_isBookmarksPresenting = false
						}
					}
				}
			}
			.presentationDetents([.medium, .large])
		}
	}

	// MARK: Address bar
	private var _addressBar: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.foregroundStyle(.secondary)

			TextField(.localized("Search or enter website"), text: $_input)
				.focused($_isEditing)
				.keyboardType(.webSearch)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.submitLabel(.go)
				.onSubmit {
					_isEditing = false
					_model.load(_input)
				}

			if _isEditing, !_input.isEmpty {
				Button {
					_input = ""
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.borderless)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(Color(uiColor: .secondarySystemBackground))
		.clipShape(Capsule())
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
	}

	// MARK: Bottom bar
	private var _bottomBar: some View {
		HStack {
			Button { _model.goBack() } label: {
				Image(systemName: "chevron.left")
			}
			.disabled(!_model.canGoBack)

			Spacer()

			Button { _model.goForward() } label: {
				Image(systemName: "chevron.right")
			}
			.disabled(!_model.canGoForward)

			Spacer()

			Button {
				if _model.isLoading { _model.stop() } else { _model.reload() }
			} label: {
				Image(systemName: _model.isLoading ? "xmark" : "arrow.clockwise")
			}
			.disabled(_model.url == nil)

			Spacer()

			Button { _isBookmarksPresenting = true } label: {
				Image(systemName: "book")
			}

			Spacer()

			Menu {
				Button {
					if let url = _model.url {
						BookmarkStore.shared.add(title: _model.title, url: url)
						_model.showBanner(String.localized("Bookmark added"))
					}
				} label: {
					Label(.localized("Add Bookmark"), systemImage: "star")
				}
				.disabled(_model.url == nil)

				Button {
					if let url = _model.url {
						UIActivityViewController.show(activityItems: [url])
					}
				} label: {
					Label(.localized("Share"), systemImage: "square.and.arrow.up")
				}
				.disabled(_model.url == nil)

				Button {
					if let url = _model.url {
						UIApplication.shared.open(url)
					}
				} label: {
					Label(.localized("Open in Safari"), systemImage: "safari")
				}
				.disabled(_model.url == nil)

				Toggle(isOn: $_model.desktopMode) {
					Label(.localized("Request Desktop Site"), systemImage: "desktopcomputer")
				}

				Divider()

				Button(role: .destructive) {
					_model.clearBrowsingData()
				} label: {
					Label(.localized("Clear Browsing Data"), systemImage: "trash")
				}
			} label: {
				Image(systemName: "ellipsis.circle")
			}
		}
		.font(.title3)
		.padding(.horizontal, 24)
		.padding(.vertical, 10)
	}
}
