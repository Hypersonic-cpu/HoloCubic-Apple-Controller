import Foundation

public protocol HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public struct ActionStatus: Decodable, Sendable {
    public let ok: Bool
    public let source: String?
    public let buttons: Int?
    public let queueLength: Int?

    enum CodingKeys: String, CodingKey {
        case ok
        case source
        case buttons
        case queueLength = "queue_length"
    }
}

public struct TapReceipt: Decodable, Sendable {
    public let ok: Bool
    public let requestID: String?
    public let queued: Bool?
    public let duplicate: Bool?

    enum CodingKeys: String, CodingKey {
        case ok
        case requestID = "request_id"
        case queued
        case duplicate
    }
}

public enum ActionClientError: Error, LocalizedError, Sendable, Equatable {
    case invalidDeviceAddress
    case invalidResponse
    case rejected(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidDeviceAddress:
            "设备 IP 无效，请检查地址"
        case .invalidResponse:
            "设备返回了无法识别的响应"
        case .rejected(let statusCode):
            switch statusCode {
            case 401: "Token 不匹配，请检查输入"
            case 409: "ble-main 正被其他服务占用"
            case 429: "设备按键队列已满，请稍后再试"
            case 503: "ActionCtrlHTTP 尚未配置或未就绪"
            default: "设备拒绝请求（HTTP \(statusCode)）"
            }
        }
    }
}

public struct ActionCtrlHTTPClient {
    public let baseURL: URL
    private let token: String
    private let transport: any HTTPTransport

    public init(baseURL: URL, token: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    public func status() async throws -> ActionStatus {
        var request = URLRequest(url: endpoint("status"))
        request.httpMethod = "GET"
        addAuthentication(to: &request)

        let (data, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ActionClientError.invalidResponse
        }
        guard response.statusCode == 200 else {
            throw ActionClientError.rejected(statusCode: response.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(ActionStatus.self, from: data), decoded.ok else {
            throw ActionClientError.invalidResponse
        }
        return decoded
    }

    @discardableResult
    public func tap(_ button: RemoteButton) async throws -> TapReceipt {
        var request = URLRequest(url: endpoint("tap"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TapRequest(
            button: button.rawValue,
            requestID: "mac-\(UUID().uuidString.lowercased())"
        ))
        addAuthentication(to: &request)

        let (data, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ActionClientError.invalidResponse
        }
        guard response.statusCode == 202 else {
            throw ActionClientError.rejected(statusCode: response.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(TapReceipt.self, from: data), decoded.ok else {
            throw ActionClientError.invalidResponse
        }
        return decoded
    }

    private func endpoint(_ leaf: String) -> URL {
        baseURL
            .appendingPathComponent("remote")
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent(leaf)
    }

    private func addAuthentication(to request: inout URLRequest) {
        request.setValue(token, forHTTPHeaderField: "X-ActionCtrl-Token")
    }
}

private struct TapRequest: Encodable {
    let button: String
    let requestID: String

    enum CodingKeys: String, CodingKey {
        case button
        case requestID = "request_id"
    }
}
