import Foundation

public enum BLEProtocolError: Error, Equatable {
    case emptyMessage
    case messageTooLarge
    case invalidMTU
    case invalidFrame
    case unsupportedVersion
    case tooManyFragments
    case tooManyIncompleteMessages
    case fragmentConflict
}

/// Shared framing rules for the ActionCtrl BLE GATT transport.
public enum BLEProtocol {
    public static let version = 1
    public static let maximumMessageSize = 1_024
    public static let frameHeaderSize = 6
    public static let defaultATTMTU = 23
    public static let serviceUUID = "7d5e9a00-4eb4-47d1-b591-cc6e7ef6a100"
    public static let commandCharacteristicUUID = "7d5e9a01-4eb4-47d1-b591-cc6e7ef6a100"
    public static let responseCharacteristicUUID = "7d5e9a02-4eb4-47d1-b591-cc6e7ef6a100"

    /// `maximumATTValueLength` is MTU minus the three-byte ATT operation overhead.
    public static func fragment(
        _ message: Data,
        maximumATTValueLength: Int,
        messageID: UInt16
    ) throws -> [Data] {
        guard !message.isEmpty else { throw BLEProtocolError.emptyMessage }
        guard message.count <= maximumMessageSize else { throw BLEProtocolError.messageTooLarge }
        let payloadSize = maximumATTValueLength - frameHeaderSize
        guard payloadSize > 0 else { throw BLEProtocolError.invalidMTU }
        let count = (message.count + payloadSize - 1) / payloadSize
        guard count <= UInt8.max else { throw BLEProtocolError.tooManyFragments }

        return (0..<count).map { index in
            let lower = index * payloadSize
            let upper = min(lower + payloadSize, message.count)
            var frame = Data([
                0xC7,
                UInt8(version),
                UInt8((messageID >> 8) & 0xff),
                UInt8(messageID & 0xff),
                UInt8(index),
                UInt8(count),
            ])
            frame.append(message[lower..<upper])
            return frame
        }
    }
}

/// Reassembles frames for one GATT connection and one data direction.
public final class BLEFrameAssembler {
    private struct PartialMessage {
        let fragmentCount: Int
        var fragments: [Int: Data]
        var totalBytes: Int
        var lastUpdated: Date
    }

    private var partialMessages: [UInt16: PartialMessage] = [:]
    private let maximumIncompleteMessages: Int
    private let timeout: TimeInterval

    public init(maximumIncompleteMessages: Int = 4, timeout: TimeInterval = 5) {
        self.maximumIncompleteMessages = maximumIncompleteMessages
        self.timeout = timeout
    }

    /// Returns a complete JSON message, or nil while more fragments are needed.
    public func append(_ frame: Data, now: Date = Date()) throws -> Data? {
        expire(now: now)
        guard frame.count > BLEProtocol.frameHeaderSize,
              frame[frame.startIndex] == 0xC7 else {
            throw BLEProtocolError.invalidFrame
        }
        guard frame[frame.startIndex + 1] == UInt8(BLEProtocol.version) else {
            throw BLEProtocolError.unsupportedVersion
        }

        let messageID = UInt16(frame[frame.startIndex + 2]) << 8
            | UInt16(frame[frame.startIndex + 3])
        let fragmentIndex = Int(frame[frame.startIndex + 4])
        let fragmentCount = Int(frame[frame.startIndex + 5])
        guard fragmentCount > 0, fragmentIndex < fragmentCount else {
            throw BLEProtocolError.invalidFrame
        }
        let payload = Data(frame.dropFirst(BLEProtocol.frameHeaderSize))

        var partial: PartialMessage
        if let existing = partialMessages[messageID] {
            guard existing.fragmentCount == fragmentCount else {
                partialMessages[messageID] = nil
                throw BLEProtocolError.fragmentConflict
            }
            partial = existing
        } else {
            guard partialMessages.count < maximumIncompleteMessages else {
                throw BLEProtocolError.tooManyIncompleteMessages
            }
            partial = PartialMessage(
                fragmentCount: fragmentCount,
                fragments: [:],
                totalBytes: 0,
                lastUpdated: now
            )
        }

        if let existingPayload = partial.fragments[fragmentIndex] {
            guard existingPayload == payload else {
                partialMessages[messageID] = nil
                throw BLEProtocolError.fragmentConflict
            }
        } else {
            partial.totalBytes += payload.count
            guard partial.totalBytes <= BLEProtocol.maximumMessageSize else {
                partialMessages[messageID] = nil
                throw BLEProtocolError.messageTooLarge
            }
            partial.fragments[fragmentIndex] = payload
        }
        partial.lastUpdated = now

        guard partial.fragments.count == fragmentCount else {
            partialMessages[messageID] = partial
            return nil
        }

        var complete = Data()
        for index in 0..<fragmentCount {
            guard let fragment = partial.fragments[index] else {
                partialMessages[messageID] = partial
                return nil
            }
            complete.append(fragment)
        }
        partialMessages[messageID] = nil
        return complete
    }

    public func reset() {
        partialMessages.removeAll(keepingCapacity: true)
    }

    private func expire(now: Date) {
        partialMessages = partialMessages.filter { _, value in
            now.timeIntervalSince(value.lastUpdated) <= timeout
        }
    }
}
