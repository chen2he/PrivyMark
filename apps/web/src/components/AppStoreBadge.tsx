// App Store 上架状态开关：上架后把 COMING 置 false（对齐 OC 的做法）。
export const APP_STORE_URL = "https://apps.apple.com/app/id6782443539";
export const APP_STORE_COMING = true;

/** 上架前显示置灰「即将登陆」，上架后变成可点的下载按钮 */
export default function AppStoreBadge({ coming, alt }: { coming: string; alt: string }) {
	const apple = (
		<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
			<path d="M17.05 12.53c-.03-2.68 2.19-3.97 2.29-4.03-1.25-1.83-3.19-2.08-3.88-2.11-1.65-.17-3.22.97-4.06.97-.84 0-2.13-.95-3.5-.92-1.8.03-3.46 1.05-4.38 2.66-1.87 3.24-.48 8.04 1.34 10.67.89 1.29 1.95 2.73 3.34 2.68 1.34-.05 1.85-.87 3.47-.87 1.62 0 2.08.87 3.5.84 1.45-.02 2.36-1.31 3.24-2.6 1.02-1.49 1.44-2.94 1.46-3.01-.03-.02-2.8-1.07-2.82-4.28zM14.4 4.66c.74-.9 1.24-2.14 1.1-3.38-1.07.04-2.36.71-3.12 1.6-.69.8-1.29 2.07-1.13 3.29 1.19.09 2.41-.6 3.15-1.51z" />
		</svg>
	);

	if (APP_STORE_COMING) {
		return (
			<span className="cta-store select-none" aria-disabled="true" title={alt}>
				{apple}
				{coming}
			</span>
		);
	}
	return (
		<a className="cta-store" href={APP_STORE_URL} aria-label={alt}>
			{apple}
			{alt}
		</a>
	);
}
