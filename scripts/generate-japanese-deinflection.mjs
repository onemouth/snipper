#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later
// Converts the pinned, unmodified Yomitan sources into native runtime/test data.
// Node is needed only when regenerating these checked-in files.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import vm from 'node:vm';
import {japaneseTransforms} from '../ThirdParty/Yomitan/ext/js/language/ja/japanese-transforms.js';

const root = new URL('../', import.meta.url);
const upstream = 'e7334a96106a6c74e6fa75bd33a5ea1219d92712';
const engineSource = await readFile(new URL('ThirdParty/Yomitan/ext/js/language/language-transformer.js', root), 'utf8');
// The upstream algorithm only uses log.warn for cycle diagnostics. Do not load
// browser logging modules or evaluate any user/dictionary content.
const Transformer = vm.runInNewContext(engineSource.replace(/^import .*;$/gm, '').replace('export class ', 'class ') + '\nLanguageTransformer;', {
    log: {warn: () => { throw new Error('Unexpected upstream rule cycle'); }},
});
const transformer = new Transformer();
transformer.addDescriptor(japaneseTransforms);
const conditions = Object.fromEntries(Object.keys(japaneseTransforms.conditions).map((name) => [name, transformer.getConditionFlagsFromConditionType(name) >>> 0]));
const dictionaryConditions = Object.fromEntries(Object.entries(japaneseTransforms.conditions)
    .filter(([, value]) => value.isDictionaryForm).map(([name]) => [name, conditions[name]]));
const mask = (names) => names.reduce((value, name) => value | conditions[name], 0) >>> 0;
const names = {};
const rules = [];
for (const [id, transform] of Object.entries(japaneseTransforms.transforms)) {
    names[id] = transform.name;
    for (const [index, rule] of transform.rules.entries()) {
        assert(['suffix', 'wholeWord'].includes(rule.type));
        const suffix = rule.isInflected.source.slice(rule.type === 'wholeWord' ? 1 : 0, -1);
        assert(!/[.*+?^${}()|[\]\\]/u.test(suffix), 'Native rules require literal suffixes');
        assert(rule.isInflected.test(suffix));
        const replacement = rule.deinflect(suffix);
        if (rule.type === 'suffix') {
            assert.equal(replacement, rule.deinflected);
            assert.equal(rule.deinflect('前' + suffix), '前' + replacement);
        }
        rules.push({suffix, replacement, wholeWord: rule.type === 'wholeWord',
            conditionsIn: mask(rule.conditionsIn), conditionsOut: mask(rule.conditionsOut), reason: id, index});
    }
}
const metadata = {source: 'https://github.com/yomidevs/yomitan', revision: upstream,
    license: 'GPL-3.0-or-later', copyright: 'Copyright (C) 2024-2026 Yomitan Authors'};
await writeFile(new URL('Sources/Snipper/Resources/JapaneseDeinflection.json', root),
    JSON.stringify({...metadata, conditions, dictionaryConditions, names, rules}, null, 2) + '\n');

const testSource = await readFile(new URL('ThirdParty/Yomitan/test/language/japanese-transforms.test.js', root), 'utf8');
const categories = vm.runInNewContext(testSource.slice(testSource.indexOf('const tests = ['), testSource.indexOf('/* eslint-enable')) + '\ntests;');
const cases = categories.flatMap(({category, valid, tests}) => tests.map(({source, term, rule, reasons}) => ({
    category, valid, source, term, conditions: rule === null ? null : conditions[rule], reasons,
})));
await writeFile(new URL('Tests/SnipperTests/Resources/JapaneseDeinflectionTests.json', root),
    JSON.stringify({...metadata, copyright: 'Copyright (C) 2023-2026 Yomitan Authors; Copyright (C) 2020-2022 Yomichan Authors', cases}, null, 2) + '\n');
console.log(`Generated ${rules.length} rules and ${cases.length} upstream test cases from ${upstream}.`);
