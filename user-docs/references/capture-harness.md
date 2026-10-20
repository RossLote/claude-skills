# Capture harness

Screenshots come from **scripts, not people**. Each script signs in as the reader, does the task
the way the guide says, and saves named pictures. This makes the screenshots reproducible, and
it means every documented flow is actually run. When a guide's steps can't be scripted, that's
usually a finding.

The shape in a repo: `e2e/docs/` (`shoot.ts`, `world.ts`, one `<area>.docs.ts` per writer
bead, and a README), `e2e/playwright.docs.config.ts`, and a `docs-screenshots` Makefile
target.

## Shape

- **A separate Playwright project/config** that reuses the e2e stack, servers and sign-in setup
  (including 2FA enrolment). Its test directory is `docs/` and its files are `*.docs.ts`. These
  are **not tests**, and `make e2e` never runs them.
- **One command** recaptures everything on a fresh throwaway stack and tears it down afterwards.
  It can also take a filter to recapture one area:
  ```make
  docs-screenshots: e2e-install ## Recapture the user-docs screenshots (DOCS=<file filter> for one area)
  	$(E2E_COMPOSE) down -v >/dev/null 2>&1 || true
  	$(E2E_COMPOSE) up -d --wait
  	<pkg runner> run docs-screenshots $(DOCS); s=$$?; $(E2E_COMPOSE) down -v >/dev/null 2>&1; exit $$s
  ```
- **One fixed frame**, so pictures stay the same from run to run: viewport 1280×800,
  `deviceScaleFactor: 1`, `colorScheme: "light"`, plus the product's locale and time zone. Use
  `retries: 0`, and `trace: "retain-on-failure"`.
- **Files run one after another, in one process, on one database.** Only one file per writer
  bead, so parallel beads never edit the same file.

```ts
// playwright.docs.config.ts
import { defineConfig, devices } from "@playwright/test";
import base from "./playwright.config";

export default defineConfig({
  ...base,
  testDir: "./docs",
  retries: 0,
  reporter: [["list"]],
  use: { ...base.use, trace: "retain-on-failure", video: "off" },
  projects: [
    { name: "setup", testDir: "./tests", testMatch: /.*\.setup\.ts/ }, // reuse e2e auth setup
    {
      name: "docs",
      testMatch: /.*\.docs\.ts/,
      dependencies: ["setup"],
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1280, height: 800 },
        deviceScaleFactor: 1,
        colorScheme: "light",
        locale: "<en-GB>",
        timezoneId: "<Europe/London>",
      },
    },
  ],
});
```

## `shoot()`

This frames and saves the picture. It never sets up state: the page must already show exactly
what the guide describes.

```ts
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Locator, Page } from "@playwright/test";
import sharp from "sharp";

export const SHOTS_DIR = join(REPO_ROOT, "<docs-root>/screenshots");
const NAME = /^(<area>|<area>)-[a-z0-9-]+$/;

export interface ShootOptions {
  crop?: Locator;                   // frame a dialog, form or table rather than the viewport
  padding?: number;                 // px kept around crop (default 16)
  highlight?: Locator | Locator[];  // ring the control the guide tells the reader to use
  fullPage?: boolean;
}

export async function shoot(page: Page, name: string, opts: ShootOptions = {}) {
  if (!NAME.test(name)) throw new Error(`Screenshot name "${name}" must be <area>-<words-with-dashes>`);
  // Hide dev-server overlays; they are not part of the product.
  await page.addStyleTag({ content: "nextjs-portal{display:none!important}" });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForLoadState("networkidle").catch(() => {});

  const rings = opts.highlight ? [opts.highlight].flat() : [];
  for (const r of rings)
    await r.first().evaluate((el) => {
      const e = el as HTMLElement;
      e.style.setProperty("outline", "3px solid #f59e0b", "important");
      e.style.setProperty("outline-offset", "3px", "important");
    });

  let clip;
  if (opts.crop) {
    await opts.crop.scrollIntoViewIfNeeded();
    const box = await opts.crop.boundingBox();
    if (!box) throw new Error(`Screenshot ${name}: crop target is not visible`);
    const pad = opts.padding ?? 16;
    const size = await page.evaluate(() => ({
      w: document.documentElement.scrollWidth, h: document.documentElement.scrollHeight,
    }));
    const x = Math.max(0, box.x - pad), y = Math.max(0, box.y - pad);
    clip = { x, y, width: Math.min(size.w - x, box.width + pad * 2), height: Math.min(size.h - y, box.height + pad * 2) };
  }

  const png = await page.screenshot({ animations: "disabled", caret: "hide", fullPage: opts.fullPage ?? false, clip });

  for (const r of rings)
    await r.first().evaluate((el) => {
      (el as HTMLElement).style.removeProperty("outline");
      (el as HTMLElement).style.removeProperty("outline-offset");
    });

  mkdirSync(SHOTS_DIR, { recursive: true });
  writeFileSync(join(SHOTS_DIR, `${name}.webp`), await sharp(png).webp({ quality: 88, effort: 6 }).toBuffer());
}
```

Name screenshots `<area>-<page>-<what>`, for example `billing-balances-list`. The prefix makes
it obvious which area a picture belongs to. For a non-JS stack, keep the same behaviour: a fixed
frame, crop, highlight ring, WebP output and name check.

## The demo world

Screenshots show **believable people and organisations**, never "E2E Test Centre" or
`admin@example.local`. Build them once per capture run with an idempotent `ensureWorld()` that
every docs file calls first; only the first call does the work.

- **One named person per persona** (an admin Jordan Hale, a customer admin Priya Shah, an
  operator Tom Reed, and the partner, say), all with one shared password. Add
  `signInAs(page, persona)` that handles 2FA, and API contexts per persona for setting up state.
- **A main organisation** with realistic details, and enough data to make lists look real
  (six bookings on one event, say). Rename the seeded test organisations so
  network-wide views read naturally.
- **Shared-world rule**: files run on one database, so no file may disable, rename or empty the
  shared world. For a destructive screenshot (disabling, revoking, deleting), create your own
  object first.

## Driving vs staging

- **Drive through the UI** everything the guide tells the reader to do. That's what gets
  checked.
- **Set up through the API or test helpers** everything else: history the reader didn't create,
  the passing of time, third-party results, background jobs.
- **Add a command to the test driver instead of reaching round the app.** One capture script
  ran `docker-compose exec … psql` to fake third-party status. It ignored the configured port and
  compose project, and needed a fix bead of its own later.

## Freshness checks

These run as ordinary unit tests in the normal gate, so the docs can't quietly go stale:

- Every article loads, and its frontmatter is valid (required fields, `area` matches the folder,
  known audiences).
- Every `shot:<name>` an article uses has a file in `screenshots/`.
- Every file in `screenshots/` is used by some article, so none are orphaned.
- Every `help:<area>/<slug>` link points to an article that exists.
- Every `routes` entry is a page the app still has. Derive the list from the router's files or
  route table; don't hard-code it.
- Titles are unique.

With in-app help, add an **e2e boundary test**: a lower-privileged reader can't fetch another
audience's article or screenshot, and can't widen their view through query parameters.
