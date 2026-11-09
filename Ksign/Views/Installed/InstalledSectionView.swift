//
//  InstalledSectionView.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//  Content of the "Installed Apps" tab in the Library.
//

import SwiftUI
import NimbleExtensions
import NimbleViews

// MARK: - InstalledSectionView
struct InstalledSectionView: View {
	@ObservedObject private var _store = InstalledStore.shared

	var searchText: String

	private var _filteredApps: [InstalledApp] {
		guard !searchText.isEmpty else { return _store.apps }
		return _store.apps.filter {
			$0.displayName.localizedCaseInsensitiveContains(searchText) ||
			$0.installedBundleID.localizedCaseInsensitiveContains(searchText)
		}
	}

	// MARK: Body
	var body: some View {
		NBSection(
			.localized("Installed Apps"),
			secondary: _filteredApps.count.description
		) {
			if _filteredApps.isEmpty {
				Text(.localized("Apps you install with Ksign will appear here."))
					.font(.subheadline)
					.foregroundStyle(.secondary)
			} else {
				ForEach(_filteredApps) { app in
					InstalledCellView(app: app)
						.swipeActions(edge: .trailing, allowsFullSwipe: true) {
							Button(role: .destructive) {
								withAnimation {
									_store.remove(app.id)
								}
							} label: {
								Label(.localized("Delete"), systemImage: "trash")
							}
						}
				}
			}
		}
	}
}

// MARK: - InstalledCellView
struct InstalledCellView: View {
	var app: InstalledApp

	private var _origin: String {
		app.provenance?.repoName ?? .localized("Manually imported")
	}

	private var _subtitle: String {
		var parts: [String] = []
		if let version = app.version, !version.isEmpty {
			parts.append(version)
		}
		parts.append(_origin)
		parts.append(app.installDate.formatted(date: .abbreviated, time: .omitted))
		return parts.joined(separator: " · ")
	}

	// MARK: Body
	var body: some View {
		FRIconCellView(
			title: app.displayName,
			subtitle: _subtitle,
			iconUrl: app.provenance?.iconURL
		)
	}
}
