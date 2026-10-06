import Foundation

enum Checks {
    /// 실제 식당 목록·기준 지점은 Supabase 에만 있으므로, 검사는 가상의 지점과 식당으로 한다.
    static let origin = Origin(name: "테스트 지점", latitude: 37.5, longitude: 127.0, radiusMeters: 1000)

    static func fixture(_ id: String, _ category: String, _ name: String, _ menu: String,
                        north meters: Double = 200, naver: Double? = 4.3, google: Double? = 4.2) -> Restaurant {
        Restaurant(id: id, name: name, category: category, address: "테스트 주소", menu: menu, price: 12_000,
                   latitude: origin.latitude + meters / 111_000, longitude: origin.longitude,
                   naverRating: naver, googleRating: google, naverReviews: 100, googleReviews: 50,
                   naverURL: "https://example.com/n", googleURL: "https://example.com/g", priceURL: "https://example.com/p",
                   checkedAt: "2026-01-01", note: "", tags: nil, openingURL: nil, openedAt: nil,
                   ratingSourceURL: nil, priceCheckedAt: nil, newOpenCheckedAt: nil)
    }

    static let fixtures: [Restaurant] = [
        fixture("k1", "한식", "가 국밥", "돼지국밥"),
        fixture("k2", "육류,고기요리", "나 고깃집", "점심 정식", north: 400),
        fixture("c1", "중식당", "다 반점", "짬뽕", north: 300),
        fixture("j1", "돈가스", "라 카츠", "등심카츠", north: 500),
        fixture("w1", "이탈리아음식", "마 키친", "파스타", north: 600),
        fixture("a1", "베트남음식", "바 포", "쌀국수", north: 700),
        fixture("far", "한식", "사 식당", "백반", north: 1_500),
        fixture("low", "한식", "아 식당", "백반", naver: 3.8, google: 4.4),
    ]

    @MainActor static func run() {
        do {
            let eligible = fixtures.filter { $0.eligible(from: origin) }
            precondition(eligible.map(\.id) == ["k1", "k2", "c1", "j1", "w1", "a1"])
            var r = eligible[0]
            r.price = 30_000; precondition(!r.eligible(from: origin))
            r.price = 29_999; precondition(r.eligible(from: origin))
            r.naverRating = nil; precondition(r.eligible(from: origin))
            r.googleRating = nil; precondition(!r.eligible(from: origin))
            r.naverRating = 4.2; precondition(r.eligible(from: origin))
            r.naverRating = 3.9; precondition(!r.eligible(from: origin))
            r.googleRating = 4.5; r.naverRating = 3.9; precondition(!r.eligible(from: origin))
            r.naverRating = 4.5; r.googleRating = 3.9; precondition(!r.eligible(from: origin))
            r.googleRating = 4.5; r.latitude += 0.02; precondition(!r.eligible(from: origin))
            var wide = origin; wide.radiusMeters = 2_000
            precondition(fixtures.first { $0.id == "far" }!.eligible(from: wide))

            let first = Draw.pick(eligible, drawn: [], previous: nil)!
            let next = Draw.pick(eligible, drawn: [first.id], previous: first.id)!
            precondition(first.id != next.id)
            precondition(Draw.pick([], drawn: [], previous: nil) == nil)
            precondition(Draw.pick([first], drawn: [first.id], previous: first.id)?.id == first.id)
            do { _ = try Cloud(url: "https://example.supabase.co", key: "sb_secret_test"); preconditionFailure("secret accepted") } catch {}

            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lunch-draw-check-\(UUID())")
            let store = Store(directory: dir)
            precondition(store.candidates.isEmpty, "기준 지점 없이는 추천하지 않는다")
            store.state.restaurants = fixtures
            store.state.defaultOrigin = origin
            store.state.favorites.insert(first.id); try store.persist()
            let restored = Store(directory: dir)
            precondition(restored.state.favorites.contains(first.id))
            precondition(restored.origin == origin)
            precondition(restored.candidates.count == eligible.count)

            // 기준 지점 변경: 사용자 값이 기본값보다 앞서고, 되돌리면 기본값을 쓴다.
            let moved = Origin(name: "다른 지점", latitude: origin.latitude + 1_500 / 111_000, longitude: origin.longitude)
            restored.state.selectedID = first.id
            restored.setOrigin(moved)
            precondition(restored.origin == moved && restored.state.selectedID == nil)
            precondition(restored.candidates.contains { $0.id == "far" })
            restored.setRadius(2_000)
            precondition(restored.origin?.radiusMeters == 2_000 && restored.origin?.name == "다른 지점")
            restored.setOrigin(nil)
            precondition(restored.origin == origin)
            let legacy = try JSONDecoder().decode(SavedState.self, from: Data(#"{"restaurants":[],"favorites":[],"excluded":[],"drawn":[],"visits":{},"snapshots":[],"revision":3}"#.utf8))
            precondition(legacy.origin == nil && legacy.revision == 3)
            let bare = try JSONDecoder().decode(Origin.self, from: Data(#"{"name":"x","latitude":1,"longitude":2}"#.utf8))
            precondition(bare.radiusMeters == 1000)

            precondition(CuisineTheme.classify(category: "새로오픈", name: "가 카츠", menu: "카츠 도시락") == .japanese)
            precondition(CuisineTheme.classify(category: "새로오픈", name: "나 미식", menu: "양지쌀국수") == .asian)
            precondition(CuisineTheme.classify(category: "새로오픈", name: "다 반점", menu: "짜장면") == .chinese)
            precondition(CuisineTheme.classify(category: "새로오픈", name: "라 버거", menu: "치즈버거") == .western)
            precondition(CuisineTheme.classify(category: "새로오픈", name: "마 순대", menu: "순대국밥") == .korean)
            precondition(CuisineTheme.classify(category: "중식당", name: "x", menu: "x") == .chinese)
            precondition(CuisineTheme.classify(category: "돈가스", name: "x", menu: "x") == .japanese)
            precondition(CuisineTheme.classify(category: "베트남음식", name: "x", menu: "x") == .asian)
            precondition(CuisineTheme.classify(category: "이탈리아음식", name: "x", menu: "x") == .western)
            precondition(CuisineTheme.classify(category: "육류,고기요리", name: "x", menu: "x") == .korean)

            restored.state.drawn.removeAll()
            for theme in CuisineTheme.allCases {
                restored.category = theme.rawValue
                precondition(restored.candidates.allSatisfy { $0.theme == theme })
            }
            restored.category = "전체"
            // 500m 필터: 기본 반경(1km) 안에서도 500m 넘는 곳은 뺀다.
            restored.nearOnly = true
            precondition(!restored.candidates.isEmpty && restored.candidates.allSatisfy { $0.distance(from: restored.origin!) <= Store.nearMeters })
            precondition(!restored.candidates.contains { $0.id == "w1" || $0.id == "a1" })
            restored.nearOnly = false
            restored.state.selectedID = first.id
            precondition(restored.visibleSelected?.id == first.id)
            let differentTheme = CuisineTheme.allCases.first { theme in
                theme != first.theme && eligible.contains { $0.theme == theme }
            }
            if let differentTheme {
                restored.category = differentTheme.rawValue
                precondition(restored.visibleSelected == nil)
                restored.refreshRecommendationForFilter()
                precondition(restored.visibleSelected?.theme == differentTheme)
            }
            // 목록 자동 갱신: 같으면 그대로, 다르면 교체하고 기록은 남은 식당에 한해 유지한다.
            precondition(!restored.applyCatalog(restored.state.restaurants))
            restored.state.excluded = ["k1", "gone"]
            var renewed = fixtures.filter { $0.id != "k2" }
            renewed[0].tags = ["새로오픈"]
            let snapshotsBefore = restored.state.snapshots.count
            precondition(restored.applyCatalog(renewed))
            precondition(restored.state.restaurants == renewed && restored.state.restaurants[0].isNew)
            precondition(restored.state.excluded == ["k1"])
            precondition(restored.state.favorites.contains(first.id))
            precondition(restored.state.snapshots.count == min(snapshotsBefore + 1, Store.maxSnapshots))
            for n in 0..<5 { renewed[0].note = "갱신 \(n)"; restored.applyCatalog(renewed) }
            precondition(restored.state.snapshots.count == Store.maxSnapshots)

            r = eligible[0]; r.naverRating = nil; r.tags = ["새로오픈"]; r.openingURL = "https://example.com/opening"
            precondition(r.isNew && r.eligible(from: origin))
            let roundTrip = try JSONDecoder().decode(Restaurant.self, from: JSONEncoder().encode(r))
            precondition(roundTrip == r)
            try? FileManager.default.removeItem(at: dir)
            print("PASS: budget, radius, ratings, origin, draw, persistence, cuisine filters")
        } catch { fputs("Verification failed: \(error)\n", stderr); exit(1) }
    }
}
