// App Store 上架状态开关：上架后把 COMING 置 false（对齐 OC 的做法）。
// 2026-07-09：已提交 App Store 审核（通常 24h 内上架），切上线状态。
export const APP_STORE_URL = "https://apps.apple.com/app/id6782443539";
export const APP_STORE_COMING = false;

// 官方「Download on the App Store」本地化徽章（Apple 营销资源，存 public/appstore/）。
// 遵循 Apple《营销资源和识别标志指南》：使用官方原图、不改比例/颜色/文案，
// 深色背景改用白色版（`-wht`）。黑白两版均来自 Apple 官方下载包。
const BADGE_LOCALES = [
	"en", "zh-Hans", "zh-Hant", "zh-HK",
	"es-ES", "es-MX", "pt-PT", "pt-BR", "fr", "de", "it",
];

function badgeSrc(locale: string, dark: boolean): string {
	const l = BADGE_LOCALES.includes(locale) ? locale : "en";
	return `/appstore/${l}${dark ? "-wht" : ""}.svg`;
}

/**
 * 官方 App Store 徽章。
 * - `dark`：深色背景用白色版徽章。
 * - `coming=true`：审核中，降透明度 + 下方状态标签，不可点（上架后置 false 即变可点）。
 */
export default function AppStoreBadge({
	locale = "en",
	alt,
	comingLabel,
	coming = false,
	dark = false,
	className = "",
}: {
	locale?: string;
	alt: string;
	comingLabel?: string;
	coming?: boolean;
	dark?: boolean;
	className?: string;
}) {
	const img = (
		// eslint-disable-next-line @next/next/no-img-element
		<img
			src={badgeSrc(locale, dark)}
			alt={alt}
			width={145}
			height={48}
			style={{ height: "48px", width: "auto", display: "block" }}
		/>
	);

	if (coming) {
		return (
			<div className={`inline-block cursor-not-allowed select-none ${className}`}>
				<div className="opacity-50">{img}</div>
				{comingLabel && (
					<p className="mt-2 flex items-center gap-1.5 text-[12px] t-secondary">
						<span
							className="inline-block h-[5px] w-[5px] flex-none animate-pulse rounded-full"
							style={{ background: "#fbbf24" }}
						/>
						{comingLabel}
					</p>
				)}
			</div>
		);
	}

	return (
		<a
			href={APP_STORE_URL}
			target="_blank"
			rel="noopener noreferrer"
			aria-label={alt}
			className={`inline-block no-underline transition-transform duration-150 ease-out hover:scale-[1.03] active:scale-[0.97] ${className}`}
		>
			{img}
		</a>
	);
}
