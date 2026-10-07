import Foundation

/// `hankki --self-check`. 웹판의 테스트(tests/*.test.cjs)를 옮기고 동기화·메뉴·저장 점검을 더했다.
@MainActor enum Checks {
    private static var failures = 0

    private static func expect(_ name: String, _ condition: () throws -> Bool) {
        do {
            if try condition() { return }
            print("FAIL \(name)")
        } catch {
            print("FAIL \(name): \(error.localizedDescription)")
        }
        failures += 1
    }

    private static func run(_ sentence: String, pantry: Set<String> = [], staples: Set<String> = []) throws -> (pantry: Set<String>, staples: Set<String>) {
        var pantry = pantry, staples = staples
        _ = PantryLanguage.apply(try PantryLanguage.parse(sentence), pantry: &pantry, staples: &staples)
        return (pantry, staples)
    }

    static func run() -> Bool {
        failures = 0
        typealias C = PantryLanguage.Command

        // 문장으로 재료 관리
        expect("mixed requests and aliases") {
            let out = try run("당근이랑 양파 추가하고, 우유는 다 먹었어. 계란은 항상 있어", pantry: ["우유"])
            return out.pantry == ["당근", "양파"] && out.staples == ["달걀"]
        }
        expect("quantities and exact ingredients do not overlap") {
            try Set(PantryLanguage.parse("사과 2개와 오이 3개 추가해줘").map(\.ingredient)) == ["사과", "오이"]
                && PantryLanguage.parse("참기름 추가해줘") == [C(ingredient: "참기름", action: .add)]
        }
        expect("staple removal moves back to today") {
            try run("달걀은 상시 재료에서 빼줘", staples: ["달걀"]).pantry == ["달걀"]
                && run("달걀 다 먹었어", staples: ["달걀"]).staples.isEmpty
        }
        for text in ["우유 추가하지 마", "당근 빼지마", "우유가 있어?", "당근 있으면 넣어줘", "당근 추가하고 당근 삭제해줘", "양파 추가하고 우유는 나중에 살 거야"] {
            expect("refuses: \(text)") {
                do { _ = try PantryLanguage.parse(text); return false } catch { return true }
            }
        }
        expect("custom and persisted names") {
            try PantryLanguage.parse("콜라비 추가해줘") == [C(ingredient: "콜라비", action: .add)]
                && PantryLanguage.parse("루콜라는 항상 있어", known: ["루콜라"]) == [C(ingredient: "루콜라", action: .staple)]
        }
        expect("plain names add") {
            try Set(PantryLanguage.parse("두부, 시금치").map(\.ingredient)) == ["두부", "시금치"]
        }

        // 장보기 목록
        expect("shopping merges duplicates and remembers recipes") {
            var list: [ShoppingItem] = []
            let first = try ShoppingList.add(["두부", "애호박"], recipe: "두부 채소 덮밥", to: &list)
            let second = try ShoppingList.add(["두부", "간장"], recipe: "다른 메뉴", to: &list)
            return first == ["두부", "애호박"] && second == ["간장"] && list.count == 3
                && list.first { $0.name == "두부" }?.recipes == ["두부 채소 덮밥", "다른 메뉴"]
        }
        expect("re-adding a bought item unchecks it") {
            var list = [ShoppingItem(name: "우유", checked: true)]
            return try ShoppingList.add(["우유"], to: &list) == ["우유"] && !list[0].checked
        }
        expect("invalid names change nothing") {
            var list = [ShoppingItem(name: "당근")]
            do { try ShoppingList.add(["양파", "<b>"], to: &list); return false } catch { return list.count == 1 }
        }
        expect("stocking moves checked items and skips staples") {
            var kitchen = Kitchen(pantry: ["밥"], staples: ["달걀"],
                                  shopping: [ShoppingItem(name: "당근", checked: true), ShoppingItem(name: "달걀", checked: true), ShoppingItem(name: "양파")])
            let moved = ShoppingList.stock(&kitchen)
            return moved == ["당근", "달걀"] && kitchen.pantry == ["밥", "당근"] && kitchen.shopping.map(\.name) == ["양파"]
        }
        expect("shopping text and manual input") {
            ShoppingList.text([ShoppingItem(name: "두부", checked: true, recipes: ["덮밥"]), ShoppingItem(name: "파")]) == "장보기 목록\n[x] 두부 (덮밥)\n[ ] 파"
                && ShoppingList.text([]).isEmpty
                && ShoppingList.names(from: "계란, 우유 시금치") == ["달걀", "우유", "시금치"]
        }

        // 메뉴 고르기
        let kitchen = Kitchen(pantry: ["밥", "당근", "양파"], staples: ["달걀", "식용유"])
        expect("only recipes we can make") {
            Menu.candidates(kitchen, DrawOptions()).map(\.id) == ["f1"]
        }
        expect("baby age and exclusions") {
            var options = DrawOptions(audience: .baby, babyAge: 0, onlyWhatWeHave: false)
            let infant = Menu.candidates(kitchen, options).map(\.id)
            options.babyAge = 1
            let toddler = Menu.candidates(kitchen, options).map(\.id)
            options.excluded = ["달걀", "대두"]
            let excluded = Menu.candidates(kitchen, options).map(\.id)
            return !infant.contains("b8") && toddler.contains("b8") && !excluded.contains("b8") && !excluded.contains("b5")
        }
        expect("baby age is fixed at 2+ and shows every baby menu") {
            let options = DrawOptions(audience: .baby, onlyWhatWeHave: false)
            return options.babyAge == 2
                && Menu.candidates(Kitchen(), options).count == Catalog.recipes.filter { $0.audience == .baby }.count
        }
        expect("recipes use known ingredients and unique ids") {
            let known = Set(Catalog.groups.flatMap(\.items))
            return Catalog.recipes.allSatisfy { $0.ingredients.allSatisfy { known.contains($0) } }
                && Set(Catalog.recipes.map(\.id)).count == Catalog.recipes.count
        }
        expect("draw avoids the previous pick") {
            let two = Array(Catalog.recipes.prefix(2))
            return (0..<20).allSatisfy { _ in Menu.pick(two, previous: "f1")?.id == "f2" } && Menu.pick([], previous: nil) == nil
        }

        // 동기화 변경 계산
        expect("sync changes round trip") {
            let before = Kitchen(pantry: ["밥"], staples: ["달걀"], favorites: ["f1"])
            let after = Kitchen(pantry: ["당근"], staples: ["달걀", "밥"], favorites: ["f2"], shopping: [ShoppingItem(name: "우유")])
            let changes = KitchenSync.changes(from: before, to: after)
            let row = KitchenSync.applying(changes, to: KitchenSync.row(before))
            let rebuilt = KitchenSync.kitchen(row, keeping: after)
            return changes.count == 4 && rebuilt == after
                && changes.contains(KitchenChange(kind: "ingredient", key: "밥", value: "staple"))
                && changes.contains(KitchenChange(kind: "favorite", key: "f1", value: "deleted"))
        }
        expect("server row decoding") {
            let json = #"{"items":{"당근":"today","달걀":"staple"},"favorites":{"f1":true},"revision":3}"#
            let row = try JSONDecoder().decode(KitchenRow.self, from: Data(json.utf8))
            let kitchen = KitchenSync.kitchen(row, keeping: Kitchen())
            return kitchen.pantry == ["당근"] && kitchen.staples == ["달걀"] && kitchen.favorites == ["f1"]
        }
        expect("cloud refuses secret keys") {
            do { _ = try Cloud(url: "https://example.supabase.co", key: "sb_secret_test"); return false } catch {}
            do { _ = try Cloud(url: "http://example.supabase.co", key: "sb_publishable_test"); return false } catch {}
            return (try? Cloud(url: "https://example.supabase.co", key: "sb_publishable_test")) != nil
        }

        // 저장
        expect("store saves and reloads") {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hankki-check-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = Store(directory: dir, useCloud: false)
            guard store.applySentence("콜라비 추가하고 달걀은 상시 재료에서 빼줘") else { return false }
            store.addToShopping(["우유"])
            store.toggleFavorite("f3")
            let reloaded = Store(directory: dir, useCloud: false)
            return reloaded.kitchen == store.kitchen && reloaded.kitchen.pantry.contains("콜라비")
                && reloaded.kitchen.pantry.contains("달걀") && reloaded.kitchen.shopping.map(\.name) == ["우유"]
        }
        expect("undo restores the previous sentence") {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hankki-check-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = Store(directory: dir, useCloud: false)
            let before = store.kitchen
            store.applySentence("시금치 추가해줘")
            store.undoSentence()
            return store.kitchen == before
        }

        print(failures == 0 ? "PASS" : "\(failures) check(s) failed")
        return failures == 0
    }
}
