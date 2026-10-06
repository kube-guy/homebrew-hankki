import Foundation

struct Session: Codable {
    var access_token: String
    var refresh_token: String
    var expires_at: Int?
}

/// 익명 로그인 세션을 Keychain 에 둔다. Security 프레임워크를 직접 부르지 않고 `/usr/bin/security` 를 거친다.
/// ad-hoc 서명 앱은 빌드마다 서명이 바뀌어, 프레임워크로 접근하면 실행할 때마다 "키체인 접근 허용" 창이 뜬다.
/// `security` 가 만든 항목은 `security` 자신을 신뢰하므로 앱을 다시 빌드해도 묻지 않는다.
/// 서비스 이름은 v2: 예전 빌드가 프레임워크로 만든 항목을 건드리면 그 자체로 허용 창이 뜬다.
enum Vault {
    static let service = "app.lunchdraw.session.v2"

    static func read(_ account: String) throws -> Data? {
        let (status, out) = try run(["find-generic-password", "-s", service, "-a", account, "-w"])
        if status == 44 { return nil }  // 항목 없음
        guard status == 0 else { throw failure(status) }
        let text = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // 값에 출력할 수 없는 문자가 있으면 security 는 16진수로 돌려준다. 세션 JSON 은 보통 평문으로 나온다.
        return hexDecoded(text) ?? Data(text.utf8)
    }

    static func write(_ data: Data, account: String) throws {
        // 토큰을 인자로 넘기면 프로세스 목록에 보인다. `security -i` 의 표준 입력으로 명령을 넘긴다.
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -s \(service) -a \(account) -X \(hex)\n"
        let (status, _) = try run(["-i"], input: Data(command.utf8))
        guard status == 0 else { throw failure(status) }
    }

    private static func run(_ arguments: [String], input: Data? = nil) throws -> (Int32, Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe(), stdin = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        try process.run()
        if let input {
            stdin.fileHandleForWriting.write(input)
            try stdin.fileHandleForWriting.close()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    private static func hexDecoded(_ text: String) -> Data? {
        guard text.count % 2 == 0, !text.isEmpty, text.allSatisfy(\.isHexDigit) else { return nil }
        var bytes = [UInt8](); bytes.reserveCapacity(text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte); index = next
        }
        return Data(bytes)
    }

    private static func failure(_ status: Int32) -> NSError {
        NSError(domain: "LunchDraw", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain 에 로그인 정보를 저장하지 못했습니다 (security \(status))."])
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
    /// isNew 는 이번에 익명 계정을 새로 만들었는지. 새 계정에는 클라우드 저장 행이 없으므로
    /// 호출하는 쪽이 저장 버전(revision)을 0 부터 다시 시작해야 한다.
    func session() async throws -> (session: Session, isNew: Bool) {
        if let saved = try Vault.read(base.host!), let old = try? JSONDecoder().decode(Session.self, from: saved) {
            if (old.expires_at ?? 0) > Int(Date().timeIntervalSince1970) + 60 { return (old, false) }
            // A failed refresh must not silently replace the user with a new identity.
            var components = URLComponents(url: base.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
            var req = URLRequest(url: components.url!); req.httpMethod = "POST"; req.timeoutInterval = 25
            req.setValue(key, forHTTPHeaderField: "apikey"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": old.refresh_token])
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NSError(domain: "LunchDraw", code: 3, userInfo: [NSLocalizedDescriptionKey: "로그인 갱신에 실패했습니다. 기존 식당 목록은 유지됩니다."]) }
            let session = try JSONDecoder().decode(Session.self, from: data)
            try Vault.write(data, account: base.host!); return (session, false)
        }
        let data = try await request("auth/v1/signup", method: "POST", body: Data("{}".utf8))
        let session = try JSONDecoder().decode(Session.self, from: data)
        try Vault.write(data, account: base.host!); return (session, true)
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
