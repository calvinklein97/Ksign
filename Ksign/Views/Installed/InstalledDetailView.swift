//
//  InstalledDetailView.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//  Sheet that shows everything stored about an installed app.
//

import SwiftUI
import NimbleExtensions

// MARK: - InstalledDetailView
struct InstalledDetailView: View {
	@Environment(\.dismiss) private var dismiss

	var app: InstalledApp

	// MARK: Body
	var body: some View {
		NavigationStack {
			List {
				Section {
					_row(.localized("Name"), app.name)
					_row(.localized("Version"), app.version)
					_row(.localized("Bundle ID"), app.installedBundleID)
					_row(
						.localized("Installed"),
						app.installDate.formatted(date: .abbreviated, time: .shortened)
					)
				} header: {
					Text(.localized("Installed App"))
				}

				if let provenance = app.provenance {
					Section {
						_row(.localized("Repo"), provenance.repoName)
						_row(.localized("Repo build"), provenance.appName)
						_row(.localized("Repo bundle ID"), provenance.appBundleID)
						_row(.localized("Repo version"), provenance.version)
						_row(
							.localized("Upload date"),
							provenance.uploadDate?.formatted(date: .abbreviated, time: .omitted)
						)
						_row(.localized("File name"), provenance.downloadFileName)
						_row(.localized("Download URL"), provenance.downloadURL?.absoluteString)
					} header: {
						Text(.localized("Source"))
					}
				} else {
					Section {
						Text(.localized("Manually imported"))
							.foregroundStyle(.secondary)
					} header: {
						Text(.localized("Source"))
					}
				}
			}
			.navigationTitle(app.name)
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

	// MARK: Row
	@ViewBuilder
	private func _row(_ title: String, _ value: String?) -> some View {
		if let value, !value.isEmpty {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.caption)
					.foregroundStyle(.secondary)
				Text(value)
					.font(.subheadline)
					.textSelection(.enabled)
			}
		}
	}
}
