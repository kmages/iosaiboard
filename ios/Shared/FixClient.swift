import Foundation

enum FixError: LocalizedError {
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .badResponse: return "Unexpected reply from the server"
        }
    }
}

enum FixClient {
    private struct Reply: Decodable {
        let fixed: String?
        let detail: String?
    }

    /// Sends text to the proxy and returns it corrected.
    /// Leading and trailing whitespace never leaves the phone and is put back untouched.
    static func fix(_ text: String) async throws -> String {
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty, let range = text.range(of: core) else { return text }
        let lead = text[text.startIndex..<range.lowerBound]
        let trail = text[range.upperBound...]

        var request = URLRequest(url: Config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["text": core])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FixError.badResponse }
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        guard http.statusCode == 200, let fixed = reply?.fixed else {
            throw FixError.server(reply?.detail ?? "Server error \(http.statusCode)")
        }
        return String(lead) + fixed.trimmingCharacters(in: .whitespacesAndNewlines) + String(trail)
    }
}
