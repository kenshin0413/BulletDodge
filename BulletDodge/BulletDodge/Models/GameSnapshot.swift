import Foundation
import Combine

struct GameSnapshot: Equatable {
    var currentHP: CGFloat
    var maxHP: CGFloat
    var survivalTime: TimeInterval
    var dodgedCount: Int
    var hitCount: Int

    static let initial = GameSnapshot(
        currentHP: GameConfig.playerMaxHP,
        maxHP: GameConfig.playerMaxHP,
        survivalTime: 0,
        dodgedCount: 0,
        hitCount: 0
    )

    var hpRatio: CGFloat {
        guard maxHP > 0 else { return 0 }
        return max(0, min(1, currentHP / maxHP))
    }
}

@MainActor
final class GameSessionStore: ObservableObject {
    @Published var snapshot = GameSnapshot.initial

    func update(_ snapshot: GameSnapshot) {
        self.snapshot = snapshot
    }

    func reset() {
        snapshot = .initial
    }
}
