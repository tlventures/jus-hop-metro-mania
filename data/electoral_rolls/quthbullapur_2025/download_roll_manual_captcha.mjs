#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const scriptDir = path.dirname(new URL(import.meta.url).pathname);
const manifestPath = path.join(scriptDir, "quthbullapur_roll_links_2025.json");
const outputDir = path.join(scriptDir, "downloads");

const usage = `
Usage:
  node download_roll_manual_captcha.mjs --part 1 --language English --roll-type "Final Roll"

Options:
  --part        Polling-station part number, required
  --language    English or Telugu, default: English
  --roll-type   "Final Roll", Supplement2, Supplement3, or Supplement4. Default: "Final Roll"
  --headed      Keep the browser visible after completion

This helper opens the official Telangana Electoral Rolls CAPTCHA page and waits for
you to enter the verification code manually. It does not solve or bypass CAPTCHA.
`;

function readArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    if (key === "headed") {
      args[key] = true;
      continue;
    }
    args[key] = argv[i + 1];
    i += 1;
  }
  return args;
}

function sanitizeFilename(value) {
  return String(value)
    .replace(/[^a-z0-9._-]+/gi, "_")
    .replace(/^_+|_+$/g, "");
}

async function waitForPdf(page, targetPath) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error("Timed out waiting for a PDF after CAPTCHA submission."));
    }, 120_000);

    const cleanup = () => {
      clearTimeout(timeout);
      page.off("response", onResponse);
      page.off("download", onDownload);
    };

    const saveBuffer = async (buffer) => {
      if (!buffer.subarray(0, 5).equals(Buffer.from("%PDF-"))) {
        throw new Error("The server response was not a PDF.");
      }
      await fs.mkdir(path.dirname(targetPath), { recursive: true });
      await fs.writeFile(targetPath, buffer);
      cleanup();
      resolve(targetPath);
    };

    const onResponse = async (response) => {
      try {
        const headers = response.headers();
        const contentType = headers["content-type"] || "";
        const disposition = headers["content-disposition"] || "";
        const isPdf =
          contentType.toLowerCase().includes("application/pdf") ||
          disposition.toLowerCase().includes(".pdf") ||
          response.url().toLowerCase().includes(".pdf");

        if (!isPdf) return;
        await saveBuffer(await response.body());
      } catch (error) {
        cleanup();
        reject(error);
      }
    };

    const onDownload = async (download) => {
      try {
        await fs.mkdir(path.dirname(targetPath), { recursive: true });
        await download.saveAs(targetPath);
        cleanup();
        resolve(targetPath);
      } catch (error) {
        cleanup();
        reject(error);
      }
    };

    page.on("response", onResponse);
    page.on("download", onDownload);
  });
}

async function main() {
  const args = readArgs(process.argv);
  const part = args.part;
  const language = args.language || "English";
  const rollType = args["roll-type"] || "Final Roll";

  if (!part) {
    console.error(usage);
    process.exitCode = 1;
    return;
  }

  let chromium;
  try {
    ({ chromium } = await import("playwright"));
  } catch {
    throw new Error(
      "Playwright is not installed here. Run: npm install --save-dev playwright && npx playwright install chromium",
    );
  }

  const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
  const row = manifest.find(
    (item) =>
      item.part_number === String(part) &&
      item.language.toLowerCase() === language.toLowerCase() &&
      item.roll_type.toLowerCase() === rollType.toLowerCase(),
  );

  if (!row) {
    throw new Error(
      `No manifest row found for part=${part}, language=${language}, roll-type=${rollType}`,
    );
  }

  const filename = [
    "quthbullapur_2025",
    `part_${row.part_number.padStart(3, "0")}`,
    row.language,
    row.roll_type,
  ]
    .map(sanitizeFilename)
    .join("__");
  const targetPath = path.join(outputDir, `${filename}.pdf`);

  const browser = await chromium.launch({
    headless: false,
    downloadsPath: outputDir,
  });

  try {
    const context = await browser.newContext({
      acceptDownloads: true,
      ignoreHTTPSErrors: true,
    });
    const page = await context.newPage();

    console.log(`Opening: ${row.official_popup_url}`);
    console.log("Enter the verification code in the browser and click Submit.");
    console.log(`Waiting to save PDF to: ${targetPath}`);

    await page.goto(row.official_popup_url, {
      waitUntil: "domcontentloaded",
      timeout: 60_000,
    });

    await page.locator("#txtVerificationCode").waitFor({ timeout: 30_000 });
    const savedPath = await waitForPdf(page, targetPath);
    console.log(`Saved: ${savedPath}`);

    if (args.headed) {
      console.log("Browser left open because --headed was provided.");
      return;
    }
  } finally {
    if (!args.headed) {
      await browser.close();
    }
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
