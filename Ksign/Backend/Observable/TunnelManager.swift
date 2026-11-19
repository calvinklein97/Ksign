//
//  TunnelManager.swift
//  Ksign
//
//  Starts the LocalDevVPN loopback tunnel for the idevice installation
//  method. An app cannot switch on another app's VPN, so LocalDevVPN is
//  opened through its `localdevvpn://enable` link; it connects its tunnel and
//  then opens CaliSign again through the given callback scheme.
//

import UIKit
import IDeviceSwift

@MainActor
final class TunnelManager {
	static let shared = TunnelManager()

	/// Setting "Start LocalDevVPN when needed", on by default
	static let autoStartKey = "Feather.autoStartVPN"

	private static let _scheme = "localdevvpn"
	private static let _callbackScheme = "calisign"
	/// The address range LocalDevVPN uses for its tunnel
	private static let _tunnelPrefix = "10.7.0."

	private var _lastStart: Date?

	static var autoStartEnabled: Bool {
		(UserDefaults.standard.object(forKey: autoStartKey) as? Bool) ?? true
	}

	var isInstalled: Bool {
		guard let url = URL(string: "\(Self._scheme)://") else { return false }
		return UIApplication.shared.canOpenURL(url)
	}

	/// True while a tunnel interface (`utun*`) with an address of LocalDevVPN's range is up
	nonisolated static func isTunnelUp() -> Bool {
		var list: UnsafeMutablePointer<ifaddrs>?
		guard getifaddrs(&list) == 0, let first = list else { return false }
		defer { freeifaddrs(list) }

		var pointer: UnsafeMutablePointer<ifaddrs>? = first
		while let current = pointer {
			defer { pointer = current.pointee.ifa_next }

			let name = String(cString: current.pointee.ifa_name)
			guard
				name.hasPrefix("utun"),
				(current.pointee.ifa_flags & UInt32(IFF_UP)) != 0,
				let address = current.pointee.ifa_addr,
				address.pointee.sa_family == UInt8(AF_INET)
			else { continue }

			var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
			let result = getnameinfo(
				address,
				socklen_t(address.pointee.sa_len),
				&host,
				socklen_t(host.count),
				nil,
				0,
				NI_NUMERICHOST
			)
			if result == 0, String(cString: host).hasPrefix(_tunnelPrefix) {
				return true
			}
		}
		return false
	}

	/// Opens LocalDevVPN so it connects and returns. False if nothing opened.
	@discardableResult
	func start() async -> Bool {
		guard let url = URL(string: "\(Self._scheme)://enable?scheme=\(Self._callbackScheme)") else { return false }
		_lastStart = Date()
		guard await UIApplication.shared.open(url) else {
			_lastStart = nil
			return false
		}
		return true
	}

	/// Makes sure the tunnel is up before something uses it. With the setting on
	/// and no tunnel, LocalDevVPN is started and waited for. Returns whether the tunnel is up.
	@discardableResult
	func ensureUp() async -> Bool {
		if Self.isTunnelUp() { return true }
		guard Self.autoStartEnabled, isInstalled else { return false }

		// A start a moment ago is still under way, do not open LocalDevVPN again
		let handingOver = _lastStart.map { Date().timeIntervalSince($0) < 5 } ?? false
		if !handingOver {
			guard await start() else { return false }
		}

		// Only time spent in CaliSign counts, so the VPN permission prompt
		// inside LocalDevVPN does not use up the wait
		var waited = 0.0
		while waited < 15 {
			try? await Task.sleep(nanoseconds: 500_000_000)
			if Task.isCancelled { return false }
			if Self.isTunnelUp() {
				// The heartbeat tried before the tunnel existed
				HeartbeatManager.shared.start(true)
				try? await Task.sleep(nanoseconds: 1_000_000_000)
				return true
			}
			if UIApplication.shared.applicationState == .active { waited += 0.5 }
		}
		return false
	}
}
