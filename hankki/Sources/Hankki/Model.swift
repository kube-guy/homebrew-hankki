import Foundation

enum Audience: String, Codable, CaseIterable { case family, baby }

struct Recipe: Identifiable, Hashable {
    var id: String
    var name: String
    var audience: Audience
    /// 아기 메뉴의 참고 시작 연령(개월). 가족 메뉴는 0.
    var ageMonths: Int
    var minutes: Int
    var emoji: String
    var ingredients: [String]
    var amounts: [String]
    var steps: [String]
    var ageYears: Int { ageMonths / 12 }
}

struct IngredientGroup: Identifiable, Hashable {
    var name: String
    var items: [String]
    var id: String { name }
}

struct ShoppingItem: Codable, Hashable, Identifiable {
    var name: String
    var checked = false
    /// 이 재료를 담게 한 메뉴 이름들. 직접 입력하면 비어 있다.
    var recipes: [String] = []
    var id: String { name }
}

struct AppError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// 재료·상시 재료·찜·장보기 목록. Mac 에 저장하고, 장보기 목록을 뺀 나머지는 클라우드와 동기화한다.
struct Kitchen: Codable, Equatable {
    var pantry: Set<String> = []
    var staples: Set<String> = []
    var favorites: Set<String> = []
    var shopping: [ShoppingItem] = []

    static let starter: Kitchen = {
        var kitchen = Kitchen(pantry: ["밥", "당근", "애호박"], staples: ["달걀", "식용유"])
        kitchen.pantry.subtract(kitchen.staples)
        return kitchen
    }()

    func has(_ ingredient: String) -> Bool { pantry.contains(ingredient) || staples.contains(ingredient) }
    func missing(_ recipe: Recipe) -> [String] { recipe.ingredients.filter { !has($0) } }
}

struct DrawOptions: Equatable {
    var audience: Audience = .family
    /// 아기 연령(만 나이). 앱에서는 만 2세 이상으로 고정해 아기 메뉴를 모두 보여 준다.
    var babyAge = 2
    var excluded: Set<String> = []
    var onlyWhatWeHave = true
}

enum Menu {
    static func isExcluded(_ recipe: Recipe, by excluded: Set<String>) -> Bool {
        excluded.contains { key in
            let items = Catalog.allergens.first { $0.name == key }?.items ?? [key]
            return items.contains { recipe.ingredients.contains($0) }
        }
    }

    static func candidates(_ kitchen: Kitchen, _ options: DrawOptions, recipes: [Recipe] = Catalog.recipes) -> [Recipe] {
        recipes.filter {
            $0.audience == options.audience &&
            (options.audience != .baby || $0.ageYears <= options.babyAge) &&
            !isExcluded($0, by: options.excluded) &&
            (!options.onlyWhatWeHave || kitchen.missing($0).isEmpty)
        }
    }

    /// 방금 뽑은 메뉴는 다른 후보가 있으면 다시 뽑지 않는다.
    static func pick(_ candidates: [Recipe], previous: String?) -> Recipe? {
        let others = candidates.filter { $0.id != previous }
        return (others.isEmpty ? candidates : others).randomElement()
    }

    /// 제외 목록에 보여줄 이름: 알레르기 묶음 다음에 묶음에 속하지 않은 기본 재료.
    static var exclusionChoices: [String] {
        let grouped = Set(Catalog.allergens.flatMap(\.items))
        var seen = Set<String>()
        let rest = Catalog.groups.flatMap(\.items).filter { !grouped.contains($0) && seen.insert($0).inserted }
        return Catalog.allergens.map(\.name) + rest
    }
}

enum ShoppingList {
    static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[가-힣A-Za-z]{1,15}$", options: .regularExpression) != nil
    }

    /// 새로 담았거나 다시 사야 할 것으로 바뀐 재료 이름을 돌려준다. 이름이 하나라도 잘못되면 아무것도 바꾸지 않는다.
    @discardableResult
    static func add(_ names: [String], recipe: String? = nil, to list: inout [ShoppingItem]) throws -> [String] {
        if let bad = names.first(where: { !isValidName($0) }) {
            throw AppError("‘\(bad)’은(는) 재료 이름으로 쓸 수 없어요. 한글이나 영문 15자 이내로 적어 주세요.")
        }
        var added: [String] = []
        for name in names {
            if let index = list.firstIndex(where: { $0.name == name }) {
                if list[index].checked { list[index].checked = false; added.append(name) }
                if let recipe, !list[index].recipes.contains(recipe) { list[index].recipes.append(recipe) }
            } else {
                list.append(ShoppingItem(name: name, recipes: recipe.map { [$0] } ?? []))
                added.append(name)
            }
        }
        return added
    }

    /// 체크한 재료를 오늘 재료로 옮긴다. 상시 재료는 이미 있으므로 목록에서만 뺀다.
    static func stock(_ kitchen: inout Kitchen) -> [String] {
        let bought = kitchen.shopping.filter(\.checked).map(\.name)
        for name in bought where !kitchen.staples.contains(name) { kitchen.pantry.insert(name) }
        kitchen.shopping.removeAll(where: \.checked)
        return bought
    }

    static func text(_ list: [ShoppingItem]) -> String {
        guard !list.isEmpty else { return "" }
        return (["장보기 목록"] + list.map { item in
            "\(item.checked ? "[x]" : "[ ]") \(item.name)" + (item.recipes.isEmpty ? "" : " (\(item.recipes.joined(separator: ", ")))")
        }).joined(separator: "\n")
    }

    /// 직접 입력: 쉼표·가운뎃점·공백으로 나누고 별칭을 통일한다.
    static func names(from input: String) -> [String] {
        input.components(separatedBy: CharacterSet(charactersIn: ",·").union(.whitespacesAndNewlines))
            .filter { !$0.isEmpty }
            .map { PantryLanguage.aliases[$0] ?? $0 }
    }
}
