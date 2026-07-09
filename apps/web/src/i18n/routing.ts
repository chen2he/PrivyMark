import { defineRouting } from "next-intl/routing";

// 已支持语言体系（对齐 App 检测覆盖：英/中/西/葡/法/德/意）+ 地区变体。
// en 默认无前缀；其余带前缀（localePrefix: "as-needed"）。
export const routing = defineRouting({
	locales: [
		"en",
		"zh-Hans", // 简体（大陆）
		"zh-Hant", // 繁体（台湾）
		"zh-HK", // 繁体（香港）
		"es-ES", // 西班牙语（西班牙 / 欧洲）
		"es-MX", // 西班牙语（墨西哥 / 拉美）
		"pt-PT", // 葡萄牙语（葡萄牙 / 欧洲）
		"pt-BR", // 葡萄牙语（巴西 / 拉美）
		"fr", // 法语
		"de", // 德语
		"it", // 意大利语
	],
	defaultLocale: "en",
	localePrefix: "as-needed",
});

export type AppLocale = (typeof routing.locales)[number];

/** 截图资源目录（public/shots/<dir>）。中文用中文场景截图，其余（拉丁字母语言）用英文截图。 */
export function shotLocale(locale: string): "en" | "zh-Hans" {
	return locale.startsWith("zh") ? "zh-Hans" : "en";
}
