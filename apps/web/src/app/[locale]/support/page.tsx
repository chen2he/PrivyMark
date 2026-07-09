import type { Metadata } from "next";
import { getTranslations, setRequestLocale } from "next-intl/server";
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";

export async function generateMetadata({
	params,
}: {
	params: Promise<{ locale: string }>;
}): Promise<Metadata> {
	const { locale } = await params;
	const t = await getTranslations({ locale, namespace: "support" });
	return { title: `${t("title")} — PrivyMark` };
}

export default async function SupportPage({ params }: { params: Promise<{ locale: string }> }) {
	const { locale } = await params;
	setRequestLocale(locale);
	const t = await getTranslations("support");
	const faq = t.raw("faq") as Array<{ q: string; a: string }>;

	return (
		<div className="theme-light band band-paper paper-glow grain flex min-h-screen flex-col overflow-x-clip">
			<SiteHeader />
			<main className="relative mx-auto w-full max-w-[760px] flex-1 px-6 pb-20 pt-32">
				<h1 className="f-display text-[34px] font-bold t-primary">{t("title")}</h1>
				<p className="mt-3 max-w-[52ch] text-[16px] t-secondary">{t("sub")}</p>
				<div className="card r-card mt-8 px-7 sm:px-9">
					{faq.map((item, i) => (
						<section
							key={item.q}
							className="py-7"
							style={i > 0 ? { borderTop: "0.5px solid var(--divider)" } : undefined}
						>
							<h2 className="text-[17px] font-semibold t-primary">{item.q}</h2>
							<p className="mt-2.5 text-[15px] leading-relaxed t-secondary">{item.a}</p>
						</section>
					))}
				</div>
				<div className="card r-card mt-6 px-7 py-7 sm:px-9">
					<h2 className="text-[17px] font-semibold t-primary">{t("contactTitle")}</h2>
					<p className="mt-2.5 text-[15px] leading-relaxed t-secondary">{t("contactBody")}</p>
				</div>
			</main>
			<SiteFooter />
		</div>
	);
}
