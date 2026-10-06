import Foundation

/// 한국어 문장으로 재료를 추가·삭제·상시 등록한다. 규칙 기반이며 문장을 외부로 보내지 않는다.
/// 문장 전체를 먼저 해석하고, 하나라도 이해하지 못하면 아무것도 바꾸지 않는다.
enum PantryLanguage {
    enum Action: String { case add, remove, staple, unstaple }
    struct Command: Equatable { var ingredient: String; var action: Action }
    enum Place: String { case absent, today, staple }
    struct Change: Equatable { var ingredient: String; var action: Action; var before: Place; var after: Place }

    static let aliases = ["계란": "달걀", "쇠고기": "소고기", "닭가슴살": "닭고기", "스파게티면": "파스타", "파스타면": "파스타", "오트": "오트밀"]
    static let foods = "밥 쌀 오트밀 파스타 당근 애호박 브로콜리 감자 양파 시금치 단호박 토마토 달걀 두부 닭고기 소고기 연어 바나나 사과 식용유 간장 참기름 우유 치즈 버터 요거트 요구르트 밀가루 설탕 소금 후추 고추장 된장 마늘 대파 쪽파 오이 배추 양배추 고구마 옥수수 완두콩 콩 검은콩 병아리콩 렌틸콩 피망 파프리카 가지 버섯 표고버섯 새송이버섯 팽이버섯 배 딸기 블루베리 귤 오렌지 포도 키위 복숭아 돼지고기 새우 참치 고등어 멸치 김 미역 다시마 국수 빵 떡 올리브유 들기름 깨 두유 생크림 부추 숙주 콩나물 무 시래기 청경채 김치 양송이버섯 콜라비 퀴노아 아보카도 레몬 생강"
        .split(separator: " ").map(String.init)

    private static let suffix = #"(?:해\s*주세요|해\s*줘|해주세요|해줘|해요|하고|주세요|해|줘|고|요|습니다|다|음)?"#
    private static let stapleWords = #"(?:상시\s*(?:재료)?|기본\s*재료|항상\s*(?:있는|두는)\s*재료)"#
    /// 같은 위치에서 여러 규칙이 맞으면 더 긴 쪽, 길이도 같으면 앞의 규칙이 이긴다.
    private static let rules: [(Action, NSRegularExpression)] = [
        (.unstaple, regex(stapleWords + #"(?:에서|에서는)\s*(?:빼|제외|삭제|해제)"# + suffix)),
        (.staple, regex(#"(?:항상|늘|언제나)\s*(?:있(?:어요|어|고|다|음)|두(?:고\s*있어요|고\s*있어|는\s*재료|어요|고|자)|구비(?:해요|해줘|해|하고))"#)),
        (.staple, regex(stapleWords + #"(?:로|에)?(?:\s*(?:등록|추가|설정|넣어|해)"# + suffix + ")?")),
        (.remove, regex(#"(?:다\s*(?:먹었(?:어요|어|고|다)?|썼(?:어요|어|고|다)?|사용했(?:어요|어|고|다)?)|떨어졌(?:어요|어|고|다)?|없(?:어요|어|고|다|음)|(?:삭제|제거|빼|제외)"# + suffix + ")")),
        (.add, regex(#"(?:(?:추가|넣어|등록)"# + suffix + #"|사\s*왔(?:어요|어|고|다)?|샀(?:어요|어|고|다)?|있(?:어요|어|고|다|음)|남았(?:어요|어|고|다)?)"#)),
    ]
    private static let refused = regex(#"[?？]|하지\s*마|하지\s*말|지\s*마|지\s*말|말고|아니|않|없지|있지|면\s|경우|알레르기|살\s*예정|살\s*거|사야|나중에|내일"#)
    private static let leadingFiller = regex(#"^(?:(?:그리고|또|그런데|근데|오늘은|오늘|냉장고에|집에|우리집에|지금|이제|재료는)\s*)+"#)
    private static let placeholder = regex(#"◇\s*(?:이랑|하고|은|는|이|가|을|를|도|과|와|랑)?"#)
    private static let quantity = regex(#"\d+(?:\.\d+)?\s*(?:kg|g|ml|l|개|봉지|봉|팩|통|병|모|단|줌|장|알|근|킬로|그램)(?:씩|은|는|을|를|도)?"#, [.caseInsensitive])
    private static let wordQuantity = regex(#"(?:^|\s)(?:한|두|세|네)\s*(?:개|봉지|팩|통|병|모|단|줌|장|알)(?:은|는|을|를|도)?(?=\s|$)"#)
    private static let filler = regex(#"(?:^|\s)(?:그리고|또|및|좀|조금|오늘|지금|이제|냉장고에|집에)(?=\s|$)"#)
    private static let separators = regex(#"[,·]|\s+(?:그리고|및)\s+|(?:이랑|랑|하고)(?=\s)|\s+"#)
    private static let particleOnly = regex(#"^(?:은|는|이|가|을|를|도|과|와|랑|이랑|하고)$"#)
    private static let trailingParticle = regex(#"(?:은|는|을|를|도)$"#)
    private static let nameShape = regex(#"^[가-힣A-Za-z]{2,15}$"#)
    private static let notAName = regex(#"(?:주세요|해줘|하지|않|말|없|있|먹|싶|좋|알레르기|전부|모두|전체|재료|항상|상시|기본|늘|구매|나중|내일)"#)
    private static let edgePunctuation = regex(#"^[\s,.;!\n]+"#)
    private static let trailingJoiner = regex(#"(?:그리고|\s고)\s*$"#)
    private static let bothEdges = regex(#"^[\s,.;!\n]+|[\s,.;!\n]+$"#)
    private static let politeTail = regex(#"^(?:줘|주세요|해줘|해요|요|고|부탁해|부탁해요)$"#)

    static func parse(_ input: String, known: [String] = []) throws -> [Command] {
        let text = input.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = text as NSString
        guard !text.isEmpty, ns.length <= 500 else { throw AppError("재료 요청을 500자 이내로 적어 주세요.") }
        if refused.hits(text) {
            throw AppError("질문·부정·조건이 섞인 문장은 아직 처리하기 어려워요. “당근 추가, 우유 삭제”처럼 적어 주세요. 변경하지 않았어요.")
        }
        var commands: [Command] = []
        var start = 0
        while start < ns.length {
            var hit: (action: Action, range: NSRange)?
            for (action, rule) in rules {
                guard let match = rule.firstMatch(in: text, range: NSRange(location: start, length: ns.length - start)) else { continue }
                if hit == nil || match.range.location < hit!.range.location ||
                    (match.range.location == hit!.range.location && match.range.length > hit!.range.length) {
                    hit = (action, match.range)
                }
            }
            guard let hit else { break }
            let subject = ns.substring(with: NSRange(location: start, length: hit.range.location - start))
                .replacing(edgePunctuation, with: "").replacing(trailingJoiner, with: "")
            let names = try ingredients(in: subject, known: known)
            if names.isEmpty { throw AppError("어떤 재료인지 찾지 못했어요. “달걀은 항상 있어”처럼 재료를 먼저 적어 주세요. 변경하지 않았어요.") }
            commands += names.map { Command(ingredient: $0, action: hit.action) }
            start = hit.range.location + hit.range.length
        }
        let tail = ns.substring(from: start).replacing(bothEdges, with: "")
        if commands.isEmpty {
            commands = try ingredients(in: tail, known: known).map { Command(ingredient: $0, action: .add) }
        } else if !tail.isEmpty && !politeTail.hits(tail) {
            throw AppError("문장 끝의 요청을 이해하지 못했어요. 재료마다 “추가·삭제·상시 재료로 등록”을 적어 주세요. 변경하지 않았어요.")
        }
        if commands.isEmpty { throw AppError("재료 이름을 적어 주세요.") }
        var result: [Command] = []
        for command in commands {
            if let same = result.first(where: { $0.ingredient == command.ingredient }) {
                if same.action != command.action {
                    throw AppError("\(command.ingredient)에 서로 다른 요청이 있어요. 한 가지로 적어 주세요. 변경하지 않았어요.")
                }
            } else {
                result.append(command)
            }
        }
        return result
    }

    static func apply(_ commands: [Command], pantry: inout Set<String>, staples: inout Set<String>) -> [Change] {
        var changes: [Change] = []
        for command in commands {
            let name = command.ingredient
            let before = place(of: name, pantry: pantry, staples: staples)
            switch command.action {
            case .staple: staples.insert(name); pantry.remove(name)
            case .remove: pantry.remove(name); staples.remove(name)
            case .unstaple: if staples.remove(name) != nil { pantry.insert(name) }
            case .add: if !staples.contains(name) { pantry.insert(name) }
            }
            changes.append(Change(ingredient: name, action: command.action, before: before,
                                  after: place(of: name, pantry: pantry, staples: staples)))
        }
        return changes
    }

    private static func place(of name: String, pantry: Set<String>, staples: Set<String>) -> Place {
        staples.contains(name) ? .staple : pantry.contains(name) ? .today : .absent
    }

    private static func ingredients(in text: String, known: [String]) throws -> [String] {
        var seen = Set<String>()
        // 긴 이름부터 찾는다(예: 표고버섯 → 버섯). 같은 길이는 목록 순서를 지킨다.
        let names = (foods + known + Array(aliases.keys)).filter { seen.insert($0).inserted }
            .enumerated().sorted { ($0.element.count, -$0.offset) > ($1.element.count, -$1.offset) }.map(\.element)
        var found: [String] = []
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines).replacing(leadingFiller, with: "")
        // 조사를 떼기 전에 정확한 재료 이름부터 표시해 둔다(예: 사과, 오이).
        for name in names {
            let exact = regex(#"(^|[\s,·])"# + NSRegularExpression.escapedPattern(for: name) +
                              #"(?=(?:은|는|이|가|을|를|도|이랑|랑|하고|과|와)?(?:[\s,·]|$|[0-9]))"#)
            let count = exact.numberOfMatches(in: rest, range: rest.fullRange)
            guard count > 0 else { continue }
            found += Array(repeating: aliases[name] ?? name, count: count)
            rest = rest.replacing(exact, with: "$1 ◇ ")
        }
        rest = rest.replacing(placeholder, with: " ").replacing(quantity, with: " ")
            .replacing(wordQuantity, with: " ").replacing(filler, with: " ")
        for var part in rest.split(by: separators) {
            if particleOnly.hits(part) { continue }
            part = part.replacing(trailingParticle, with: "")
            if !nameShape.hits(part) || notAName.hits(part) {
                throw AppError("재료 이름을 분명히 적어 주세요. 예: “당근과 양파 추가해줘”.")
            }
            found.append(aliases[part] ?? part)
        }
        var unique = Set<String>()
        return found.filter { unique.insert($0).inserted }
    }
}

func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: options)
}

extension String {
    var fullRange: NSRange { NSRange(location: 0, length: (self as NSString).length) }
    func hits(_ expression: NSRegularExpression) -> Bool { expression.firstMatch(in: self, range: fullRange) != nil }
    func replacing(_ expression: NSRegularExpression, with template: String) -> String {
        expression.stringByReplacingMatches(in: self, range: fullRange, withTemplate: template)
    }
    func split(by expression: NSRegularExpression) -> [String] {
        let ns = self as NSString
        var parts: [String] = []
        var start = 0
        for match in expression.matches(in: self, range: fullRange) {
            parts.append(ns.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = match.range.location + match.range.length
        }
        parts.append(ns.substring(from: start))
        return parts.filter { !$0.isEmpty }
    }
}

extension NSRegularExpression {
    func hits(_ text: String) -> Bool { text.hits(self) }
}
