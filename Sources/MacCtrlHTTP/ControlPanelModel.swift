import Combine
import Foundation
#if SWIFT_PACKAGE
import MacCtrlHTTPCore
#endif

@MainActor
final class ControlPanelModel: ObservableObject {
    @Published var token: String
    @Published var deviceAddress: String
    @Published var bleToken: String
    @Published var bufferSize: Int
    @Published var keyDelayMilliseconds: Int
    @Published var transportMode: ControlTransportMode
    @Published var revealsToken = false
    @Published private(set) var language: ControllerLanguage
    @Published private(set) var online = false
    @Published private(set) var httpOnline = false
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
    let bleManager: BLEPeripheralManager
    private var lastSavedToken: String
    private var lastSavedDeviceAddress: String
    private var lastAcceptedKeyTime: TimeInterval?

    private struct QueueSyncResult {
        let status: ActionStatus
        let capacity: Int?
        let queueLength: Int?
        let uploaded: Bool
    }

    private enum ModelTransportError: Error {
        case missingToken
    }

    private static let bufferSizeRange = 1...32
    private static let keyDelayRange = 0...999

    init(
        tokenStore: any TokenStore = UserDefaultsTokenStore(),
        deviceAddressStore: any DeviceAddressStore = UserDefaultsDeviceAddressStore(),
        controlSettingsStore: any ControlSettingsStore = UserDefaultsControlSettingsStore(),
        transport: any HTTPTransport = URLSessionTransport(),
        bleManager: BLEPeripheralManager? = nil
    ) {
        self.tokenStore = tokenStore
        self.deviceAddressStore = deviceAddressStore
        self.controlSettingsStore = controlSettingsStore
        self.transport = transport
        let bleManager = bleManager ?? BLEPeripheralManager.shared
        self.bleManager = bleManager

        let loadedLanguage = ControllerLanguage.preferred
        self.language = loadedLanguage
        self.actionMessage = loadedLanguage.text(.ready)
        let loadedToken = (try? tokenStore.load()) ?? ""
        let loadedAddress = (try? deviceAddressStore.load()) ?? ""
        let loadedTransport = UserDefaults.standard.string(forKey: "controlTransportMode")
            .flatMap(ControlTransportMode.init(rawValue:)) ?? .auto
        self.token = loadedToken
        self.deviceAddress = loadedAddress
        self.bleToken = bleManager.token
        self.transportMode = loadedTransport
        self.bufferSize = Self.clamp(controlSettingsStore.loadBufferSize() ?? 16, to: Self.bufferSizeRange)
        self.keyDelayMilliseconds = Self.clamp(
            controlSettingsStore.loadKeyDelayMilliseconds() ?? 500,
            to: Self.keyDelayRange
        )
        self.lastSavedToken = loadedToken
        self.lastSavedDeviceAddress = loadedAddress

        if loadedTransport == .ble {
            self.connectionMessage = loadedLanguage.text(.checkingDevice)
        } else if loadedAddress.isEmpty {
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
        if transportMode == .ble {
            connectionMessage = bleStateMessage
        } else if deviceAddress.isEmpty {
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

    func setTransportMode(_ mode: ControlTransportMode) {
        guard transportMode != mode else { return }
        transportMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "controlTransportMode")
        syncSucceeded = nil
        refreshTransportStatus()
        checkConnection()
    }

    func saveBLEToken(_ value: String) {
        do {
            try bleManager.updateToken(value)
            bleToken = value
            actionMessage = language.text(.bleTokenSaved)
        } catch {
            actionMessage = error is BLEConfigurationError
                ? language.text(.invalidBLEToken)
                : language.text(.bleConfigError)
        }
    }

    func setBLEAdvertising(_ enabled: Bool) {
        bleManager.setAdvertisingOnLaunch(enabled)
        refreshTransportStatus()
    }

    func refreshTransportStatus() {
        switch transportMode {
        case .http:
            online = httpOnline
        case .ble:
            online = bleManager.state.canControl
        case .auto:
            online = httpOnline || bleManager.state.canControl
        }
        if online {
            connectionMessage = language.text(.deviceOnline)
        } else if transportMode == .ble {
            connectionMessage = bleStateMessage
        } else if transportMode == .auto && !httpOnline {
            connectionMessage = bleManager.state.canControl ? bleStateMessage : language.text(.waiting)
        }
    }

    var bleStateMessage: String {
        switch bleManager.state {
        case .initializing: language.text(.connecting)
        case .disabled: language.text(.bleDisabled)
        case .bluetoothOff: language.text(.bleBluetoothOff)
        case .advertising: language.text(.bleAdvertising)
        case .connected: language.text(.bleConnected)
        case .authorizing: language.text(.bleAuthorizing)
        case .ready: language.text(.bleReady)
        case .authenticationFailed: language.text(.bleAuthenticationFailed)
        case .error(let message): language.text(.bleError, message)
        }
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
        let client = transportMode == .ble ? nil : makeClient(timeoutInterval: transportMode == .auto ? 1.5 : 60)
        let checkHTTP = transportMode != .ble
        let checkBLE = transportMode != .http && bleManager.state.canControl
        if transportMode == .http, client == nil {
            httpOnline = false
            refreshTransportStatus()
            connectionMessage = token.isEmpty ? language.text(.fillToken) : language.text(.invalidAddress)
            return
        }
        if transportMode == .ble, !bleManager.state.canControl {
            online = false
            connectionMessage = bleStateMessage
            return
        }

        isCheckingConnection = true
        connectionMessage = language.text(.checkingDevice)
        Task {
            defer { isCheckingConnection = false }
            var httpStatus: ActionStatus?
            var httpError: Error?
            var bleStatus: ActionStatus?
            var bleError: Error?

            if checkHTTP {
                if let client {
                    do { httpStatus = try await client.status() }
                    catch { httpError = error }
                } else {
                    httpError = token.isEmpty ? ModelTransportError.missingToken : ActionClientError.invalidDeviceAddress
                }
            }
            if checkBLE {
                do { bleStatus = try await requestBLEStatus() }
                catch { bleError = error }
            }

            httpOnline = httpStatus != nil
            if let httpStatus { apply(httpStatus) }
            switch transportMode {
            case .http:
                online = httpStatus != nil
            case .ble:
                online = bleStatus != nil
                if let bleStatus { apply(bleStatus) }
            case .auto:
                online = httpStatus != nil || bleStatus != nil
                if let bleStatus, httpStatus == nil { apply(bleStatus) }
            }
            if online {
                connectionMessage = language.text(.deviceOnline)
                actionMessage = (bleStatus ?? httpStatus)?.queueCapacity.map {
                    language.text(.deviceOnlineCapacity, $0)
                } ?? language.text(.serviceUpdate)
            } else {
                let error = transportMode == .ble ? (bleError ?? BLETransportError.notReady) : (httpError ?? bleError ?? ActionClientError.invalidResponse)
                connectionMessage = localizedMessage(for: error)
                actionMessage = localizedMessage(for: error)
                if httpStatus == nil { onboardBufferSize = nil }
            }
        }
    }

    func syncDeviceSettings() {
        guard !isCheckingConnection, !isSyncingSettings else { return }
        syncSucceeded = nil
        isSyncingSettings = true
        actionMessage = language.text(.settingsSyncing)
        Task {
            defer { isSyncingSettings = false }
            do {
                let requestedCapacity = bufferSize
                let result = try await syncQueueCapacity(requestedCapacity)
                apply(result.status)
                onboardBufferSize = result.capacity
                if let queueLength = result.queueLength { self.queueLength = queueLength }
                refreshTransportStatus()
                guard bufferSize == requestedCapacity,
                      result.capacity == requestedCapacity else {
                    syncSucceeded = false
                    actionMessage = language.text(.bufferChanged)
                    return
                }
                syncSucceeded = true
                connectionMessage = language.text(.deviceOnline)
                actionMessage = result.uploaded ? language.text(.bufferUploaded) : language.text(.bufferSynced)
            } catch {
                syncSucceeded = false
                refreshTransportStatus()
                if !online { connectionMessage = localizedMessage(for: error) }
                actionMessage = localizedMessage(for: error)
            }
        }
    }

    func send(
        _ button: RemoteButton,
        holdMilliseconds: Int? = nil,
        isAutoRepeat: Bool = false
    ) {
        guard transportMode != .http || !token.isEmpty else {
            actionMessage = language.text(.missingAuth)
            return
        }
        if transportMode == .ble && !bleManager.state.canControl {
            actionMessage = bleStateMessage
            return
        }
        if transportMode == .http && makeClient() == nil {
            actionMessage = language.text(.invalidAddress)
            return
        }
        if transportMode == .auto && makeClient(timeoutInterval: 1.5) == nil && !bleManager.state.canControl {
            actionMessage = token.isEmpty ? language.text(.missingAuth) : language.text(.invalidAddress)
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
        let requestID = "mac-\(UUID().uuidString.lowercased())"
        Task {
            do {
                let receipt = try await performTap(
                    button,
                    holdMilliseconds: holdMilliseconds,
                    requestID: requestID
                )
                refreshTransportStatus()
                if receipt.duplicate == true {
                    actionMessage = language.text(.duplicate, buttonTitle)
                } else if let holdMilliseconds {
                    actionMessage = language.text(.holdSent, buttonTitle, holdMilliseconds)
                } else {
                    actionMessage = language.text(.tapSent, buttonTitle)
                }
            } catch {
                refreshTransportStatus()
                connectionMessage = localizedMessage(for: error)
                actionMessage = localizedMessage(for: error)
            }
        }
    }

    private func apply(_ status: ActionStatus) {
        queueLength = status.queueLength
        onboardBufferSize = status.queueCapacity
    }

    private func syncQueueCapacity(_ requestedCapacity: Int) async throws -> QueueSyncResult {
        func syncOverHTTP() async throws -> QueueSyncResult {
            guard let client = makeClient(timeoutInterval: transportMode == .auto ? 1.5 : 8) else {
                throw token.isEmpty ? ModelTransportError.missingToken : ActionClientError.invalidDeviceAddress
            }
            let status: ActionStatus
            do {
                status = try await client.status()
                httpOnline = true
            } catch {
                httpOnline = false
                throw error
            }
            guard let currentCapacity = status.queueCapacity else {
                throw ActionClientError.rejected(statusCode: 404)
            }
            guard currentCapacity != requestedCapacity else {
                httpOnline = true
                return QueueSyncResult(
                    status: status,
                    capacity: currentCapacity,
                    queueLength: status.queueLength,
                    uploaded: false
                )
            }
            let receipt = try await client.setQueueCapacity(requestedCapacity)
            httpOnline = true
            return QueueSyncResult(
                status: status,
                capacity: receipt.queueCapacity,
                queueLength: receipt.queueLength ?? status.queueLength,
                uploaded: receipt.persisted == true
            )
        }

        func syncOverBLE() async throws -> QueueSyncResult {
            let status = try await requestBLEStatus()
            guard let currentCapacity = status.queueCapacity else {
                throw ActionClientError.rejected(statusCode: 404)
            }
            guard currentCapacity != requestedCapacity else {
                return QueueSyncResult(
                    status: status,
                    capacity: currentCapacity,
                    queueLength: status.queueLength,
                    uploaded: false
                )
            }
            let requestID = "mac-ble-\(UUID().uuidString.lowercased())"
            let receipt = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QueueCapacityReceipt, Error>) in
                bleManager.setQueueCapacity(requestedCapacity, requestID: requestID) { result in
                    continuation.resume(with: result)
                }
            }
            return QueueSyncResult(
                status: status,
                capacity: receipt.queueCapacity,
                queueLength: receipt.queueLength ?? status.queueLength,
                uploaded: receipt.persisted == true
            )
        }

        switch transportMode {
        case .http:
            return try await syncOverHTTP()
        case .ble:
            return try await syncOverBLE()
        case .auto:
            if httpOnline, makeClient(timeoutInterval: 1.5) != nil {
                do {
                    return try await syncOverHTTP()
                } catch {
                    if let clientError = error as? ActionClientError,
                       case .rejected = clientError {
                        throw error
                    }
                    httpOnline = false
                    guard bleManager.state.canControl else { throw error }
                    return try await syncOverBLE()
                }
            }
            if bleManager.state.canControl { return try await syncOverBLE() }
            return try await syncOverHTTP()
        }
    }

    private func performTap(
        _ button: RemoteButton,
        holdMilliseconds: Int?,
        requestID: String
    ) async throws -> TapReceipt {
        func sendOverHTTP() async throws -> TapReceipt {
            guard let client = makeClient(timeoutInterval: transportMode == .auto ? 1.5 : 60) else {
                throw token.isEmpty ? ModelTransportError.missingToken : ActionClientError.invalidDeviceAddress
            }
            do {
                let receipt = try await client.tap(button, holdMilliseconds: holdMilliseconds, requestID: requestID)
                httpOnline = true
                return receipt
            } catch let error as ActionClientError {
                if case .rejected = error { httpOnline = true }
                else { httpOnline = false }
                throw error
            } catch {
                httpOnline = false
                throw error
            }
        }

        func sendOverBLE() async throws -> TapReceipt {
            guard bleManager.state.canControl else { throw BLETransportError.notReady }
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TapReceipt, Error>) in
                bleManager.sendTap(button, holdMilliseconds: holdMilliseconds, requestID: requestID) { result in
                    continuation.resume(with: result)
                }
            }
        }

        switch transportMode {
        case .http:
            return try await sendOverHTTP()
        case .ble:
            return try await sendOverBLE()
        case .auto:
            if httpOnline {
                do {
                    return try await sendOverHTTP()
                } catch {
                    if let clientError = error as? ActionClientError,
                       case .rejected = clientError {
                        throw error
                    }
                    httpOnline = false
                    guard bleManager.state.canControl else { throw error }
                    return try await sendOverBLE()
                }
            }
            if bleManager.state.canControl { return try await sendOverBLE() }
            return try await sendOverHTTP()
        }
    }

    private func requestBLEStatus() async throws -> ActionStatus {
        let requestID = "mac-ble-status-\(UUID().uuidString.lowercased())"
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ActionStatus, Error>) in
            bleManager.fetchStatus(requestID: requestID) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func invalidateConnection(message: String) {
        httpOnline = false
        queueLength = nil
        onboardBufferSize = nil
        syncSucceeded = nil
        actionMessage = language.text(.ready)
        connectionMessage = message
        refreshTransportStatus()
    }

    private func makeClient(timeoutInterval: TimeInterval = 60) -> ActionCtrlHTTPClient? {
        guard let baseURL = Self.deviceURL(from: deviceAddress), !token.isEmpty else { return nil }
        return ActionCtrlHTTPClient(
            baseURL: baseURL,
            token: token,
            transport: transport,
            timeoutInterval: timeoutInterval
        )
    }

    private func localizedMessage(for error: Error) -> String {
        if error is ModelTransportError {
            return language.text(.missingAuth)
        }
        if let error = error as? BLETransportError {
            switch error {
            case .notReady, .peripheralUnavailable: return bleStateMessage
            case .tokenMismatch, .unauthorized: return language.text(.bleAuthenticationFailed)
            default: return language.text(.requestFailed)
            }
        }
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
