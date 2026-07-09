import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { hasLocale, NextIntlClientProvider } from "next-intl";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { routing } from "@/i18n/routing";
import "../globals.css";

const SITE_URL = "https://privymark.o-c.do";
const APP_STORE_ID = "6782443539";

const OG_LOCALES: Record<string, string> = {
	en: "en_US",
	"zh-Hans": "zh_CN",
	"zh-Hant": "zh_TW",
	"zh-HK": "zh_HK",
	"es-ES": "es_ES",
	"es-MX": "es_MX",
	"pt-PT": "pt_PT",
	"pt-BR": "pt_BR",
	fr: "fr_FR",
	de: "de_DE",
	it: "it_IT",
};

// 各语言社交分享图（打码纸感横幅 1280×640）。生成：apps/iOS/appstore/render/og.mjs
// 中文用中文横幅；拉丁字母语言暂复用英文横幅（本地化横幅为后续优化项）。
const OG_IMAGES: Record<string, string> = {
	en: "/og/en.jpg",
	"zh-Hans": "/og/zh-Hans.jpg",
	"zh-Hant": "/og/zh-Hans.jpg",
	"zh-HK": "/og/zh-Hans.jpg",
	"es-ES": "/og/en.jpg",
	"es-MX": "/og/en.jpg",
	"pt-PT": "/og/en.jpg",
	"pt-BR": "/og/en.jpg",
	fr: "/og/en.jpg",
	de: "/og/en.jpg",
	it: "/og/en.jpg",
};

// hreflang：语言-脚本码 + 地区码（地理定向），指向对应本地化路由。
const HREFLANG_ALTERNATES: Record<string, string> = {
	en: "/",
	"zh-Hans": "/zh-Hans",
	"zh-CN": "/zh-Hans",
	"zh-Hant": "/zh-Hant",
	"zh-TW": "/zh-Hant",
	"zh-HK": "/zh-HK",
	"es-ES": "/es-ES",
	"es-MX": "/es-MX",
	"es-419": "/es-MX",
	"pt-PT": "/pt-PT",
	"pt-BR": "/pt-BR",
	fr: "/fr",
	"fr-FR": "/fr",
	de: "/de",
	"de-DE": "/de",
	it: "/it",
	"it-IT": "/it",
	"x-default": "/",
};

export function generateStaticParams() {
	return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({
	params,
}: {
	params: Promise<{ locale: string }>;
}): Promise<Metadata> {
	const { locale } = await params;
	if (!hasLocale(routing.locales, locale)) notFound();
	const t = await getTranslations({ locale, namespace: "meta" });
	const path = locale === routing.defaultLocale ? "/" : `/${locale}`;
	const ogImage = OG_IMAGES[locale] ?? OG_IMAGES.en;

	return {
		metadataBase: new URL(SITE_URL),
		title: t("title"),
		description: t("description"),
		alternates: {
			canonical: path,
			languages: HREFLANG_ALTERNATES,
		},
		icons: {
			icon: [
				{ url: "/icons/icon-32.png", sizes: "32x32", type: "image/png" },
				{ url: "/icons/icon-64.png", sizes: "64x64", type: "image/png" },
			],
			apple: "/icons/icon-180.png",
		},
		openGraph: {
			title: t("title"),
			description: t("description"),
			url: path,
			siteName: "PrivyMark",
			type: "website",
			locale: OG_LOCALES[locale],
			images: [{ url: ogImage, width: 1280, height: 640, alt: t("title") }],
		},
		twitter: {
			card: "summary_large_image",
			title: t("title"),
			description: t("description"),
			images: [ogImage],
		},
		itunes: {
			appId: APP_STORE_ID,
		},
		keywords: t("keywords")
			.split(",")
			.map((keyword: string) => keyword.trim()),
	};
}

export default async function LocaleLayout({
	children,
	params,
}: {
	children: React.ReactNode;
	params: Promise<{ locale: string }>;
}) {
	const { locale } = await params;
	if (!hasLocale(routing.locales, locale)) {
		notFound();
	}
	setRequestLocale(locale);
	const t = await getTranslations({ locale, namespace: "meta" });

	const jsonLd = {
		"@context": "https://schema.org",
		"@type": "SoftwareApplication",
		name: "PrivyMark",
		operatingSystem: "iOS 17.6+",
		applicationCategory: "MultimediaApplication",
		description: t("description"),
		url: SITE_URL,
		downloadUrl: `https://apps.apple.com/app/id${APP_STORE_ID}`,
		offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
	};

	return (
		<html lang={locale}>
			<body className="antialiased">
				<script
					type="application/ld+json"
					dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
				/>
				<NextIntlClientProvider>{children}</NextIntlClientProvider>
			</body>
		</html>
	);
}
