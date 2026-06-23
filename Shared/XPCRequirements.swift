import Foundation

enum XPCRequirements {
    static let daemonServiceName = "com.grepguru.lockin.daemon"
    static let agentServiceName = "com.grepguru.lockin.agent"

    static let teamIdentifier = "REPLACE_TEAMID"

    static let daemonClientRequirement = """
    anchor apple generic \
    and (identifier "com.grepguru.lockin" or identifier "com.grepguru.lockin.agent") \
    and certificate leaf[subject.OU] = "\(teamIdentifier)"
    """

    static let agentClientRequirement = """
    anchor apple generic \
    and identifier "com.grepguru.lockin.daemon" \
    and certificate leaf[subject.OU] = "\(teamIdentifier)"
    """
}
