import Foundation

struct AppUpdateInfo: Identifiable, Equatable {
    let id = UUID()
    let version: String
    let storeURL: URL
}

enum AppUpdateService {
    private static let appID = "6763877227"
    private static let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=\(appID)&country=cn")!
    static let appStoreURL = URL(string: "itms-apps://apps.apple.com/app/id\(appID)")!

    static func availableUpdate() async -> AppUpdateInfo? {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: lookupURL)
            let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            guard let app = response.results.first,
                  isVersion(app.version, newerThan: currentVersion) else {
                return nil
            }

            let storeURL = URL(string: app.trackViewUrl) ?? appStoreURL
            return AppUpdateInfo(version: app.version, storeURL: storeURL)
        } catch {
            return nil
        }
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let left = versionParts(candidate)
        let right = versionParts(current)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { part in
                let numericPrefix = part.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
            }
    }
}

private struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreLookupResult]
}

private struct AppStoreLookupResult: Decodable {
    let version: String
    let trackViewUrl: String
}
