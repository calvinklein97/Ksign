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
	@Environment(\.editMode) private var _editMode
	@AppStorage(InstalledSortStorage.keyName) private var _sortKeyRaw: String = InstalledSortKey.installDate.rawValue
	@AppStorage(InstalledSortStorage.ascendingName) private var _sortAscending: Bool = false

	var searchText: String
	/// The app whose details sheet is shown. The sheet itself lives in LibraryView.
	@Binding var selectedApp: InstalledApp?
	/// The app whose update comparison sheet is shown (also lives in LibraryView)
	@Binding var compareApp: InstalledApp?
	/// IDs of the apps selected in edit mode (shared with the other Library tabs)
	@Binding var selectedIDs: Set<String>

	private var _filteredApps: [InstalledApp] {
		let list: [InstalledApp]
		if searchText.isEmpty {
			list = _store.apps
		} else {
			list = _store.apps.filter {
				$0.name.localizedCaseInsensitiveContains(searchText) ||
				$0.displayName.localizedCaseInsensitiveContains(searchText) ||
				$0.installedBundleID.localizedCaseInsensitiveContains(searchText)
			}
		}
		return list.sorted(
			by: InstalledSortKey(rawValue: _sortKeyRaw) ?? .installDate,
			ascending: _sortAscending,
			hasUpdate: { _updates.hasUpdate($0) }
		)
	}

	private var _isEditing: Bool {
		_editMode?.wrappedValue == .active
	}

	// MARK: Body
	var body: some View {
		NBSection(
			.localized("Installed Apps"),
			secondary: _filteredApps.count.description
		) {
			if _filteredApps.isEmpty {
				Text(.localized("Apps you install with CaliSign will appear here."))
					.font(.subheadline)
					.foregroundStyle(.secondary)
			} else {
				ForEach(_filteredApps) { app in
					InstalledCellView(
						app: app,
						hasUpdate: _updates.hasUpdate(app),
						onUpdate: { compareApp = app },
						isEditing: _isEditing,
						isSelected: selectedIDs.contains(app.id),
						onToggle: { _toggle(app) }
					)
					.onTapGesture {
						if _isEditing {
							_toggle(app)
						} else {
							selectedApp = app
						}
					}
					.swipeActions(edge: .trailing, allowsFullSwipe: true) {
						if !_isEditing {
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

				_lastCheckedFooter
			}
		}
	}

	private func _toggle(_ app: InstalledApp) {
		UIImpactFeedbackGenerator(style: .light).impactOccurred()
		withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)) {
			if selectedIDs.contains(app.id) {
				selectedIDs.remove(app.id)
			} else {
				selectedIDs.insert(app.id)
			}
		}
	}

	// MARK: Footer
	private var _lastCheckedFooter: some View {
		Group {
			if _updates.isChecking {
				Text(.localized("Checking for updates…"))
			} else if let last = _updates.lastChecked {
				Text("\(String.localized("Last checked")): \(last.formatted(date: .abbreviated, time: .shortened))")
			}
		}
		.font(.footnote)
		.foregroundStyle(.secondary)
		.frame(maxWidth: .infinity)
		.listRowSeparator(.hidden)
	}
}

// MARK: - UpdateCheckButton
/// Toolbar button that checks all repos for updates.
struct UpdateCheckButton: View {
	@ObservedObject private var _updates = UpdateChecker.shared

	var body: some View {
		Button {
			_updates.check()
		} label: {
			if _updates.isChecking {
				ProgressView()
			} else {
				Image(systemName: "arrow.triangle.2.circlepath")
			}
		}
		.disabled(_updates.isChecking)
		.accessibilityLabel(Text(.localized("Check for Updates")))
	}
}

// MARK: - InstalledCellView
struct InstalledCellView: View {
	var app: InstalledApp
	/// Shows the yellow "Update" badge instead of the version. Set by the update check.
	var hasUpdate: Bool = false
	/// Tapping the yellow pill opens the update comparison
	var onUpdate: (() -> Void)? = nil
	/// Edit mode: shows a selection circle instead of the badge
	var isEditing: Bool = false
	var isSelected: Bool = false
	var onToggle: (() -> Void)? = nil

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
			if isEditing {
				Button {
					onToggle?()
				} label: {
					Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
						.foregroundColor(isSelected ? .accentColor : .secondary)
						.font(.title2)
				}
				.buttonStyle(.borderless)
			}

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

			if !isEditing {
				_badge
			}
		}
		.scaleEffect(isSelected ? 0.98 : 1.0)
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
			Button {
				onUpdate?()
			} label: {
				_pill(
					text: .localized("Update"),
					systemImage: "arrow.up.circle",
					background: .yellow,
					foreground: .black
				)
			}
			.buttonStyle(.borderless)
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
