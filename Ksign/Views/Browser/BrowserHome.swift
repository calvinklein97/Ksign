//
//  BrowserHome.swift
//  Ksign
//
//  Part of the in-app browser module.
//  Home page: bookmarks and tiles of the recently visited sites.
//

import SwiftUI
import NimbleExtensions

struct BrowserHomeView: View {
	@ObservedObject private var _history = HistoryStore.shared
	@ObservedObject private var _bookmarks = BookmarkStore.shared

	var onOpen: (URL) -> Void

	private let _columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
	private let _bookmarkColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 24) {
				if !_bookmarks.bookmarks.isEmpty {
					_section(.localized("Bookmarks")) {
						LazyVGrid(columns: _bookmarkColumns, spacing: 16) {
							ForEach(_bookmarks.bookmarks.prefix(8)) { bookmark in
								Button { onOpen(bookmark.url) } label: {
									VStack(spacing: 6) {
										FaviconView(url: bookmark.url, size: 52)
										Text(bookmark.title)
											.font(.caption2)
											.foregroundStyle(.primary)
											.lineLimit(1)
									}
								}
								.buttonStyle(.plain)
							}
						}
					}
				}

				_section(.localized("Recently visited")) {
					let sites = _history.recentSites(limit: 8)
					if sites.isEmpty {
						Text(.localized("Enter a web address or a search term above. Visited sites show up here."))
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 32)
					} else {
						LazyVGrid(columns: _columns, spacing: 12) {
							ForEach(sites) { entry in
								_tile(entry)
							}
						}
					}
				}
			}
			.padding(16)
		}
	}

	private func _section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(title)
				.font(.title3.weight(.semibold))
			content()
		}
	}

	private func _tile(_ entry: HistoryEntry) -> some View {
		let host = (entry.url.host ?? "").replacingOccurrences(of: "www.", with: "")
		return Button {
			onOpen(entry.url)
		} label: {
			VStack(alignment: .leading, spacing: 8) {
				FaviconView(url: entry.url, size: 36)

				Text(entry.title)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.primary)
					.lineLimit(2)
					.multilineTextAlignment(.leading)

				if let summary = _history.summary(for: entry) {
					Text(summary)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(3)
						.multilineTextAlignment(.leading)
				}

				Spacer(minLength: 0)

				Text(host)
					.font(.caption2)
					.foregroundStyle(.tertiary)
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
			.padding(14)
			.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
			.contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
		}
		.buttonStyle(.plain)
		.contextMenu {
			Button(role: .destructive) {
				_history.removeSite(host: entry.url.host ?? "")
			} label: {
				Label(.localized("Remove from History"), systemImage: "trash")
			}
		}
	}
}
