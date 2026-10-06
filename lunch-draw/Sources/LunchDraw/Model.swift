import Foundation

struct Restaurant: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: String
    var address: String
    var menu: String
    var price: Int
    var latitude: Double
    var longitude: Double
    var naverRating: Double?
    var googleRating: Double?
    var naverReviews: Int?
    var googleReviews: Int?
    var naverURL: String
    var googleURL: String
    var priceURL: String
    var checkedAt: String
    var note: String
    var tags: [String]?
    var openingURL: String?
    var openedAt: String?
    var ratingSourceURL: String?
    var priceCheckedAt: String?
    var newOpenCheckedAt: String?
    var isNew: Bool { (tags ?? []).contains("새로오픈") }
    var theme: CuisineTheme { CuisineTheme.classify(category: category, name: name, menu: menu) }
    func distance(from origin: Origin) -> Double { Geo.distance(from: origin, to: latitude, longitude) }
    /// 공개된 평점(네이버·구글)이 하나 이상 있고, 있는 평점은 모두 4.0 이상이어야 한다.
    /// 구글 평점이 아직 없는 신상도 네이버 평점이 4.0 이상이면 후보에 넣는다.
    var ratingsOK: Bool {
        let ratings = [naverRating, googleRating].compactMap { $0 }
        return !ratings.isEmpty && ratings.allSatisfy { $0 >= 4 }
    }
    var priceOK: Bool { price > 0 && price < 30_000 }
    func eligible(from origin: Origin) -> Bool {
        priceOK && ratingsOK && distance(from: origin) <= origin.radiusMeters
    }
}

enum CuisineTheme: String, CaseIterable {
    case korean = "한식", chinese = "중식", japanese = "일식", western = "양식", asian = "아시아", other = "기타"

    /// 네이버·SeoulRestaurants 업종 이름을 먼저 보고, '새로오픈'처럼 업종이 없으면 이름·메뉴로 짐작한다.
    static func classify(category: String, name: String, menu: String) -> Self {
        func has(_ text: String, any words: [String]) -> Bool { words.contains { text.contains($0) } }
        let chinese = ["중식", "중국", "양꼬치", "마라", "딤섬", "훠궈"]
        let japanese = ["일식", "일본", "초밥", "스시", "돈가스", "돈까스", "카츠", "라멘", "우동", "소바", "생선회", "회", "샤브샤브", "이자카야", "덮밥"]
        let western = ["양식", "이탈리아", "프랑스", "스페인", "멕시코", "피자", "파스타", "햄버거", "버거", "스테이크", "브런치", "샌드위치", "바스버거"]
        let asian = ["베트남", "태국", "인도", "아시아", "쌀국수", "동남아"]
        let korean = ["한식", "냉면", "분식", "육류", "고기", "설렁탕", "곰탕", "국밥", "해물", "생선", "복어", "족발", "보쌈", "갈비", "만두", "한정식", "감자탕", "곱창", "막창", "칼국수", "두부", "국수", "김밥", "순대", "닭", "백반", "찌개", "삼겹", "죽", "낙지", "주꾸미", "쭈꾸미"]
        if category != "새로오픈" && !category.isEmpty {
            if has(category, any: chinese) { return .chinese }
            if has(category, any: japanese) { return .japanese }
            if has(category, any: western) { return .western }
            if has(category, any: asian) { return .asian }
            if has(category, any: korean) { return .korean }
            return .other
        }

        let title = name.lowercased()
        let dish = menu.lowercased()
        if has(title, any: ["김밥", "한식", "장어", "순대", "국밥", "갈비", "찌개", "솥밥", "막창", "도시락"]) { return .korean }
        if has(title, any: ["양꼬치"]) || has(dish, any: ["양꼬치", "짜장", "짬뽕", "마라", "딤섬"]) { return .chinese }
        if has(title, any: ["카츠", "초밥", "스시"]) || has(dish, any: ["카츠", "초밥", "스시", "텐동", "우동", "사시미"]) { return .japanese }
        if has(dish, any: ["쌀국수", "카우팟"]) || has(title, any: ["타이", "베트남"]) { return .asian }
        if has(dish, any: ["파스타", "라구", "라자냐", "리가토니", "나폴리탄", "햄버거", "버거", "샌드위치", "치아바타", "잠봉", "카치오페페"]) || has(title, any: ["버거", "샌드위치", "비스트로"]) { return .western }
        if has(dish, any: ["타코", "비리아"]) || has(title, any: ["타코"]) { return .other }
        if has(dish, any: ["국밥", "비빔밥", "냉면", "찌개", "김밥", "감자탕", "곰탕", "칼국수", "막국수", "라볶이", "순두부", "샤브", "메밀", "육회", "솥밥", "된장", "닭강정", "등갈비"]) { return .korean }
        return .other
    }
}

/// 거리를 재는 기준 지점. 모두에게 적용되는 기본값은 Supabase `lunch_settings` 에 있고,
/// 사용자가 바꾼 값은 저장 상태(`SavedState.origin`)에 들어가 Supabase 에 함께 저장된다.
struct Origin: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double = 1000

    static let radiusChoices: [Double] = [500, 1000, 1500, 2000]

    init(name: String, latitude: Double, longitude: Double, radiusMeters: Double = 1000) {
        self.name = name; self.latitude = latitude; self.longitude = longitude; self.radiusMeters = radiusMeters
    }
    // Supabase 설정 행에 radiusMeters 가 빠져 있어도 1km 로 읽는다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        radiusMeters = try c.decodeIfPresent(Double.self, forKey: .radiusMeters) ?? 1000
    }
}

enum Geo {
    static func distance(from origin: Origin, to lat: Double, _ lon: Double) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((lat - origin.latitude) * r / 2), 2)
            + cos(origin.latitude * r) * cos(lat * r) * pow(sin((lon - origin.longitude) * r / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}

struct Snapshot: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var restaurants: [Restaurant]
}

struct SavedState: Codable, Equatable {
    var restaurants: [Restaurant] = []
    var favorites: Set<String> = []
    var excluded: Set<String> = []
    var drawn: Set<String> = []
    var visits: [String: Date] = [:]
    var snapshots: [Snapshot] = []
    var selectedID: String?
    var revision: Int = 0
    /// 사용자가 고른 기준 지점. nil 이면 `defaultOrigin` 을 쓴다.
    var origin: Origin?
    /// Supabase 에서 마지막으로 받아 둔 기본 지점. 오프라인에서도 거리를 계산하려고 보관한다.
    var defaultOrigin: Origin?
    var effectiveOrigin: Origin? { origin ?? defaultOrigin }
}

enum Draw {
    static func pick(_ candidates: [Restaurant], drawn: Set<String>, previous: String?) -> Restaurant? {
        let unseen = candidates.filter { !drawn.contains($0.id) }
        let pool = unseen.isEmpty ? candidates : unseen
        let alternatives = pool.filter { $0.id != previous }
        return (alternatives.isEmpty ? pool : alternatives).randomElement()
    }
}


