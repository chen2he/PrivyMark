import type { MetadataRoute } from "next";
import { routing } from "@/i18n/routing";

const SITE_URL = "https://privymark.o-c.do";
const ROUTES = ["", "/privacy", "/terms", "/support"];

function urlFor(locale: string, route: string): string {
	const prefix = locale === routing.defaultLocale ? "" : `/${locale}`;
	const path = `${prefix}${route}`;
	return `${SITE_URL}${path === "" ? "/" : path}`;
}

export default function sitemap(): MetadataRoute.Sitemap {
	// One entry per (route × locale), each carrying hreflang alternates for the
	// same route in every locale, so search engines index the right regional page.
	return ROUTES.flatMap((route) =>
		routing.locales.map((locale) => ({
			url: urlFor(locale, route),
			changeFrequency: "monthly" as const,
			priority: route === "" ? 1 : 0.6,
			alternates: {
				languages: Object.fromEntries(
					routing.locales.map((l) => [l, urlFor(l, route)]),
				),
			},
		})),
	);
}
