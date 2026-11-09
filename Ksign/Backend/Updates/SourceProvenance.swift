//
//  SourceProvenance.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//  Describes which repo build an app originally came from.
//

import Foundation
import AltSourceKit

// MARK: - SourceProvenance
/// Snapshot of the repo entry (and, if applicable, the specific version)
/// an app was downloaded from. Everything is stored as plain values so it
/// stays valid even when the repo changes or the app package is deleted.
struct SourceProvenance: Codable, Equatable {
	/// Identifier of the repo (ASRepository.id), if the repo declares one
	var repoID: String?
	var repoName: String?
	/// Bundle identifier as declared by the repo (before any re-signing changes)
	var appBundleID: String?
	/// Exact app name as listed in the repo, including suffixes like "(YP)"
	var appName: String
	var version: String?
	/// Upload date of this build as declared by the repo
	var uploadDate: Date?
	var downloadURL: URL?
	var iconURL: URL?

	/// Full file name of the downloaded package, e.g. "YouTube_21.45.4_YTPlus.ipa"
	var downloadFileName: String? {
		guard let last = downloadURL?.lastPathComponent, !last.isEmpty else { return nil }
		return last.removingPercentEncoding ?? last
	}
}

// MARK: - Creation from repo data
extension SourceProvenance {
	/// - Parameters:
	///   - source: the repo the app was listed in
	///   - app: the repo entry
	///   - downloadURL: the URL that was actually downloaded. If it belongs to an
	///     older entry in `app.versions`, that version's data is used instead of
	///     the current one.
	init(source: ASRepository?, app: ASRepository.App, downloadURL: URL? = nil) {
		let matchedVersion: ASRepository.App.Version? = {
			guard let downloadURL else { return nil }
			return app.versions?.first(where: { $0.downloadURL == downloadURL })
		}()

		self.repoID = source?.id
		self.repoName = source?.name
		self.appBundleID = app.id
		self.appName = app.currentName
		self.version = matchedVersion?.version ?? app.currentVersion
		self.uploadDate = matchedVersion?.date?.date ?? app.currentDate?.date
		self.downloadURL = downloadURL ?? app.currentDownloadUrl
		self.iconURL = app.iconURL
	}
}
