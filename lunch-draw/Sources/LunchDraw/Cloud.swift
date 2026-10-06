import Foundation
import Security

struct Session: Codable {
    var access_token: String
    var refresh_token: String
    var expires_at: Int?
}

enum Vault {
    static func read(_ account: String) throws -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.lunchdraw.session", kSecAttrAccount as String: account, kSecReturnData as String: true]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return value as? Data
    }
    static func write(_ data: Data, account: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.lunchdraw.session", kSecAttrAccount as String: account]
        let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = q; add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        } else if update != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(update)) }
    }
}

struct Cloud {
    var base: URL
    var key: String
    init(url: String, key: String) throws {
        guard let u = URL(string: url), u.scheme == "https", let host = u.host, host.hasSuffix(".supabase.co"), u.path.isEmpty || u.path == "/", !key.isEmpty else {
            throw NSError(domain: "LunchDraw", code: 1, userInfo: [NSLocalizedDescriptionKey: "Supabase 연결 정보가 없습니다. ~/.config/lunch-draw/config.json 에 supabaseURL·supabaseKey 를 적어주세요."])
        }
        // Secret and service-role keys must never be used by the desktop client.
        guard !key.hasPrefix("sb_secret_") else { throw NSError(domain: "LunchDraw", code: 2, userInfo: [NSLocalizedDescriptionKey: "공개 publishable/anon 키만 사용할 수 있습니다."]) }
        if key.split(separator: ".").count == 3 {
            var payload = String(key.split(separator: ".")[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let data = Data(base64Encoded: payload), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["role"] as? String == "service_role" {
                throw NSError(domain: "LunchDraw", code: 2, userInfo: [NSLocalizedDescriptionKey: "service_role 키는 앱에 넣을 수 없습니다."])
            }
        }
        base = u; self.key = key
    }
    func request(_ path: String, method: String = "GET", body: Data? = nil, token: String? = nil) async throws -> Data {
        var req = URLRequest(url: base.appendingPathComponent(path)); req.httpMethod = method; req.httpBody = body; req.timeoutInterval = 25
        req.setValue(key, forHTTPHeaderField: "apikey")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "LunchDraw", code: status, userInfo: [NSLocalizedDescriptionKey: "클라우드 요청 실패 (\(status)). 연결·익명 로그인·데이터베이스 설정을 확인해주세요."])
        }
        return data
    }
    func session() async throws -> Session {
        if let saved = try Vault.read(base.host!), let old = try? JSONDecoder().decode(Session.self, from: saved) {
            if (old.expires_at ?? 0) > Int(Date().timeIntervalSince1970) + 60 { return old }
            // A failed refresh must not silently replace the user with a new identity.
            var components = URLComponents(url: base.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
            var req = URLRequest(url: components.url!); req.httpMethod = "POST"; req.timeoutInterval = 25
            req.setValue(key, forHTTPHeaderField: "apikey"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": old.refresh_token])
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NSError(domain: "LunchDraw", code: 3, userInfo: [NSLocalizedDescriptionKey: "로그인 갱신에 실패했습니다. 기존 식당 목록은 유지됩니다."]) }
            let session = try JSONDecoder().decode(Session.self, from: data)
            try Vault.write(data, account: base.host!); return session
        }
        let data = try await request("auth/v1/signup", method: "POST", body: Data("{}".utf8))
        let session = try JSONDecoder().decode(Session.self, from: data)
        try Vault.write(data, account: base.host!); return session
    }
    struct Reply: Decodable { var revision: Int; var state: SavedState? }
    func save(_ state: SavedState, session: Session) async throws -> Int {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
        let body = try JSONSerialization.data(withJSONObject: ["p_state": object, "p_expected_revision": state.revision])
        let reply = try JSONDecoder().decode(Reply.self, from: await request("rest/v1/rpc/save_lunch_state", method: "POST", body: body, token: session.access_token))
        return reply.revision
    }
    /// 모두에게 적용되는 기본 기준 지점. 설정 행이 없으면 nil.
    func defaultOrigin(session: Session) async throws -> Origin? {
        let data = try await request("rest/v1/rpc/lunch_default_origin", method: "POST", body: Data("{}".utf8), token: session.access_token)
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "null" { return nil }
        return try JSONDecoder().decode(Origin.self, from: data)
    }
    func catalog(session: Session) async throws -> [Restaurant] {
        try JSONDecoder().decode([Restaurant].self, from: await request("rest/v1/rpc/lunch_catalog", method: "POST", body: Data("{}".utf8), token: session.access_token))
    }
}
