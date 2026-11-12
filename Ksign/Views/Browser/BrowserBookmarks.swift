//
//  BrowserBookmarks.swift
//  Ksign
//
//  Part of the in-app browser module.
//  Bookmarks of the browser, stored in UserDefaults.
//

import SwiftUI

// MARK: - Bookmark
struct Bookmark: Codable, Identifiable, Equatable {
	var id = UUID()
	var title: String
	var url: URL
}

// MARK: - BookmarkStore
final class BookmarkStore: ObservableObject {
	static let shared = BookmarkStore()

	static let defaultsKey = "ksign.browser.bookmarks"

	@Published private(set) var bookmarks: [Bookmark] = []

	private init() {
		reload()
	}

	/// Reads the saved list again, e.g. after a backup was imported
	func reload() {
		if
			let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
			let saved = try? JSONDecoder().decode([Bookmark].self, from: data)
		{
			bookmarks = saved
		} else {
			bookmarks = []
		}
	}

	func add(title: String, url: URL) {
		guard !bookmarks.contains(where: { $0.url == url }) else { return }
		bookmarks.append(Bookmark(title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url))
		_save()
	}

	func remove(at offsets: IndexSet) {
		bookmarks.remove(atOffsets: offsets)
		_save()
	}

	private func _save() {
		if let data = try? JSONEncoder().encode(bookmarks) {
			UserDefaults.standard.set(data, forKey: Self.defaultsKey)
		}
	}
}

// MARK: - BrowserBookmarksList
struct BrowserBookmarksList: View {
	@ObservedObject private var _store = BookmarkStore.shared

	var onSelect: (Bookmark) -> Void

	var body: some View {
		List {
			ForEach(_store.bookmarks) { bookmark in
				Button {
					onSelect(bookmark)
				} label: {
					HStack(spacing: 12) {
						FaviconView(url: bookmark.url)
						VStack(alignment: .leading, spacing: 2) {
							Text(bookmark.title)
								.foregroundStyle(.primary)
								.lineLimit(1)
							Text(bookmark.url.absoluteString)
								.font(.caption)
								.foregroundStyle(.secondary)
								.lineLimit(1)
								.truncationMode(.middle)
						}
					}
				}
				.buttonStyle(.plain)
				.listRowBackground(Color.clear)
			}
			.onDelete { offsets in
				_store.remove(at: offsets)
			}
		}
		.listStyle(.plain)
		.scrollContentBackground(.hidden)
		.overlay {
			if _store.bookmarks.isEmpty {
				Text(.localized("No bookmarks yet. Add them from the menu."))
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.padding(32)
			}
		}
	}
}
