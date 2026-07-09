# PrivyMark — web

The landing page for [PrivyMark](../../README.md), served at **privymark.o-c.do**.

Next.js (App Router) + [next-intl](https://next-intl.dev) + [OpenNext](https://opennext.js.org/cloudflare) → Cloudflare Workers.

The design language mirrors the app: **redacted-paper** — a warm paper canvas,
floating cover bars (black = a risk, green = covered), and a headline keyword
hidden under a redaction block you can peek at on hover. The page scrolls from
paper (risks laid out) down into ink (everything covered).

## Structure

- `src/i18n/` — next-intl routing (`en` with no prefix + `zh-Hans`,
  `localePrefix: "as-needed"`). Add a locale in `routing.ts` + `messages/`.
- `src/messages/{en,zh-Hans}.json` — all copy (marketing + privacy policy +
  terms + support FAQ). Detection copy avoids absolute claims.
- `src/app/[locale]/page.tsx` — the landing page: hero → privacy stance →
  screenshot gallery → feature grid → the honesty section → "actually free" →
  sibling projects → CTA + footer.
- `src/app/[locale]/{privacy,terms,support}/` — legal + support pages (the App
  Store listing's privacy / support URLs point here).
- `public/shots/`, `public/og/`, `public/icons/` — statically served
  screenshots, social images, and icons.

## Develop / build / deploy

```bash
pnpm install
pnpm dev        # local dev server
pnpm build      # static prerender (8 pages: 2 locales × 4 routes)
pnpm deploy     # opennextjs-cloudflare build && deploy (needs Cloudflare creds)
```

Deploy the site before submitting the app to App Store review — Apple must be
able to reach the privacy-policy URL at review time.
