import Image from "next/image";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import LocaleSwitcher from "./LocaleSwitcher";
import { APP_STORE_URL, APP_STORE_COMING } from "./AppStoreBadge";

/** 顶部导航：绝对定位浮在纸面上，不做 sticky（对齐 OC） */
export default async function SiteHeader() {
	const t = await getTranslations("header");

	return (
		<header className="absolute inset-x-0 top-0 z-20">
			<div className="mx-auto flex max-w-[1120px] items-center justify-between px-6 py-5">
				<Link href="/" className="flex items-center gap-2.5 no-underline">
					<Image
						src="/icons/icon-64.png"
						alt=""
						width={30}
						height={30}
						className="rounded-[8px]"
						priority
					/>
					<span className="f-display text-[17px] font-bold t-primary">PrivyMark</span>
				</Link>
				<div className="flex items-center gap-3">
					<LocaleSwitcher label={t("language")} />
					{APP_STORE_COMING ? (
						<span
							className="hidden cursor-not-allowed select-none rounded-full px-4 py-[7px] text-[13px] font-semibold text-white opacity-50 sm:block"
							style={{ background: "var(--pm-green)" }}
						>
							{t("downloadComing")}
						</span>
					) : (
						<a
							href={APP_STORE_URL}
							className="hidden rounded-full px-4 py-[7px] text-[13px] font-semibold text-white no-underline sm:block"
							style={{ background: "var(--pm-green)" }}
						>
							{t("download")}
						</a>
					)}
				</div>
			</div>
		</header>
	);
}
