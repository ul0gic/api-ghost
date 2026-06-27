import Foundation

struct Endpoint: Identifiable, Codable, Hashable {
    // MARK: - Properties

    let id: String

    let host: String

    let pathPattern: String

    let method: String

    var callCount: Int

    var typicalStatus: Int?

    var lastSeen: Date

    var hasInterestingFindings: Bool

    var findings: [EndpointFinding]

    // MARK: - Initialization

    init(
        host: String,
        pathPattern: String,
        method: String,
        callCount: Int = 1,
        typicalStatus: Int? = nil,
        lastSeen: Date = Date(),
        hasInterestingFindings: Bool = false,
        findings: [EndpointFinding] = []
    ) {
        self.id = "\(method):\(host)\(pathPattern)"
        self.host = host
        self.pathPattern = pathPattern
        self.method = method
        self.callCount = callCount
        self.typicalStatus = typicalStatus
        self.lastSeen = lastSeen
        self.hasInterestingFindings = hasInterestingFindings
        self.findings = findings
    }
}

struct EndpointFinding: Identifiable, Codable, Hashable {
    // MARK: - Properties

    let id: String

    let type: FindingType

    let description: String

    let severity: FindingSeverity

    // MARK: - Initialization

    init(type: FindingType, description: String, severity: FindingSeverity = .info) {
        self.id = UUID().uuidString
        self.type = type
        self.description = description
        self.severity = severity
    }
}

enum FindingType: String, Codable, Hashable {
    case internalEndpoint = "internal_endpoint"
    case debugEndpoint = "debug_endpoint"
    case adminEndpoint = "admin_endpoint"
    case sequentialIds = "sequential_ids"
    case largeResponse = "large_response"
    case errorWithStackTrace = "error_with_stack_trace"
    case sensitiveData = "sensitive_data"
}

enum FindingSeverity: String, Codable, Hashable {
    case info
    case low
    case medium
    case high
}

// MARK: - Path Parameterization

extension Endpoint {
    static func parameterizePath(_ path: String) -> String {
        let components = path.split(separator: "/")
        let parameterized = components.map { component -> String in
            let str = String(component)
            if str.isLikelyId {
                return "{id}"
            }
            return str
        }
        return "/" + parameterized.joined(separator: "/")
    }
}

// MARK: - String ID Detection

extension String {
    var isLikelyId: Bool {
        if Int(self) != nil { return true }

        if self.count == 36 && self.contains("-") {
            let uuidRegex = try? NSRegularExpression(
                pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
            )
            let range = NSRange(self.startIndex..., in: self)
            if uuidRegex?.firstMatch(in: self, range: range) != nil { return true }
        }

        if self.count >= 16 && self.count <= 32 {
            let hexRegex = try? NSRegularExpression(pattern: "^[0-9a-fA-F]+$")
            let range = NSRange(self.startIndex..., in: self)
            if hexRegex?.firstMatch(in: self, range: range) != nil { return true }
        }

        return false
    }
}
