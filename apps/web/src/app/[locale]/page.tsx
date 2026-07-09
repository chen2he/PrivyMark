import Image from "next/image";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { shotLocale } from "@/i18n/routing";
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import AppStoreBadge from "@/components/AppStoreBadge";
import Reveal from "@/components/Reveal";

const SHOT_FILES = ["01_scan", "02_languages", "03_review", "04_private"];

/** 标题里的关键词打码块（悬停偷看）——文案里 line1 是 {t}|{r} 段数组 */
function RedactedLine({ segments }: { segments: Array<{ t?: string; r?: string }> }) {
	return (
		<>
			{segments.map((seg, i) =>
				seg.r ? (
					<span key={i} className="redacted">
						<span>{seg.r}</span>
					</span>
				) : (
					<span key={i}>{seg.t}</span>
				),
			)}
		</>
	);
}

/** 特性图标（描边风格，对齐 App 内 SF Symbols 气质） */
function FeatureGlyph({ name }: { name: string }) {
	const common = {
		width: 22,
		height: 22,
		viewBox: "0 0 24 24",
		fill: "none",
		stroke: "currentColor",
		strokeWidth: 1.6,
		strokeLinecap: "round" as const,
		strokeLinejoin: "round" as const,
		"aria-hidden": true,
	};
	switch (name) {
		case "scan":
			return (
				<svg {...common}>
					<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2" />
					<path d="M7 12h10" />
				</svg>
			);
		case "cover":
			return (
				<svg {...common}>
					<rect x="4" y="9" width="12" height="6" rx="2" fill="currentColor" stroke="none" />
					<rect x="8" y="4" width="12" height="6" rx="2" opacity="0.35" fill="currentColor" stroke="none" />
				</svg>
			);
		case "hide":
			return (
				<svg {...common}>
					<path d="M4 7h16M4 12h7M4 17h11" />
					<path d="M14 12h6" opacity="0.25" />
				</svg>
			);
		case "explode":
			return (
				<svg {...common}>
					<rect x="3" y="10" width="5" height="4" rx="1.4" />
					<rect x="10" y="10" width="5" height="4" rx="1.4" fill="currentColor" />
					<rect x="17" y="10" width="4" height="4" rx="1.4" />
				</svg>
			);
		case "marker":
			return (
				<svg {...common}>
					<path d="M4 20c4-1 3-4 6-6l6-6 4 4-6 6c-2 3-5 2-6 6z" />
				</svg>
			);
		case "emoji":
			return (
				<svg {...common}>
					<circle cx="12" cy="12" r="8" />
					<path d="M9 10h.01M15 10h.01M8.5 14.5a5 5 0 0 0 7 0" />
				</svg>
			);
		case "metadata":
			return (
				<svg {...common}>
					<circle cx="12" cy="10" r="3.4" />
					<path d="M12 13.4V21M12 21l-2.6-2.6M12 21l2.6-2.6" />
				</svg>
			);
		case "share":
			return (
				<svg {...common}>
					<path d="M12 15V4M12 4l-3.4 3.4M12 4l3.4 3.4" />
					<path d="M6 11v8a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2v-8" />
				</svg>
			);
		default:
			return null;
	}
}

const FEATURE_GLYPHS = ["scan", "cover", "hide", "explode", "marker", "emoji", "metadata", "share"];

export default async function HomePage({ params }: { params: Promise<{ locale: string }> }) {
	const { locale } = await params;
	setRequestLocale(locale);
	const t = await getTranslations();
	const shots = shotLocale(locale);
	const heroShot = shots === "zh-Hans" ? "detect_zh" : "detect_en";

	const heroLine1 = t.raw("hero.line1") as Array<{ t?: string; r?: string }>;
	const heroLine2 = t("hero.line2");
	const trustCards = t.raw("trust.cards") as Array<{ t: string; b: string }>;
	const galleryAlts = t.raw("gallery.alts") as string[];
	const featureItems = t.raw("features.items") as Array<{ t: string; b: string }>;
	const honestPoints = t.raw("honest.points") as Array<{ t: string; b: string }>;
	const freeItems = t.raw("free.items") as string[];
	const familyItems = t.raw("family.items") as Array<{ name: string; desc: string; domain: string; url: string }>;

	return (
		<>
			{/* ============ 纸面（风险摊开 → 逐段盖住） ============ */}
			<div className="theme-light">
				{/* —— Hero —— */}
				<section className="band band-paper paper-glow grain overflow-hidden">
					{/* 遮挡条装饰：黑绿混排（风险与遮盖并存）。
					    钉在 1120px 内容列外侧、只在 ≥1280px 显示——窄视口下会压到文字。 */}
					<div className="redbar hidden xl:block" style={{ left: "-70px", bottom: "18%", width: "210px", height: "28px", transform: "rotate(-13deg)" }} />
					<div className="redbar g hidden xl:block" style={{ right: "-60px", top: "120px", width: "230px", height: "32px", transform: "rotate(11deg)" }} />
					<SiteHeader />
					<div className="relative mx-auto grid max-w-[1120px] items-center gap-14 px-6 pb-20 pt-28 lg:grid-cols-[1fr_auto] lg:pb-24 lg:pt-36">
						<div>
							<Reveal index={0}>
								<span className="card r-chip inline-flex items-center gap-2 rounded-full px-4 py-1.5 text-[13px] font-medium t-secondary">
									<span
										className="h-[6px] w-[6px] rounded-full"
										style={{ background: "var(--pm-green)", boxShadow: "0 0 6px rgba(33,166,83,0.7)" }}
									/>
									{t("hero.kicker")}
								</span>
							</Reveal>
							<Reveal index={1}>
								<h1 className="f-display mt-5 text-[40px] font-extrabold leading-[1.14] t-primary sm:text-[54px]">
									<RedactedLine segments={heroLine1} />
									{heroLine2 ? (
										<>
											<br />
											{heroLine2}
										</>
									) : null}
								</h1>
							</Reveal>
							<Reveal index={2}>
								<p className="mt-5 max-w-[46ch] text-[17px] leading-relaxed t-secondary">{t("hero.sub")}</p>
								<p className="mt-2 text-[13px] t-tertiary">{t("hero.peek")}</p>
							</Reveal>
							<Reveal index={3}>
								<div className="mt-8">
									<AppStoreBadge coming={t("badge.coming")} alt={t("badge.alt")} />
								</div>
								<p className="mt-3 text-[13px] t-tertiary">{t("hero.note")}</p>
							</Reveal>
						</div>
						<Reveal index={2} className="justify-self-center">
							<div className="demo-device">
								<div className="screen">
									<Image
										src={`/shots/raw/${heroShot}.jpg`}
										alt={galleryAlts[0]}
										width={296}
										height={642}
										priority
										unoptimized
									/>
								</div>
								<div className="dynamic-island" />
							</div>
						</Reveal>
					</div>
				</section>

				{/* —— 隐私架构 —— */}
				<section className="band band-paper-2">
					<div className="mx-auto max-w-[1120px] px-6 py-20">
						<Reveal index={0}>
							<h2 className="f-display text-[32px] font-bold t-primary sm:text-[38px]">{t("trust.title")}</h2>
							<p className="mt-3 max-w-[56ch] text-[16px] t-secondary">{t("trust.sub")}</p>
						</Reveal>
						<div className="mt-10 grid gap-4 md:grid-cols-3">
							{trustCards.map((card, i) => (
								<Reveal key={card.t} index={i + 1}>
									<div className="card r-card h-full p-6">
										<div
											className="flex h-10 w-10 items-center justify-center rounded-full"
											style={{ background: "rgba(33,166,83,0.12)", color: "var(--pm-green)" }}
										>
											{i === 0 ? (
												<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
													<rect x="5" y="4" width="14" height="17" rx="3" />
													<path d="M9 21v-4h6v4" />
												</svg>
											) : i === 1 ? (
												<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
													<circle cx="12" cy="12" r="8.5" />
													<path d="M5 5l14 14" />
												</svg>
											) : (
												<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
													<path d="M6 4h9l4 4v12a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 20V5.5A1.5 1.5 0 0 1 6.5 4z" />
													<path d="M9 13l6 0M12 10v6" opacity="0" />
													<path d="M9 12.5l2.2 2.2L15.6 10" />
												</svg>
											)}
										</div>
										<h3 className="mt-4 text-[17px] font-semibold t-primary">{card.t}</h3>
										<p className="mt-2 text-[14px] leading-relaxed t-secondary">{card.b}</p>
									</div>
								</Reveal>
							))}
						</div>
					</div>
				</section>

				{/* —— 截图画廊（商店成品同源） —— */}
				<section className="band band-paper-3">
					<div className="mx-auto max-w-[1120px] px-6 pt-20">
						<Reveal index={0}>
							<h2 className="f-display text-[32px] font-bold t-primary sm:text-[38px]">{t("gallery.title")}</h2>
							<p className="mt-3 max-w-[56ch] text-[16px] t-secondary">{t("gallery.sub")}</p>
						</Reveal>
					</div>
					<Reveal index={1}>
						<div className="gallery mt-10">
							{SHOT_FILES.map((file, i) => (
								<div key={file} className="shot">
									<Image
										src={`/shots/${shots}/${file}.jpg`}
										alt={galleryAlts[i]}
										width={630}
										height={1368}
										loading="lazy"
										unoptimized
									/>
								</div>
							))}
						</div>
					</Reveal>
				</section>

				{/* —— 功能宫格 —— */}
				<section className="band band-paper-3" style={{ background: "#efece2" }}>
					<div className="mx-auto max-w-[1120px] px-6 py-20">
						<Reveal index={0}>
							<h2 className="f-display text-[32px] font-bold t-primary sm:text-[38px]">{t("features.title")}</h2>
							<p className="mt-3 max-w-[56ch] text-[16px] t-secondary">{t("features.sub")}</p>
						</Reveal>
						<div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
							{featureItems.map((item, i) => (
								<Reveal key={item.t} index={(i % 4) + 1}>
									<div className="card r-card h-full p-5">
										<span style={{ color: "var(--pm-green)" }}>
											<FeatureGlyph name={FEATURE_GLYPHS[i]} />
										</span>
										<h3 className="mt-3 text-[16px] font-semibold t-primary">{item.t}</h3>
										<p className="mt-1.5 text-[13.5px] leading-relaxed t-secondary">{item.b}</p>
									</div>
								</Reveal>
							))}
						</div>
					</div>
				</section>
			</div>

			{/* ============ 打码缝：一条绿色遮挡带把纸面「盖」进墨面 ============ */}
			<div className="band band-seam relative h-[200px] overflow-hidden" aria-hidden="true">
				<div
					className="absolute left-1/2 top-1/2 h-[30px] w-[130%] -translate-x-1/2 -translate-y-1/2 rounded-[12px]"
					style={{
						background: "var(--pm-green)",
						transform: "translate(-50%,-50%) rotate(-2.4deg)",
						boxShadow: "0 0 40px rgba(33,166,83,0.55), 0 8px 24px rgba(0,0,0,0.35)",
					}}
				/>
			</div>

			{/* ============ 墨面（全部盖住之后） ============ */}
			<div className="theme-dark">
				{/* —— 诚实边界 —— */}
				<section className="band band-ink">
					<div className="mx-auto max-w-[1120px] px-6 py-20">
						<Reveal index={0}>
							<h2 className="f-display text-[32px] font-bold t-primary sm:text-[38px]">{t("honest.title")}</h2>
							<p className="mt-3 max-w-[56ch] text-[16px] t-secondary">{t("honest.body")}</p>
						</Reveal>
						<div className="mt-10 grid gap-4 md:grid-cols-3">
							{honestPoints.map((point, i) => (
								<Reveal key={point.t} index={i + 1}>
									<div className="card r-card h-full p-6">
										<h3 className="text-[16px] font-semibold t-primary">{point.t}</h3>
										<p className="mt-2 text-[14px] leading-relaxed t-secondary">{point.b}</p>
									</div>
								</Reveal>
							))}
						</div>
					</div>
				</section>

				{/* —— 完全免费 —— */}
				<section className="band band-ink" style={{ background: "#12110d" }}>
					<div className="mx-auto max-w-[1120px] px-6 py-20">
						<Reveal index={0}>
							<div className="card r-card p-8 sm:p-10" style={{ borderColor: "rgba(33,166,83,0.35)" }}>
								<h2 className="f-display text-[28px] font-bold t-primary sm:text-[34px]">{t("free.title")}</h2>
								<p className="mt-3 max-w-[56ch] text-[15px] leading-relaxed t-secondary">{t("free.sub")}</p>
								<ul className="mt-6 grid gap-x-8 gap-y-3 sm:grid-cols-2 lg:grid-cols-3">
									{freeItems.map((item) => (
										<li key={item} className="flex items-start gap-2.5 text-[15px] t-secondary">
											<svg className="mt-1 flex-none" width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="var(--pm-green)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
												<path d="M2.5 7.5 5.5 10.5 11.5 3.5" />
											</svg>
											{item}
										</li>
									))}
								</ul>
							</div>
						</Reveal>
					</div>
				</section>

				{/* —— 同门作品（Orange Cloud / Yield） —— */}
				<section className="band band-ink" style={{ background: "#12110d" }}>
					<div className="mx-auto max-w-[1120px] px-6 pb-20">
						<Reveal index={0}>
							<h2 className="f-display text-[26px] font-bold t-primary sm:text-[30px]">{t("family.title")}</h2>
							<p className="mt-2.5 max-w-[56ch] text-[15px] t-secondary">{t("family.sub")}</p>
						</Reveal>
						<div className="mt-8 grid gap-4 md:grid-cols-2">
							{familyItems.map((app, i) => (
								<Reveal key={app.name} index={i + 1}>
									<a
										href={app.url}
										className="card r-card group flex h-full items-start gap-5 p-6 no-underline transition-transform duration-150 ease-out hover:scale-[1.01]"
									>
										<Image
											src={`/icons/app-${app.name.toLowerCase().replace(/\s+/g, "-")}.png`}
											alt=""
											width={56}
											height={56}
											unoptimized
											className="mt-0.5 flex-none rounded-[14px] shadow-[0_8px_20px_rgba(0,0,0,0.35)]"
										/>
										<span className="min-w-0">
											<span className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
												<span className="text-[17px] font-semibold t-primary">{app.name}</span>
												<span className="text-[13px] font-medium" style={{ color: "var(--pm-green)" }}>
													{app.domain} ↗
												</span>
											</span>
											<span className="mt-1.5 block text-[14px] leading-relaxed t-secondary">{app.desc}</span>
										</span>
									</a>
								</Reveal>
							))}
						</div>
					</div>
				</section>

				{/* —— 终幕 CTA + 页脚 —— */}
				<section className="band band-ink relative" style={{ background: "#0f0e0c" }}>
					<div className="relative mx-auto max-w-[1120px] px-6 pb-10 pt-24 text-center">
						<Reveal index={0}>
							<Image
								src="/icons/icon-180.png"
								alt="PrivyMark"
								width={96}
								height={96}
								unoptimized
								className="mx-auto rounded-[24px] shadow-[0_14px_38px_rgba(33,166,83,0.25)]"
							/>
						</Reveal>
						<Reveal index={1}>
							<h2 className="f-display mt-8 text-[34px] font-bold t-primary sm:text-[42px]">{t("cta.title")}</h2>
							<p className="mt-3 text-[17px] t-secondary">{t("cta.sub")}</p>
						</Reveal>
						<Reveal index={2}>
							<div className="mt-9 flex flex-col items-center gap-4">
								<AppStoreBadge coming={t("badge.coming")} alt={t("badge.alt")} />
							</div>
							<p className="mt-5 text-[13px] t-tertiary">{t("cta.requirement")}</p>
						</Reveal>
					</div>
					<div className="relative mt-14">
						<SiteFooter />
					</div>
				</section>
			</div>
		</>
	);
}
