import Foundation
@preconcurrency import WatchConnectivity

final class DeviceConnectivityCoordinator: NSObject, WCSessionDelegate, @unchecked Sendable {
    private enum Key {
        static let snapshot = "snapshot"
        static let command = "command"
        static let refresh = "refresh"
        static let modelStatsPeriod = "modelStatsPeriod"
    }

    var onSnapshot: (@MainActor @Sendable (DeviceSyncSnapshot) async -> Void)?
    var onRefreshRequest: (@MainActor @Sendable (String?) async -> Void)?
    var onStatusChange: (@MainActor @Sendable (Bool, Bool) -> Void)?

    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    func activate() {
        session?.delegate = self
        session?.activate()
        reportStatus()
    }

    func publish(_ snapshot: DeviceSyncSnapshot) {
#if os(iOS)
        guard let session, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext([Key.snapshot: data])
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
        }
        reportStatus()
#endif
    }

    func requestRefresh(modelStatsPeriod: String?) {
#if os(watchOS)
        guard let session else { return }
        var message: [String: Any] = [Key.command: Key.refresh]
        if let modelStatsPeriod {
            message[Key.modelStatsPeriod] = modelStatsPeriod
        }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(message)
        }
        reportStatus()
#endif
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        reportStatus()
#if os(watchOS)
        receiveSnapshot(from: session.receivedApplicationContext)
#endif
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        reportStatus()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receiveSnapshot(from: applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        receiveSnapshotData(messageData)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receiveCommand(from: message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receiveCommand(from: userInfo)
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        reportStatus()
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        reportStatus()
    }
#endif

    private func receiveSnapshot(from context: [String: Any]) {
        guard let data = context[Key.snapshot] as? Data else { return }
        receiveSnapshotData(data)
    }

    private func receiveSnapshotData(_ data: Data) {
#if os(watchOS)
        guard let snapshot = try? JSONDecoder().decode(DeviceSyncSnapshot.self, from: data),
              snapshot.schemaVersion == DeviceSyncSnapshot.currentSchemaVersion else { return }
        Task { @MainActor [weak self] in
            await self?.onSnapshot?(snapshot)
        }
#endif
    }

    private func receiveCommand(from message: [String: Any]) {
#if os(iOS)
        guard message[Key.command] as? String == Key.refresh else { return }
        let period = message[Key.modelStatsPeriod] as? String
        Task { @MainActor [weak self] in
            await self?.onRefreshRequest?(period)
        }
#endif
    }

    private func reportStatus() {
        guard let session else { return }
#if os(iOS)
        let installed = session.isWatchAppInstalled
#else
        let installed = session.isCompanionAppInstalled
#endif
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.onStatusChange?(installed, reachable)
        }
    }
}
