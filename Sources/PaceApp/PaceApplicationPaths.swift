import Foundation

enum PaceApplicationPaths {
    private static var applicationSupportURL: URL {
        if let override = ProcessInfo.processInfo.environment[
            "PACE_APPLICATION_SUPPORT_DIRECTORY",
        ], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory).standardizedFileURL
        }
        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    static var preferencesURL: URL {
        applicationSupportURL
            .appending(path: "Pace", directoryHint: .isDirectory)
            .appending(path: "preferences.json")
    }

    static var stateURL: URL {
        applicationSupportURL
            .appending(path: "Pace", directoryHint: .isDirectory)
            .appending(path: "state.json")
    }
}
