import { localeCatalog } from "./site-locales.mjs";

const aliases = {
  zh: "zh-CN",
  "zh-cn": "zh-CN",
  "zh-hans": "zh-CN",
  "zh-hant": "zh-TW",
  "zh-hk": "zh-TW",
  "zh-mo": "zh-TW",
  "zh-tw": "zh-TW",
  ja: "ja-JP",
  pt: "pt-BR",
};

export function normalizeLocale(value) {
  if (typeof value !== "string" || !value) return null;
  // Match script preferences before dropping their regional suffix, e.g. zh-Hant-HK.
  let candidate = value.toLowerCase();
  while (candidate) {
    if (Object.hasOwn(aliases, candidate)) return aliases[candidate];
    const supported = localeCatalog.find((locale) => locale.code.toLowerCase() === candidate);
    if (supported) return supported.code;
    const separator = candidate.lastIndexOf("-");
    if (separator < 0) break;
    candidate = candidate.slice(0, separator);
  }
  return null;
}
