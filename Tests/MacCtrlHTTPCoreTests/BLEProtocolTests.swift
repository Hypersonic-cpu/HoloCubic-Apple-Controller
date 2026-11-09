import Foundation
import XCTest
@testable import MacCtrlHTTPCore

final class BLEProtocolTests: XCTestCase {
    func testDefaultMTUFragmentsAndReassemblesOutOfOrder() throws {
        let message = Data((0..<1_024).map { UInt8($0 % 251) })
        let frames = try BLEProtocol.fragment(message, maximumATTValueLength: 20, messageID: 0x1234)
        XCTAssertEqual(frames.count, 74)
        XCTAssertTrue(frames.allSatisfy { $0.count <= 20 })

        let assembler = BLEFrameAssembler()
        var reassembled: Data?
        for frame in frames.reversed() {
            reassembled = try assembler.append(frame) ?? reassembled
        }
        XCTAssertEqual(reassembled, message)
    }

    func testIdenticalDuplicateFragmentIsIgnored() throws {
        let message = Data(repeating: 0x5a, count: 30)
        let frames = try BLEProtocol.fragment(message, maximumATTValueLength: 20, messageID: 8)
        let assembler = BLEFrameAssembler()

        XCTAssertNil(try assembler.append(frames[0]))
        XCTAssertNil(try assembler.append(frames[0]))
        XCTAssertNil(try assembler.append(frames[1]))
        XCTAssertEqual(try assembler.append(frames[2]), message)
    }

    func testConflictingDuplicateFragmentDiscardsMessage() throws {
        let frames = try BLEProtocol.fragment(Data(repeating: 0x5a, count: 30), maximumATTValueLength: 20, messageID: 9)
        let assembler = BLEFrameAssembler()
        XCTAssertNil(try assembler.append(frames[0]))

        var conflicting = frames[0]
        conflicting[BLEProtocol.frameHeaderSize] ^= 0xff
        XCTAssertThrowsError(try assembler.append(conflicting)) { error in
            XCTAssertEqual(error as? BLEProtocolError, .fragmentConflict)
        }
    }

    func testExpiredPartialMessageIsDiscarded() throws {
        let frames = try BLEProtocol.fragment(Data(repeating: 1, count: 30), maximumATTValueLength: 20, messageID: 10)
        let assembler = BLEFrameAssembler(timeout: 5)
        let start = Date(timeIntervalSince1970: 10)
        XCTAssertNil(try assembler.append(frames[0], now: start))
        XCTAssertNil(try assembler.append(frames[1], now: start.addingTimeInterval(6)))
    }

    func testRejectsOversizedMessagesAndInvalidFrames() throws {
        XCTAssertThrowsError(try BLEProtocol.fragment(Data(repeating: 0, count: 1_025), maximumATTValueLength: 20, messageID: 1)) { error in
            XCTAssertEqual(error as? BLEProtocolError, .messageTooLarge)
        }
        XCTAssertThrowsError(try BLEProtocol.fragment(Data([1]), maximumATTValueLength: 6, messageID: 1)) { error in
            XCTAssertEqual(error as? BLEProtocolError, .invalidMTU)
        }
        XCTAssertThrowsError(try BLEFrameAssembler().append(Data([0, 0, 0, 0, 0, 1, 2]))) { error in
            XCTAssertEqual(error as? BLEProtocolError, .invalidFrame)
        }
    }
}
