import Foundation

/// 재료 분류·알레르기 묶음·레시피. 원본은 hankki/catalog.json 이고, scripts/build-catalog.py 가
/// 검사한 뒤 CatalogData.swift 에 문자열로 넣는다. 앱은 처음 쓸 때 한 번 해석한다.
/// f1–f8·b1–b8 은 0.2.0 웹판에서 옮겼고, 나머지는 흔한 집밥·유아식(만 2세 이상) 레시피를 앱 형식에 맞게 새로 쓴 것이다.
enum Catalog {
    struct File: Decodable {
        var categories: [String]
        var groups: [IngredientGroup]
        var allergens: [IngredientGroup]
        var recipes: [Recipe]
    }

    static let file: File = {
        do {
            return try JSONDecoder().decode(File.self, from: Data(CatalogData.json.utf8))
        } catch {
            fatalError("레시피 목록을 읽지 못했어요: \(error)")
        }
    }()

    static let categories = file.categories
    static let groups = file.groups
    static let allergens = file.allergens
    static let recipes = file.recipes
}
