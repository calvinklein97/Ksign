//
//  BackupSection.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//  Settings section to export and import the app's data.
//

import SwiftUI
import UniformTypeIdentifiers
import NimbleViews
import NimbleExtensions

// MARK: - BackupSection
struct BackupSection: View {
	@State private var _isChoosingExport = false
	@State private var _isImporting = false

	var body: some View {
		Section {
			Button(.localized("Export Backup"), systemImage: "square.and.arrow.up") {
				_isChoosingExport = true
			}
			Button(.localized("Import Backup"), systemImage: "square.and.arrow.down") {
				_isImporting = true
			}
		} header: {
			Text(.localized("Backup"))
		} footer: {
			Text(.localized("Saves the installed apps list, repos and settings, optionally with certificates, to a file. Use it to move to a new installation."))
		}
		.confirmationDialog(
			.localized("Export Backup"),
			isPresented: $_isChoosingExport,
			titleVisibility: .visible
		) {
			Button(.localized("With certificates")) {
				_export(includeCertificates: true)
			}
			Button(.localized("Without certificates")) {
				_export(includeCertificates: false)
			}
			Button(.localized("Cancel"), role: .cancel) {}
		} message: {
			Text(.localized("With certificates, the file contains your signing certificate and its password. Keep it private."))
		}
		.sheet(isPresented: $_isImporting) {
			FileImporterRepresentableView(
				allowedContentTypes: [.json],
				allowsMultipleSelection: false,
				onDocumentsPicked: { urls in
					_isImporting = false
					guard let url = urls.first else { return }
					// Wait until the picker is gone before importing and showing the result
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
						BackupManager.importBackup(from: url) { summary in
							UIAlertController.showAlertWithOk(
								title: .localized("Import Backup"),
								message: summary
							)
						}
					}
				}
			)
		}
	}

	private func _export(includeCertificates: Bool) {
		do {
			let url = try BackupManager.export(includeCertificates: includeCertificates)
			UIActivityViewController.show(activityItems: [url])
		} catch {
			UIAlertController.showAlertWithOk(
				title: .localized("Error"),
				message: error.localizedDescription
			)
		}
	}
}
