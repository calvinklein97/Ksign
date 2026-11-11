//
//  BrowserView.swift
//  Ksign
//
//  Part of the in-app browser module.
//  Full-screen browser with floating glass bars. Downloads go to the Library.
//

import SwiftUI
import WebKit
import NimbleExtensions

// MARK: - Glass
extension View {
	/// Liquid Glass on iOS 26, a blurred material on older versions
	@ViewBuilder
	func browserGlass<S: Shape>(in shape: S) -> some View {
		if #available(iOS 26.0, *) {
			self.glassEffect(.regular.interactive(), in: shape)
		} else {
			self.background(.ultraThinMaterial, in: shape)
				.overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
		}
	}
}

// MARK: - BrowserWebView
struct BrowserWebView: UIViewRepresentable {
	let model: BrowserModel
	var topInset: CGFloat
	var bottomInset: CGFloat

	func makeUIView(context: Context) -> WKWebView {
		model.webView
	}

	func updateUIView(_ uiView: WKWebView, context: Context) {
		model.applyInsets(top: topInset, bottom: bottomInset)
	}
}

// MARK: - BrowserView
struct BrowserView: View {
	@ObservedObject private var _model = BrowserModel.shared

	@State private var _input = ""
	@State private var _isBookmarksPresenting = false
	@FocusState private var _isEditing: Bool

	/// Height reserved for the floating bars
	private let _topBarHeight: CGFloat = 62
	private let _bottomBarHeight: CGFloat = 64

	private var _isCompact: Bool {
		_model.isCollapsed && !_isEditing && _model.url != nil
	}

	private var _host: String {
		(_model.url?.host ?? "").replacingOccurrences(of: "www.", with: "")
	}

	// MARK: Body
	var body: some View {
		GeometryReader { proxy in
			ZStack {
				// Page across the whole screen
				if _model.url == nil {
					Color(uiColor: .systemBackground)
						.ignoresSafeArea()
					BrowserBookmarksList { bookmark in
						_model.load(bookmark.url.absoluteString)
					}
					.padding(.top, _topBarHeight)
					.padding(.bottom, _bottomBarHeight)
				} else {
					BrowserWebView(
						model: _model,
						topInset: proxy.safeAreaInsets.top + _topBarHeight,
						bottomInset: proxy.safeAreaInsets.bottom + _bottomBarHeight
					)
					.ignoresSafeArea()
				}

				// Floating bars
				VStack(spacing: 0) {
					_addressBar

					Spacer(minLength: 0)

					if let banner = _model.banner {
						Text(banner)
							.font(.subheadline)
							.padding(.horizontal, 16)
							.padding(.vertical, 10)
							.browserGlass(in: Capsule())
							.padding(.bottom, 8)
							.transition(.move(edge: .bottom).combined(with: .opacity))
					}

					if !_isEditing {
						_bottomBar
					}
				}
				.animation(.spring(response: 0.35, dampingFraction: 0.85), value: _model.banner)
			}
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
	@ViewBuilder
	private var _addressBar: some View {
		Group {
			if _isCompact {
				Button {
					_model.expandBar()
				} label: {
					Text(_host)
						.font(.footnote.weight(.medium))
						.foregroundStyle(.primary)
						.lineLimit(1)
						.padding(.horizontal, 16)
						.padding(.vertical, 7)
				}
				.buttonStyle(.plain)
				.browserGlass(in: Capsule())
				.padding(.top, 6)
				.transition(.scale(scale: 0.9).combined(with: .opacity))
			} else {
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
					} else if _model.url != nil {
						Button {
							if _model.isLoading { _model.stop() } else { _model.reload() }
						} label: {
							Image(systemName: _model.isLoading ? "xmark" : "arrow.clockwise")
								.foregroundStyle(.secondary)
						}
						.buttonStyle(.borderless)
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
				.browserGlass(in: Capsule())
				.padding(.horizontal, 16)
				.padding(.top, 6)
				.transition(.scale(scale: 0.95).combined(with: .opacity))
			}
		}
		.frame(maxWidth: .infinity)
		.animation(.spring(response: 0.35, dampingFraction: 0.85), value: _isCompact)
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
				Image(systemName: "ellipsis")
			}
		}
		.font(.title3)
		.foregroundStyle(.primary)
		.padding(.horizontal, 28)
		.padding(.vertical, 14)
		.browserGlass(in: Capsule())
		.padding(.horizontal, 24)
		.padding(.bottom, 8)
	}
}
