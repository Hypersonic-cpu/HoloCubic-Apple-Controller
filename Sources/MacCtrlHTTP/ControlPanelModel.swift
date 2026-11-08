import Combine
import Foundation
import MacCtrlHTTPCore

@MainActor
final class ControlPanelModel: ObservableObject {
    @Published var token: String
    @Published var deviceAddress: String
    @Published private(set) var online = false
    @Published private(set) var isConfirmingToken = false
    @Published private(set) var isTestingConnection = false
    @Published private(set) var connectionMessage: String
    @Published private(set) var actionMessage = "准备就绪"
    @Published private(set) var queueLength: Int?

    private let tokenStore: any TokenStore
    private let deviceAddressStore: any DeviceAddressStore
    private let transport: any HTTPTransport
    private var lastSavedToken: String
    private var lastSavedDeviceAddress: String

    init(
        tokenStore: any TokenStore = UserDefaultsTokenStore(),
        deviceAddressStore: any DeviceAddressStore = UserDefaultsDeviceAddressStore(),
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.tokenStore = tokenStore
        self.deviceAddressStore = deviceAddressStore
        self.transport = transport

        let loadedToken = (try? tokenStore.load()) ?? ""
        let loadedAddress = (try? deviceAddressStore.load()) ?? ""
        self.token = loadedToken
        self.deviceAddress = loadedAddress
        self.lastSavedToken = loadedToken
        self.lastSavedDeviceAddress = loadedAddress
        if loadedAddress.isEmpty {
            self.connectionMessage = "填写设备 IP 并点击联通测试"
        } else if loadedToken.isEmpty {
            self.connectionMessage = "填写 Token 后点击上箭头"
        } else {
            self.connectionMessage = "点击联通测试检查设备"
        }
    }

    func saveToken(_ newValue: String) {
        token = newValue
        let changed = newValue != lastSavedToken
        if changed {
            online = false
            queueLength = nil
            actionMessage = "准备就绪"
        }
        do {
            try tokenStore.save(newValue)
            lastSavedToken = newValue
            if changed, !newValue.isEmpty, !deviceAddress.isEmpty {
                connectionMessage = "Token 已保存，点击上箭头发送 B 验证"
            } else if newValue.isEmpty {
                online = false
                connectionMessage = "填写 Token 后点击上箭头"
            }
        } catch {
            connectionMessage = "保存 Token 失败"
        }
    }

    func saveDeviceAddress(_ newValue: String) {
        deviceAddress = newValue
        let changed = newValue != lastSavedDeviceAddress
        if changed {
            online = false
            queueLength = nil
            actionMessage = "准备就绪"
        }
        do {
            try deviceAddressStore.save(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            lastSavedDeviceAddress = newValue
            if changed, !newValue.isEmpty {
                connectionMessage = "IP 已保存，点击联通测试"
            } else if newValue.isEmpty {
                online = false
                connectionMessage = "填写设备 IP 并点击联通测试"
            }
        } catch {
            connectionMessage = "保存设备 IP 失败"
        }
    }

    func testConnection() {
        guard !token.isEmpty else {
            online = false
            connectionMessage = "先填写 Auth Token"
            actionMessage = "先填写 Auth Token"
            return
        }
        guard let baseURL = Self.deviceURL(from: deviceAddress) else {
            online = false
            connectionMessage = "填写有效的设备 IP 或主机名"
            actionMessage = "设备 IP 无效"
            return
        }

        let client = ActionCtrlHTTPClient(baseURL: baseURL, token: token, transport: transport)
        isTestingConnection = true
        online = false
        connectionMessage = "正在测试联通…"
        actionMessage = "正在测试联通…"
        Task {
            defer { isTestingConnection = false }
            do {
                let status = try await client.status()
                online = true
                queueLength = status.queueLength
                connectionMessage = "联通测试成功"
                actionMessage = status.queueLength.map { "连接正常 · 队列 \($0)" } ?? "连接正常"
            } catch {
                show(error)
                actionMessage = error.localizedDescription
            }
        }
    }

    func confirmToken() {
        guard !token.isEmpty else {
            online = false
            connectionMessage = "填写 Token 后点击上箭头"
            actionMessage = "先填写 Auth Token"
            return
        }
        guard let client = makeClient() else {
            online = false
            connectionMessage = "填写有效的设备 IP 或主机名"
            actionMessage = "设备 IP 无效"
            return
        }

        isConfirmingToken = true
        online = false
        connectionMessage = "正在发送 B 验证 Token…"
        actionMessage = "正在发送 B…"
        Task {
            defer { isConfirmingToken = false }
            do {
                let receipt = try await client.tap(.b)
                online = true
                connectionMessage = "B 已传输 · ActionCtrlHTTP 在线"
                actionMessage = receipt.duplicate == true ? "B 已确认" : "B 已发送 · 设备已接收"
            } catch {
                show(error)
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

        actionMessage = "正在发送 \(button.title)…"
        Task {
            do {
                let receipt = try await client.tap(button)
                online = true
                actionMessage = receipt.duplicate == true
                    ? "\(button.title) 已去重"
                    : "\(button.title) 已发送 · 设备已接收"
            } catch {
                show(error)
                actionMessage = error.localizedDescription
            }
        }
    }

    private func makeClient() -> ActionCtrlHTTPClient? {
        guard let baseURL = Self.deviceURL(from: deviceAddress), !token.isEmpty else { return nil }
        return ActionCtrlHTTPClient(baseURL: baseURL, token: token, transport: transport)
    }

    private func show(_ error: Error) {
        online = false
        connectionMessage = error.localizedDescription
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
