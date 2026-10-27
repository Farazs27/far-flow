import Foundation

/// Fn is hold-to-talk; two short taps lock recording until the next Fn press.
public struct FnGesture: Sendable {
    public enum Action: Equatable, Sendable {case start,stop,lock}
    private enum Phase: Sendable {case idle,held(Double),waiting(Double),lockedHeld,locked,stopping}
    private var phase: Phase = .idle
    public let holdThreshold: Double
    public let doubleTapWindow: Double
    public init(holdThreshold: Double = 0.22,doubleTapWindow: Double = 0.35) {self.holdThreshold=holdThreshold;self.doubleTapWindow=doubleTapWindow}
    public var pendingStopDeadline: Double? {if case .waiting(let deadline)=phase{return deadline};return nil}
    public var isLocked: Bool {switch phase{case .locked,.lockedHeld:true;default:false}}
    public mutating func press(at time: Double) -> [Action] {
        switch phase {
        case .idle:phase = .held(time);return [.start]
        case .waiting(let deadline) where time<=deadline:phase = .lockedHeld;return [.lock]
        case .waiting:phase = .held(time);return [.stop,.start]
        case .locked:phase = .stopping;return [.stop]
        default:return []
        }
    }
    public mutating func release(at time: Double) -> [Action] {
        switch phase {
        case .held(let began):
            if time-began>=holdThreshold {phase = .idle;return [.stop]}
            phase = .waiting(time+doubleTapWindow);return []
        case .lockedHeld:phase = .locked;return []
        case .stopping:phase = .idle;return []
        default:return []
        }
    }
    public mutating func expire(at time: Double) -> [Action] {
        if case .waiting(let deadline)=phase,time>=deadline {phase = .idle;return [.stop]}
        return []
    }
    public mutating func reset() {phase = .idle}
    public mutating func lockRecording(){phase = .locked}
}
