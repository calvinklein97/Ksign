//
//  BrowserHistory.swift
//  Ksign
//
//  Part of the in-app browser module.
//  Browsing history and the address suggestions built from it.
//

import SwiftUI
import NukeUI

// MARK: - HistoryEntry
struct HistoryEntry: Codable, Identifiable, Equatable {
	var url: URL
	var title: String
	var lastVisited: Date
	var visitCount: Int
	/// Favicon and short page description, read from the page itself
	var iconURL: URL?
	var summary: String?

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

	func record(url: URL, title: String, iconURL: URL? = nil, summary: String? = nil) {
		guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }

		if let index = entries.firstIndex(where: { $0.url == url }) {
			var entry = entries.remove(at: index)
			entry.lastVisited = Date()
			entry.visitCount += 1
			if !title.isEmpty { entry.title = title }
			if let iconURL { entry.iconURL = iconURL }
			if let summary, !summary.isEmpty { entry.summary = summary }
			entries.insert(entry, at: 0)
		} else {
			entries.insert(
				HistoryEntry(
					url: url,
					title: title.isEmpty ? (url.host ?? url.absoluteString) : title,
					lastVisited: Date(),
					visitCount: 1,
					iconURL: iconURL,
					summary: (summary?.isEmpty ?? true) ? nil : summary
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

	// MARK: Sites
	/// Latest visit of every host, newest first
	func recentSites(limit: Int) -> [HistoryEntry] {
		var seen = Set<String>()
		var result: [HistoryEntry] = []
		for entry in entries {
			let host = entry.url.host ?? entry.url.absoluteString
			guard seen.insert(host).inserted else { continue }
			result.append(entry)
			if result.count == limit { break }
		}
		return result
	}

	func removeSite(host: String) {
		entries.removeAll { $0.url.host == host }
		_save()
	}

	/// The icon saved for a page, or for any page of the same host
	func favicon(for url: URL) -> URL? {
		if let icon = entries.first(where: { $0.url == url })?.iconURL { return icon }
		if let host = url.host {
			if let icon = entries.first(where: { $0.url.host == host && $0.iconURL != nil })?.iconURL { return icon }
			return URL(string: "\(url.scheme ?? "https")://\(host)/favicon.ico")
		}
		return nil
	}

	func summary(for entry: HistoryEntry) -> String? {
		if let text = entry.summary { return text }
		return entries.first(where: { $0.url.host == entry.url.host && $0.summary != nil })?.summary
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

// MARK: - Favicon
struct FaviconView: View {
	let url: URL
	var size: CGFloat = 32

	@ObservedObject private var _history = HistoryStore.shared

	var body: some View {
		LazyImage(url: _history.favicon(for: url)) { state in
			if let image = state.image {
				image
					.resizable()
					.scaledToFit()
					.padding(size * 0.12)
			} else {
				Text(String((url.host ?? "?").replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
					.font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
					.foregroundStyle(.secondary)
			}
		}
		.frame(width: size, height: size)
		.background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
		.clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
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
					HStack(spacing: 12) {
						FaviconView(url: entry.url)
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
			if _store.entries.isEmpty {
				Text(.localized("No history yet."))
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
	}
}
