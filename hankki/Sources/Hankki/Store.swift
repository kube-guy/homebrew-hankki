import AppKit
import Foundation

struct Feedback: Equatable {
    var text: String
    var isError = false
}

/// 로그인한 계정별 전송 대기열. 오프라인에서 바꾼 내용도 다시 연결되면 보낸다.
struct SyncQueue: Codable {
    struct Batch: Codable { var id: UUID; var changes: [KitchenChange] }
    /// 이 Mac 을 해당 계정과 동기화하기로 정했는지 (처음 연결할 때 합치기/불러오기를 고른다).
    var connected = false
    var pending: [KitchenChange] = []
    var batch: Batch?
    var isEmpty: Bool { pending.isEmpty && batch == nil }
}

@MainActor final class Store: ObservableObject {
    @Published private(set) var kitchen: Kitchen
    @Published var options = DrawOptions()
    @Published private(set) var drawn: Recipe?
    @Published private(set) var drewNothing = false
    @Published var commandFeedback: Feedback?
    @Published private(set) var canUndo = false
    @Published var shoppingFeedback: Feedback?
    @Published private(set) var saveProblem: String?

    @Published private(set) var account: Account?
    @Published private(set) var syncStatus = "이 Mac에 저장 중"
    @Published private(set) var needsChoice = false
    @Published private(set) var codeSentTo: String?
    @Published private(set) var syncBusy = false
    let cloud: Cloud?
    let cloudProblem: String?

    private let directory: URL
    private var undo: (before: Kitchen, after: Kitchen)?
    private var lastDrawn: String?
    private var baseline = Kitchen()
    private var queue = SyncQueue()
    private var connected = false
    private var running = false
    /// 로그아웃·다른 계정 로그인 뒤에 도착한 이전 응답을 버리기 위한 세대 번호.
    private var generation = 0

    init(directory: URL? = nil, useCloud: Bool = true) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hankki")
        var loaded = Kitchen.starter
        var problem: String?
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("kitchen.json")
            if FileManager.default.fileExists(atPath: file.path) {
                loaded = try JSONDecoder().decode(Kitchen.self, from: Data(contentsOf: file))
                loaded.pantry.subtract(loaded.staples)
            }
        } catch {
            problem = "저장 파일을 읽지 못했어요: \(error.localizedDescription)"
        }
        let (cloud, cloudProblem): (Cloud?, String?) = useCloud ? Self.connect() : (nil, "동기화를 사용하지 않아요.")
        self.directory = dir
        self.cloud = cloud
        self.cloudProblem = cloudProblem
        kitchen = loaded
        saveProblem = problem
        if cloud == nil { syncStatus = "이 Mac에 저장 중 · 클라우드 연결 정보 없음" }
    }

    private nonisolated static func connect() -> (Cloud?, String?) {
        do { return (try Cloud(url: AppConfig.url, key: AppConfig.key), nil) }
        catch { return (nil, error.localizedDescription) }
    }

    // MARK: - 재료

    var knownIngredients: [String] { Catalog.groups.flatMap(\.items) + kitchen.pantry.sorted() + kitchen.staples.sorted() }
    /// 기본 분류에 없는 오늘 재료는 "추가" 분류로 보여준다.
    var customIngredients: [String] {
        let known = Set(Catalog.groups.flatMap(\.items))
        return kitchen.pantry.filter { !known.contains($0) }.sorted()
    }
    var stapleChoices: [String] {
        var seen = Set<String>()
        return (Catalog.groups.flatMap(\.items) + kitchen.pantry.sorted() + kitchen.staples.sorted()).filter { seen.insert($0).inserted }
    }

    @discardableResult
    func applySentence(_ text: String) -> Bool {
        do {
            let commands = try PantryLanguage.parse(text, known: knownIngredients)
            let before = kitchen
            var pantry = kitchen.pantry, staples = kitchen.staples
            let changes = PantryLanguage.apply(commands, pantry: &pantry, staples: &staples)
            edit { $0.pantry = pantry; $0.staples = staples }
            undo = (before, kitchen)
            canUndo = changes.contains { $0.before != $0.after }
            commandFeedback = Feedback(text: changes.map { "\($0.ingredient): \(Self.describe($0))" }.joined(separator: " · "))
            return true
        } catch {
            commandFeedback = Feedback(text: error.localizedDescription, isError: true)
            return false
        }
    }

    private static func describe(_ change: PantryLanguage.Change) -> String {
        if change.before == change.after { return "이미 반영되어 있어요" }
        switch change.after {
        case .staple: return "상시 재료에 등록했어요"
        case .today: return change.action == .unstaple ? "오늘 재료로 옮겼어요" : "추가했어요"
        case .absent: return "삭제했어요"
        }
    }

    func undoSentence() {
        guard let undo else { return }
        canUndo = false
        self.undo = nil
        guard kitchen.pantry == undo.after.pantry && kitchen.staples == undo.after.staples else {
            commandFeedback = Feedback(text: "그 뒤에 재료가 변경되어 되돌리지 않았어요. 새 문장으로 수정해 주세요.")
            return
        }
        edit { $0.pantry = undo.before.pantry; $0.staples = undo.before.staples }
        commandFeedback = Feedback(text: "방금 문장으로 바꾼 재료를 되돌렸어요.")
    }

    func toggleIngredient(_ name: String) {
        edit { if $0.pantry.remove(name) == nil { $0.pantry.insert(name) } }
    }

    func toggleStaple(_ name: String) {
        edit { if $0.staples.remove(name) == nil { $0.staples.insert(name); $0.pantry.remove(name) } }
    }

    func clearToday() { edit { $0.pantry.removeAll() } }

    func toggleFavorite(_ id: String) {
        edit { if $0.favorites.remove(id) == nil { $0.favorites.insert(id) } }
    }

    // MARK: - 메뉴 뽑기

    var candidates: [Recipe] { Menu.candidates(kitchen, options) }

    func draw() {
        let pick = Menu.pick(candidates, previous: lastDrawn)
        drawn = pick
        drewNothing = pick == nil
        if let pick { lastDrawn = pick.id }
    }

    func clearDraw() { drawn = nil; drewNothing = false }

    // MARK: - 장보기 목록

    func addMissing(of recipe: Recipe) {
        addToShopping(kitchen.missing(recipe), recipe: recipe.name)
    }

    @discardableResult
    func addToShopping(_ names: [String], recipe: String? = nil) -> Bool {
        guard !names.isEmpty else { return false }
        var list = kitchen.shopping
        do {
            let added = try ShoppingList.add(names, recipe: recipe, to: &list)
            edit { $0.shopping = list }
            shoppingFeedback = Feedback(text: added.isEmpty ? "이미 장보기 목록에 있어요." : "\(added.joined(separator: ", "))을(를) 장보기 목록에 담았어요.")
            return true
        } catch {
            shoppingFeedback = Feedback(text: error.localizedDescription, isError: true)
            return false
        }
    }

    func toggleShopping(_ name: String) {
        edit { kitchen in
            if let index = kitchen.shopping.firstIndex(where: { $0.name == name }) { kitchen.shopping[index].checked.toggle() }
        }
    }

    func removeShopping(_ name: String) { edit { $0.shopping.removeAll { $0.name == name } } }

    func stockShopping() {
        var moved: [String] = []
        edit { moved = ShoppingList.stock(&$0) }
        if !moved.isEmpty { shoppingFeedback = Feedback(text: "\(moved.joined(separator: ", "))을(를) 냉장고에 넣었어요.") }
    }

    func clearShopping() {
        edit { $0.shopping.removeAll() }
        shoppingFeedback = nil
    }

    func copyShopping() {
        let text = ShoppingList.text(kitchen.shopping)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        shoppingFeedback = Feedback(text: "장보기 목록을 복사했어요.")
    }

    // MARK: - 저장

    private func edit(_ change: (inout Kitchen) -> Void) {
        var next = kitchen
        change(&next)
        guard next != kitchen else { return }
        let ingredientsChanged = next.pantry != kitchen.pantry || next.staples != kitchen.staples
        kitchen = next
        if ingredientsChanged { clearDraw() }
        persist()
        queueLocalChanges()
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(kitchen).write(to: directory.appendingPathComponent("kitchen.json"), options: .atomic)
            saveProblem = nil
        } catch {
            saveProblem = "이 Mac에 저장하지 못했어요: \(error.localizedDescription)"
        }
    }

    // MARK: - 동기화

    func start() async {
        guard let cloud, account == nil else { return }
        do {
            if let session = try await cloud.session(), let user = session.user { activate(user) }
        } catch {
            syncStatus = "로그인 정보를 확인하지 못했어요 · \(error.localizedDescription)"
        }
    }

    func sendCode(to email: String) async {
        guard let cloud else { return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else { syncStatus = "이메일 주소를 확인해 주세요."; return }
        syncBusy = true
        defer { syncBusy = false }
        do {
            try await cloud.sendCode(to: email)
            codeSentTo = email
            syncStatus = "\(email)로 보낸 메일의 로그인 코드를 입력해 주세요."
        } catch {
            syncStatus = "로그인 메일을 보내지 못했어요 · \(error.localizedDescription)"
        }
    }

    func verify(code: String) async {
        guard let cloud, let email = codeSentTo else { return }
        syncBusy = true
        defer { syncBusy = false }
        do {
            let session = try await cloud.verify(email: email, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let user = session.user else { throw AppError("로그인 응답에 사용자 정보가 없어요.") }
            codeSentTo = nil
            activate(user)
        } catch {
            syncStatus = "로그인하지 못했어요. 코드를 다시 확인해 주세요 · \(error.localizedDescription)"
        }
    }

    func cancelCode() { codeSentTo = nil; syncStatus = "이 Mac에 저장 중" }

    private func activate(_ user: Account) {
        generation += 1
        account = user
        queue = loadQueue(user.id)
        baseline = kitchen
        if queue.connected {
            connected = true
            needsChoice = false
            Task { await syncNow() }
        } else {
            needsChoice = true
            syncStatus = "로그인됨 · 동기화 방법을 골라 주세요"
        }
    }

    /// 처음 연결할 때: merge 면 이 Mac 의 재료·찜을 클라우드에 더하고, 아니면 클라우드 목록을 그대로 불러온다.
    func choose(merge: Bool) async {
        guard account != nil else { return }
        if merge { queue.pending += KitchenSync.changes(from: Kitchen(), to: kitchen) }
        queue.connected = true
        saveQueue()
        baseline = kitchen
        connected = true
        needsChoice = false
        await syncNow()
    }

    private func queueLocalChanges() {
        guard connected, account != nil else { return }
        let changes = KitchenSync.changes(from: baseline, to: kitchen)
        guard !changes.isEmpty else { return }
        queue.pending += changes
        baseline = kitchen
        saveQueue()
        Task { await syncNow() }
    }

    func syncNow() async {
        guard connected, !running, let cloud, let user = account else { return }
        running = true
        defer { running = false }
        let current = generation
        syncStatus = "동기화 중…"
        do {
            guard let session = try await cloud.session() else { throw AppError("로그인이 만료됐어요. 다시 로그인해 주세요.") }
            guard current == generation else { return }
            if queue.batch == nil && !queue.pending.isEmpty {
                let count = min(500, queue.pending.count)
                queue.batch = SyncQueue.Batch(id: UUID(), changes: Array(queue.pending.prefix(count)))
                queue.pending.removeFirst(count)
                saveQueue()
            }
            let row: KitchenRow
            if let batch = queue.batch {
                row = try await cloud.apply(batch.changes, requestID: batch.id, session: session)
                guard current == generation else { return }
                queue.batch = nil
                saveQueue()
            } else {
                row = try await cloud.fetch(session)
                guard current == generation else { return }
            }
            // 기다리는 동안 생긴 이 Mac 의 변경은 서버 행 위에 다시 얹는다.
            let merged = KitchenSync.kitchen(KitchenSync.applying(queue.pending, to: row), keeping: kitchen)
            baseline = merged
            if merged.pantry != kitchen.pantry || merged.staples != kitchen.staples { clearDraw() }
            if merged != kitchen { kitchen = merged; persist() }
            let time = Date().formatted(date: .omitted, time: .shortened)
            syncStatus = queue.pending.isEmpty ? "동기화됨 · \(time)" : "변경 사항 전송 대기 중"
            if !queue.pending.isEmpty && user == account { Task { await syncNow() } }
        } catch {
            if current == generation { syncStatus = "동기화 대기 · 이 Mac에 저장했어요. 연결되면 다시 시도해요. (\(error.localizedDescription))" }
        }
    }

    func signOut() async {
        guard queue.isEmpty else {
            syncStatus = "전송할 변경 사항이 남아 있어요. 동기화가 끝난 뒤 로그아웃해 주세요."
            return
        }
        generation += 1
        connected = false
        if let cloud {
            if let session = try? await cloud.session() { await cloud.signOut(session) } else { try? Vault.delete(cloud.account) }
        }
        if let id = account?.id { try? FileManager.default.removeItem(at: queueFile(id)) }
        account = nil
        needsChoice = false
        queue = SyncQueue()
        // 클라우드에는 남아 있다. 장보기 목록은 이 Mac 에만 있으므로 지우지 않는다.
        kitchen = Kitchen(shopping: kitchen.shopping)
        clearDraw()
        persist()
        syncStatus = "로그아웃됨 · 이 Mac의 재료와 찜을 비웠어요"
    }

    private func queueFile(_ id: String) -> URL { directory.appendingPathComponent("sync-\(id).json") }

    private func loadQueue(_ id: String) -> SyncQueue {
        guard let data = try? Data(contentsOf: queueFile(id)) else { return SyncQueue() }
        return (try? JSONDecoder().decode(SyncQueue.self, from: data)) ?? SyncQueue()
    }

    private func saveQueue() {
        guard let id = account?.id else { return }
        do {
            try JSONEncoder().encode(queue).write(to: queueFile(id), options: .atomic)
        } catch {
            syncStatus = "전송 대기열을 저장하지 못해 동기화를 멈췄어요 · \(error.localizedDescription)"
            connected = false
        }
    }
}
