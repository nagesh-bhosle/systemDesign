//
//  LaunchAtLoginHelper.swift
//  VoiceDictation
//
//  Launch at login via SMAppService (macOS 13+).
//

import Foundation
import ServiceManagement
import os

enum LaunchAtLoginHelper {
    private static let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "LaunchAtLogin")

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        guard #available(macOS 13.0, *) else {
            return .failure(LaunchAtLoginError.unsupported)
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            logger.warning("Launch at login failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Launch at login requires macOS 13 or later."
        }
    }
}
