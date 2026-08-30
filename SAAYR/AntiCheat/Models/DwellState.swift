import Foundation

enum DwellState: Equatable {
    case idle
    case scanning
    case dwelling(startedAt: Date)
    case verifiedDwell
    case collecting
    case submitted
    case failed(reason: String)

    static func == (lhs: DwellState, rhs: DwellState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
            (.scanning, .scanning),
            (.verifiedDwell, .verifiedDwell),
            (.collecting, .collecting),
            (.submitted, .submitted):
            return true
        case (.dwelling(let a), .dwelling(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}
