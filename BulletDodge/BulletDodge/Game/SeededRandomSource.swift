import CoreGraphics
import Foundation

/// A stable SplitMix64 stream. Ranked battles reuse the same seed so random
/// combat decisions are identical across devices and launches.
final class SeededRandomSource {
    private var state: UInt64

    init(seed: UUID) {
        state = seed.uuidString.utf8.reduce(0xcbf29ce484222325) { value, byte in
            (value ^ UInt64(byte)) &* 0x100000001b3
        }
    }

    func bool() -> Bool { next() & 1 == 0 }

    func int(in range: Range<Int>) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        return range.lowerBound + Int(next() % UInt64(range.count))
    }

    func cgFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(unitInterval())
    }

    func timeInterval(in range: ClosedRange<TimeInterval>) -> TimeInterval {
        range.lowerBound + (range.upperBound - range.lowerBound) * unitInterval()
    }

    func shuffled<Element>(_ values: [Element]) -> [Element] {
        guard values.count > 1 else { return values }
        var result = values
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            result.swapAt(index, int(in: 0..<(index + 1)))
        }
        return result
    }

    private func unitInterval() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    private func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
