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

	/// Upload date of the installed build as declared by its repo
	private var _uploadDate: String? {
		app.provenance?.uploadDate?.formatted(date: .abbreviated, time: .omitted)
	}

	/// Name of the build in its repo, only shown when it differs from the installed name
	private var _repoBuildName: String? {
		guard let repoName = app.provenance?.appName, repoName != app.name else { return nil }
		return repoName
	}

	private var _subtitle: String {
		var lines: [String] = [app.installedBundleID]

		var origin = [_origin]
		if app.isFromRepo {
			origin.append(_uploadDate ?? .localized("Upload date unknown"))
		}
		lines.append(origin.joined(separator: " · "))

		if let repoBuildName = _repoBuildName {
			let label: String = .localized("Repo build")
			lines.append("\(label): \(repoBuildName)")
		}
		return lines.joined(separator: "\n")
	}

	// MARK: Body
	var body: some View {
		FRIconCellView(
			title: app.name,
			subtitle: _subtitle,
			iconUrl: app.provenance?.iconURL,
			trailing: _versionLabel
		)
	}

	private var _versionLabel: AnyView? {
		guard let version = app.version, !version.isEmpty else { return nil }
		return AnyView(
			Text(version)
				.font(.subheadline)
				.foregroundStyle(.secondary)
		)
	}
}
