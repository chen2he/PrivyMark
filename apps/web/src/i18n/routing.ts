import { defineRouting } from "next-intl/routing";

// 首发双语，对齐 ASC metadata 的 en-US / zh-Hans（fastlane 同名目录）；后续加语言在此处扩。
export const routing = defineRouting({
	locales: ["en", "zh-Hans"],
	defaultLocale: "en",
	localePrefix: "as-needed",
});

export type AppLocale = (typeof routing.locales)[number];

/** 截图资源目录（public/shots/<dir>），与 appstore 流水线成品同源 */
export function shotLocale(locale: string): "en" | "zh-Hans" {
	return locale === "zh-Hans" ? "zh-Hans" : "en";
}
