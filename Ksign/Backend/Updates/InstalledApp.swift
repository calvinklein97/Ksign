//
//  InstalledApp.swift
//  Ksign
//
//  Part of the installed-apps / update tracking module.
//  A lightweight record of an app that was installed on the device.
//  It only holds metadata, never the app package itself.
//

import Foundation

// MARK: - InstalledApp
struct InstalledApp: Codable, Identifiable, Equatable {
	/// Bundle identifier of the app as installed on the device (after signing).
	/// There can only be one app per bundle identifier, so it doubles as the record ID.
	var installedBundleID: String
	var id: String { installedBundleID }

	/// Name of the installed app
	var name: String
	var version: String?
	var installDate: Date

	/// Where the app came from. `nil` means it was imported manually.
	var provenance: SourceProvenance?

	/// Reserved for the update check: builds uploaded on or before this date
	/// are not offered as updates anymore.
	var ignoredBuildDate: Date?

	/// Name to show in lists: the exact repo name (with suffix) if known
	var displayName: String {
		provenance?.appName ?? name
	}

	var isFromRepo: Bool {
		provenance != nil
	}

	enum CodingKeys: String, CodingKey {
		case installedBundleID, name, version, installDate, provenance, ignoredBuildDate
	}
}
