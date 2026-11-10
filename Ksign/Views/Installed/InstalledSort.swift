//
//  InstalledSort.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//  Sort options for the Installed tab and the sheet to pick them.
//

import SwiftUI

// MARK: - InstalledSortKey
enum InstalledSortKey: String, CaseIterable, Identifiable {
	case alphabetical
	case installDate
	case updateStatus

	var id: String { rawValue }

	var title: String {
		switch self {
		case .alphabetical: return .localized("Alphabetical")
		case .installDate: return .localized("Installation date")
		case .updateStatus: return .localized("Update status")
		}
	}

	var systemImage: String {
		switch self {
		case .alphabetical: return "textformat"
		case .installDate: return "calendar"
		case .updateStatus: return "arrow.up.circle"
		}
	}

	func directionTitle(ascending: Bool) -> String {
		switch self {
		case .alphabetical:
			return ascending ? .localized("A to Z") : .localized("Z to A")
		case .installDate:
			return ascending ? .localized("Oldest first") : .localized("Newest first")
		case .updateStatus:
			return ascending ? .localized("Updates first") : .localized("Updates last")
		}
	}
}

enum InstalledSortStorage {
	static let keyName = "ksign.installed.sortKey"
	static let ascendingName = "ksign.installed.sortAscending"
}

// MARK: - InstalledSortSheet
struct InstalledSortSheet: View {
	@Environment(\.dismiss) private var dismiss

	@AppStorage(InstalledSortStorage.keyName) private var _keyRaw: String = InstalledSortKey.installDate.rawValue
	@AppStorage(InstalledSortStorage.ascendingName) private var _ascending: Bool = false

	private var _key: InstalledSortKey {
		InstalledSortKey(rawValue: _keyRaw) ?? .installDate
	}

	var body: some View {
		NavigationStack {
			List {
				Section {
					ForEach(InstalledSortKey.allCases) { key in
						Button {
							_keyRaw = key.rawValue
						} label: {
							HStack {
								Label(key.title, systemImage: key.systemImage)
									.foregroundStyle(.primary)
								Spacer()
								if key == _key {
									Image(systemName: "checkmark")
										.foregroundStyle(Color.accentColor)
								}
							}
							.contentShape(Rectangle())
						}
					}
				} header: {
					Text(.localized("Sort by"))
				}

				Section {
					ForEach([true, false], id: \.self) { ascending in
						Button {
							_ascending = ascending
						} label: {
							HStack {
								Text(_key.directionTitle(ascending: ascending))
									.foregroundStyle(.primary)
								Spacer()
								if ascending == _ascending {
									Image(systemName: "checkmark")
										.foregroundStyle(Color.accentColor)
								}
							}
							.contentShape(Rectangle())
						}
					}
				} header: {
					Text(.localized("Order"))
				}
			}
			.navigationTitle(.localized("Sort"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Done")) {
						dismiss()
					}
				}
			}
		}
	}
}

// MARK: - Sorting
extension Array where Element == InstalledApp {
	func sorted(by key: InstalledSortKey, ascending: Bool, hasUpdate: (InstalledApp) -> Bool) -> [InstalledApp] {
		func byName(_ a: InstalledApp, _ b: InstalledApp) -> Bool {
			let result = a.name.localizedCaseInsensitiveCompare(b.name)
			if result == .orderedSame { return a.id < b.id }
			return result == .orderedAscending
		}

		return self.sorted { a, b in
			switch key {
			case .alphabetical:
				return ascending ? byName(a, b) : byName(b, a)
			case .installDate:
				if a.installDate == b.installDate { return byName(a, b) }
				return ascending ? a.installDate < b.installDate : a.installDate > b.installDate
			case .updateStatus:
				let ua = hasUpdate(a), ub = hasUpdate(b)
				if ua == ub { return byName(a, b) }
				// ascending: apps with an update first
				return ascending ? ua : ub
			}
		}
	}
}
