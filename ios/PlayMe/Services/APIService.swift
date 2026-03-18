import Foundation

nonisolated struct APIUserResponse: Codable, Sendable {
    let id: String
    let phone: String
    let firstName: String
    let username: String
    let createdAt: String
}

nonisolated struct APISongResponse: Codable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumArtURL: String
    let duration: String
}

nonisolated struct APIShareResponse: Codable, Sendable {
    let id: String
    let senderId: String
    let recipientId: String
    let songId: String
    let note: String?
    let createdAt: String
    let song: APISongResponse?
    let sender: APIUserResponse?
    let recipient: APIUserResponse?
}

nonisolated struct APIUsernameCheck: Codable, Sendable {
    let available: Bool
}

nonisolated struct APIError: Error, Sendable {
    let message: String
}

actor APIService {
    static let shared = APIService()

    private let baseURL: String

    init() {
        let rorkURL = MainActor.assumeIsolated { Config.EXPO_PUBLIC_RORK_API_BASE_URL }
        if !rorkURL.isEmpty {
            baseURL = rorkURL + "/api/rest"
        } else {
            baseURL = ""
        }
    }

    private func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard !baseURL.isEmpty else {
            throw APIError(message: "API base URL not configured")
        }

        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError(message: "Invalid URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError(message: "Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError(message: "HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    func register(phone: String, firstName: String, username: String) async throws -> APIUserResponse {
        return try await request("/users/register", method: "POST", body: [
            "phone": phone,
            "firstName": firstName,
            "username": username,
        ])
    }

    func getUserByPhone(_ phone: String) async throws -> APIUserResponse {
        return try await request("/users/by-phone/\(phone)")
    }

    func checkUsername(_ username: String) async throws -> Bool {
        let result: APIUsernameCheck = try await request("/users/check-username/\(username)")
        return result.available
    }

    func searchUsers(query: String, excludeUserId: String?) async throws -> [APIUserResponse] {
        var path = "/users/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        if let excludeId = excludeUserId {
            path += "&excludeUserId=\(excludeId)"
        }
        return try await request(path)
    }

    func getFriends(userId: String) async throws -> [APIUserResponse] {
        return try await request("/users/\(userId)/friends")
    }

    func getSongs(query: String? = nil) async throws -> [APISongResponse] {
        var path = "/songs"
        if let q = query, !q.isEmpty {
            path += "?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)"
        }
        return try await request(path)
    }

    func sendShare(senderId: String, recipientId: String, songId: String, note: String?) async throws -> APIShareResponse {
        return try await request("/shares", method: "POST", body: [
            "senderId": senderId,
            "recipientId": recipientId,
            "songId": songId,
            "note": note as Any,
        ])
    }

    func getReceivedShares(userId: String) async throws -> [APIShareResponse] {
        return try await request("/shares/received/\(userId)")
    }

    func getSentShares(userId: String) async throws -> [APIShareResponse] {
        return try await request("/shares/sent/\(userId)")
    }

    func connect(userAId: String, userBId: String) async throws {
        let _: [String: String] = try await request("/connections", method: "POST", body: [
            "userAId": userAId,
            "userBId": userBId,
        ])
    }
}
