import Foundation

/// Everything a user can configure, bundled for export/import as JSON.
public struct SettingsExport: Sendable, Codable {
    public var version: Int
    public var settings: AppSettings
    public var ignoredApps: [IgnoredApp]
    public var ignoreRegexRules: [IgnoreRegexRule]
    public var appPrivacyRules: [AppPrivacyRule]

    public init(
        version: Int = SettingsCodec.formatVersion,
        settings: AppSettings,
        ignoredApps: [IgnoredApp] = [],
        ignoreRegexRules: [IgnoreRegexRule] = [],
        appPrivacyRules: [AppPrivacyRule] = []
    ) {
        self.version = version
        self.settings = settings
        self.ignoredApps = ignoredApps
        self.ignoreRegexRules = ignoreRegexRules
        self.appPrivacyRules = appPrivacyRules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? SettingsCodec.formatVersion
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        ignoredApps = try container.decodeIfPresent([IgnoredApp].self, forKey: .ignoredApps) ?? []
        ignoreRegexRules = try container.decodeIfPresent([IgnoreRegexRule].self, forKey: .ignoreRegexRules) ?? []
        appPrivacyRules = try container.decodeIfPresent([AppPrivacyRule].self, forKey: .appPrivacyRules) ?? []
    }
}

public enum SettingsCodecError: Error {
    case unsupportedVersion(Int)
}

public enum SettingsCodec {
    public static let formatVersion = 1

    public static func encode(_ export: SettingsExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    public static func decode(_ data: Data) throws -> SettingsExport {
        let export = try JSONDecoder().decode(SettingsExport.self, from: data)
        guard export.version <= formatVersion else {
            throw SettingsCodecError.unsupportedVersion(export.version)
        }
        return export
    }
}
