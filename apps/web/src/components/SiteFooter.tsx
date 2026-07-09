import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { GITHUB_URL } from "./SiteHeader";

/** 页脚：纯内容、不带底色——颜色全部取自所在 theme 上下文 */
export default async function SiteFooter() {
	const t = await getTranslations("footer");

	return (
		<footer className="relative">
			<div
				className="mx-auto max-w-[1120px] px-6 py-10"
				style={{ borderTop: "0.5px solid var(--divider)" }}
			>
				<div className="flex flex-col items-start justify-between gap-4 sm:flex-row sm:items-center">
					<p className="text-[13px] t-secondary">{t("copyright")}</p>
					<nav className="flex items-center gap-6 text-[13px]">
						<Link href="/privacy" className="link-quiet">
							{t("privacy")}
						</Link>
						<Link href="/terms" className="link-quiet">
							{t("terms")}
						</Link>
						<Link href="/support" className="link-quiet">
							{t("support")}
						</Link>
						<a
							href={GITHUB_URL}
							target="_blank"
							rel="noopener noreferrer"
							className="link-quiet"
						>
							GitHub
						</a>
					</nav>
				</div>
				<p className="mt-5 max-w-[64ch] text-[12px] leading-relaxed t-tertiary">{t("disclaimer")}</p>
			</div>
		</footer>
	);
}
