/// This is a block-only experiment, not a VPN admission policy.
/// Never infer VPN safety from this decision or from an interface name.
public enum ProbePolicy {
    public static let signingIdentifier = "org.vpnguard.prototype.probe"

    public enum Decision: Equatable {
        case blockProbe
        case allowUnrelated
        case unresolvedIdentity
    }

    public static func evaluate(appID: String?, processID: String?) -> Decision {
        // Check both the responsible application and the actual socket owner.
        if appID == signingIdentifier || processID == signingIdentifier {
            return .blockProbe
        }
        guard let appID, !appID.isEmpty, let processID, !processID.isEmpty else {
            return .unresolvedIdentity
        }
        return .allowUnrelated
    }
}

