import Foundation
import Network

enum PlaybackNetwork: Sendable {
    case cellular, wifi

    /// Wait for the initial path rather than reading the monitor's uninitialized currentPath.
    static func current() async -> PlaybackNetwork {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.pathUpdateHandler = nil
                monitor.cancel()
                let network: PlaybackNetwork = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) ? .wifi : .cellular
                continuation.resume(returning: network)
            }
            monitor.start(queue: DispatchQueue(label: "com.nembx.JLive.playback-network"))
        }
    }
}
