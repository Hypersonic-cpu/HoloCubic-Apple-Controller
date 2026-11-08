import Foundation

public enum RemoteButton: String, CaseIterable, Codable, Sendable, Identifiable {
    case up
    case down
    case left
    case right
    case a
    case b

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .up: "上"
        case .down: "下"
        case .left: "左"
        case .right: "右"
        case .a: "A"
        case .b: "B"
        }
    }
}
