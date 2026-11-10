//
//  BackupManager.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//  Exports and imports the app's data as one file, e.g. to move to a new
//  bundle identifier. Holds: installed apps list, repos, settings and,
//  optionally, signing certificates.
//

import Foundation
import CoreData

// MARK: - Backup file
struct BackupFile: Codable {
	var format: Int = 1
	var created: Date = Date()
	var installedApps: [InstalledApp] = []
	var repos: [BackupRepo] = []
	/// Property list (binary) with the saved settings
	var settingsPlist: Data?
	/// nil when the backup was made without certificates
	var certificates: [BackupCertificate]?
}

struct BackupRepo: Codable {
	var name: String?
	var url: URL
	var identifier: String
	var iconURL: URL?
}

struct BackupCertificate: Codable {
	var nickname: String?
	var password: String?
	var p12FileName: String
	var provisionFileName: String
	var p12: Data
	var provision: Data
}

// MARK: - BackupManager
enum BackupManager {
	/// Settings that are carried over. Everything else stays at its default.
	private static let settingsKeys: [String] = [
		"Feather.accentColor",
		"Feather.customAccentColor",
		"Feather.compressionLevel",
		"Feather.extractionLibrary",
		"Feather.installationMethod",
		"Feather.ipFix",
		"Feather.libraryCellAppearance",
		"Feather.serverMethod",
		"Feather.storeCellAppearance",
		"Feather.useLastExportLocation",
		"Feather.useShareSheetForArchiving",
		"Feather.userInterfaceStyle",
		"signing_options",
		InstalledSortStorage.keyName,
		InstalledSortStorage.ascendingName
	]

	enum BackupError: LocalizedError {
		case unreadable

		var errorDescription: String? {
			String.localized("The file is not a valid backup.")
		}
	}

	// MARK: Export
	/// Must be called on the main thread. Returns the file to share.
	static func export(includeCertificates: Bool) throws -> URL {
		var backup = BackupFile()
		backup.installedApps = InstalledStore.shared.apps

		backup.repos = Storage.shared.getSources().compactMap { source in
			guard let url = source.sourceURL, let identifier = source.identifier else { return nil }
			return BackupRepo(name: source.name, url: url, identifier: identifier, iconURL: source.iconURL)
		}

		var settings: [String: Any] = [:]
		for key in settingsKeys {
			if let value = UserDefaults.standard.object(forKey: key) {
				settings[key] = value
			}
		}
		backup.settingsPlist = try? PropertyListSerialization.data(
			fromPropertyList: settings,
			format: .binary,
			options: 0
		)

		if includeCertificates {
			let request = NSFetchRequest<CertificatePair>(entityName: "CertificatePair")
			let certificates = (try? Storage.shared.context.fetch(request)) ?? []
			backup.certificates = certificates.compactMap { cert in
				guard
					let p12URL = Storage.shared.getFile(.certificate, from: cert),
					let provisionURL = Storage.shared.getFile(.provision, from: cert),
					let p12 = try? Data(contentsOf: p12URL),
					let provision = try? Data(contentsOf: provisionURL)
				else { return nil }
				return BackupCertificate(
					nickname: cert.nickname,
					password: cert.password,
					p12FileName: p12URL.lastPathComponent,
					provisionFileName: provisionURL.lastPathComponent,
					p12: p12,
					provision: provision
				)
			}
		}

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let data = try encoder.encode(backup)

		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("AppBackup-\(formatter.string(from: Date())).json")
		try data.write(to: url, options: .atomic)
		return url
	}

	// MARK: Import
	/// Must be called on the main thread. `completion` gets a summary text on the main thread.
	static func importBackup(from url: URL, completion: @escaping (String) -> Void) {
		let backup: BackupFile
		do {
			let data = try Data(contentsOf: url)
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			backup = try decoder.decode(BackupFile.self, from: data)
		} catch {
			completion(String.localized("The file is not a valid backup."))
			return
		}

		// Installed apps
		let appCount = InstalledStore.shared.mergeImported(backup.installedApps)

		// Repos
		var repoCount = 0
		let existing = Set(Storage.shared.getSources().compactMap { $0.identifier })
		for repo in backup.repos where !existing.contains(repo.identifier) {
			Storage.shared.addSource(
				repo.url,
				name: repo.name,
				identifier: repo.identifier,
				iconURL: repo.iconURL
			) { _ in }
			repoCount += 1
		}

		// Settings
		var settingsRestored = false
		if
			let plist = backup.settingsPlist,
			let settings = (try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)) as? [String: Any]
		{
			for key in settingsKeys {
				if let value = settings[key] {
					UserDefaults.standard.set(value, forKey: key)
				}
			}
			if
				let data = UserDefaults.standard.data(forKey: "signing_options"),
				let options = try? JSONDecoder().decode(Options.self, from: data)
			{
				OptionsManager.shared.options = options
				OptionsManager.shared.saveOptions()
			}
			settingsRestored = true
		}

		// Certificates (skips ones that are already there)
		let finish: (Int) -> Void = { certCount in
			var lines: [String] = []
			lines.append("\(String.localized("Installed apps")): \(appCount)")
			lines.append("\(String.localized("Repos")): \(repoCount)")
			if backup.certificates != nil {
				lines.append("\(String.localized("Certificates")): \(certCount)")
			}
			if settingsRestored {
				lines.append(String.localized("Settings restored"))
			}
			completion(lines.joined(separator: "\n"))
		}

		guard let certificates = backup.certificates, !certificates.isEmpty else {
			finish(0)
			return
		}

		let request = NSFetchRequest<CertificatePair>(entityName: "CertificatePair")
		let current = (try? Storage.shared.context.fetch(request)) ?? []
		let known: [Data] = current.compactMap { cert in
			Storage.shared.getFile(.certificate, from: cert).flatMap { try? Data(contentsOf: $0) }
		}

		let tempDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("BackupImport-\(UUID().uuidString)", isDirectory: true)
		try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

		let group = DispatchGroup()
		var imported = 0

		for (index, cert) in certificates.enumerated() where !known.contains(cert.p12) {
			let folder = tempDir.appendingPathComponent("\(index)", isDirectory: true)
			try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			let p12URL = folder.appendingPathComponent(cert.p12FileName)
			let provisionURL = folder.appendingPathComponent(cert.provisionFileName)
			guard
				(try? cert.p12.write(to: p12URL)) != nil,
				(try? cert.provision.write(to: provisionURL)) != nil
			else { continue }

			group.enter()
			FR.handleCertificateFiles(
				p12URL: p12URL,
				provisionURL: provisionURL,
				p12Password: cert.password ?? "",
				certificateName: cert.nickname ?? ""
			) { error in
				if error == nil { imported += 1 }
				group.leave()
			}
		}

		group.notify(queue: .main) {
			try? FileManager.default.removeItem(at: tempDir)
			finish(imported)
		}
	}
}
