//
//  BrowserView.swift
//  Ksign
//
//  Part of the in-app browser module.
//  Browser with floating glass bars; the page colour runs under them. Downloads go to the Library.
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

	func makeUIView(context: Context) -> WKWebView {
		model.webView
	}

	func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - BrowserView
struct BrowserView: View {
	@ObservedObject private var _model = BrowserModel.shared
	@ObservedObject private var _history = HistoryStore.shared
	@ObservedObject private var _bookmarks = BookmarkStore.shared

	@State private var _input = ""
	@State private var _isSheetPresenting = false
	@State private var _sheetTab = 0
	@State private var _isEditing = false

	private var _isCompact: Bool {
		_model.isCollapsed && !_isEditing && _model.url != nil
	}

	private var _host: String {
		(_model.url?.host ?? "").replacingOccurrences(of: "www.", with: "")
	}

	/// While the whole address is selected, the latest visits are offered
	private var _suggestions: [BrowserSuggestion] {
		let query = (_input == _model.url?.absoluteString) ? "" : _input
		return _history.suggestions(for: query, bookmarks: _bookmarks.bookmarks)
	}

	// MARK: Body
	private static let _cornerRadius: CGFloat = 28
	private static let _bottomBarHeight: CGFloat = 62

	var body: some View {
		let compact = _isCompact
		let topHeight: CGFloat = compact ? 42 : 56
		let bottomHeight: CGFloat = (compact || _isEditing) ? 0 : Self._bottomBarHeight

		ZStack {
			// The page colour continues under the bars, the page itself stays in the safe area
			Color(uiColor: _model.url == nil ? .systemBackground : (_model.pageColor ?? .systemBackground))
				.ignoresSafeArea()

			ZStack {
				if _model.url == nil {
					BrowserBookmarksList { bookmark in
						_model.load(bookmark.url.absoluteString)
					}
				} else {
					BrowserWebView(model: _model)
				}

				if _isEditing {
					_suggestionList
				}
			}
			.clipShape(RoundedRectangle(cornerRadius: Self._cornerRadius, style: .continuous))
			.padding(.top, topHeight)
			.padding(.bottom, bottomHeight)

			VStack(spacing: 0) {
				GeometryReader { geometry in
					_addressBar(width: geometry.size.width)
				}
				.frame(height: topHeight)

				Spacer(minLength: 0)

				_bottomBar
					.offset(y: (compact || _isEditing) ? Self._bottomBarHeight + 20 : 0)
					.opacity((compact || _isEditing) ? 0 : 1)
					.allowsHitTesting(!(compact || _isEditing))
			}
			.overlay(alignment: .bottom) {
				if let banner = _model.banner {
					Text(banner)
						.font(.subheadline)
						.padding(.horizontal, 16)
						.padding(.vertical, 10)
						.browserGlass(in: Capsule())
						.padding(.bottom, bottomHeight + 8)
						.transition(.move(edge: .bottom).combined(with: .opacity))
				}
			}
		}
		.animation(.spring(response: 0.4, dampingFraction: 0.88), value: compact)
		.animation(.spring(response: 0.35, dampingFraction: 0.85), value: _model.banner)
		.onReceive(_model.$url) { url in
			if !_isEditing {
				_input = url?.absoluteString ?? ""
			}
		}
		.onChange(of: _isEditing) { editing in
			// Leaving the field without opening anything restores the current address
			if !editing {
				_input = _model.url?.absoluteString ?? ""
			}
		}
		.onChange(of: _model.desktopMode) { _ in
			_model.reload()
		}
		.sheet(isPresented: $_isSheetPresenting) {
			_bookmarksAndHistorySheet
		}
	}

	// MARK: Suggestions
	private var _suggestionList: some View {
		List {
			ForEach(_suggestions) { suggestion in
				Button {
					_isEditing = false
					_model.load(suggestion.url.absoluteString)
				} label: {
					VStack(alignment: .leading, spacing: 2) {
						Text(suggestion.title)
							.foregroundStyle(.primary)
							.lineLimit(1)
						Text(suggestion.url.absoluteString)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.truncationMode(.middle)
					}
				}
			}
		}
		.listStyle(.plain)
		.background(Color(uiColor: .systemBackground))
		.overlay {
			if _suggestions.isEmpty {
				Text(.localized("No matches in your history."))
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: Bookmarks and history
	private var _bookmarksAndHistorySheet: some View {
		NavigationStack {
			VStack(spacing: 0) {
				Picker("", selection: $_sheetTab) {
					Text(.localized("Bookmarks")).tag(0)
					Text(.localized("History")).tag(1)
				}
				.pickerStyle(.segmented)
				.padding(.horizontal, 16)
				.padding(.vertical, 8)

				if _sheetTab == 0 {
					BrowserBookmarksList { bookmark in
						_isSheetPresenting = false
						_model.load(bookmark.url.absoluteString)
					}
				} else {
					BrowserHistoryList { entry in
						_isSheetPresenting = false
						_model.load(entry.url.absoluteString)
					}
				}
			}
			.navigationTitle(_sheetTab == 0 ? .localized("Bookmarks") : .localized("History"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					if _sheetTab == 1, !_history.entries.isEmpty {
						Button(.localized("Clear"), role: .destructive) {
							_history.clear()
						}
					}
				}
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Done")) {
						_isSheetPresenting = false
					}
				}
			}
		}
		.presentationDetents([.medium, .large])
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
					idleText: _host,
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
		.frame(maxWidth: .infinity, maxHeight: .infinity)
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

			Button { _isSheetPresenting = true } label: { _icon("book") }

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
