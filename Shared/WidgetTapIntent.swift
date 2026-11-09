import AppIntents
import Foundation
import WidgetKit

struct WidgetTapIntent: AppIntent {
    static var title: LocalizedStringResource = "Send HoloCubic Button"
    static var openAppWhenRun = false

    @Parameter(title: "Button") var button: String

    init() {
        button = "up"
    }

    init(button: String) {
        self.button = button
    }

    func perform() async throws -> some IntentResult {
        let allowedButtons: Set<String> = ["up", "down", "left", "right", "a", "b", "home"]
        guard allowedButtons.contains(button),
              let defaults = UserDefaults(suiteName: "group.com.clocteck.MacCtrlHTTP"),
              let token = defaults.string(forKey: "actionCtrlToken"), !token.isEmpty,
              let address = defaults.string(forKey: "deviceAddress"),
              let baseURL = Self.deviceURL(address),
              let requestURL = URL(string: "/remote/api/v1/tap", relativeTo: baseURL)?.absoluteURL else {
            throw WidgetTapError.notConfigured
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-ActionCtrl-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "button": button,
            "request_id": "widget-\(UUID().uuidString.lowercased())",
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 202 else {
            throw WidgetTapError.requestRejected
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "HoloCubicControlWidget")
        return .result()
    }

    private static func deviceURL(_ address: String) -> URL? {
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = raw.hasPrefix("http://") ? raw : "http://\(raw)"
        guard let url = URL(string: normalized), url.scheme == "http", url.host != nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}

private enum WidgetTapError: Error, LocalizedError {
    case notConfigured
    case requestRejected

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Open HoloCubic Controller and configure the device first."
        case .requestRejected: "The HoloCubic did not accept the button press."
        }
    }
}
