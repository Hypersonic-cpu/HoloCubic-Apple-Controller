import Foundation

public enum RemoteButton: String, CaseIterable, Codable, Sendable, Identifiable {
    case up
    case down
    case left
    case right
    case a
    case b
    case home

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .up: "上"
        case .down: "下"
        case .left: "左"
        case .right: "右"
        case .a: "A"
        case .b: "B"
        case .home: "Home"
        }
    }

    public func title(in language: ControllerLanguage) -> String {
        switch self {
        case .up: language.text(.up)
        case .down: language.text(.down)
        case .left: language.text(.left)
        case .right: language.text(.right)
        case .a: "A"
        case .b: "B"
        case .home: language.text(.home)
        }
    }
}
