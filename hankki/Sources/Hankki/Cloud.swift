import Foundation

/// Supabase 연결 정보는 저장소에 두지 않는다. 찾는 순서:
/// 1. 앱 번들 Info.plist 의 HankkiSupabaseURL / HankkiSupabaseKey
/// 2. 환경 변수 HANKKI_SUPABASE_URL / HANKKI_SUPABASE_KEY — `swift run` 개발용
/// 3. ~/.config/hankki/config.json — Homebrew 설치본용 (config.example.json 과 같은 형식)
enum AppConfig {
    static var url: String { value("HankkiSupabaseURL", env: "HANKKI_SUPABASE_URL", file: "supabaseURL") }
    static var key: String { value("HankkiSupabaseKey", env: "HANKKI_SUPABASE_KEY", file: "supabaseKey") }
    static let configFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/hankki/config.json")
    private static func value(_ plistKey: String, env: String, file fileKey: String) -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String, !value.isEmpty { return value }
        if let value = ProcessInfo.processInfo.environment[env], !value.isEmpty { return value }
        guard let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return json[fileKey] as? String ?? ""
    }
}

struct Account: Codable, Equatable {
    var id: String
    var email: String?
}

struct Session: Codable {
    var access_token: String
    var refresh_token: String
    var expires_at: Int?
    var user: Account?
}

/// 로그인 세션을 Keychain 에 둔다. Security 프레임워크를 직접 부르지 않고 `/usr/bin/security` 를 거친다.
/// ad-hoc 서명 앱은 빌드마다 서명이 바뀌어, 프레임워크로 접근하면 실행할 때마다 "키체인 접근 허용" 창이 뜬다.
enum Vault {
    static let service = "app.hankki.session.v1"

    static func read(_ account: String) throws -> Data? {
        let (status, out) = try run(["find-generic-password", "-s", service, "-a", account, "-w"])
        if status == 44 { return nil }  // 항목 없음
        guard status == 0 else { throw failure(status) }
        let text = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // 값에 출력할 수 없는 문자가 있으면 security 는 16진수로 돌려준다.
        return hexDecoded(text) ?? Data(text.utf8)
    }

    static func write(_ data: Data, account: String) throws {
        // 토큰을 인자로 넘기면 프로세스 목록에 보인다. `security -i` 의 표준 입력으로 명령을 넘긴다.
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let (status, _) = try run(["-i"], input: Data("add-generic-password -U -s \(service) -a \(account) -X \(hex)\n".utf8))
        guard status == 0 else { throw failure(status) }
    }

    static func delete(_ account: String) throws {
        let (status, _) = try run(["delete-generic-password", "-s", service, "-a", account])
        guard status == 0 || status == 44 else { throw failure(status) }
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
        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte); index = next
        }
        return Data(bytes)
    }

    private static func failure(_ status: Int32) -> AppError {
        AppError("Keychain 에 로그인 정보를 저장하지 못했어요 (security \(status)).")
    }
}

/// 서버의 apply_hankki_changes 가 받는 변경 한 건. 웹판과 같은 형식이다.
struct KitchenChange: Codable, Equatable {
    var kind: String   // "ingredient" | "favorite"
    var key: String
    var value: String  // ingredient: today | staple | deleted, favorite: saved | deleted
}

/// hankki_state 행. items 는 {재료: "today"|"staple"}, favorites 는 {레시피 id: true}.
struct KitchenRow: Decodable, Equatable {
    var items: [String: String] = [:]
    var favorites: [String: Bool] = [:]
}

enum KitchenSync {
    static func changes(from before: Kitchen, to after: Kitchen) -> [KitchenChange] {
        let a = row(before), b = row(after)
        var out: [KitchenChange] = []
        for key in Set(a.items.keys).union(b.items.keys).sorted() where a.items[key] != b.items[key] {
            out.append(KitchenChange(kind: "ingredient", key: key, value: b.items[key] ?? "deleted"))
        }
        for key in Set(a.favorites.keys).union(b.favorites.keys).sorted() where a.favorites[key] != b.favorites[key] {
            out.append(KitchenChange(kind: "favorite", key: key, value: b.favorites[key] == true ? "saved" : "deleted"))
        }
        return out
    }

    static func row(_ kitchen: Kitchen) -> KitchenRow {
        var row = KitchenRow()
        for name in kitchen.pantry { row.items[name] = "today" }
        for name in kitchen.staples { row.items[name] = "staple" }
        for id in kitchen.favorites { row.favorites[id] = true }
        return row
    }

    /// 아직 서버에 보내지 못한 변경을 서버 행 위에 다시 얹는다.
    static func applying(_ changes: [KitchenChange], to row: KitchenRow) -> KitchenRow {
        var row = row
        for change in changes {
            if change.kind == "ingredient" {
                row.items[change.key] = change.value == "deleted" ? nil : change.value
            } else {
                row.favorites[change.key] = change.value == "deleted" ? nil : true
            }
        }
        return row
    }

    /// 서버 행을 화면 상태로 바꾼다. 장보기 목록은 이 Mac 에만 있으므로 그대로 둔다.
    static func kitchen(_ row: KitchenRow, keeping local: Kitchen) -> Kitchen {
        var kitchen = local
        kitchen.pantry = Set(row.items.filter { $0.value == "today" }.keys)
        kitchen.staples = Set(row.items.filter { $0.value == "staple" }.keys)
        kitchen.favorites = Set(row.favorites.filter { $0.value }.keys)
        return kitchen
    }
}

struct Cloud {
    var base: URL
    var key: String

    init(url: String, key: String) throws {
        guard let u = URL(string: url), u.scheme == "https", let host = u.host, host.hasSuffix(".supabase.co"),
              u.path.isEmpty || u.path == "/", !key.isEmpty else {
            throw AppError("Supabase 연결 정보가 없어요. ~/.config/hankki/config.json 에 supabaseURL·supabaseKey 를 적어 주세요.")
        }
        // 관리자 키는 데스크톱 앱에 절대 넣지 않는다.
        guard !key.hasPrefix("sb_secret_") else { throw AppError("공개 publishable/anon 키만 사용할 수 있어요.") }
        if key.split(separator: ".").count == 3 {
            var payload = String(key.split(separator: ".")[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let data = Data(base64Encoded: payload),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["role"] as? String == "service_role" {
                throw AppError("service_role 키는 앱에 넣을 수 없어요.")
            }
        }
        base = u; self.key = key
    }

    var account: String { base.host ?? "supabase" }

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], json: Any? = nil, token: String? = nil) async throws -> Data {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.timeoutInterval = 25
        if let json { req.httpBody = try JSONSerialization.data(withJSONObject: json) }
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let reason = (body?["msg"] ?? body?["message"] ?? body?["error_description"]) as? String
            throw AppError("클라우드 요청 실패 (\(status))" + (reason.map { " · \($0)" } ?? ""))
        }
        return data
    }

    /// 이메일로 로그인 코드를 보낸다. 없는 계정이면 새로 만든다.
    func sendCode(to email: String) async throws {
        _ = try await request("auth/v1/otp", method: "POST", json: ["email": email, "create_user": true])
    }

    func verify(email: String, code: String) async throws -> Session {
        let data = try await request("auth/v1/verify", method: "POST", json: ["type": "email", "email": email, "token": code])
        let session = try JSONDecoder().decode(Session.self, from: data)
        try Vault.write(data, account: account)
        return session
    }

    /// 저장된 세션. 만료가 가까우면 갱신한다. 로그인한 적이 없으면 nil.
    func session() async throws -> Session? {
        guard let saved = try Vault.read(account), let old = try? JSONDecoder().decode(Session.self, from: saved) else { return nil }
        if (old.expires_at ?? 0) > Int(Date().timeIntervalSince1970) + 60 { return old }
        let data = try await request("auth/v1/token", method: "POST", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                     json: ["refresh_token": old.refresh_token])
        var session = try JSONDecoder().decode(Session.self, from: data)
        if session.user == nil { session.user = old.user }
        try Vault.write(JSONEncoder().encode(session), account: account)
        return session
    }

    func signOut(_ session: Session) async {
        _ = try? await request("auth/v1/logout", method: "POST", query: [URLQueryItem(name: "scope", value: "local")], token: session.access_token)
        try? Vault.delete(account)
    }

    func fetch(_ session: Session) async throws -> KitchenRow {
        guard let id = session.user?.id else { throw AppError("로그인 정보에 사용자 ID가 없어요. 다시 로그인해 주세요.") }
        let data = try await request("rest/v1/hankki_state", query: [
            URLQueryItem(name: "select", value: "items,favorites"), URLQueryItem(name: "user_id", value: "eq.\(id)"),
        ], token: session.access_token)
        return try JSONDecoder().decode([KitchenRow].self, from: data).first ?? KitchenRow()
    }

    /// 같은 요청 ID 는 서버가 한 번만 적용한다. 전송 도중 끊겨도 같은 ID 로 다시 보내면 된다.
    func apply(_ changes: [KitchenChange], requestID: UUID, session: Session) async throws -> KitchenRow {
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changes))
        let data = try await request("rest/v1/rpc/apply_hankki_changes", method: "POST",
                                     json: ["p_request_id": requestID.uuidString.lowercased(), "p_changes": payload], token: session.access_token)
        return try JSONDecoder().decode(KitchenRow.self, from: data)
    }
}
