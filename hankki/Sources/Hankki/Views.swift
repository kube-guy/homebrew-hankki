import AppKit
import SwiftUI

enum Palette {
    static let ink = Color(red: 0x25 / 255, green: 0x39 / 255, blue: 0x30 / 255)
    static let muted = Color(red: 0x74 / 255, green: 0x79 / 255, blue: 0x6e / 255)
    static let paper = Color(red: 0xfc / 255, green: 0xfb / 255, blue: 0xf7 / 255)
    static let orange = Color(red: 0xff / 255, green: 0x97 / 255, blue: 0x5f / 255)
    static let line = Color(red: 0xe6 / 255, green: 0xe7 / 255, blue: 0xdd / 255)
    static let green = Color(red: 0xea / 255, green: 0xf0 / 255, blue: 0xe6 / 255)
    static let greenLine = Color(red: 0xc4 / 255, green: 0xd2 / 255, blue: 0xb9 / 255)
    static let cream = Color(red: 0xff / 255, green: 0xf4 / 255, blue: 0xe9 / 255)
    static let step = Color(red: 0xaf / 255, green: 0x64 / 255, blue: 0x40 / 255)
    static let warn = Color(red: 0x9a / 255, green: 0x47 / 255, blue: 0x2e / 255)
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSync = false
    @State private var detail: Recipe?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                HStack(alignment: .top, spacing: 20) {
                    PantryPanel()
                    ChooserPanel(detail: $detail)
                }
                ShoppingPanel()
                RecipeCollection(detail: $detail)
                BabyGuide()
                if let problem = store.saveProblem {
                    Text(problem).font(.caption).foregroundStyle(Palette.warn)
                }
            }
            .padding(32)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
        .sheet(item: $detail) { RecipeDetail(recipe: $0).environmentObject(store) }
        .sheet(isPresented: $showingSync) { SyncSheet().environmentObject(store) }
        .task {
            await store.start()
            // 창이 앞에 있을 때 10초마다 다른 기기의 변경을 확인한다.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if NSApp.isActive { await store.syncNow() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.syncNow() } }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("◡")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Palette.orange)
                .frame(width: 42, height: 42)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("한 끼 꾸러미").font(.system(size: 24, weight: .heavy))
                Text("작은 재료로, 다정한 한 끼").font(.callout).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button { showingSync = true } label: {
                Label(store.account == nil ? "동기화" : "동기화됨", systemImage: store.account == nil ? "icloud" : "checkmark.icloud")
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Palette.green, in: Capsule())
                    .overlay(Capsule().stroke(Palette.greenLine))
            }
            .buttonStyle(.plain)
            .help(store.syncStatus)
        }
        .padding(.bottom, 6)
    }
}

// MARK: - 공통 조각

struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            row = max(row, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                Text(title)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(selected ? Palette.green : Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Palette.greenLine : Palette.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PanelTitle: View {
    let step: String
    let title: String
    var body: some View {
        HStack(spacing: 10) {
            Text(step).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.step)
            Text(title).font(.system(size: 20, weight: .bold))
        }
    }
}

struct FeedbackText: View {
    let feedback: Feedback
    var body: some View {
        Text(feedback.text)
            .font(.callout)
            .foregroundStyle(feedback.isError ? Palette.warn : Palette.ink)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(feedback.isError ? Color(red: 1, green: 0.94, blue: 0.92) : Palette.green, in: RoundedRectangle(cornerRadius: 9))
            .textSelection(.enabled)
    }
}

extension View {
    func panel() -> some View {
        padding(26)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line))
    }
}

// MARK: - 01 재료

struct PantryPanel: View {
    @EnvironmentObject var store: Store
    @State private var sentence = ""
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelTitle(step: "01", title: "오늘 있는 재료")
                Spacer()
                Button("오늘 재료 비우기") { store.clearToday() }.buttonStyle(.link).foregroundStyle(Palette.muted)
            }
            Text("냉장고 속 재료를 톡톡 골라 주세요.").font(.callout).foregroundStyle(Palette.muted)
            commandBox
            if let feedback = store.commandFeedback { FeedbackText(feedback: feedback) }
            if store.canUndo { Button("방금 변경 되돌리기") { store.undoSentence() }.buttonStyle(.link) }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("재료 찾기 또는 직접 입력 (Enter로 추가)", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { if store.applySentence(query) { query = "" } }
                Button { if store.applySentence(query) { query = "" } } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("입력한 재료 추가")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
            staples
            Text("오늘 추가할 재료").font(.system(size: 14, weight: .bold))
            ingredientRows
            Divider()
            HStack {
                Text("\(store.kitchen.pantry.count)").font(.system(size: 17, weight: .bold)).foregroundColor(Palette.step)
                    + Text("개 담았어요").font(.caption).foregroundColor(Palette.muted)
                Spacer()
                Text("물은 기본 재료로 포함해요").font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .panel()
    }

    private var commandBox: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("말로 알려주세요").font(.system(size: 14, weight: .bold))
            TextField("당근이랑 양파 추가하고, 우유는 삭제해줘. 달걀은 항상 있어.", text: $sentence, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.9, green: 0.86, blue: 0.81)))
                .onSubmit(apply)
            HStack {
                Text("추가 · 삭제 · 상시 등록을 한 번에").font(.caption).foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.37))
                Spacer()
                Button("재료 반영", action: apply)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .disabled(sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(15)
        .background(Palette.cream, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(red: 0.94, green: 0.84, blue: 0.76)))
    }

    private func apply() {
        if store.applySentence(sentence) { sentence = "" }
    }

    private var staples: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("늘 있는 상시 재료").font(.system(size: 14, weight: .bold))
                Spacer()
                Text("추천에 자동 포함").font(.caption).foregroundStyle(Palette.muted)
            }
            if store.kitchen.staples.isEmpty {
                Text("항상 두는 재료를 등록해 보세요.").font(.caption).foregroundStyle(Palette.muted)
            } else {
                FlowLayout {
                    ForEach(store.kitchen.staples.sorted(), id: \.self) { name in
                        Label(name, systemImage: "checkmark")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.26, green: 0.38, blue: 0.21))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            DisclosureGroup("상시 재료 관리") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("항상 두는 재료를 골라 주세요. 오늘의 재료를 비워도 유지돼요.").font(.caption).foregroundStyle(Palette.muted)
                    FlowLayout {
                        ForEach(store.stapleChoices, id: \.self) { name in
                            Chip(title: name, selected: store.kitchen.staples.contains(name)) { store.toggleStaple(name) }
                        }
                    }
                }
                .padding(.top, 8)
            }
            .font(.callout)
        }
        .padding(15)
        .background(Color(red: 0.95, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.86, green: 0.9, blue: 0.83)))
    }

    private var groups: [IngredientGroup] {
        var all = Catalog.groups
        if !store.customIngredients.isEmpty { all.append(IngredientGroup(name: "추가", items: store.customIngredients)) }
        let q = query.trimmingCharacters(in: .whitespaces)
        return all.map { group in
            IngredientGroup(name: group.name, items: group.items.filter { (q.isEmpty || $0.contains(q)) && !store.kitchen.staples.contains($0) })
        }.filter { !$0.items.isEmpty }
    }

    private var ingredientRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            if groups.isEmpty {
                Text("등록된 재료가 없어요. 위 입력란에 적고 Enter를 눌러 추가할 수 있어요.").font(.caption).foregroundStyle(Palette.muted)
            }
            ForEach(groups) { group in
                HStack(alignment: .top, spacing: 10) {
                    Text(group.name).font(.caption).foregroundStyle(Palette.muted).frame(width: 44, alignment: .leading).padding(.top, 7)
                    FlowLayout {
                        ForEach(group.items, id: \.self) { name in
                            Chip(title: name, selected: store.kitchen.pantry.contains(name)) { store.toggleIngredient(name) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 02 메뉴 고르기

struct ChooserPanel: View {
    @EnvironmentObject var store: Store
    @Binding var detail: Recipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelTitle(step: "02", title: "누구를 위한 한 끼인가요?")
            HStack(spacing: 10) {
                modeCard(.family, symbol: "face.smiling", title: "가족 한 끼", note: "함께 먹는 든든한 메뉴")
                modeCard(.baby, symbol: "heart", title: "아기 한 끼", note: "우리 아이를 위한 메뉴")
            }
            if store.options.audience == .baby {
                Label("아기 연령 · 만 2세 이상", systemImage: "figure.and.child.holdinghands")
                    .font(.callout)
                Text("만 2세 이상 아이 기준으로 모든 아기 메뉴를 보여 줘요. 이미 먹어본 재료와 아이에게 맞는 크기·질감을 확인해 주세요.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            DisclosureGroup("알레르기 · 제외할 재료 (\(store.options.excluded.count)개)") {
                VStack(alignment: .leading, spacing: 8) {
                    FlowLayout {
                        ForEach(Menu.exclusionChoices, id: \.self) { name in
                            Chip(title: name, selected: store.options.excluded.contains(name)) {
                                if store.options.excluded.remove(name) == nil { store.options.excluded.insert(name) }
                            }
                        }
                    }
                    Text("선택한 재료가 포함된 메뉴를 제외해요. 실제 식품의 원재료·교차접촉도 확인해 주세요.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                .padding(.top, 8)
            }
            .font(.callout)
            Toggle("있는 재료만으로 만들 수 있는 메뉴", isOn: $store.options.onlyWhatWeHave).toggleStyle(.checkbox)
            Button { store.draw() } label: {
                Label("오늘의 메뉴 뽑기", systemImage: "die.face.5")
                    .font(.system(size: 18, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Palette.orange, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: .command)
            Text("조건에 맞는 메뉴 \(store.candidates.count)가지 · \(store.options.onlyWhatWeHave ? "모든 재료 보유 기준" : "부족한 재료가 있는 메뉴도 포함")")
                .font(.caption).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
            result
        }
        .panel()
        .onChange(of: store.options) { _, _ in store.clearDraw() }
    }

    private func modeCard(_ audience: Audience, symbol: String, title: String, note: String) -> some View {
        let active = store.options.audience == audience
        return Button { store.options.audience = audience } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .bold))
                    Text(note).font(.caption2).foregroundStyle(Palette.muted)
                }
                Spacer()
                if active { Image(systemName: "checkmark") }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(active ? Color(red: 0.96, green: 0.97, blue: 0.95) : Color.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(active ? Palette.ink : Palette.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    static func summary(_ recipe: Recipe, missing: [String]) -> String {
        var parts = ["\(recipe.minutes)분", missing.isEmpty ? "담아둔 재료로 만들 수 있어요" : "더 필요한 재료: \(missing.joined(separator: ", "))"]
        if recipe.audience == .baby { parts.append("만 \(recipe.ageYears)세부터 참고") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var result: some View {
        if let recipe = store.drawn {
            let need = store.kitchen.missing(recipe)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    Text(recipe.emoji).font(.system(size: 48))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("오늘의 한 끼, 골랐어요!").font(.caption).foregroundStyle(Color(red: 1, green: 0.71, blue: 0.55))
                        Text(recipe.name).font(.system(size: 22, weight: .bold))
                        Text(Self.summary(recipe, missing: need))
                            .font(.callout).foregroundStyle(Color(red: 0.84, green: 0.88, blue: 0.82))
                    }
                }
                HStack {
                    if !need.isEmpty { Button("부족한 재료 담기") { store.addMissing(of: recipe) } }
                    Button("다시 뽑기") { store.draw() }
                    Spacer()
                    Button("레시피 보기") { detail = recipe }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Palette.ink)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 18))
        } else if store.drewNothing {
            VStack(alignment: .leading, spacing: 6) {
                Text("조건에 맞는 메뉴가 없어요").font(.caption).foregroundStyle(Color(red: 1, green: 0.71, blue: 0.55))
                Text("재료를 조금 더 담아볼까요?").font(.title3.bold())
                Text("재료·제외 조건을 바꾸거나, ‘있는 재료만’ 옵션을 해제해 주세요.").font(.callout)
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

// MARK: - 03 장보기

struct ShoppingPanel: View {
    @EnvironmentObject var store: Store
    @State private var input = ""
    @State private var confirmingClear = false

    var body: some View {
        let list = store.kitchen.shopping
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PanelTitle(step: "03", title: "장보기 목록")
                if !list.isEmpty {
                    Text("\(list.filter { !$0.checked }.count)/\(list.count)").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.orange)
                }
                Spacer()
                if !list.isEmpty { Button("목록 복사") { store.copyShopping() }.buttonStyle(.link) }
            }
            Text("메뉴에 부족한 재료를 담거나 직접 적어 두세요. 산 재료를 체크하고 냉장고에 넣으면 오늘 재료로 옮겨져요.")
                .font(.callout).foregroundStyle(Palette.muted)
            HStack {
                Image(systemName: "cart").foregroundStyle(Palette.muted)
                TextField("살 재료 입력 (예: 두부, 시금치)", text: $input).textFieldStyle(.plain).onSubmit(add)
                Button("담기", action: add).buttonStyle(.borderedProminent).tint(Palette.ink)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
            if let feedback = store.shoppingFeedback { FeedbackText(feedback: feedback) }
            if list.isEmpty {
                Text("아직 담은 재료가 없어요.").font(.callout).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(list) { item in row(item) }
                }
            }
            HStack {
                Button("산 재료 냉장고에 넣기") { store.stockShopping() }
                    .buttonStyle(.borderedProminent).tint(Palette.orange)
                    .disabled(!list.contains(where: \.checked))
                Spacer()
                if !list.isEmpty { Button("목록 비우기") { confirmingClear = true }.buttonStyle(.link).foregroundStyle(Palette.muted) }
            }
            Text("장보기 목록은 이 Mac에만 저장돼요.").font(.caption).foregroundStyle(Palette.muted)
        }
        .panel()
        .confirmationDialog("장보기 목록을 모두 비울까요?", isPresented: $confirmingClear) {
            Button("비우기", role: .destructive) { store.clearShopping() }
        }
    }

    private func add() {
        if store.addToShopping(ShoppingList.names(from: input)) { input = "" }
    }

    private func row(_ item: ShoppingItem) -> some View {
        let note = ([store.kitchen.has(item.name) ? "냉장고에 있어요" : ""] + [item.recipes.joined(separator: ", ")])
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { item.checked }, set: { _ in store.toggleShopping(item.name) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.system(size: 14, weight: .bold)).strikethrough(item.checked)
                    if !note.isEmpty { Text(note).font(.caption).foregroundStyle(Palette.muted).lineLimit(1).help(note) }
                }
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 0)
            Button { store.removeShopping(item.name) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("\(item.name) 목록에서 빼기")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
        .opacity(item.checked ? 0.6 : 1)
    }
}

// MARK: - 레시피 꾸러미

struct RecipeCollection: View {
    enum Filter: String, CaseIterable { case all = "모두", family = "가족 메뉴", baby = "아기 메뉴", saved = "찜한 메뉴" }
    @EnvironmentObject var store: Store
    @Binding var detail: Recipe?
    @State private var filter = Filter.all

    private var recipes: [Recipe] {
        Catalog.recipes.filter {
            switch filter {
            case .all: return true
            case .family: return $0.audience == .family
            case .baby: return $0.audience == .baby
            case .saved: return store.kitchen.favorites.contains($0.id)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A LITTLE COLLECTION OF GOOD MEALS").font(.system(size: 10, weight: .bold)).kerning(2).foregroundStyle(Palette.muted)
                    Text("우리 집 레시피 꾸러미").font(.system(size: 22, weight: .bold))
                        + Text("  \(Catalog.recipes.count)가지").font(.callout).foregroundColor(Palette.muted)
                }
                Spacer()
                Picker("레시피 종류", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if recipes.isEmpty {
                Text("아직 찜한 메뉴가 없어요. 마음에 드는 레시피의 ♡를 눌러 주세요.")
                    .foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(35)
                    .background(Color(red: 0.94, green: 0.95, blue: 0.91), in: RoundedRectangle(cornerRadius: 15))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                    ForEach(recipes) { card($0) }
                }
            }
        }
        .padding(.top, 14)
    }

    private func card(_ recipe: Recipe) -> some View {
        let need = store.kitchen.missing(recipe).count
        let saved = store.kitchen.favorites.contains(recipe.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button { detail = recipe } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.emoji).font(.system(size: 34)).frame(width: 66, height: 66)
                        .background(Color(red: 0.96, green: 0.94, blue: 0.9), in: Circle())
                        .padding(.bottom, 8)
                    Text(recipe.audience == .baby ? "아기 메뉴 · 만 \(recipe.ageYears)세부터" : "가족 메뉴")
                        .font(.caption2).foregroundStyle(Color(red: 0.55, green: 0.38, blue: 0.27))
                    Text(recipe.name).font(.system(size: 16, weight: .bold)).lineLimit(2, reservesSpace: true)
                    Text("\(recipe.minutes)분 · \(recipe.ingredients.count)가지 재료").font(.caption).foregroundStyle(Palette.muted)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            HStack {
                Text(need == 0 ? "✓ 지금 만들 수 있어요" : "재료 \(need)개 더 필요")
                    .foregroundStyle(need == 0 ? Color(red: 0.39, green: 0.5, blue: 0.27) : Color(red: 0.62, green: 0.52, blue: 0.42))
                Spacer()
                Text(recipe.audience == .baby ? "순한 맛" : "집밥").foregroundStyle(Palette.muted)
            }
            .font(.caption)
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line))
        .overlay(alignment: .topTrailing) {
            Button { store.toggleFavorite(recipe.id) } label: {
                Image(systemName: saved ? "heart.fill" : "heart").font(.title3)
                    .foregroundStyle(saved ? Color(red: 0.84, green: 0.44, blue: 0.28) : Color(red: 0.54, green: 0.57, blue: 0.51))
            }
            .buttonStyle(.plain)
            .padding(14)
            .help(saved ? "\(recipe.name) 찜 해제" : "\(recipe.name) 찜하기")
        }
    }
}

struct RecipeDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe

    var body: some View {
        let need = store.kitchen.missing(recipe)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(recipe.emoji).font(.system(size: 44))
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.title3) }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction).help("레시피 닫기")
                }
                Text((recipe.audience == .baby ? "아기 메뉴 · 참고 연령 만 \(recipe.ageYears)세부터" : "가족 메뉴") + " · \(recipe.minutes)분")
                    .font(.caption).foregroundStyle(Color(red: 0.55, green: 0.38, blue: 0.27))
                Text(recipe.name).font(.system(size: 26, weight: .bold))
                Text("준비할 재료").font(.headline)
                Text(recipe.amounts.joined(separator: " · "))
                    .font(.callout).lineSpacing(6)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12))
                if !need.isEmpty {
                    HStack {
                        Text("더 필요한 재료: \(need.joined(separator: ", "))").font(.caption).foregroundStyle(Palette.muted)
                        Spacer()
                        Button("부족한 재료 장보기에 담기") { store.addMissing(of: recipe); dismiss() }
                    }
                }
                Text("이렇게 만들어요").font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1).").bold()
                            Text(step).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if recipe.audience == .baby {
                    Text("재료량은 조리 예시이며 1회 권장 섭취량이 아니에요. 연령만으로 적합성을 판단하지 말고 이미 먹어본 재료와 아이의 발달을 확인하세요. 소금·설탕·꿀은 넣지 않아요.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }
            .padding(30)
        }
        .frame(width: 540, height: 600)
        .background(Color.white)
        .foregroundStyle(Palette.ink)
    }
}

struct BabyGuide: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "heart").font(.title)
            VStack(alignment: .leading, spacing: 8) {
                Text("아기와 함께하는 식탁은 조금 더 세심하게").font(.system(size: 15, weight: .bold))
                Text("이유식은 보통 생후 약 6개월, 준비가 되었을 때 시작해요. 돌 전 꿀은 피하고, 모든 음식은 충분히 익혀 발달에 맞는 크기와 질감으로 주세요. 앉은 자세에서 보호자가 지켜봐 주세요.")
                    .font(.callout).foregroundStyle(Color(red: 0.4, green: 0.44, blue: 0.37))
                HStack(spacing: 14) {
                    Link("이유식 시작 안내 · CDC", destination: URL(string: "https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/when-what-and-how-to-introduce-solid-foods.html")!)
                    Link("질식 예방 안내", destination: URL(string: "https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/choking-hazards.html")!)
                }
                .font(.caption)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.94, green: 0.95, blue: 0.91), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 동기화

struct SyncSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("어디서든 같은 냉장고").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            Text("같은 이메일로 로그인한 기기끼리 오늘 재료·상시 재료·찜을 동기화해요. 장보기 목록은 이 Mac에만 저장돼요.")
                .font(.callout).foregroundStyle(Palette.muted)
            Text(store.syncStatus).font(.callout).textSelection(.enabled)
            if store.cloud == nil {
                Text("Supabase 연결 정보가 없어 이 Mac에만 저장하고 있어요. ~/.config/hankki/config.json 에 supabaseURL·supabaseKey 를 적은 뒤 앱을 다시 열어 주세요.")
                    .font(.caption).foregroundStyle(Palette.warn)
            } else if let account = store.account {
                Text(account.email ?? "로그인됨").bold()
                if store.needsChoice {
                    Text("처음 연결하는 Mac이에요. 저장된 재료를 어떻게 할까요?")
                    HStack {
                        Button("이 Mac 재료도 합치기") { Task { await store.choose(merge: true) } }
                        Button("클라우드 재료 불러오기") { Task { await store.choose(merge: false) } }
                    }
                }
                HStack {
                    Button("지금 동기화") { Task { await store.syncNow() } }.disabled(store.needsChoice)
                    Button("로그아웃") { Task { await store.signOut() } }
                }
                Text("로그아웃하면 이 Mac의 재료와 찜은 비워지고 클라우드에는 보관돼요.").font(.caption).foregroundStyle(Palette.muted)
            } else if store.codeSentTo != nil {
                TextField("메일로 받은 로그인 코드", text: $code).textFieldStyle(.roundedBorder).onSubmit(verify)
                HStack {
                    Button("로그인", action: verify).buttonStyle(.borderedProminent).tint(Palette.ink)
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || store.syncBusy)
                    Button("다른 이메일로") { code = ""; store.cancelCode() }
                }
            } else {
                TextField("이메일 주소", text: $email).textFieldStyle(.roundedBorder).onSubmit(send)
                Button("로그인 코드 받기", action: send).buttonStyle(.borderedProminent).tint(Palette.ink)
                    .disabled(email.isEmpty || store.syncBusy)
            }
            if store.syncBusy { ProgressView().controlSize(.small) }
        }
        .padding(28)
        .frame(width: 460)
        .background(Color.white)
        .foregroundStyle(Palette.ink)
    }

    private func send() { Task { await store.sendCode(to: email) } }
    private func verify() { Task { await store.verify(code: code); if store.account != nil { code = "" } } }
}
