import Combine
import Foundation
#if SWIFT_PACKAGE
import MacCtrlHTTPCore
#endif

@MainActor
final class ControlPanelModel: ObservableObject {
    @Published var token: String
    @Published var deviceAddress: String
    @Published var bufferSize: Int
    @Published var keyDelayMilliseconds: Int
    @Published var revealsToken = false
    @Published private(set) var language: ControllerLanguage
    @Published private(set) var online = false
    @Published private(set) var isCheckingConnection = false
    @Published private(set) var isSyncingSettings = false
    @Published private(set) var connectionMessage: String
    @Published private(set) var actionMessage: String
    @Published private(set) var queueLength: Int?
    @Published private(set) var onboardBufferSize: Int?
    @Published private(set) var syncSucceeded: Bool?

    private let tokenStore: any TokenStore
    private let deviceAddressStore: any DeviceAddressStore
    private let controlSettingsStore: any ControlSettingsStore
    private let transport: any HTTPTransport
    private var lastSavedToken: String
    private var lastSavedDeviceAddress: String
    private var lastAcceptedKeyTime: TimeInterval?

    private static let bufferSizeRange = 1...32
    private static let keyDelayRange = 0...999

    init(
        tokenStore: any TokenStore = UserDefaultsTokenStore(),
        deviceAddressStore: any DeviceAddressStore = UserDefaultsDeviceAddressStore(),
        controlSettingsStore: any ControlSettingsStore = UserDefaultsControlSettingsStore(),
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.tokenStore = tokenStore
        self.deviceAddressStore = deviceAddressStore
        self.controlSettingsStore = controlSettingsStore
        self.transport = transport

        let loadedLanguage = ControllerLanguage.preferred
        self.language = loadedLanguage
        self.actionMessage = loadedLanguage.text(.ready)
        let loadedToken = (try? tokenStore.load()) ?? ""
        let loadedAddress = (try? deviceAddressStore.load()) ?? ""
        self.token = loadedToken
        self.deviceAddress = loadedAddress
        self.bufferSize = Self.clamp(controlSettingsStore.loadBufferSize() ?? 16, to: Self.bufferSizeRange)
        self.keyDelayMilliseconds = Self.clamp(
            controlSettingsStore.loadKeyDelayMilliseconds() ?? 500,
            to: Self.keyDelayRange
        )
        self.lastSavedToken = loadedToken
        self.lastSavedDeviceAddress = loadedAddress

        if loadedAddress.isEmpty {
            self.connectionMessage = loadedLanguage.text(.fillDevice)
        } else if loadedToken.isEmpty {
            self.connectionMessage = loadedLanguage.text(.fillToken)
        } else {
            self.connectionMessage = loadedLanguage.text(.checkingDevice)
        }
    }

    var syncButtonTitle: String {
        if isCheckingConnection || isSyncingSettings { return language.text(.syncing) }
        if syncSucceeded == true { return language.text(.synced) }
        if syncSucceeded == false { return language.text(.retry) }
        return language.text(.sync)
    }

    func setLanguage(_ newLanguage: ControllerLanguage) {
        guard language != newLanguage else { return }
        language = newLanguage
        if deviceAddress.isEmpty {
            connectionMessage = language.text(.fillDevice)
        } else if token.isEmpty {
            connectionMessage = language.text(.fillToken)
        } else if isCheckingConnection || isSyncingSettings {
            connectionMessage = language.text(.checkingDevice)
        } else if online {
            connectionMessage = language.text(.deviceOnline)
        } else {
            connectionMessage = language.text(.waiting)
        }
        actionMessage = online
            ? language.text(.deviceOnlineCapacity, onboardBufferSize ?? bufferSize)
            : language.text(.ready)
    }

    func saveToken(_ newValue: String) {
        token = newValue
        let changed = newValue != lastSavedToken
        if changed {
            invalidateConnection(message: language.text(.tokenModified))
        }
        do {
            try tokenStore.save(newValue)
            lastSavedToken = newValue
            if newValue.isEmpty {
                invalidateConnection(message: language.text(.fillToken))
            }
        } catch {
            invalidateConnection(message: language.text(.tokenSaveFailed))
        }
    }

    func saveDeviceAddress(_ newValue: String) {
        deviceAddress = newValue
        let changed = newValue != lastSavedDeviceAddress
        if changed {
            invalidateConnection(message: language.text(.addressChanged))
        }
        do {
            try deviceAddressStore.save(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            lastSavedDeviceAddress = newValue
            if newValue.isEmpty {
                invalidateConnection(message: language.text(.fillDevice))
            }
        } catch {
            invalidateConnection(message: language.text(.addressSaveFailed))
        }
    }

    func saveBufferSize(_ value: Int) {
        let bounded = Self.clamp(value, to: Self.bufferSizeRange)
        if bufferSize != bounded { bufferSize = bounded }
        controlSettingsStore.saveBufferSize(bounded)
        syncSucceeded = nil
        if let onboardBufferSize, onboardBufferSize != bounded {
            actionMessage = language.text(.bufferPending)
        }
    }

    func adjustBufferSize(by delta: Int) {
        saveBufferSize(bufferSize + delta)
    }

    func saveKeyDelay(_ value: Int) {
        let bounded = Self.clamp(value, to: Self.keyDelayRange)
        if keyDelayMilliseconds != bounded { keyDelayMilliseconds = bounded }
        controlSettingsStore.saveKeyDelayMilliseconds(bounded)
    }

    func checkConnection() {
        guard !isCheckingConnection, !isSyncingSettings else { return }
        guard let client = makeClient() else {
            online = false
            connectionMessage = token.isEmpty ? language.text(.fillToken) : language.text(.invalidAddress)
            return
        }

        isCheckingConnection = true
        connectionMessage = language.text(.checkingDevice)
        Task {
            defer { isCheckingConnection = false }
            do {
                let status = try await client.status()
                apply(status)
                online = true
                connectionMessage = language.text(.deviceOnline)
                actionMessage = status.queueCapacity.map { language.text(.deviceOnlineCapacity, $0) }
                    ?? language.text(.serviceUpdate)
            } catch {
                online = false
                onboardBufferSize = nil
                connectionMessage = localizedMessage(for: error)
                actionMessage = localizedMessage(for: error)
            }
        }
    }

    func syncDeviceSettings() {
        guard !isCheckingConnection, !isSyncingSettings else { return }
        guard let client = makeClient() else {
            online = false
            syncSucceeded = false
            connectionMessage = token.isEmpty ? language.text(.fillToken) : language.text(.invalidAddress)
            actionMessage = connectionMessage
            return
        }

        syncSucceeded = nil
        isSyncingSettings = true
        actionMessage = language.text(.settingsSyncing)
        Task {
            defer { isSyncingSettings = false }
            var connected = false
            do {
                let status = try await client.status()
                connected = true
                apply(status)
                online = true

                guard let currentCapacity = status.queueCapacity else {
                    syncSucceeded = false
                    connectionMessage = language.text(.onboardUpdateRequired)
                    actionMessage = language.text(.serviceNoBufferSync)
                    return
                }

                let requestedCapacity = bufferSize
                if currentCapacity != requestedCapacity {
                    let receipt = try await client.setQueueCapacity(requestedCapacity)
                    onboardBufferSize = receipt.queueCapacity
                    queueLength = receipt.queueLength ?? status.queueLength
                    guard bufferSize == requestedCapacity,
                          receipt.queueCapacity == requestedCapacity else {
                        syncSucceeded = false
                        actionMessage = language.text(.bufferChanged)
                        return
                    }
                }

                syncSucceeded = true
                connectionMessage = language.text(.deviceOnline)
                actionMessage = currentCapacity == requestedCapacity
                    ? language.text(.bufferSynced)
                    : language.text(.bufferUploaded)
            } catch {
                syncSucceeded = false
                if connected {
                    online = true
                    connectionMessage = language.text(.deviceOnline)
                } else {
                    online = false
                    onboardBufferSize = nil
                    connectionMessage = localizedMessage(for: error)
                }
                actionMessage = localizedMessage(for: error)
            }
        }
    }

    func send(
        _ button: RemoteButton,
        holdMilliseconds: Int? = nil,
        isAutoRepeat: Bool = false
    ) {
        guard !token.isEmpty else {
            actionMessage = language.text(.missingAuth)
            return
        }
        guard let client = makeClient() else {
            actionMessage = language.text(.invalidAddress)
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let minimumInterval = TimeInterval(keyDelayMilliseconds) / 1_000
        if isAutoRepeat,
           holdMilliseconds == nil,
           minimumInterval > 0,
           let lastAcceptedKeyTime,
           now - lastAcceptedKeyTime < minimumInterval {
            actionMessage = language.text(.repeatLimited)
            return
        }
        lastAcceptedKeyTime = now

        let buttonTitle = button.title(in: language)
        actionMessage = holdMilliseconds.map {
            language.text(.sendingHold, buttonTitle, $0)
        } ?? language.text(.sendingTap, buttonTitle)
        Task {
            do {
                let receipt = try await client.tap(button, holdMilliseconds: holdMilliseconds)
                online = true
                if receipt.duplicate == true {
                    actionMessage = language.text(.duplicate, buttonTitle)
                } else if let holdMilliseconds {
                    actionMessage = language.text(.holdSent, buttonTitle, holdMilliseconds)
                } else {
                    actionMessage = language.text(.tapSent, buttonTitle)
                }
            } catch {
                online = false
                connectionMessage = localizedMessage(for: error)
                actionMessage = localizedMessage(for: error)
            }
        }
    }

    private func apply(_ status: ActionStatus) {
        queueLength = status.queueLength
        onboardBufferSize = status.queueCapacity
    }

    private func invalidateConnection(message: String) {
        online = false
        queueLength = nil
        onboardBufferSize = nil
        syncSucceeded = nil
        actionMessage = language.text(.ready)
        connectionMessage = message
    }

    private func makeClient() -> ActionCtrlHTTPClient? {
        guard let baseURL = Self.deviceURL(from: deviceAddress), !token.isEmpty else { return nil }
        return ActionCtrlHTTPClient(baseURL: baseURL, token: token, transport: transport)
    }

    private func localizedMessage(for error: Error) -> String {
        guard let error = error as? ActionClientError else {
            return language.text(.requestFailed)
        }
        return switch error {
        case .invalidDeviceAddress: language.text(.invalidDeviceAddress)
        case .invalidHoldDuration: language.text(.invalidHoldDuration)
        case .invalidResponse: language.text(.invalidResponse)
        case .rejected(let statusCode):
            switch statusCode {
            case 401: language.text(.tokenMismatch)
            case 409: language.text(.serviceBusy)
            case 429: language.text(.queueFull)
            case 503: language.text(.serviceNotReady)
            case 404: language.text(.unsupportedBuffer)
            default: language.text(.deviceRejected, statusCode)
            }
        }
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func deviceURL(from address: String) -> URL? {
        var host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("http://") {
            host.removeFirst("http://".count)
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !host.isEmpty,
              !host.contains("/"),
              !host.contains(where: \.isWhitespace),
              let url = URL(string: "http://\(host)"),
              url.scheme == "http",
              url.host != nil,
              url.query == nil,
              url.fragment == nil else {
            return nil
        }
        return url
    }
}
