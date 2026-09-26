import Foundation

/// Classifies errors into concise, aggregatable telemetry strings.
///
/// Produces strings like "URLError.notConnectedToInternet", "DictationServiceError",
/// "CancellationError" — more useful for grouping than raw `type(of:)` class names.
/// NSError domains are retained only for known platform errors; custom domains
/// become `NSError.<code>` even when their text resembles a technical identifier
/// (upstream MacParakeet v0.8.7).
public enum TelemetryErrorClassifier {
    private static let knownNSErrorDomains: Set<String> = [
        NSCocoaErrorDomain,
        NSPOSIXErrorDomain,
        NSOSStatusErrorDomain,
        NSURLErrorDomain,
        "AVFoundationErrorDomain",
        "com.apple.coreaudio.avfaudio",
    ]

    public static func classify(_ error: Error) -> String {
        // URLError: include the code name for network diagnosis
        if let urlError = error as? URLError {
            return "URLError.\(urlErrorCodeName(urlError.code))"
        }

        // Swift-native error types (enums, structs, classes) — include case name for enums
        let typeName = String(describing: type(of: error))
        if typeName != "_SwiftNativeNSError" && typeName != "NSError" {
            // For enum errors, extract the case name (e.g., "AudioProcessorError.insufficientSamples")
            let mirror = Mirror(reflecting: error)
            if let caseName = mirror.children.first?.label {
                return "\(typeName).\(caseName)"
            }
            // Non-enum errors or cases without associated values (Mirror has no children
            // for simple enum cases) — use String(describing:) which prints the case name
            let described = String(describing: error)
            if described != typeName && !described.contains("(") {
                return "\(typeName).\(described)"
            }
            return typeName
        }

        // Retain only known platform domains. Custom NSError domains are
        // arbitrary strings, so even single-word values are discarded.
        let nsError = error as NSError
        let safeDomain = knownNSErrorDomains.contains(nsError.domain) ? nsError.domain : "NSError"
        return "\(safeDomain).\(nsError.code)"
    }

    /// Returns a privacy-safe error detail string: paths and URLs stripped, truncated to 512 chars.
    public static func errorDetail(_ error: Error) -> String {
        return String(sanitize(error.localizedDescription).prefix(512))
    }

    /// Strips file paths and URLs from an arbitrary string. Idempotent — running
    /// twice produces the same result. Used both by `errorDetail(_:)` for Error
    /// values and by `TelemetryEvent.errorOccurred` for raw description strings,
    /// so any caller route into telemetry is automatically privacy-clean even
    /// if the caller forgot to invoke `errorDetail` themselves. No truncation
    /// here — callers truncate to whatever budget they're enforcing.
    public static func sanitize(_ string: String) -> String {
        var sanitized = string
        // Strip file:// URLs (must run before path stripping to catch file:///Users/...)
        sanitized = sanitized.replacingOccurrences(
            of: #"file://[^\s\"',)\]]+"#,
            with: "<path>",
            options: .regularExpression
        )
        // Strip absolute paths: /Users/..., /var/folders/..., /private/..., /tmp/...
        sanitized = sanitized.replacingOccurrences(
            of: #"(?:/Volumes/[^\s/]+)?/(?:Users/[^\s/]+|private/var/folders|var/folders|tmp)[^\s\"',)\]]*"#,
            with: "<path>",
            options: .regularExpression
        )
        // Strip http(s) URLs that may contain video IDs, tokens, or query params
        sanitized = sanitized.replacingOccurrences(
            of: #"https?://[^\s\"',)\]]+"#,
            with: "<url>",
            options: .regularExpression
        )
        return sanitized
    }

    private static func urlErrorCodeName(_ code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet: return "notConnectedToInternet"
        case .timedOut: return "timedOut"
        case .cannotFindHost: return "cannotFindHost"
        case .cannotConnectToHost: return "cannotConnectToHost"
        case .networkConnectionLost: return "networkConnectionLost"
        case .cancelled: return "cancelled"
        case .badServerResponse: return "badServerResponse"
        case .secureConnectionFailed: return "secureConnectionFailed"
        default: return "code\(code.rawValue)"
        }
    }
}
