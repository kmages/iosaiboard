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

/// The person's saved words and corrections. Stored on the server, edited in the app.
struct SavedDictionary: Codable, Equatable {
    struct Replacement: Codable, Equatable, Hashable {
        var typed: String
        var wanted: String
    }
    var keep: [String] = []
    var replace: [Replacement] = []
}

enum FixClient {
    private struct Reply: Decodable {
        let fixed: String?
        let detail: String?
    }

    private static var dictionaryURL: URL {
        Config.endpoint.deletingLastPathComponent().appendingPathComponent("dictionary")
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FixError.badResponse }
        guard http.statusCode == 200 else {
            let reply = try? JSONDecoder().decode(Reply.self, from: data)
            throw FixError.server(reply?.detail ?? "Server error \(http.statusCode)")
        }
        return data
    }

    static func loadDictionary() async throws -> SavedDictionary {
        let data = try await send(URLRequest(url: dictionaryURL))
        return try JSONDecoder().decode(SavedDictionary.self, from: data)
    }

    /// Saves and returns the cleaned-up copy the server kept.
    static func saveDictionary(_ dictionary: SavedDictionary) async throws -> SavedDictionary {
        var request = URLRequest(url: dictionaryURL)
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(dictionary)
        let data = try await send(request)
        return try JSONDecoder().decode(SavedDictionary.self, from: data)
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
        request.httpBody = try JSONEncoder().encode(["text": core])
        let data = try await send(request)
        guard let fixed = try? JSONDecoder().decode(Reply.self, from: data).fixed else {
            throw FixError.badResponse
        }
        return String(lead) + fixed.trimmingCharacters(in: .whitespacesAndNewlines) + String(trail)
    }
}
