import Foundation

public enum FieldReadinessSeverity: String, Equatable, Sendable {
    case blocking
    case warning
}

public struct FieldReadinessIssue: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let severity: FieldReadinessSeverity

    public init(id: String, title: String, detail: String, severity: FieldReadinessSeverity) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

public struct FieldReadiness: Equatable, Sendable {
    public let blocking: [FieldReadinessIssue]
    public let warnings: [FieldReadinessIssue]

    public init(blocking: [FieldReadinessIssue], warnings: [FieldReadinessIssue]) {
        self.blocking = blocking
        self.warnings = warnings
    }

    public var canStartMatch: Bool { blocking.isEmpty }
}
