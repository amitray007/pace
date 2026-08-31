import Foundation

enum PaceApplicationPaths {
    static var preferencesURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return applicationSupportURL
            .appending(path: "Pace", directoryHint: .isDirectory)
            .appending(path: "preferences.json")
    }
}
