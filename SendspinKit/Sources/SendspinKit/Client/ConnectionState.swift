// ABOUTME: Represents the connection state of the Sendspin client
// ABOUTME: Used to track connection lifecycle from disconnected to connected

import Foundation

/// Connection state of the Sendspin client
public enum ConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case error(String) // Store error description instead of Error to maintain Sendable
}

extension ConnectionState: Equatable {
    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case let (.error(lhsError), .error(rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}
