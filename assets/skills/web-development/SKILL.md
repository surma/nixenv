---
name: web-development
description: Use when building, scaffolding, testing, or maintaining a browser web app/frontend. Establishes the preferred default stack and project structure.
---

# Web Development Defaults

Use this skill when building a browser app/frontend and the project does not already mandate a different stack. This is the default recommendation for new web apps, not a requirement to rewrite existing projects.

If a repo already has conventions, follow them unless explicitly asked to change stacks.

## Default stack

Use:

- **Vite** for dev server and production bundling.
- **Preact** for UI components.
- **Preact Signals** for state management.
- **TypeScript** for application and test code.
- **Tailwind CSS** for styling, via the Vite Tailwind plugin.
- **Vitest Browser Mode** for component/app tests in a real browser.
- **Playwright Chromium provider** for Vitest browser execution.
- **Testing Library for Preact** for DOM-oriented tests.
- **jest-dom Vitest matchers** for readable DOM assertions.
- **Nix flake checks** when the project uses Nix.
- **agent-browser** for manual browser validation and screenshots; load the `agent-browser` skill for command details.

Do not add CDN dependencies for app runtime code. Bundle runtime dependencies through the app build.

Do not use jsdom for app-level UI tests in this default stack. Prefer real browser tests by default.

## Dependency guidance

For a new Vite/Preact app, expect these packages unless the repo already has equivalents:

Runtime:

- `preact`
- `@preact/signals`

Development/test/build:

- `vite`
- `typescript`
- `vitest`
- `@vitest/browser-playwright`
- `playwright`
- `@preact/preset-vite`
- `tailwindcss`
- `@tailwindcss/vite`
- `@testing-library/preact`
- `@testing-library/jest-dom`
- `@types/node` when config files or tests need Node types

Use the package manager already used by the repo. If there is no package-manager convention, ask when it matters; otherwise npm is a reasonable baseline because it is ubiquitous and works well with Nix `buildNpmPackage`.

## Project structure

For repos that are not already JavaScript projects, prefer a root package workspace with the web app in its own directory:

```text
package.json
package-lock.json
web-app/
  index.html
  package.json
  tsconfig.json
  vite.config.ts
  src/
    main.tsx
    style.css
    app/
    views/
    test/setup.ts
```

Names should match the project, e.g. `foo-web`, `web`, or `app`; do not force `web-app` if the repo has naming conventions.

Ignore generated artifacts:

```gitignore
node_modules/
/<web-app>/dist/
```

Keep root scripts as thin delegators when using workspaces:

- `web:dev` → app dev server
- `web:build` → production bundle
- `web:test` → browser tests
- `web:typecheck` → TypeScript checking
- `web:check` → typecheck + tests + build

## Typechecking is verification, not bundling

Do not hide TypeScript checking inside the production build command by default.

Prefer separate scripts:

- `build`: run the bundler, e.g. `vite build`
- `typecheck`: run `tsc --noEmit`
- `test`: run `vitest run`
- `check`: run typecheck, tests, and build

Rationale: `tsc --noEmit` is an executable verification step. Treat it like a test/check so CI and `nix flake check` can report it clearly.

## Vite and Vitest config

Use `defineConfig` from `vitest/config` when the Vite config includes Vitest settings.

Baseline shape:

```ts
import preact from "@preact/preset-vite";
import tailwindcss from "@tailwindcss/vite";
import { playwright } from "@vitest/browser-playwright";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [preact(), tailwindcss()],
  test: {
    browser: {
      enabled: true,
      headless: true,
      instances: [{ browser: "chromium" }],
      provider: playwright({
        launchOptions: {
          executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
        },
      }),
    },
    setupFiles: ["./src/test/setup.ts"],
  },
});
```

Test setup:

```ts
import "@testing-library/jest-dom/vitest";
```

### Browser launch flags

Do not disable GPU by default. Browser tests should run as close to a real browser as practical.

Only add flags such as `--no-sandbox`, `--disable-setuid-sandbox`, `--disable-dev-shm-usage`, or `--disable-gpu` when the environment requires them, and prefer a short comment explaining why. In Nix sandbox or container environments, `--no-sandbox` and fontconfig setup are often necessary; `--disable-gpu` is situational, not a default architectural choice.

## State management

Use Preact Signals for app state. Do not duplicate signal rules here; load and follow the `preact-signals` skill for details.

At the project level, prefer a small model/factory for cohesive app state and actions rather than scattering global signals across components.

## UI defaults

- Build responsive/mobile/touch-compatible layouts from the start.
- Use semantic HTML controls and accessible labels.
- Do not rely on keyboard shortcuts for core actions.
- For tabs, use `role="tablist"`, `role="tab"`, and `aria-selected`.
- Prefer custom Preact/Tailwind components first.
- Do not introduce React-only component systems unless explicitly asked or the project already uses React.

## Browser tests

Test user-visible behavior through the DOM. Prefer tests that would fail if the UI contract breaks, not tests that merely assert implementation details.

Good default coverage:

- Initial render/default view.
- View or route switching without page reload when relevant.
- Form/file-input flows using real browser `File` objects.
- Loading, success, and failure states.
- Accessible labels/roles for core controls.
- Important visual semantics via `getComputedStyle()` when colors/layout states are part of the contract.

Example pattern:

```ts
import { cleanup, fireEvent, render, screen } from "@testing-library/preact";
import { afterEach, describe, expect, test } from "vitest";

import { App } from "./App";

afterEach(cleanup);

describe("App", () => {
  test("loads a file through the UI", async () => {
    render(<App />);

    fireEvent.change(screen.getByLabelText("Data file"), {
      target: { files: [new File(["hello"], "demo.txt")] },
    });

    expect(await screen.findByText("demo.txt")).toBeInTheDocument();
  });
});
```

## Nix integration

When the project has a flake, `nix flake check` should run the web verification gate.

Use `pkgs.buildNpmPackage` for the web package when possible:

- Set `npmDepsHash` from the lockfile.
- Set `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`.
- Point `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` at `${pkgs.chromium}/bin/chromium`.
- Set `FONTCONFIG_FILE` and `FONTCONFIG_PATH` for sandboxed/headless Chromium.
- Run typecheck and browser tests in `checkPhase`.
- Run the production bundle as part of the package build.
- Expose the package under `checks` so `nix flake check` covers it.

Dev shells for this stack should usually include:

- `pkgs.nodejs`
- `pkgs.chromium`
- `pkgs.fontconfig`

and export:

```sh
export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=${pkgs.chromium}/bin/chromium
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf
export FONTCONFIG_PATH=${pkgs.fontconfig.out}/etc/fonts
```

If Chromium fails only inside the Nix sandbox, fix the sandbox environment rather than weakening the app code.

## Manual browser validation

After meaningful UI changes, validate in a real browser and capture screenshots with `agent-browser`. Do not duplicate browser-automation instructions here; load and follow the `agent-browser` skill for the current command workflow.

## Verification checklist

Before reporting done on a web change, run the strongest practical gate for the repo. For this default stack that usually means:

```sh
npm run web:typecheck
npm run web:test
npm run web:build
```

or the repo's combined equivalent:

```sh
npm run web:check
```

For Nix projects, also run:

```sh
nix flake check
```
