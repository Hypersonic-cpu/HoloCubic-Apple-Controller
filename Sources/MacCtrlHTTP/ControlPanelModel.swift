import Combine
import Foundation
import MacCtrlHTTPCore

@MainActor
final class ControlPanelModel: ObservableObject {
    @Published var token: String
    @Published var deviceAddress: String
    @Published var bufferSize: Int
    @Published var keyDelayMilliseconds: Int
    @Published private(set) var online = false
    @Published private(set) var isCheckingConnection = false
    @Published private(set) var isSyncingSettings = false
    @Published private(set) var connectionMessage: String
    @Published private(set) var actionMessage = "准备就绪"
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
            self.connectionMessage = "填写设备 IP 后同步"
        } else if loadedToken.isEmpty {
            self.connectionMessage = "填写 Token 后同步"
        } else {
            self.connectionMessage = "正在检查设备连接…"
        }
    }

    var syncButtonTitle: String {
        if isCheckingConnection || isSyncingSettings { return "同步中" }
        if syncSucceeded == true { return "已同步" }
        if syncSucceeded == false { return "重试" }
        return "同步"
    }

    func saveToken(_ newValue: String) {
        token = newValue
        let changed = newValue != lastSavedToken
        if changed {
            invalidateConnection(message: "Token 已修改，待检查")
        }
        do {
            try tokenStore.save(newValue)
            lastSavedToken = newValue
            if newValue.isEmpty {
                invalidateConnection(message: "填写 Token 后同步")
            }
        } catch {
            invalidateConnection(message: "保存 Token 失败")
        }
    }

    func saveDeviceAddress(_ newValue: String) {
        deviceAddress = newValue
        let changed = newValue != lastSavedDeviceAddress
        if changed {
            invalidateConnection(message: "设备地址已修改，待检查")
        }
        do {
            try deviceAddressStore.save(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            lastSavedDeviceAddress = newValue
            if newValue.isEmpty {
                invalidateConnection(message: "填写设备 IP 后同步")
            }
        } catch {
            invalidateConnection(message: "保存设备 IP 失败")
        }
    }

    func saveBufferSize(_ value: Int) {
        let bounded = Self.clamp(value, to: Self.bufferSizeRange)
        if bufferSize != bounded { bufferSize = bounded }
        controlSettingsStore.saveBufferSize(bounded)
        syncSucceeded = nil
        if let onboardBufferSize, onboardBufferSize != bounded {
            actionMessage = "BUFFER SIZE 待同步"
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
            connectionMessage = token.isEmpty ? "填写 Token 后同步" : "检查设备 IP 格式"
            return
        }

        isCheckingConnection = true
        connectionMessage = "正在检查设备连接…"
        Task {
            defer { isCheckingConnection = false }
            do {
                let status = try await client.status()
                apply(status)
                online = true
                connectionMessage = "设备在线"
                actionMessage = status.queueCapacity.map { "设备在线 · BUFFER SIZE \($0)" }
                    ?? "设备在线 · 请更新 Onboard 服务"
            } catch {
                online = false
                onboardBufferSize = nil
                connectionMessage = error.localizedDescription
                actionMessage = error.localizedDescription
            }
        }
    }

    func syncDeviceSettings() {
        guard !isCheckingConnection, !isSyncingSettings else { return }
        guard let client = makeClient() else {
            online = false
            syncSucceeded = false
            connectionMessage = token.isEmpty ? "填写 Token 后同步" : "检查设备 IP 格式"
            actionMessage = connectionMessage
            return
        }

        syncSucceeded = nil
        isSyncingSettings = true
        actionMessage = "正在检查连接并同步 BUFFER SIZE…"
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
                    connectionMessage = "在线，但 Onboard 服务需更新"
                    actionMessage = "服务版本不支持 BUFFER SIZE 同步"
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
                        actionMessage = "BUFFER SIZE 已变化，请再次同步"
                        return
                    }
                }

                syncSucceeded = true
                connectionMessage = "设备在线"
                actionMessage = currentCapacity == requestedCapacity
                    ? "设备在线 · BUFFER SIZE 已同步"
                    : "BUFFER SIZE 已上传并保存到设备"
            } catch {
                syncSucceeded = false
                if connected {
                    online = true
                    connectionMessage = "设备在线"
                } else {
                    online = false
                    onboardBufferSize = nil
                    connectionMessage = error.localizedDescription
                }
                actionMessage = error.localizedDescription
            }
        }
    }

    func send(_ button: RemoteButton) {
        guard !token.isEmpty else {
            actionMessage = "先填写 Auth Token"
            return
        }
        guard let client = makeClient() else {
            actionMessage = "设备 IP 无效"
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let minimumInterval = TimeInterval(keyDelayMilliseconds) / 1_000
        if minimumInterval > 0,
           let lastAcceptedKeyTime,
           now - lastAcceptedKeyTime < minimumInterval {
            actionMessage = "按键间隔内的输入已忽略"
            return
        }
        lastAcceptedKeyTime = now

        actionMessage = "正在发送 \(button.title)…"
        Task {
            do {
                let receipt = try await client.tap(button)
                online = true
                actionMessage = receipt.duplicate == true
                    ? "\(button.title) 已去重"
                    : "\(button.title) 已发送 · 设备已接收"
            } catch {
                online = false
                connectionMessage = error.localizedDescription
                actionMessage = error.localizedDescription
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
        actionMessage = "准备就绪"
        connectionMessage = message
    }

    private func makeClient() -> ActionCtrlHTTPClient? {
        guard let baseURL = Self.deviceURL(from: deviceAddress), !token.isEmpty else { return nil }
        return ActionCtrlHTTPClient(baseURL: baseURL, token: token, transport: transport)
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
