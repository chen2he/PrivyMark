import { defineRouting } from "next-intl/routing";

// 已支持语言体系：英文 + 中文。中文补齐地区变体——简体（大陆）、繁体（台湾）、繁体（香港）。
// en 默认无前缀；其余带前缀（localePrefix: "as-needed"）。
export const routing = defineRouting({
	locales: ["en", "zh-Hans", "zh-Hant", "zh-HK"],
	defaultLocale: "en",
	localePrefix: "as-needed",
});

export type AppLocale = (typeof routing.locales)[number];

/** 截图资源目录（public/shots/<dir>）。繁体地区复用简体截图（内容同为中文场景）。 */
export function shotLocale(locale: string): "en" | "zh-Hans" {
	return locale.startsWith("zh") ? "zh-Hans" : "en";
}
