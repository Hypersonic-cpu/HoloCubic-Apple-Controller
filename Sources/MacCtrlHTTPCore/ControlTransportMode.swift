import Foundation

public enum ControlTransportMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case http
    case ble

    public var id: String { rawValue }

    public func title(in language: ControllerLanguage) -> String {
        switch self {
        case .auto: language.text(.transportAuto)
        case .http: language.text(.transportHTTP)
        case .ble: language.text(.transportBLE)
        }
    }
}
