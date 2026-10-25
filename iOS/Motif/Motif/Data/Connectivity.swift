import Network

/// Keep transport availability separate from HTTP/auth errors. Foregrounding
/// also refreshes the store, even when this reachability flag did not change.
@MainActor
final class Connectivity {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Motif.connectivity")
    func start(_ store: LibraryStore) {
        monitor.pathUpdateHandler = { [weak store] path in
            let online = path.status == .satisfied
            Task { @MainActor in await store?.setOnline(online) }
        }
        monitor.start(queue: queue)
    }
    func stop() { monitor.cancel() }
}
