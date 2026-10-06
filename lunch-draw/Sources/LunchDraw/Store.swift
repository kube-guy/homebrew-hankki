import SwiftUI

/// Supabase 연결 정보는 저장소에 두지 않는다. 키만 있으면 기본 지점과 식당 목록을 읽을 수 있기 때문이다.
/// 찾는 순서:
/// 1. 앱 번들 Info.plist — scripts/package-app.sh 가 config.local.json 값을 넣는다
/// 2. 환경 변수 LUNCH_DRAW_SUPABASE_URL / KEY — `swift run` 개발용
/// 3. ~/.config/lunch-draw/config.json — Homebrew 설치본용 (config.example.json 과 같은 형식)
enum AppConfig {
    static var url: String { value("LunchDrawSupabaseURL", env: "LUNCH_DRAW_SUPABASE_URL", file: "supabaseURL") }
    static var key: String { value("LunchDrawSupabaseKey", env: "LUNCH_DRAW_SUPABASE_KEY", file: "supabaseKey") }
    static let configFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/lunch-draw/config.json")
    private static func value(_ plistKey: String, env: String, file fileKey: String) -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String, !value.isEmpty { return value }
        if let value = ProcessInfo.processInfo.environment[env], !value.isEmpty { return value }
        guard let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return json[fileKey] as? String ?? ""
    }
}

@MainActor final class Store: ObservableObject {
    @Published var state = SavedState()
    @Published var busy = false
    @Published var status = "이 Mac에 저장됨"
    @Published var error: String?
    @Published var category = "전체"
    @Published var favoritesOnly = false
    @Published var newOnly = false
    @Published var search = ""
    let file: URL
    private var pendingSync: Task<Void, Never>?
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LunchDraw")
        file = dir.appendingPathComponent("state.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // 첫 실행에는 식당 목록이 비어 있다. 앱이 뜨면 sync() 가 Supabase 에서 받아온다.
            if FileManager.default.fileExists(atPath: file.path) {
                state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file))
            } else {
                try persist()
            }
        } catch { self.error = "저장 파일을 읽지 못했습니다: \(error.localizedDescription)" }
    }
    var origin: Origin? { state.effectiveOrigin }
    func distance(_ restaurant: Restaurant) -> Double? { origin.map { restaurant.distance(from: $0) } }
    func eligible(_ restaurant: Restaurant) -> Bool { origin.map { restaurant.eligible(from: $0) } ?? false }
    var candidates: [Restaurant] {
        guard let origin else { return [] }
        return state.restaurants.filter {
            $0.eligible(from: origin) && !state.excluded.contains($0.id) &&
            (category == "전체" || $0.theme.rawValue == category) &&
            (!favoritesOnly || state.favorites.contains($0.id)) &&
            (!newOnly || $0.isNew) &&
            (search.isEmpty || ($0.name + $0.menu + $0.category).localizedCaseInsensitiveContains(search))
        }.sorted { $0.distance(from: origin) < $1.distance(from: origin) }
    }
    var categories: [String] { ["전체"] + CuisineTheme.allCases.map(\.rawValue) }
    /// 새로오픈인데 평점이나 가격이 아직 없어 추천에 못 들어간 곳.
    var pendingNew: [Restaurant] {
        guard let origin else { return [] }
        return state.restaurants.filter {
            $0.isNew && !$0.eligible(from: origin) && $0.distance(from: origin) <= origin.radiusMeters
                && [$0.naverRating, $0.googleRating].compactMap { $0 }.allSatisfy { $0 >= 4 }
        }
    }
    var selected: Restaurant? { state.restaurants.first { $0.id == state.selectedID } }
    var visibleSelected: Restaurant? { selected.flatMap { restaurant in candidates.contains(restaurant) ? restaurant : nil } }
    func refreshRecommendationForFilter() {
        if !candidates.isEmpty && visibleSelected == nil { pick() }
    }
    func persist() throws { try JSONEncoder().encode(state).write(to: file, options: .atomic) }
    func changed() {
        do { try persist(); status = "이 Mac에 저장됨 · 클라우드 저장 대기" }
        catch { self.error = error.localizedDescription; return }
        pendingSync?.cancel()
        pendingSync = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await sync()
        }
    }
    func pick() {
        guard let restaurant = Draw.pick(candidates, drawn: state.drawn, previous: state.selectedID) else { return }
        if candidates.allSatisfy({ state.drawn.contains($0.id) }) { state.drawn.removeAll() }
        state.selectedID = restaurant.id; state.drawn.insert(restaurant.id); changed()
    }
    func favorite(_ id: String) {
        if state.favorites.contains(id) { state.favorites.remove(id) } else { state.favorites.insert(id) }
        changed()
    }
    /// 기준 지점을 바꾸면 거리 조건이 달라지므로 뽑기 기록과 현재 추천을 비운다.
    func setOrigin(_ origin: Origin?) {
        guard state.origin != origin else { return }
        state.origin = origin; state.drawn.removeAll(); state.selectedID = nil
        changed()
    }
    func setRadius(_ meters: Double) {
        guard var next = state.effectiveOrigin, next.radiusMeters != meters else { return }
        next.radiusMeters = meters
        setOrigin(next)
    }
    func exclude(_ id: String) { state.excluded.insert(id); changed() }
    func visited(_ id: String) { state.visits[id] = Date(); changed() }
    func sync() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let cloud = try Cloud(url: AppConfig.url, key: AppConfig.key)
            let session = try await cloud.session()
            if let fresh = try await cloud.defaultOrigin(session: session), fresh != state.defaultOrigin {
                state.defaultOrigin = fresh
            }
            if state.restaurants.isEmpty {
                state.restaurants = try await cloud.catalog(session: session)
            }
            let saving = state
            let revision = try await cloud.save(saving, session: session)
            // Keep any UI edits made while the network request was running.
            let edited = state != saving
            state.revision = revision; try persist()
            status = edited ? "새 변경사항 저장 대기" : "Supabase에 저장됨"
            if edited { changed() }
        } catch { status = "Mac에 저장됨 · 클라우드 저장 재시도 필요"; self.error = error.localizedDescription }
    }
    func reset() async {
        guard !busy else { return }
        pendingSync?.cancel(); busy = true; defer { busy = false }
        do {
            let cloud = try Cloud(url: AppConfig.url, key: AppConfig.key)
            let session = try await cloud.session()
            let fresh = try await cloud.catalog(session: session)
            guard fresh.contains(where: eligible) else { throw NSError(domain: "LunchDraw", code: 4, userInfo: [NSLocalizedDescriptionKey: "조건을 만족하는 식당이 없어 기존 목록을 유지합니다."]) }
            var next = state
            next.snapshots.append(Snapshot(restaurants: next.restaurants))
            next.restaurants = fresh; next.excluded.removeAll(); next.drawn.removeAll(); next.selectedID = nil
            next.revision = try await cloud.save(next, session: session)
            state = next; try persist(); status = "목록 재설정 완료 · Supabase에 저장됨"
        } catch { self.error = error.localizedDescription; status = "재설정 실패 · 기존 목록 유지" }
    }
    func restore(_ snapshot: Snapshot) {
        state.snapshots.append(Snapshot(restaurants: state.restaurants))
        state.restaurants = snapshot.restaurants; state.excluded.removeAll(); state.drawn.removeAll(); state.selectedID = nil
        changed()
    }
}
