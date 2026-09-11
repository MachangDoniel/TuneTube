import Foundation
import os.log

/// NetworkLogger provides structured, readable logging for HTTP requests, responses,
/// headers, and authorization/Bearer tokens during development.
///
/// Guarded by `#if DEBUG` so logging only runs in debug builds.
public enum NetworkLogger {

    public struct Configuration: Sendable {
        /// Whether network logging is enabled.
        public var isEnabled: Bool
        
        /// Whether to print request & response HTTP headers.
        public var logHeaders: Bool
        
        /// If true, masks Bearer / Authorization tokens (e.g. "Bearer abc...[REDACTED]").
        /// If false, logs the full token for easy inspection and copying into curl/Postman.
        public var maskBearerTokens: Bool
        
        /// Whether to log the response body payload.
        public var logResponseBody: Bool
        
        /// Whether to pretty-print JSON payloads for readability.
        public var prettyPrintJSON: Bool
        
        /// Maximum characters of body to print before truncating.
        public var maxBodyLength: Int

        public init(
            isEnabled: Bool = true,
            logHeaders: Bool = true,
            maskBearerTokens: Bool = false,
            logResponseBody: Bool = true,
            prettyPrintJSON: Bool = true,
            maxBodyLength: Int = 4096
        ) {
            self.isEnabled = isEnabled
            self.logHeaders = logHeaders
            self.maskBearerTokens = maskBearerTokens
            self.logResponseBody = logResponseBody
            self.prettyPrintJSON = prettyPrintJSON
            self.maxBodyLength = maxBodyLength
        }
    }

    #if DEBUG
    public static var configuration = Configuration()
    private static let osLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.tunetube", category: "Network")
    #endif

    // MARK: - Request Logging

    public static func logRequest(_ request: URLRequest) {
        #if DEBUG
        guard configuration.isEnabled else { return }

        let method = request.httpMethod ?? "GET"
        let urlString = request.url?.absoluteString ?? "(unknown url)"

        var output = """
        \n┌─── 🚀 HTTP REQUEST ──────────────────────────────────────────────────────────
        │ 🌐 \(method) \(urlString)
        """

        if configuration.logHeaders, let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            output += "\n│ 📋 HEADERS (\(headers.count)):"
            for (key, value) in headers.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
                let displayValue = formatHeaderValue(key: key, value: value)
                output += "\n│   • \(key): \(displayValue)"
            }
        }

        if let body = request.httpBody, !body.isEmpty {
            output += "\n│ 📦 REQUEST BODY (\(byteCountDescription(body.count))):"
            output += "\n" + formatBody(body)
        }

        output += "\n└──────────────────────────────────────────────────────────────────────────────"
        print(output)
        osLogger.debug("\(method, privacy: .public) \(urlString, privacy: .public)")
        #endif
    }

    // MARK: - Response Logging

    public static func logResponse(
        _ response: URLResponse?,
        data: Data?,
        duration: TimeInterval,
        for request: URLRequest
    ) {
        #if DEBUG
        guard configuration.isEnabled else { return }

        let method = request.httpMethod ?? "GET"
        let urlString = request.url?.absoluteString ?? "(unknown url)"
        let ms = String(format: "%.0fms", duration * 1000)

        guard let http = response as? HTTPURLResponse else {
            let statusBadge = "⚪️ NON-HTTP"
            print("""
            \n┌─── \(statusBadge) [\(ms)] ──────────────────────────────────────────────────
            │ 🌐 \(method) \(urlString)
            └──────────────────────────────────────────────────────────────────────────────
            """)
            return
        }

        let statusCode = http.statusCode
        let badge = statusBadge(for: statusCode)

        var output = """
        \n┌─── \(badge) (\(statusCode)) [\(ms)] ─────────────────────────────────────────
        │ 🌐 \(method) \(urlString)
        """

        if configuration.logHeaders && !http.allHeaderFields.isEmpty {
            output += "\n│ 📋 RESPONSE HEADERS (\(http.allHeaderFields.count)):"
            for (key, value) in http.allHeaderFields.sorted(by: { String(describing: $0.key).lowercased() < String(describing: $1.key).lowercased() }) {
                output += "\n│   • \(key): \(value)"
            }
        }

        if configuration.logResponseBody, let data, !data.isEmpty {
            output += "\n│ 📦 RESPONSE BODY (\(byteCountDescription(data.count))):"
            output += "\n" + formatBody(data)
        }

        output += "\n└──────────────────────────────────────────────────────────────────────────────"
        print(output)
        osLogger.info("[\(statusCode)] \(method, privacy: .public) \(urlString, privacy: .public) in \(ms, privacy: .public)")
        #endif
    }

    // MARK: - Error Logging

    public static func logError(
        _ error: Error,
        duration: TimeInterval,
        for request: URLRequest
    ) {
        #if DEBUG
        guard configuration.isEnabled else { return }

        let method = request.httpMethod ?? "GET"
        let urlString = request.url?.absoluteString ?? "(unknown url)"
        let ms = String(format: "%.0fms", duration * 1000)
        let nsError = error as NSError

        let output = """
        \n┌─── 🔴 REQUEST FAILED [\(ms)] ────────────────────────────────────────────────
        │ 🌐 \(method) \(urlString)
        │ ⚠️  ERROR: \(error.localizedDescription)
        │ 🔍 DOMAIN: \(nsError.domain) (Code \(nsError.code))
        └──────────────────────────────────────────────────────────────────────────────
        """
        print(output)
        osLogger.error("FAIL [\(nsError.code)] \(method, privacy: .public) \(urlString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        #endif
    }

    // MARK: - Formatters & Helpers

    #if DEBUG
    private static func formatHeaderValue(key: String, value: String) -> String {
        let lower = key.lowercased()
        if lower == "authorization" || lower == "proxy-authorization" {
            if value.lowercased().hasPrefix("bearer ") {
                let token = String(value.dropFirst(7))
                if configuration.maskBearerTokens {
                    let masked = maskToken(token)
                    return "🔑 Bearer \(masked)"
                } else {
                    return "🔑 Bearer \(token)"
                }
            }
            if configuration.maskBearerTokens {
                return "🔑 [REDACTED]"
            }
            return "🔑 \(value)"
        }
        return value
    }

    private static func maskToken(_ token: String) -> String {
        guard token.count > 10 else { return "[REDACTED]" }
        let prefix = token.prefix(4)
        let suffix = token.suffix(4)
        return "\(prefix)...\(suffix) (len: \(token.count))"
    }

    private static func statusBadge(for code: Int) -> String {
        switch code {
        case 200..<300: return "🟢 HTTP"
        case 300..<400: return "🟡 HTTP"
        case 400..<500: return "🟠 HTTP"
        case 500..<600: return "🔴 HTTP"
        default:        return "⚪️ HTTP"
        }
    }

    private static func formatBody(_ data: Data) -> String {
        if configuration.prettyPrintJSON,
           let jsonObject = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return truncateIfNeeded(prettyString)
        }

        if let text = String(data: data, encoding: .utf8) {
            return truncateIfNeeded(text)
        }

        return "│ [Binary data: \(byteCountDescription(data.count))]"
    }

    private static func truncateIfNeeded(_ text: String) -> String {
        let lines: [String]
        if text.count > configuration.maxBodyLength {
            let truncated = String(text.prefix(configuration.maxBodyLength))
            lines = truncated.components(separatedBy: .newlines) + ["... [truncated, \(text.count) total chars]"]
        } else {
            lines = text.components(separatedBy: .newlines)
        }
        return lines.map { "│ \($0)" }.joined(separator: "\n")
    }

    private static func byteCountDescription(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    #endif
}
