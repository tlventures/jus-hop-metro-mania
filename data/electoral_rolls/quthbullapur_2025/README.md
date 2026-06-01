# Quthbullapur Electoral Roll Manifest

This folder contains a manifest of official Telangana Electoral Rolls links for
Quthbullapur Assembly Constituency, Medchal Malkajgiri district, 2025.

## Files

- `quthbullapur_roll_links_2025.csv`: CSV manifest of official popup URLs.
- `quthbullapur_roll_links_2025.json`: JSON version of the same manifest.
- `source_polling_stations_page.html`: saved copy of the official polling-station listing page.
- `download_roll_manual_captcha.mjs`: Playwright helper for one selected roll PDF.

## Manual CAPTCHA Download Helper

Install Playwright from this directory or the repo root:

```bash
npm install --save-dev playwright
npx playwright install chromium
```

Download one selected roll PDF:

```bash
node data/electoral_rolls/quthbullapur_2025/download_roll_manual_captcha.mjs \
  --part 1 \
  --language English \
  --roll-type "Final Roll"
```

The browser opens the official CAPTCHA page. Enter the verification code manually
and click Submit. If the site returns a PDF response, the script saves it under
`data/electoral_rolls/quthbullapur_2025/downloads/`.

The helper does not solve or bypass CAPTCHA and is intentionally scoped to one
selected part at a time.
