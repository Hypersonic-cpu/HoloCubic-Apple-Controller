import Foundation
import XCTest
@testable import MacCtrlHTTPCore

final class ActionCtrlHTTPClientTests: XCTestCase {
    func testTapUsesActionCtrlHTTPContract() async throws {
        let body = Data(#"{"ok":true,"request_id":"mac-test","queued":true}"#.utf8)
        let transport = MockHTTPTransport(statusCode: 202, body: body)
        let client = ActionCtrlHTTPClient(
            baseURL: URL(string: "http://holo.test")!,
            token: "unit-test-token",
            transport: transport
        )

        let receipt = try await client.tap(.left)
        XCTAssertTrue(receipt.ok)
        XCTAssertTrue(receipt.queued ?? false)

        let request = await transport.capturedRequest()
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.path, "/remote/api/v1/tap")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-ActionCtrl-Token"), "unit-test-token")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let payload = try XCTUnwrap(request?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: String])
        XCTAssertEqual(object["button"], "left")
        XCTAssertTrue(object["request_id"]?.hasPrefix("mac-") == true)
    }

    func testStatusUsesAuthenticatedGetAndDecodesQueue() async throws {
        let body = Data(#"{"ok":true,"source":"ble-main","buttons":0,"queue_length":3}"#.utf8)
        let transport = MockHTTPTransport(statusCode: 200, body: body)
        let client = ActionCtrlHTTPClient(
            baseURL: URL(string: "http://holo.test")!,
            token: "unit-test-token",
            transport: transport
        )

        let status = try await client.status()
        XCTAssertTrue(status.ok)
        XCTAssertEqual(status.source, "ble-main")
        XCTAssertEqual(status.buttons, 0)
        XCTAssertEqual(status.queueLength, 3)

        let request = await transport.capturedRequest()
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.url?.path, "/remote/api/v1/status")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-ActionCtrl-Token"), "unit-test-token")
    }

    func testHomeTapUsesHomeButtonName() async throws {
        let body = Data(#"{"ok":true,"request_id":"mac-home","queued":true}"#.utf8)
        let transport = MockHTTPTransport(statusCode: 202, body: body)
        let client = ActionCtrlHTTPClient(
            baseURL: URL(string: "http://holo.test")!,
            token: "unit-test-token",
            transport: transport
        )

        _ = try await client.tap(.home)

        let request = await transport.capturedRequest()
        let payload = try XCTUnwrap(request?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: String])
        XCTAssertEqual(object["button"], "home")
    }

    func testUnauthorizedTapIsReported() async {
        let transport = MockHTTPTransport(statusCode: 401, body: Data(#"{"ok":false}"#.utf8))
        let client = ActionCtrlHTTPClient(
            baseURL: URL(string: "http://holo.test")!,
            token: "wrong-token",
            transport: transport
        )

        do {
            _ = try await client.tap(.a)
            XCTFail("Expected 401 rejection")
        } catch let error as ActionClientError {
            XCTAssertEqual(error, .rejected(statusCode: 401))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor MockHTTPTransport: HTTPTransport {
    private let statusCode: Int
    private let body: Data
    private var request: URLRequest?

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (body, response)
    }

    func capturedRequest() -> URLRequest? { request }
}
