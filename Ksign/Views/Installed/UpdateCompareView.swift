//
//  UpdateCompareView.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//  Comparison sheet shown before an update is started.
//

import SwiftUI
import NimbleExtensions

// MARK: - UpdateCompareView
struct UpdateCompareView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var _updates = UpdateChecker.shared

	var app: InstalledApp
	/// Called after the download was started
	var onStarted: () -> Void = {}

	@State private var _selectedID: String?

	private var _builds: [UpdateCandidate] {
		_updates.updates(for: app)
	}

	private var _selected: UpdateCandidate? {
		_builds.first(where: { $0.id == _selectedID })
	}

	// MARK: Body
	var body: some View {
		NavigationStack {
			List {
				Section {
					_row(.localized("Name"), app.provenance?.appName ?? app.name)
					_row(.localized("Bundle ID"), app.provenance?.appBundleID ?? app.installedBundleID)
					_row(.localized("Version"), app.provenance?.version ?? app.version)
					_row(
						.localized("Upload date"),
						(app.provenance?.uploadDate ?? app.installDate)
							.formatted(date: .abbreviated, time: .omitted)
					)
					_row(.localized("File name"), app.provenance?.downloadFileName)
				} header: {
					Text(.localized("Installed"))
				}

				Section {
					ForEach(_builds) { build in
						Button {
							_selectedID = build.id
						} label: {
							HStack(alignment: .top, spacing: 12) {
								Image(systemName: build.id == _selectedID ? "checkmark.circle.fill" : "circle")
									.foregroundStyle(build.id == _selectedID ? Color.accentColor : .secondary)
									.font(.title3)
								VStack(alignment: .leading, spacing: 2) {
									Text(build.appName)
										.font(.subheadline.weight(.semibold))
										.foregroundStyle(.primary)
									_detail(.localized("Bundle ID"), build.appBundleID)
									_detail(.localized("Version"), build.version)
									_detail(
										.localized("Upload date"),
										build.uploadDate?.formatted(date: .abbreviated, time: .omitted)
									)
									_detail(.localized("Repo"), build.repoName)
									_detail(.localized("File name"), build.downloadFileName)
								}
								Spacer(minLength: 0)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
					}
				} header: {
					Text(.localized("Available builds"))
				}
			}
			.navigationTitle(.localized("Update"))
			.navigationBarTitleDisplayMode(.inline)
			.safeAreaInset(edge: .bottom) {
				VStack(spacing: 8) {
					Button {
						_startUpdate()
					} label: {
						Text(.localized("Update"))
							.font(.headline)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 12)
							.background(Color.accentColor)
							.foregroundStyle(.white)
							.clipShape(RoundedRectangle(cornerRadius: 12))
					}
					.disabled(_selected == nil)
					.opacity(_selected == nil ? 0.4 : 1)

					HStack(spacing: 8) {
						Button(.localized("Cancel")) {
							dismiss()
						}
						.frame(maxWidth: .infinity)

						Button(.localized("Cancel and Ignore"), role: .destructive) {
							_ignore()
						}
						.frame(maxWidth: .infinity)
					}
					.font(.subheadline)
				}
				.padding()
				.background(.bar)
			}
			.onAppear {
				if _selectedID == nil {
					_selectedID = (_builds.first(where: { $0.isSameName }) ?? _builds.first)?.id
				}
			}
		}
	}

	// MARK: Actions
	private func _startUpdate() {
		guard let build = _selected, let url = build.downloadURL else { return }
		let download = DownloadManager.shared.startDownload(
			from: url,
			id: "KsignUpdate_\(UUID().uuidString)"
		)
		InstalledStore.shared.registerUpdateDownload(id: download.id, provenance: build.provenance)
		dismiss()
		onStarted()
	}

	private func _ignore() {
		let newest = _builds.compactMap { $0.uploadDate }.max() ?? Date()
		InstalledStore.shared.ignore(app.id, upTo: newest)
		dismiss()
	}

	// MARK: Rows
	@ViewBuilder
	private func _row(_ title: String, _ value: String?) -> some View {
		if let value, !value.isEmpty {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.caption)
					.foregroundStyle(.secondary)
				Text(value)
					.font(.subheadline)
			}
		}
	}

	@ViewBuilder
	private func _detail(_ title: String, _ value: String?) -> some View {
		if let value, !value.isEmpty {
			Text("\(title): \(value)")
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)
		}
	}
}
