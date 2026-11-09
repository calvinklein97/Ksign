//
//  InstalledStore.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//
//  Keeps the records of installed apps and the repo provenance of downloaded
//  apps in a small JSON file (Application Support/InstalledTracking). It is
//  deliberately independent from Core Data, so the existing data model does
//  not have to be touched.
//

import Foundation
import Combine
import AltSourceKit

// MARK: - InstalledStore
final class InstalledStore: ObservableObject {
	static let shared = InstalledStore()

	/// Installed apps, newest installation first. Only changed on the main thread.
	@Published private(set) var apps: [InstalledApp] = []

	// MARK: Storage
	private struct Snapshot: Codable {
		var apps: [InstalledApp] = []
		/// Provenance by download ID, valid from the download button until the app is imported
		var downloads: [String: SourceProvenance] = [:]
		/// Provenance by Library app UUID (imported and signed apps)
		var appLinks: [String: SourceProvenance] = [:]
	}

	private let lock = NSLock()
	private let ioQueue = DispatchQueue(label: "ksign.installed-store.io", qos: .utility)
	private let fileURL: URL

	// Protected by `lock`
	private var _storedApps: [InstalledApp] = []
	private var _downloads: [String: SourceProvenance] = [:]
	private var _appLinks: [String: SourceProvenance] = [:]
	/// Download IDs started from the update sheet (memory only)
	private var _pendingUpdateDownloads: Set<String> = []

	/// Posted when a download started from the update sheet has been imported.
	/// `userInfo["uuid"]` holds the UUID of the new Library app.
	static let updateDownloadReady = Notification.Name("ksign.updateDownloadReady")

	private init() {
		self.fileURL = Self.storageURL()

		if let data = try? Data(contentsOf: fileURL) {
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			if let snapshot = try? decoder.decode(Snapshot.self, from: data) {
				_storedApps = snapshot.apps
				_downloads = snapshot.downloads
				_appLinks = snapshot.appLinks
				apps = snapshot.apps
			}
		}
	}

	private static func storageURL() -> URL {
		let fileManager = FileManager.default
		let base = (try? fileManager.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: true
		)) ?? fileManager.temporaryDirectory
		let directory = base.appendingPathComponent("InstalledTracking", isDirectory: true)
		try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory.appendingPathComponent("installed.json")
	}

	/// Applies a change under the lock, saves it to disk and publishes the new list.
	private func mutate(_ change: () -> Void) {
		lock.lock()
		change()
		let snapshot = Snapshot(apps: _storedApps, downloads: _downloads, appLinks: _appLinks)
		lock.unlock()

		_persist(snapshot)

		let list = snapshot.apps
		DispatchQueue.main.async { [weak self] in
			self?.apps = list
		}
	}

	private func _persist(_ snapshot: Snapshot) {
		let url = fileURL
		ioQueue.async {
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .iso8601
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			guard let data = try? encoder.encode(snapshot) else { return }
			try? data.write(to: url, options: .atomic)
		}
	}

	// MARK: Provenance tracking

	/// Remembers which repo entry a download belongs to. Called when a download starts.
	func registerDownload(
		id: String,
		source: ASRepository?,
		app: ASRepository.App,
		downloadURL: URL? = nil
	) {
		let provenance = SourceProvenance(source: source, app: app, downloadURL: downloadURL)
		mutate {
			_downloads[id] = provenance
		}
	}

	/// Connects a finished download to the Library app that was created from it.
	/// Downloads that were not started from a repo (manual imports) are ignored.
	func linkDownload(_ downloadID: String?, toApp appUUID: String) {
		guard let downloadID else { return }

		lock.lock()
		let isKnown = _downloads[downloadID] != nil
		lock.unlock()
		guard isKnown else { return }

		mutate {
			if let provenance = _downloads.removeValue(forKey: downloadID) {
				_appLinks[appUUID] = provenance
			}
		}

		lock.lock()
		let isUpdate = _pendingUpdateDownloads.remove(downloadID) != nil
		lock.unlock()
		if isUpdate {
			DispatchQueue.main.async {
				NotificationCenter.default.post(
					name: InstalledStore.updateDownloadReady,
					object: nil,
					userInfo: ["uuid": appUUID]
				)
			}
		}
	}

	/// Registers a download that was started from the update sheet.
	func registerUpdateDownload(id: String, provenance: SourceProvenance) {
		lock.lock()
		_pendingUpdateDownloads.insert(id)
		lock.unlock()
		mutate {
			_downloads[id] = provenance
		}
	}

	/// Hides all builds uploaded on or before `date` for this app.
	func ignore(_ id: String, upTo date: Date) {
		mutate {
			if let index = _storedApps.firstIndex(where: { $0.id == id }) {
				_storedApps[index].ignoredBuildDate = date
			}
		}
	}

	/// Signing creates a new Library app with a new UUID, so the provenance is carried over.
	func copyProvenance(from sourceAppUUID: String?, to destinationAppUUID: String) {
		guard let sourceAppUUID else { return }

		lock.lock()
		let found = _appLinks[sourceAppUUID]
		lock.unlock()
		guard let found else { return }

		mutate {
			_appLinks[destinationAppUUID] = found
		}
	}

	func provenance(forApp appUUID: String?) -> SourceProvenance? {
		guard let appUUID else { return nil }
		lock.lock()
		defer { lock.unlock() }
		return _appLinks[appUUID]
	}

	// MARK: Installed apps

	/// Creates or replaces the record for an app that was just installed.
	/// An app can only exist once per bundle identifier on the device, so a
	/// newer installation replaces the previous record.
	func recordInstall(of app: AppInfoPresentable) {
		guard let bundleID = app.identifier, !bundleID.isEmpty else { return }

		let record = InstalledApp(
			installedBundleID: bundleID,
			name: app.name ?? bundleID,
			version: app.version,
			installDate: Date(),
			provenance: provenance(forApp: app.uuid),
			ignoredBuildDate: nil
		)

		mutate {
			_storedApps.removeAll { $0.installedBundleID == bundleID }
			_storedApps.insert(record, at: 0)
		}
	}

	func remove(_ id: String) {
		mutate {
			_storedApps.removeAll { $0.id == id }
		}
	}
}
