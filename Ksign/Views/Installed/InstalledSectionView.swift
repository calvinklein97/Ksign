//
//  InstalledSectionView.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//  Content of the "Installed Apps" tab in the Library.
//

import SwiftUI
import NukeUI
import NimbleExtensions
import NimbleViews

// MARK: - InstalledSectionView
struct InstalledSectionView: View {
	@ObservedObject private var _store = InstalledStore.shared
	@ObservedObject private var _updates = UpdateChecker.shared

	var searchText: String
	/// The app whose details sheet is shown. The sheet itself lives in LibraryView.
	@Binding var selectedApp: InstalledApp?

	private var _filteredApps: [InstalledApp] {
		guard !searchText.isEmpty else { return _store.apps }
		return _store.apps.filter {
			$0.name.localizedCaseInsensitiveContains(searchText) ||
			$0.displayName.localizedCaseInsensitiveContains(searchText) ||
			$0.installedBundleID.localizedCaseInsensitiveContains(searchText)
		}
	}

	// MARK: Check row
	private var _checkRow: some View {
		HStack {
			VStack(alignment: .leading, spacing: 2) {
				Text(.localized("Check for Updates"))
					.font(.subheadline)
				if _updates.isChecking {
					Text(.localized("Checking…"))
						.font(.caption)
						.foregroundStyle(.secondary)
				} else if let last = _updates.lastChecked {
					Text(last.formatted(date: .abbreviated, time: .shortened))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			Spacer()
			if _updates.isChecking {
				ProgressView()
			} else {
				Button {
					_updates.check()
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.buttonStyle(.borderless)
			}
		}
	}

	// MARK: Body
	var body: some View {
		NBSection(
			.localized("Installed Apps"),
			secondary: _filteredApps.count.description
		) {
			_checkRow

			if _filteredApps.isEmpty {
				Text(.localized("Apps you install with Ksign will appear here."))
					.font(.subheadline)
					.foregroundStyle(.secondary)
			} else {
				ForEach(_filteredApps) { app in
					InstalledCellView(app: app, hasUpdate: _updates.hasUpdate(app))
						.onTapGesture {
							selectedApp = app
						}
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
	/// Shows the yellow "Update" badge instead of the version. Set by the update check.
	var hasUpdate: Bool = false

	/// Second line: repo and upload date of the installed build
	private var _originLine: String {
		guard let provenance = app.provenance else {
			return .localized("Manually imported")
		}
		let repo: String = provenance.repoName ?? .localized("Unknown")
		let date: String = provenance.uploadDate?.formatted(date: .abbreviated, time: .omitted)
			?? .localized("Upload date unknown")
		return "\(repo) · \(date)"
	}

	// MARK: Body
	var body: some View {
		HStack(spacing: 9) {
			_icon

			VStack(alignment: .leading, spacing: 2) {
				Text(app.name)
					.font(.headline)
				Text(_originLine)
					.font(.subheadline)
					.foregroundStyle(.secondary)
				// A long bundle ID is cut in the middle instead of breaking the row
				Text(app.installedBundleID)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
			}
			.frame(maxWidth: .infinity, alignment: .leading)

			_badge
		}
		.contentShape(Rectangle())
	}

	// MARK: Icon
	@ViewBuilder
	private var _icon: some View {
		if let iconURL = app.provenance?.iconURL {
			LazyImage(url: iconURL) { state in
				if let image = state.image {
					image.appIconStyle()
				} else {
					_standardIcon
				}
			}
		} else {
			_standardIcon
		}
	}

	private var _standardIcon: some View {
		Image("App_Unknown")
			.appIconStyle()
	}

	// MARK: Badge
	/// Same look as the expiry badge on the Signed tab: green with the version,
	/// yellow with "Update" when a newer build is available.
	@ViewBuilder
	private var _badge: some View {
		if hasUpdate {
			_pill(
				text: .localized("Update"),
				systemImage: "arrow.up.circle",
				background: .yellow,
				foreground: .black
			)
		} else if let version = app.version, !version.isEmpty {
			_pill(
				text: version,
				systemImage: nil,
				background: .green,
				foreground: .white
			)
		}
	}

	private func _pill(
		text: String,
		systemImage: String?,
		background: Color,
		foreground: Color
	) -> some View {
		HStack(spacing: 4) {
			if let systemImage {
				Image(systemName: systemImage)
					.font(.system(size: 11))
			}
			Text(text)
				.font(.system(size: 12))
				.fontWeight(.semibold)
				.lineLimit(1)
		}
		.foregroundColor(foreground)
		.padding(.horizontal, 10)
		.padding(.vertical, 5)
		.background(background)
		.clipShape(Capsule())
		.padding(.trailing, 4)
	}
}
