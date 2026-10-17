// Copyright (C) 2024-2026 Yomitan Authors
// Copyright (C) 2026 Snipper contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Native adaptation of Yomitan's language-transformer.js. Rules are generated
// from its japanese-transforms.js; see ThirdParty/Yomitan/README.md and LICENSE.
// This program is distributed WITHOUT ANY WARRANTY; without even the implied
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

import Foundation

struct JapaneseDeinflection: Sendable, Hashable {
    let text: String
    let conditions: UInt32
    // Base-form → surface-form order, matching Yomitan's user-facing traces.
    let reasons: [String]
}

struct JapaneseDeinflector: Sendable {
    private struct Descriptor: Decodable {
        let revision: String
        let conditions: [String: UInt32]
        let dictionaryConditions: [String: UInt32]
        let names: [String: String]
        let rules: [Rule]
    }
    private struct Rule: Decodable, Sendable {
        let suffix: String
        let replacement: String
        let wholeWord: Bool
        let conditionsIn: UInt32
        let conditionsOut: UInt32
        let reason: String
    }
    private struct IndexedRule: Sendable {
        let id: Int
        let rule: Rule
    }
    private struct Frame: Sendable {
        let rule: Int
        let text: String
    }
    private struct State {
        let result: JapaneseDeinflection
        let trace: [Frame]
    }

    let revision: String
    let conditions: [String: UInt32]
    private let dictionaryConditions: [String: UInt32]
    private let names: [String: String]
    private let rulesByEnding: [Character: [IndexedRule]]
    private let emptySuffixRules: [IndexedRule]

    static func load() throws -> JapaneseDeinflector {
        // The app carries a direct resource; SwiftPM supplies a resource bundle
        // for CLI development/tests. No absolute build-machine path is required.
        guard let url = Bundle.main.url(forResource: "JapaneseDeinflection", withExtension: "json")
                ?? Bundle.module.url(forResource: "JapaneseDeinflection", withExtension: "json") else {
            throw DictionaryError.deinflectionRules
        }
        do {
            let descriptor = try JSONDecoder().decode(Descriptor.self, from: Data(contentsOf: url))
            return JapaneseDeinflector(descriptor: descriptor)
        } catch { throw DictionaryError.deinflectionRules }
    }

    private init(descriptor: Descriptor) {
        revision = descriptor.revision
        conditions = descriptor.conditions
        dictionaryConditions = descriptor.dictionaryConditions
        names = descriptor.names
        var byEnding: [Character: [IndexedRule]] = [:]
        var empty: [IndexedRule] = []
        for (id, rule) in descriptor.rules.enumerated() {
            let indexed = IndexedRule(id: id, rule: rule)
            if let ending = rule.suffix.last { byEnding[ending, default: []].append(indexed) }
            else { empty.append(indexed) }
        }
        rulesByEnding = byEnding
        emptySuffixRules = empty
    }

    static func looksJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30ff).contains($0.value) || (0x3400...0x9fff).contains($0.value) }
    }

    func matches(_ conditions: UInt32, dictionaryRules: String) -> Bool {
        let flags = dictionaryRules.split(whereSeparator: \.isWhitespace).reduce(UInt32(0)) {
            $0 | (dictionaryConditions[String($1)] ?? 0)
        }
        return conditions == 0 || conditions & flags != 0
    }

    func displayReasons(_ reasons: [String]) -> [String] { reasons.map { names[$0] ?? $0 } }

    func deinflect(_ text: String, maximumResults: Int = 512, maximumDepth: Int = 16) throws -> [JapaneseDeinflection] {
        let original = JapaneseDeinflection(text: text, conditions: 0, reasons: [])
        guard !text.isEmpty, text.count <= 48, Self.looksJapanese(text) else { return [original] }
        let limit = max(1, min(maximumResults, 512))
        let depth = max(0, min(maximumDepth, 16))
        var states = [State(result: original, trace: [])]
        // Keep alternate explanation chains, but collapse identical results.
        var seen: Set<JapaneseDeinflection> = [original]
        var index = 0
        while index < states.count && states.count < limit {
            try Task.checkCancellation()
            let state = states[index]
            index += 1
            let current = state.result
            guard current.reasons.count < depth else { continue }
            let endingRules = current.text.last.flatMap { rulesByEnding[$0] } ?? []
            let possible = (endingRules + emptySuffixRules).sorted { $0.id < $1.id }
            for indexed in possible {
                let rule = indexed.rule
                guard current.conditions == 0 || current.conditions & rule.conditionsIn != 0,
                      current.text.hasSuffix(rule.suffix),
                      !rule.wholeWord || current.text == rule.suffix else { continue }
                // Preserve upstream's per-rule cycle check without logging source text.
                guard !state.trace.contains(where: { $0.rule == indexed.id && $0.text == current.text }) else { continue }
                let nextText = String(current.text.dropLast(rule.suffix.count)) + rule.replacement
                guard !nextText.isEmpty, nextText.count <= 48 else { continue }
                let result = JapaneseDeinflection(text: nextText, conditions: rule.conditionsOut, reasons: [rule.reason] + current.reasons)
                guard seen.insert(result).inserted else { continue }
                states.append(State(result: result, trace: state.trace + [Frame(rule: indexed.id, text: current.text)]))
                if states.count >= limit { break }
            }
        }
        return states.map(\.result)
    }
}
