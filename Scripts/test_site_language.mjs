import assert from "node:assert/strict";
import test from "node:test";
import { normalizeLocale } from "../docs/site-language.mjs";
import { localeCatalog } from "../docs/site-locales.mjs";

test("every site language resolves unchanged", () => {
  for (const { code } of localeCatalog) assert.equal(normalizeLocale(code), code);
});

test("Chinese script and region preferences select the supported writing system", () => {
  for (const language of ["zh", "zh-Hans", "zh-Hans-CN", "zh-Hans-SG", "ZH-CN"]) {
    assert.equal(normalizeLocale(language), "zh-CN", language);
  }
  for (const language of ["zh-Hant", "zh-Hant-HK", "zh-Hant-TW", "zh-HK", "zh-MO"]) {
    assert.equal(normalizeLocale(language), "zh-TW", language);
  }
});

test("regional preferences fall back to supported languages without accepting unknown inputs", () => {
  for (const [language, expected] of [
    ["en-US", "en"],
    ["ar-SA", "ar"],
    ["ja", "ja-JP"],
    ["pt-BR", "pt-BR"],
  ]) {
    assert.equal(normalizeLocale(language), expected);
  }
  for (const value of [null, undefined, "", "zz-unknown", "<script>alert(1)</script>", "constructor", "toString"]) {
    assert.equal(normalizeLocale(value), null);
  }
});
