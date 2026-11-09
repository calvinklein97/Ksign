//
//  UpdateChecker.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//  Compares installed apps with the builds offered by all configured repos.
//

import Foundation
import Combine
import AltSourceKit
import NimbleJSON

// MARK: - UpdateCandidate
/// One build offered by a repo that is newer than the installed one.
struct UpdateCandidate: Identifiable, Equatable {
	var id: String {
		"\(repoID ?? repoName ?? "")|\(appBundleID)|\(appName)|\(version ?? "")|\(downloadURL?.absoluteString ?? "")"
	}

	var repoID: String?
	var repoName: String?
	var appBundleID: String
	/// Exact name in the repo, including suffixes such as "(YP)"
	var appName: String
	var version: String?
	var uploadDate: Date?
	var downloadURL: URL?
	var iconURL: URL?
	/// True if the name matches the name of the installed build
	var isSameName: Bool

	var downloadFileName: String? {
		guard let last = downloadURL?.lastPathComponent, !last.isEmpty else { return nil }
		return last.removingPercentEncoding ?? last
	}

	var provenance: SourceProvenance {
		SourceProvenance(
			repoID: repoID,
			repoName: repoName,
			appBundleID: appBundleID,
			appName: appName,
			version: version,
			uploadDate: uploadDate,
			downloadURL: downloadURL,
			iconURL: iconURL
		)
	}
}

// MARK: - UpdateChecker
final class UpdateChecker: ObservableObject {
	static let shared = UpdateChecker()

	/// Newer builds per installed bundle ID, newest first
	@Published private(set) var candidates: [String: [UpdateCandidate]] = [:]
	@Published private(set) var isChecking = false
	@Published private(set) var lastChecked: Date?

	private let _fetchService = NBFetchService()
	private var _repos: [ASRepository] = []
	private var _cancellables = Set<AnyCancellable>()
	private let _lastCheckedKey = "ksign.updates.lastChecked"
	/// Automatic checks at app start happen at most this often
	private let _autoInterval: TimeInterval = 6 * 60 * 60

	private init() {
		let stored = UserDefaults.standard.double(forKey: _lastCheckedKey)
		if stored > 0 { lastChecked = Date(timeIntervalSince1970: stored) }

		// Recalculate when apps are installed, removed or ignored
		InstalledStore.shared.$apps
			.dropFirst()
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in self?._recompute() }
			.store(in: &_cancellables)
	}

	/// Number of installed apps that have at least one update of the same name
	var updateCount: Int {
		InstalledStore.shared.apps.filter { hasUpdate($0) }.count
	}

	func hasUpdate(_ app: InstalledApp) -> Bool {
		candidates[app.id]?.contains(where: { $0.isSameName }) ?? false
	}

	func updates(for app: InstalledApp) -> [UpdateCandidate] {
		candidates[app.id] ?? []
	}

	// MARK: Checking

	/// Called at app start. Skips the check if the last one is recent.
	func checkIfNeeded() {
		if let lastChecked, Date().timeIntervalSince(lastChecked) < _autoInterval { return }
		check()
	}

	/// Downloads all repos and recalculates the updates.
	func check() {
		guard !isChecking else { return }
		isChecking = true

		let urls = Storage.shared.getSources().compactMap { $0.sourceURL }

		Task { [weak self] in
			guard let self else { return }
			var repos: [ASRepository] = []

			await withTaskGroup(of: ASRepository?.self) { group in
				for url in urls {
					group.addTask { [weak self] in
						guard let self else { return nil }
						return await self._fetch(url)
					}
				}
				for await repo in group {
					if let repo { repos.append(repo) }
				}
			}

			await MainActor.run {
				// If nothing could be loaded (offline), keep what we had
				if !repos.isEmpty || urls.isEmpty {
					self._repos = repos
					self.lastChecked = Date()
					UserDefaults.standard.set(
						Date().timeIntervalSince1970,
						forKey: self._lastCheckedKey
					)
				}
				self._recompute()
				self.isChecking = false
			}
		}
	}

	private func _fetch(_ url: URL) async -> ASRepository? {
		await withCheckedContinuation { continuation in
			_fetchService.fetch(from: url) { (result: Result<ASRepository, Error>) in
				switch result {
				case .success(let repo):
					continuation.resume(returning: repo)
				case .failure:
					continuation.resume(returning: nil)
				}
			}
		}
	}

	// MARK: Comparison

	private func _recompute() {
		var result: [String: [UpdateCandidate]] = [:]
		for app in InstalledStore.shared.apps {
			let found = _candidates(for: app)
			if !found.isEmpty { result[app.id] = found }
		}
		candidates = result
	}

	private func _day(_ date: Date) -> Date {
		Calendar.current.startOfDay(for: date)
	}

	private func _candidates(for app: InstalledApp) -> [UpdateCandidate] {
		guard
			let provenance = app.provenance,
			let repoBundleID = provenance.appBundleID,
			!repoBundleID.isEmpty
		else { return [] }

		let baseDate = _day(provenance.uploadDate ?? app.installDate)
		let ignoredDay = app.ignoredBuildDate.map { _day($0) }
		let installedVersion = provenance.version ?? app.version

		var found: [UpdateCandidate] = []
		var seen = Set<String>()

		for repo in _repos {
			for entry in repo.apps where entry.id == repoBundleID {
				var builds: [(version: String?, date: Date?, url: URL?)] = []
				for version in entry.versions ?? [] {
					builds.append((version.version, version.date?.date, version.downloadURL))
				}
				// Top-level fields (older repo formats, or an entry without a version list)
				builds.append((entry.version, entry.versionDate?.date, entry.downloadURL))

				for build in builds {
					guard let url = build.url else { continue }
					// The installed build itself is never an update
					if url == provenance.downloadURL { continue }

					let candidate = UpdateCandidate(
						repoID: repo.id,
						repoName: repo.name,
						appBundleID: repoBundleID,
						appName: entry.currentName,
						version: build.version,
						uploadDate: build.date,
						downloadURL: url,
						iconURL: entry.iconURL,
						isSameName: entry.currentName == provenance.appName
					)

					guard seen.insert(candidate.id).inserted else { continue }

					let newerDate = build.date.map { _day($0) > baseDate } ?? false
					let higherVersion: Bool = {
						guard let new = build.version, let old = installedVersion else { return false }
						return new.compare(old, options: .numeric) == .orderedDescending
					}()
					guard newerDate || higherVersion else { continue }

					// Ignored: not newer than the build the user chose to skip
					if let ignoredDay, let date = build.date, _day(date) <= ignoredDay { continue }

					found.append(candidate)
				}
			}
		}

		// Newest first, independent of the order in the repo
		return found.sorted {
			($0.uploadDate ?? .distantPast) > ($1.uploadDate ?? .distantPast)
		}
	}
}
