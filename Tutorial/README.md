# AppleTrace Tutorial site

A static, no-build GitHub Pages site — the comprehensive usage guide for
AppleTrace (English primary, Chinese secondary).

- `index.html` — English guide
- `zh.html` — 中文指南
- `styles.css`, `app.js` — shared styling and progressive-enhancement JS
- `.nojekyll` — serve files as-is (no Jekyll processing)

## Preview locally

```bash
cd Tutorial && python3 -m http.server 8000   # then open http://localhost:8000
```

## Publishing

Deployed by `.github/workflows/pages.yml` on every push to `master` that
touches `Tutorial/`. One-time setup: repo **Settings ▸ Pages ▸ Source =
GitHub Actions**.
