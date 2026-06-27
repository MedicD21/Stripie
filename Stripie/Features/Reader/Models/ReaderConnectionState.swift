import StripeTerminalSDK

enum ReaderConnectionState: Equatable {
    case disconnected
    case discovering
    case connecting
    case connected(Reader)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayTitle: String {
        switch self {
        case .disconnected: return "No Reader"
        case .discovering:  return "Searching…"
        case .connecting:   return "Connecting…"
        case .connected(let reader): return reader.label ?? "iPhone (Tap to Pay)"
        }
    }

    var statusColor: String {
        switch self {
        case .connected:    return "readerConnected"
        case .discovering,
             .connecting:   return "readerSearching"
        case .disconnected: return "readerDisconnected"
        }
    }
}
