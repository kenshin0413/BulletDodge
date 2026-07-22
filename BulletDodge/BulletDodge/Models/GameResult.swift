import Foundation

struct GameResult: Codable, Equatable {
    let survivalTime: TimeInterval
    let dodgedCount: Int
    let hitCount: Int
}
