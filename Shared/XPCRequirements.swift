import Foundation
import Security

enum XPCRequirements {
    static let daemonServiceName = "com.humblebee.lockin.daemon"
    static let agentServiceName = "com.humblebee.lockin.agent"

    // resolved from this binary's own signing team; placeholder fallback fails closed (no cert matches it)
    static let teamIdentifier: String = ownTeamIdentifier()
        ?? (Bundle.main.object(forInfoDictionaryKey: "LOCKIN_TEAM_ID") as? String)
        ?? "REPLACE_TEAMID"

    // invariant: identifiers must match the binaries' ACTUAL codesign identifiers. The app is a bundle
    // (com.humblebee.lockin); the daemon/agent are command-line tools signed as lockind / lockin-agent.
    static var daemonClientRequirement: String {
        """
        anchor apple generic \
        and (identifier "com.humblebee.lockin" or identifier "lockin-agent") \
        and certificate leaf[subject.OU] = "\(teamIdentifier)"
        """
    }

    static var agentClientRequirement: String {
        """
        anchor apple generic \
        and identifier "lockind" \
        and certificate leaf[subject.OU] = "\(teamIdentifier)"
        """
    }

    private static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let team = dict[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else { return nil }
        return team
    }
}
