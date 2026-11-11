//
//  BrowserHistory.swift
//  Ksign
//
//  Part of the in-app browser module.
//  Browsing history and the address suggestions built from it.
//

import SwiftUI

// MARK: - HistoryEntry
struct HistoryEntry: Codable, Identifiable, Equatable {
	var url: URL
	var title: String
	var lastVisited: Date
	var visitCount: Int

	var id: String { url.absoluteString }
}

/// One row of the suggestion list under the address bar
struct BrowserSuggestion: Identifiable {
	var title: String
	var url: URL
	var id: String { url.absoluteString }
}

// MARK: - HistoryStore
final class HistoryStore: ObservableObject {
	static let shared = HistoryStore()

	private let _key = "ksign.browser.history"
	private let _limit = 500

	/// Newest first
	@Published private(set) var entries: [HistoryEntry] = []

	private init() {
		if
			let data = UserDefaults.standard.data(forKey: _key),
			let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data)
		{
			entries = saved
		}
	}

	func record(url: URL, title: String) {
		guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }

		if let index = entries.firstIndex(where: { $0.url == url }) {
			var entry = entries.remove(at: index)
			entry.lastVisited = Date()
			entry.visitCount += 1
			if !title.isEmpty { entry.title = title }
			entries.insert(entry, at: 0)
		} else {
			entries.insert(
				HistoryEntry(
					url: url,
					title: title.isEmpty ? (url.host ?? url.absoluteString) : title,
					lastVisited: Date(),
					visitCount: 1
				),
				at: 0
			)
			if entries.count > _limit {
				entries.removeLast(entries.count - _limit)
			}
		}
		_save()
	}

	func remove(at offsets: IndexSet) {
		entries.remove(atOffsets: offsets)
		_save()
	}

	func clear() {
		entries = []
		_save()
	}

	private func _save() {
		if let data = try? JSONEncoder().encode(entries) {
			UserDefaults.standard.set(data, forKey: _key)
		}
	}

	// MARK: Suggestions
	/// Matches for what is typed in the address bar. With an empty text, the latest visits.
	func suggestions(for text: String, bookmarks: [Bookmark], limit: Int = 6) -> [BrowserSuggestion] {
		let query = text.trimmingCharacters(in: .whitespaces).lowercased()
		guard !query.isEmpty else {
			return entries.prefix(limit).map { BrowserSuggestion(title: $0.title, url: $0.url) }
		}

		func bare(_ url: URL) -> String {
			var text = url.absoluteString.lowercased()
			for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
				text.removeFirst(prefix.count)
			}
			if text.hasPrefix("www.") { text.removeFirst(4) }
			return text
		}

		struct Candidate {
			var suggestion: BrowserSuggestion
			var score: Int
			var visits: Int
			var date: Date
		}

		var candidates: [String: Candidate] = [:]

		func consider(title: String, url: URL, visits: Int, date: Date) {
			let address = bare(url)
			let score: Int
			if address.hasPrefix(query) {
				score = 0
			} else if address.contains(query) {
				score = 1
			} else if title.lowercased().contains(query) {
				score = 2
			} else {
				return
			}
			let candidate = Candidate(
				suggestion: BrowserSuggestion(title: title, url: url),
				score: score,
				visits: visits,
				date: date
			)
			if let existing = candidates[url.absoluteString], existing.score <= score { return }
			candidates[url.absoluteString] = candidate
		}

		for entry in entries {
			consider(title: entry.title, url: entry.url, visits: entry.visitCount, date: entry.lastVisited)
		}
		for bookmark in bookmarks {
			consider(title: bookmark.title, url: bookmark.url, visits: 0, date: .distantPast)
		}

		return candidates.values
			.sorted {
				if $0.score != $1.score { return $0.score < $1.score }
				if $0.visits != $1.visits { return $0.visits > $1.visits }
				return $0.date > $1.date
			}
			.prefix(limit)
			.map { $0.suggestion }
	}
}

// MARK: - BrowserHistoryList
struct BrowserHistoryList: View {
	@ObservedObject private var _store = HistoryStore.shared

	var onSelect: (HistoryEntry) -> Void

	var body: some View {
		List {
			ForEach(_store.entries) { entry in
				Button {
					onSelect(entry)
				} label: {
					VStack(alignment: .leading, spacing: 2) {
						Text(entry.title)
							.foregroundStyle(.primary)
							.lineLimit(1)
						Text(entry.url.absoluteString)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.truncationMode(.middle)
						Text(entry.lastVisited.formatted(date: .abbreviated, time: .shortened))
							.font(.caption2)
							.foregroundStyle(.tertiary)
					}
				}
			}
			.onDelete { offsets in
				_store.remove(at: offsets)
			}
		}
		.overlay {
			if _store.entries.isEmpty {
				Text(.localized("No history yet."))
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
	}
}
