import createMiddleware from "next-intl/middleware";
import { routing } from "./i18n/routing";

export default createMiddleware(routing);

export const config = {
	// 排除 API、Next 内部路径与所有带扩展名的静态资源。
	matcher: ["/((?!api|_next|_vercel|.*\\..*).*)"],
};
