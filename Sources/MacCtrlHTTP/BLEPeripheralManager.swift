import Combine
@preconcurrency import CoreBluetooth
import Foundation
import OSLog
#if SWIFT_PACKAGE
import MacCtrlHTTPCore
#endif

enum BLEPeripheralState: Equatable {
    case initializing
    case disabled
    case bluetoothOff
    case advertising
    case connected
    case authorizing
    case ready
    case authenticationFailed
    case error(String)

    var canControl: Bool {
        if case .ready = self { return true }
        return false
    }
}

enum BLETransportError: Error, LocalizedError {
    case notReady
    case invalidMessage
    case messageTooLarge
    case unsupportedMessage
    case unauthorized
    case tokenMismatch
    case requestTimedOut
    case requestInProgress
    case remoteRejected(String)
    case peripheralUnavailable

    var errorDescription: String? {
        switch self {
        case .notReady: "BLE is not ready"
        case .invalidMessage: "The BLE peer sent an invalid message"
        case .messageTooLarge: "The BLE message exceeds the 1024-byte limit"
        case .unsupportedMessage: "The BLE peer sent an unsupported message"
        case .unauthorized: "Authenticate the BLE connection before sending controls"
        case .tokenMismatch: "The BLE debug token did not match"
        case .requestTimedOut: "The BLE device did not reply in time"
        case .requestInProgress: "A BLE request with this identifier is already pending"
        case .remoteRejected(let reason): "The BLE device rejected the request: \(reason)"
        case .peripheralUnavailable: "CoreBluetooth is unavailable"
        }
    }
}

@MainActor
final class BLEPeripheralManager: NSObject, ObservableObject, @preconcurrency CBPeripheralManagerDelegate {
    static let shared = BLEPeripheralManager()
    private let logger = Logger(subsystem: "com.clocteck.MacCtrlHTTP", category: "BLE")

    @Published private(set) var state: BLEPeripheralState = .initializing
    @Published private(set) var token: String
    @Published private(set) var advertiseOnLaunch: Bool
    @Published private(set) var configurationPath: String

    private enum PendingOperation {
        case tap((Result<TapReceipt, Error>) -> Void)
        case status((Result<ActionStatus, Error>) -> Void)
        case settings((Result<QueueCapacityReceipt, Error>) -> Void)
    }

    private let configurationStore = BLEConfigurationStore()
    private var configuration = BLEConfiguration()
    private var configurationError: String?
    private var peripheralManager: CBPeripheralManager!
    private var service: CBMutableService?
    private var commandCharacteristic: CBMutableCharacteristic?
    private var responseCharacteristic: CBMutableCharacteristic?
    private var serviceAdded = false
    private var serviceAddPending = false
    private var subscribedCentral: CBCentral?
    private var authorizedCentralID: UUID?
    private var authRequestID: String?
    private var assembler = BLEFrameAssembler()
    private var outgoingFrames: [Data] = []
    private var nextMessageID: UInt16 = 1
    private var pendingOperations: [String: PendingOperation] = [:]
    private var pendingTimeouts: [String: DispatchWorkItem] = [:]

    private override init() {
        configurationPath = configurationStore.fileURL.path
        do {
            configuration = try configurationStore.loadOrCreate()
            configurationError = nil
        } catch {
            configurationError = error.localizedDescription
        }
        token = configuration.token
        advertiseOnLaunch = configuration.advertiseOnLaunch
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.peripheralManager.state == .poweredOn else { return }
            self.installServiceIfNeeded()
        }
    }

    func setAdvertisingOnLaunch(_ enabled: Bool) {
        var updated = configuration
        updated.enabled = enabled
        updated.advertiseOnLaunch = enabled
        do {
            try configurationStore.save(updated)
            configuration = updated
            advertiseOnLaunch = enabled
            configurationError = nil
            if enabled {
                if peripheralManager.state == .poweredOn { installServiceIfNeeded() }
                else { state = .initializing }
            } else {
                peripheralManager.stopAdvertising()
                peripheralManager.removeAllServices()
                serviceAdded = false
                serviceAddPending = false
                service = nil
                commandCharacteristic = nil
                responseCharacteristic = nil
                resetSession(error: BLETransportError.notReady)
                state = .disabled
            }
        } catch {
            state = .error("Could not save BLE configuration: \(error.localizedDescription)")
        }
    }

    func updateToken(_ newToken: String) throws {
        guard (1...256).contains(newToken.utf8.count) else {
            throw BLEConfigurationError.invalidToken
        }
        guard newToken != configuration.token else { return }
        var updated = configuration
        updated.token = newToken
        try configurationStore.save(updated)
        configuration = updated
        token = newToken
        configurationError = nil

        if let central = subscribedCentral, authorizedCentralID == central.identifier {
            authorizedCentralID = nil
            state = .authenticationFailed
            sendMessage([
                "version": BLEProtocol.version,
                "type": "auth_failed",
                "request_id": authRequestID ?? "token-updated",
                "error": "token_changed",
            ])
            failPending(with: BLETransportError.unauthorized)
        }
    }

    func sendTap(
        _ button: RemoteButton,
        holdMilliseconds: Int?,
        requestID: String,
        completion: @escaping (Result<TapReceipt, Error>) -> Void
    ) {
        var message: [String: Any] = [
            "version": BLEProtocol.version,
            "type": "tap",
            "request_id": requestID,
            "button": button.rawValue,
        ]
        if let holdMilliseconds { message["hold_ms"] = holdMilliseconds }
        sendRequest(message, requestID: requestID, operation: .tap(completion))
    }

    func fetchStatus(
        requestID: String,
        completion: @escaping (Result<ActionStatus, Error>) -> Void
    ) {
        sendRequest([
            "version": BLEProtocol.version,
            "type": "status",
            "request_id": requestID,
        ], requestID: requestID, operation: .status(completion))
    }

    func setQueueCapacity(
        _ capacity: Int,
        requestID: String,
        completion: @escaping (Result<QueueCapacityReceipt, Error>) -> Void
    ) {
        guard (1...32).contains(capacity) else {
            completion(.failure(BLETransportError.invalidMessage))
            return
        }
        sendRequest([
            "version": BLEProtocol.version,
            "type": "settings",
            "request_id": requestID,
            "queue_capacity": capacity,
        ], requestID: requestID, operation: .settings(completion))
    }

    func stop() {
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        serviceAdded = false
        serviceAddPending = false
        service = nil
        commandCharacteristic = nil
        responseCharacteristic = nil
        resetSession(error: BLETransportError.notReady)
        state = .disabled
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        logger.info("Peripheral manager state: \(peripheral.state.rawValue, privacy: .public)")
        guard configurationError == nil else {
            state = .error("BLE configuration error: \(configurationError!)")
            return
        }
        guard configuration.enabled, configuration.advertiseOnLaunch else {
            state = .disabled
            return
        }
        switch peripheral.state {
        case .poweredOn:
            installServiceIfNeeded()
        case .poweredOff, .resetting:
            serviceAdded = false
            serviceAddPending = false
            resetSession(error: BLETransportError.peripheralUnavailable)
            state = .bluetoothOff
        case .unauthorized:
            state = .error("Bluetooth permission is not authorized")
        case .unsupported:
            state = .error("This Mac does not support Bluetooth LE peripheral mode")
        case .unknown:
            state = .initializing
        @unknown default:
            state = .error("Unknown CoreBluetooth state")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        let errorDescription = error?.localizedDescription ?? "none"
        logger.info("GATT service add completed: \(errorDescription, privacy: .public)")
        if let error {
            serviceAdded = false
            serviceAddPending = false
            state = .error("Could not add the BLE service: \(error.localizedDescription)")
            return
        }
        serviceAdded = true
        serviceAddPending = false
        startAdvertisingIfNeeded()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        let errorDescription = error?.localizedDescription ?? "none"
        logger.info("Advertising start completed: \(errorDescription, privacy: .public)")
        if let error {
            state = .error("Could not start BLE advertising: \(error.localizedDescription)")
        } else if subscribedCentral == nil {
            state = .advertising
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == CBUUID(string: BLEProtocol.commandCharacteristicUUID) else { return }
        logger.info("Central subscribed to command notifications")
        if let existing = subscribedCentral, existing.identifier != central.identifier {
            return
        }
        subscribedCentral = central
        authorizedCentralID = nil
        authRequestID = nil
        assembler.reset()
        outgoingFrames.removeAll(keepingCapacity: true)
        state = .authorizing
        let centralID = central.identifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self,
                  self.subscribedCentral?.identifier == centralID,
                  self.authorizedCentralID == nil else { return }
            self.state = .error("BLE authentication timed out")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard subscribedCentral?.identifier == central.identifier else { return }
        logger.info("Central unsubscribed from command notifications")
        resetSession(error: BLETransportError.notReady)
        state = advertiseOnLaunch ? .initializing : .disabled
        startAdvertisingIfNeeded()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let request = requests.first else { return }
        guard requests.count == 1 else {
            peripheral.respond(to: request, withResult: .unlikelyError)
            return
        }
        guard request.characteristic.uuid == CBUUID(string: BLEProtocol.responseCharacteristicUUID) else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        guard let central = subscribedCentral,
              central.identifier == request.central.identifier else {
            peripheral.respond(to: request, withResult: .insufficientAuthorization)
            return
        }
        guard request.offset == 0, let value = request.value else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }

        peripheral.respond(to: request, withResult: .success)
        do {
            guard let complete = try assembler.append(value) else { return }
            guard let message = try JSONSerialization.jsonObject(with: complete) as? [String: Any] else {
                sendProtocolError(requestID: nil, code: "invalid_json")
                return
            }
            handle(message, from: central)
        } catch BLEProtocolError.messageTooLarge {
            sendProtocolError(requestID: nil, code: "message_too_large")
        } catch {
            sendProtocolError(requestID: nil, code: "invalid_frame")
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        pumpNotifications()
    }

    private func installServiceIfNeeded() {
        guard configurationError == nil,
              configuration.enabled,
              configuration.advertiseOnLaunch,
              peripheralManager.state == .poweredOn else { return }
        guard !serviceAdded else {
            startAdvertisingIfNeeded()
            return
        }
        guard !serviceAddPending else { return }

        let command = CBMutableCharacteristic(
            type: CBUUID(string: BLEProtocol.commandCharacteristicUUID),
            properties: [.notify],
            value: nil,
            permissions: []
        )
        let response = CBMutableCharacteristic(
            type: CBUUID(string: BLEProtocol.responseCharacteristicUUID),
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )
        let service = CBMutableService(type: CBUUID(string: BLEProtocol.serviceUUID), primary: true)
        service.characteristics = [command, response]
        self.service = service
        commandCharacteristic = command
        responseCharacteristic = response
        serviceAddPending = true
        state = .initializing
        logger.info("Adding BLE GATT service")
        peripheralManager.add(service)
    }

    private func startAdvertisingIfNeeded() {
        guard configuration.enabled,
              configuration.advertiseOnLaunch,
              peripheralManager.state == .poweredOn,
              serviceAdded,
              subscribedCentral == nil else { return }
        if peripheralManager.isAdvertising {
            state = .advertising
            return
        }
        logger.info("Starting BLE advertising")
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: BLEProtocol.serviceUUID)],
            CBAdvertisementDataLocalNameKey: "MacCtrlHTTP",
        ])
    }

    private func sendRequest(_ message: [String: Any], requestID: String, operation: PendingOperation) {
        guard state.canControl,
              let central = subscribedCentral,
              authorizedCentralID == central.identifier else {
            fail(operation, with: BLETransportError.notReady)
            return
        }
        guard pendingOperations[requestID] == nil else {
            fail(operation, with: BLETransportError.requestInProgress)
            return
        }
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(requestID, with: .failure(BLETransportError.requestTimedOut))
        }
        pendingOperations[requestID] = operation
        pendingTimeouts[requestID] = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
        sendMessage(message) { [weak self] result in
            if case .failure(let error) = result {
                self?.finish(requestID, with: .failure(error))
            }
        }
    }

    private func handle(_ message: [String: Any], from central: CBCentral) {
        guard let version = message["version"] as? Int,
              version == BLEProtocol.version,
              let type = message["type"] as? String else {
            sendProtocolError(requestID: message["request_id"] as? String, code: "invalid_message")
            return
        }
        let requestID = message["request_id"] as? String
        guard let requestID, (1...64).contains(requestID.utf8.count) else {
            sendProtocolError(requestID: nil, code: "invalid_request_id")
            return
        }

        if type == "auth" {
            guard let suppliedToken = message["token"] as? String else {
                state = .authenticationFailed
                sendMessage([
                    "version": BLEProtocol.version,
                    "type": "auth_failed",
                    "request_id": requestID,
                    "error": "token_required",
                ])
                return
            }
            authRequestID = requestID
            guard constantTimeEqual(suppliedToken, configuration.token) else {
                authorizedCentralID = nil
                state = .authenticationFailed
                sendMessage([
                    "version": BLEProtocol.version,
                    "type": "auth_failed",
                    "request_id": requestID,
                    "error": "token_mismatch",
                ])
                return
            }
            authorizedCentralID = central.identifier
            state = .ready
            sendMessage([
                "version": BLEProtocol.version,
                "type": "auth_ok",
                "request_id": requestID,
            ])
            return
        }

        guard authorizedCentralID == central.identifier else {
            sendProtocolError(requestID: requestID, code: "authentication_required")
            return
        }

        if type == "ack" || type == "status_result" || type == "settings_result" || type == "error" {
            handleReply(message, requestID: requestID)
            return
        }
        sendProtocolError(requestID: requestID, code: "unsupported_message_type")
    }

    private func handleReply(_ message: [String: Any], requestID: String) {
        guard let operation = pendingOperations[requestID] else { return }
        if message["type"] as? String == "error" || message["ok"] as? Bool == false {
            finish(requestID, with: .failure(BLETransportError.remoteRejected(message["error"] as? String ?? "command_rejected")))
            return
        }
        switch operation {
        case .tap:
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let receipt = try? JSONDecoder().decode(TapReceipt.self, from: data) else {
                finish(requestID, with: .failure(BLETransportError.invalidMessage))
                return
            }
            finish(requestID, with: .success(BLEReply.tap(receipt)))
        case .status:
            guard let statusPayload = message["status"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: statusPayload),
                  let status = try? JSONDecoder().decode(ActionStatus.self, from: data) else {
                finish(requestID, with: .failure(BLETransportError.invalidMessage))
                return
            }
            finish(requestID, with: .success(BLEReply.status(status)))
        case .settings:
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  let receipt = try? JSONDecoder().decode(QueueCapacityReceipt.self, from: data) else {
                finish(requestID, with: .failure(BLETransportError.invalidMessage))
                return
            }
            finish(requestID, with: .success(BLEReply.settings(receipt)))
        }
    }

    private enum BLEReply {
        case tap(TapReceipt)
        case status(ActionStatus)
        case settings(QueueCapacityReceipt)
    }

    private func finish(_ requestID: String, with result: Result<BLEReply, Error>) {
        guard let operation = pendingOperations.removeValue(forKey: requestID) else { return }
        pendingTimeouts.removeValue(forKey: requestID)?.cancel()
        complete(operation, with: result)
    }

    private func complete(_ operation: PendingOperation, with result: Result<BLEReply, Error>) {
        switch (operation, result) {
        case let (.tap(completion), .success(.tap(receipt))): completion(.success(receipt))
        case let (.status(completion), .success(.status(status))): completion(.success(status))
        case let (.settings(completion), .success(.settings(receipt))): completion(.success(receipt))
        case let (.tap(completion), .failure(error)): completion(.failure(error))
        case let (.status(completion), .failure(error)): completion(.failure(error))
        case let (.settings(completion), .failure(error)): completion(.failure(error))
        default:
            break
        }
    }

    private func fail(_ operation: PendingOperation, with error: Error) {
        switch operation {
        case .tap(let completion): completion(.failure(error))
        case .status(let completion): completion(.failure(error))
        case .settings(let completion): completion(.failure(error))
        }
    }

    private func sendProtocolError(requestID: String?, code: String) {
        var message: [String: Any] = [
            "version": BLEProtocol.version,
            "type": "error",
            "error": code,
        ]
        if let requestID { message["request_id"] = requestID }
        sendMessage(message)
    }

    private func sendMessage(_ message: [String: Any], completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard commandCharacteristic != nil,
              let central = subscribedCentral,
              peripheralManager.state == .poweredOn else {
            completion?(.failure(BLETransportError.notReady))
            return
        }
        do {
            let payload = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
            guard payload.count <= BLEProtocol.maximumMessageSize else {
                throw BLETransportError.messageTooLarge
            }
            let frames = try BLEProtocol.fragment(
                payload,
                maximumATTValueLength: central.maximumUpdateValueLength,
                messageID: nextMessageID
            )
            nextMessageID &+= 1
            outgoingFrames.append(contentsOf: frames)
            if let completion { completion(.success(())) }
            pumpNotifications()
        } catch {
            completion?(.failure(error))
        }
    }

    private func pumpNotifications() {
        guard let commandCharacteristic,
              let central = subscribedCentral,
              peripheralManager.state == .poweredOn else { return }
        while let frame = outgoingFrames.first {
            let accepted = peripheralManager.updateValue(
                frame,
                for: commandCharacteristic,
                onSubscribedCentrals: [central]
            )
            guard accepted else { return }
            outgoingFrames.removeFirst()
        }
    }

    private func resetSession(error: Error) {
        authorizedCentralID = nil
        subscribedCentral = nil
        authRequestID = nil
        assembler.reset()
        outgoingFrames.removeAll(keepingCapacity: true)
        let pending = pendingOperations
        pendingOperations.removeAll()
        pendingTimeouts.values.forEach { $0.cancel() }
        pendingTimeouts.removeAll()
        for operation in pending.values {
            switch operation {
            case .tap(let completion): completion(.failure(error))
            case .status(let completion): completion(.failure(error))
            case .settings(let completion): completion(.failure(error))
            }
        }
    }

    private func failPending(with error: Error) {
        let pending = pendingOperations
        pendingOperations.removeAll()
        pendingTimeouts.values.forEach { $0.cancel() }
        pendingTimeouts.removeAll()
        for operation in pending.values {
            switch operation {
            case .tap(let completion): completion(.failure(error))
            case .status(let completion): completion(.failure(error))
            case .settings(let completion): completion(.failure(error))
            }
        }
    }

    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}
