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
	func browserGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
		if #available(iOS 26.0, *) {
			if interactive {
				self.glassEffect(.regular.interactive(), in: shape)
			} else {
				self.glassEffect(.regular, in: shape)
			}
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
	@State private var _isEditing = false

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
					_addressBar(width: proxy.size.width)

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
	/// One capsule that changes size, so the shrinking is a smooth animation
	private func _addressBar(width: CGFloat) -> some View {
		let compact = _isCompact

		return ZStack {
			HStack(spacing: 8) {
				Image(systemName: "magnifyingglass")
					.foregroundStyle(.secondary)

				BrowserAddressField(
					text: $_input,
					isEditing: $_isEditing,
					placeholder: .localized("Search or enter website"),
					onSubmit: { _model.load(_input) }
				)

				if !_isEditing, _model.url != nil {
					Button {
						if _model.isLoading { _model.stop() } else { _model.reload() }
					} label: {
						Image(systemName: _model.isLoading ? "xmark" : "arrow.clockwise")
							.foregroundStyle(.secondary)
							.frame(width: 32, height: 32)
							.contentShape(Rectangle())
					}
					.buttonStyle(.borderless)
				}
			}
			.padding(.horizontal, 16)
			.opacity(compact ? 0 : 1)
			.allowsHitTesting(!compact)

			Text(_host)
				.font(.footnote.weight(.medium))
				.foregroundStyle(.primary)
				.lineLimit(1)
				.padding(.horizontal, 12)
				.opacity(compact ? 1 : 0)
		}
		.frame(width: compact ? 200 : max(width - 32, 200), height: compact ? 34 : 46)
		.browserGlass(in: Capsule())
		.overlay {
			// Tapping the small bar brings the full one back
			if compact {
				Color.clear
					.contentShape(Capsule())
					.onTapGesture { _model.expandBar() }
			}
		}
		.padding(.top, 6)
		.frame(maxWidth: .infinity)
		.animation(.spring(response: 0.4, dampingFraction: 0.88), value: compact)
	}

	// MARK: Bottom bar
	private func _icon(_ name: String) -> some View {
		Image(systemName: name)
			.frame(width: 44, height: 44)
			.contentShape(Rectangle())
	}

	private var _bottomBar: some View {
		HStack {
			Button { _model.goBack() } label: { _icon("chevron.left") }
				.disabled(!_model.canGoBack)

			Spacer()

			Button { _model.goForward() } label: { _icon("chevron.right") }
				.disabled(!_model.canGoForward)

			Spacer()

			Button { _isBookmarksPresenting = true } label: { _icon("book") }

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

				Divider()

				Toggle(isOn: $_model.adBlockEnabled) {
					Label(.localized("Block Ads"), systemImage: "shield.lefthalf.filled")
				}

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
				_icon("ellipsis")
			}
		}
		.font(.title3)
		.foregroundStyle(.primary)
		.padding(.horizontal, 20)
		.padding(.vertical, 4)
		.browserGlass(in: Capsule())
		.padding(.horizontal, 24)
		.padding(.bottom, 8)
	}
}
