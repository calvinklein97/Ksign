//
//  BrowserFileSaver.swift
//  Ksign
//
//  Part of the in-app browser module.
//  Stores browser downloads that are not IPA files in the "Downloads"
//  folder of the app files, where the Files tab shows them.
//

import Foundation

enum BrowserFileSaver {
	/// Prefix of the IDs of downloads started by the browser
	static let idPrefix = "KsignFileDownload_"

	static func isIPA(_ url: URL) -> Bool {
		["ipa", "tipa"].contains(url.pathExtension.lowercased())
	}

	/// Moves the file into Documents/Downloads and returns its new location.
	/// An existing file with the same name is never overwritten.
	@discardableResult
	static func save(_ file: URL) -> URL? {
		let manager = FileManager.default
		let folder = URL.documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)

		do {
			try manager.createDirectory(at: folder, withIntermediateDirectories: true)
			if file.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
				return file
			}

			let base = file.deletingPathExtension().lastPathComponent
			let ext = file.pathExtension
			var target = folder.appendingPathComponent(file.lastPathComponent)
			var counter = 1
			while manager.fileExists(atPath: target.path) {
				counter += 1
				let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
				target = folder.appendingPathComponent(name)
			}

			try manager.moveItem(at: file, to: target)
			return target
		} catch {
			return nil
		}
	}
}
