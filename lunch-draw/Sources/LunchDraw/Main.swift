import SwiftUI
import AppKit
import MapKit

@main struct LunchDrawApp: App {
    @StateObject private var store = Store()
    init() {
        if CommandLine.arguments.contains("--version") { print("0.4.0"); exit(0) }
        if CommandLine.arguments.contains("--self-check") { Checks.run(); exit(0) }
        if CommandLine.arguments.contains("--cloud-check") {
            Task {
                do {
                    let cloud = try Cloud(url: AppConfig.url, key: AppConfig.key)
                    let session = try await cloud.session()
                    let catalog = try await cloud.catalog(session: session)
                    guard let origin = try await cloud.defaultOrigin(session: session) else {
                        fputs("Default origin is not set in lunch_settings\n", stderr); exit(1)
                    }
                    let eligible = catalog.filter { $0.eligible(from: origin) }.count
                    print("Cloud catalog: \(catalog.count); eligible: \(eligible) (default origin, \(Int(origin.radiusMeters))m)")
                    exit(0)
                } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            }
            RunLoop.main.run()
        }
    }
    var body: some Scene {
        WindowGroup("오늘 뭐 먹지 · Lunch Draw") { ContentView().environmentObject(store).frame(minWidth: 1100, minHeight: 650).task { await store.sync() } }
        .defaultSize(width: 1180, height: 760)
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var resetting = false
    @State private var history = false
    @State private var choosingOrigin = false
    private let red = Color(red: 0.85, green: 0.22, blue: 0.16)
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 290)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("점심 고민은 여기까지.").font(.system(size: 31, weight: .bold))
                            Text(store.origin.map { "\($0.name)에서 직선 \(Self.radiusText($0.radiusMeters)) · 대표 식사 30,000원 미만" }
                                 ?? "기준 지점을 불러오는 중이에요").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("LUNCH / DRAW").font(.system(.caption, design: .monospaced)).foregroundStyle(red)
                    }
                    recommendation
                    HStack {
                        Text("저장한 식당 \(store.candidates.count)곳").font(.title3.bold())
                        Spacer()
                        Button("목록 재설정", systemImage: "arrow.clockwise") { resetting = true }.disabled(store.busy)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(store.candidates) { row($0) }
                    }
                    if store.candidates.isEmpty {
                        ContentUnavailableView("조건에 맞는 식당이 없어요", systemImage: "fork.knife", description: Text(
                            store.origin == nil ? "Supabase 에서 기준 지점과 식당 목록을 받은 뒤에 추천할 수 있어요."
                                : "필터를 풀거나 반경을 넓혀보세요. 기준 지점 근처 식당이 목록에 없으면 관리자가 식당을 추가해야 합니다."))
                    }
                    if !store.pendingNew.isEmpty {
                        Text("새로오픈 · 평점·가격 확인 중 \(store.pendingNew.count)곳").font(.headline)
                        Text("아래 식당은 정보가 더 확인되면 랜덤 추천에 포함됩니다.").font(.caption).foregroundStyle(.secondary)
                        ForEach(store.pendingNew) { row($0) }
                    }
                    Text("평점·가격은 확인일 기준입니다. 영업시간과 대기는 지도에서 확인하세요. 목록 재설정은 Supabase에 저장된 최신 식당 목록을 가져옵니다.").font(.caption).foregroundStyle(.secondary)
                }.padding(30)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(red)
        .alert("식당 목록을 재설정할까요?", isPresented: $resetting) {
            Button("취소", role: .cancel) {}
            Button("재설정") { Task { await store.reset() } }
        } message: { Text("저장된 최신 식당 목록으로 교체하고 추천 제외·뽑기 기록을 초기화합니다. 즐겨찾기와 방문 기록은 유지하며, 이전 목록은 보관합니다.") }
        .alert("저장 상태 확인", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("확인") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .sheet(isPresented: $history) { historyView }
        .sheet(isPresented: $choosingOrigin) { OriginPicker().environmentObject(store) }
        .onChange(of: store.category) { _, _ in store.refreshRecommendationForFilter() }
        .onChange(of: store.favoritesOnly) { _, _ in store.refreshRecommendationForFilter() }
        .onChange(of: store.newOnly) { _, _ in store.refreshRecommendationForFilter() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("오늘 뭐 먹지", systemImage: "fork.knife.circle.fill").font(.title2.bold()).foregroundStyle(red)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("기준 지점").font(.headline)
                HStack {
                    Label(store.origin?.name ?? "불러오는 중", systemImage: "mappin.circle")
                    Spacer()
                    Button("변경") { choosingOrigin = true }.disabled(store.origin == nil)
                }
                if store.state.origin != nil {
                    Text("내가 고른 지점 · 기본값은 \(store.state.defaultOrigin?.name ?? "없음")").font(.caption).foregroundStyle(.secondary)
                }
                Picker("반경", selection: Binding(
                    get: { store.origin?.radiusMeters ?? 1000 },
                    set: { store.setRadius($0) })) {
                    ForEach(Origin.radiusChoices, id: \.self) { Text(Self.radiusText($0)).tag($0) }
                }.disabled(store.origin == nil)
            }
            Divider()
            TextField("식당·메뉴 검색", text: $store.search).textFieldStyle(.roundedBorder)
            Picker("먹고 싶은 종류", selection: $store.category) { ForEach(store.categories, id: \.self) { Text($0) } }
            Toggle("즐겨찾기에서만 추천", isOn: $store.favoritesOnly)
            Toggle("새로오픈만 추천", isOn: $store.newOnly)
            Button("식당 리스트 리셋", systemImage: "arrow.clockwise") { resetting = true }
                .disabled(store.busy)
            VStack(alignment: .leading, spacing: 9) {
                Text("추천 기준").font(.headline)
                Label("평점 4.0 이상", systemImage: "star.fill")
                Text("네이버·구글 중 공개된 평점이 모두 4.0 이상")
                Label("기준 지점 반경 \(Self.radiusText(store.origin?.radiusMeters ?? 1000))", systemImage: "location.circle")
                Label("대표 메뉴 3만원 미만", systemImage: "wonsign.circle")
            }.font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button("이전 목록", systemImage: "clock.arrow.circlepath") { history = true }
            Button("지금 클라우드에 저장", systemImage: "icloud.and.arrow.up") { Task { await store.sync() } }.disabled(store.busy)
            HStack {
                if store.busy { ProgressView().controlSize(.small) }
                Text(store.status).font(.caption).foregroundStyle(.secondary)
            }
            Text("Lunch Draw 0.4.0").font(.caption2).foregroundStyle(.tertiary)
        }.padding(24).background(Color(nsColor: .controlBackgroundColor))
    }
    private var recommendation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TODAY'S PICK").font(.system(.caption, design: .monospaced).bold()).foregroundStyle(red)
            if let restaurant = store.visibleSelected {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(restaurant.name).font(.system(size: 33, weight: .bold))
                        Text(restaurant.theme.rawValue).font(.caption.bold()).foregroundStyle(red)
                        Text("\(restaurant.menu) · \(restaurant.price.formatted())원").font(.title3)
                        badges(restaurant)
                        Text(restaurant.address).foregroundStyle(.secondary)
                        links(restaurant)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    RestaurantMapView(origin: store.origin, restaurant: restaurant).frame(width: 320, height: 300)
                }
                HStack {
                    Button("방문했어요", systemImage: "checkmark.circle") { store.visited(restaurant.id) }
                    Button("추천에서 제외", systemImage: "minus.circle") { store.exclude(restaurant.id); store.pick() }
                    Spacer()
                    Button("다시 뽑기", systemImage: "shuffle") { store.pick() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy || store.candidates.isEmpty)
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("오늘 점심, 어디로 갈까요?").font(.system(size: 29, weight: .bold))
                        Text("검증한 식당 중 한 곳을 골라드려요. 한 바퀴 돌 때까지 중복 추천을 줄입니다.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    RestaurantMapView(origin: store.origin, restaurant: nil).frame(width: 320, height: 300)
                }
                Button("랜덤으로 추천받기", systemImage: "shuffle") { store.pick() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy || store.candidates.isEmpty)
            }
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(red.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
    private func badges(_ r: Restaurant) -> some View {
        HStack(spacing: 12) {
            if let rating = r.naverRating { Text("N ★ \(rating, specifier: "%.2f")") }
            else { Text("N 별점 없음") }
            if let rating = r.googleRating { Text("G ★ \(rating, specifier: "%.1f")") }
            else { Text("G 평점 확인 중") }
            if let meters = store.distance(r) { Text("직선 \(Int(meters))m") }
        }.font(.caption.bold()).foregroundStyle(.secondary)
    }
    private func links(_ r: Restaurant) -> some View {
        HStack {
            if let url = URL(string: r.naverURL) { Link("네이버 지도 ↗", destination: url) }
            if let url = URL(string: r.googleURL) { Link("구글 지도 ↗", destination: url) }
            if let url = URL(string: r.priceURL) { Link("메뉴·가격 출처 ↗", destination: url) }
            if let source = r.ratingSourceURL, let url = URL(string: source) { Link("평점 출처 ↗", destination: url) }
        }.font(.caption)
    }
    private func row(_ r: Restaurant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(r.name).font(.headline)
                Spacer()
                Button { store.favorite(r.id) } label: { Image(systemName: store.state.favorites.contains(r.id) ? "heart.fill" : "heart") }.buttonStyle(.plain).accessibilityLabel("\(r.name) 즐겨찾기")
            }
            Text(r.price > 0 ? "\(r.menu) · \(r.price.formatted())원" : "메뉴·가격 확인 중").font(.subheadline)
            Text(r.theme.rawValue).font(.caption.bold()).foregroundStyle(.secondary)
            if r.isNew {
                HStack {
                    Text("새로오픈").font(.caption.bold()).foregroundStyle(red)
                    if let source = r.openingURL, let url = URL(string: source) { Link("개업 확인 ↗", destination: url).font(.caption) }
                    if let date = r.openedAt { Text(date).font(.caption).foregroundStyle(.secondary) }
                }
            }
            badges(r)
            Text(r.address).font(.caption).foregroundStyle(.secondary)
            links(r)
            Text("평점 기준 \(r.checkedAt)" + (r.googleReviews.map { " · 구글 \($0)개 리뷰" } ?? " · 구글 평점 확인 중")).font(.caption2).foregroundStyle(.tertiary)
            if let date = r.priceCheckedAt { Text("가격 기준 \(date)").font(.caption2).foregroundStyle(.tertiary) }
            if !r.note.isEmpty { Text(r.note).font(.caption2).foregroundStyle(.secondary) }
            if let date = store.state.visits[r.id] { Text("최근 방문 \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(red) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
    static func radiusText(_ meters: Double) -> String {
        meters >= 1000 ? String(format: meters.truncatingRemainder(dividingBy: 1000) == 0 ? "%.0fkm" : "%.1fkm", meters / 1000) : "\(Int(meters))m"
    }
    private var historyView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("이전 식당 목록").font(.title2.bold()); Spacer(); Button("닫기") { history = false } }
            if store.state.snapshots.isEmpty { Text("재설정하면 이전 목록이 여기에 보관됩니다.").foregroundStyle(.secondary) }
            List(store.state.snapshots.reversed()) { snapshot in
                HStack {
                    Text(snapshot.date.formatted()).font(.subheadline)
                    Text("\(snapshot.restaurants.count)곳").foregroundStyle(.secondary)
                    Spacer()
                    Button("복원") { store.restore(snapshot); history = false }
                }
            }
        }.padding(24).frame(width: 640, height: 390)
    }
}

private struct RestaurantMapView: View {
    let origin: Origin?
    let restaurant: Restaurant?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("위치 · \(origin?.name ?? "기준 지점") 기준").font(.caption.bold()).foregroundStyle(.secondary)
            Map(position: $position) {
                if let origin {
                    Marker(origin.name, systemImage: "mappin", coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude))
                        .tint(.blue)
                }
                if let restaurant {
                    Marker(restaurant.name, systemImage: "fork.knife", coordinate: CLLocationCoordinate2D(latitude: restaurant.latitude, longitude: restaurant.longitude))
                        .tint(.red)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel([restaurant?.name, origin?.name].compactMap { $0 }.joined(separator: "과 ") + " 위치 지도")
        }
        .task(id: "\(restaurant?.id ?? "")|\(origin?.latitude ?? 0)|\(origin?.longitude ?? 0)") {
            if let region = Self.region(origin: origin, restaurant: restaurant) { position = .region(region) }
        }
    }

    private static func region(origin: Origin?, restaurant: Restaurant?) -> MKCoordinateRegion? {
        guard let origin else { return nil }
        guard let restaurant else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude), span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.022))
        }
        let latGap = abs(restaurant.latitude - origin.latitude)
        let lonGap = abs(restaurant.longitude - origin.longitude)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (restaurant.latitude + origin.latitude) / 2, longitude: (restaurant.longitude + origin.longitude) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.005, latGap * 2.6), longitudeDelta: max(0.006, lonGap * 2.6))
        )
    }
}

/// 기준 지점을 Apple 지도 검색으로 고른다. 고른 값은 저장 상태에 들어가 Supabase 에 함께 저장된다.
private struct OriginPicker: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("기준 지점 변경").font(.title2.bold())
                Spacer()
                Button("닫기") { dismiss() }
            }
            Text("회사·역·건물 이름으로 검색하세요. 거리는 고른 지점에서 직선으로 잽니다.").font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("예: 판교역, 강남역", text: $query).textFieldStyle(.roundedBorder).onSubmit { Task { await search() } }
                Button("검색") { Task { await search() } }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                if searching { ProgressView().controlSize(.small) }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            List(results, id: \.self) { item in
                Button {
                    let c = item.placemark.coordinate
                    store.setOrigin(Origin(name: item.name ?? query, latitude: c.latitude, longitude: c.longitude,
                                           radiusMeters: store.origin?.radiusMeters ?? 1000))
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "이름 없음").font(.headline)
                        Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            HStack {
                if let fallback = store.state.defaultOrigin {
                    Button("기본 지점(\(fallback.name))으로 되돌리기") { store.setOrigin(nil); dismiss() }
                        .disabled(store.state.origin == nil)
                }
                Spacer()
            }
        }.padding(24).frame(width: 560, height: 480)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true; defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let origin = store.origin {
            request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude),
                                                latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        }
        do {
            results = try await MKLocalSearch(request: request).start().mapItems
            message = results.isEmpty ? "검색 결과가 없어요." : nil
        } catch {
            results = []; message = "검색하지 못했어요: \(error.localizedDescription)"
        }
    }
}
