---
name: wcb
description: Investigate Shopify World Continuous Build (WCB / World CB) CI failures, task logs, dashboard/API state, workers/controller source, dependency-graph analysis, and WCB operational health. Use for WCB, World CB, Tectonix Continuous Image Build, WCB poll, wcb_evaluation, wcb_build, wcb_dependency_graph, evaluator/builder/analyzer tasks, and World image-build fallback failures.
compatibility: Requires Shopify corp access. Useful CLIs: gh, gcloud, devx/tec, rg, jq. Some controller URLs require browser/Okta rather than raw curl.
---

# WCB — World Continuous Build

Use this when investigating Shopify World Continuous Build (WCB), especially World PR failures involving **Tectonix Continuous Image Build**, **WCB poll**, `wcb_evaluation`, `wcb_build`, `wcb_dependency_graph`, evaluator tasks, builder tasks, commit/PR analysis tasks, or image-build fallbacks.

## First principles

- Do **not** start by changing WCB, Tectonix, or CI config. A failing PR check is usually caused by the PR's zone/Nix/build change.
- Find the failing phase first:
  - `wcb_evaluation` / evaluator task: Tectonix/Nix graph evaluation failed before builds existed.
  - `wcb_build` / builder task: a concrete derivation failed to build.
  - `wcb_dependency_graph` / commit or PR analysis task: `tec ci analyze-commit` or `tec ci analyze-pr` failed, affecting targeted CI/DAG generation.
- The GitHub Actions **Image build** job can be a fallback after WCB failed. Its error may be secondary/noisy. Inspect WCB evaluator/analyzer/builder logs first.
- WCB controller log URLs often redirect through Okta in raw `curl`. Prefer the WCB dashboard or the GCS log bucket once task ids are known.
- Preserve evidence: save expensive/noisy command output to files, then search those files. Do not merge stderr into stdout.
- Reuse generic Shopify helpers for generic work: prefer `devx agent-tools ci` for CI job/log discovery, `devx agent-tools observe` for Observe, and `devx agent-tools data` for BigQuery/data warehouse queries. Use this skill for WCB-specific task IDs, GCS paths, source locations, and failure interpretation.

## Mental model

WCB is the Continuous Build implementation for `shop/world`, under `//system/wcb`:

1. GitHub push/PR events flow through Kafka to the WCB controller.
2. The controller creates tasks:
   - evaluator tasks per commit/platform for Nix/Tectonix evaluation,
   - builder tasks for derivations that need building,
   - commit analysis tasks for per-commit dependency graphs,
   - PR analysis tasks for head-vs-base dependency graph diffs.
3. Rust workers claim tasks from the controller, run `tec`/`nix`, ship logs to GCS, and complete tasks.
4. Windex indexes derivations/artifacts/dependency graphs.
5. CI Controller polls WCB for evaluation/build status and consumes analysis/status publications so `wcb_evaluation`, `wcb_build`, and `wcb_dependency_graph` checks reflect WCB state.

Important source locations in World:

```text
//system/wcb/controller       Go controller API + jobs/Kafka consumer
//system/wcb/workers          Rust worker CLI: builder, evaluator, commit_analyzer, pr_analyzer
//system/ci/ci-controller     WCB polling/trigger integration
```

## Dashboards and source-of-truth URLs

```text
https://wcb-controller.shopifysvc.com/dashboard
https://wcb-controller.shopifysvc.com/dashboard/commit/<sha>
https://wcb-controller.shopifysvc.com/dashboard/pr/<pr_number>
https://wcb-controller.shopifysvc.com/dashboard/task/<task_type>/<task_id>
```

Task type mapping:

| Phase/check | Dashboard `task_type` | API/GCS prefix | Notes |
|---|---|---|---|
| Evaluation / `wcb_evaluation` | `evaluator` | `evaluator_tasks` | Tectonix/Nix graph evaluation |
| Build / `wcb_build` | `builder` | `builder_tasks` | concrete derivation builds |
| Commit dependency graph / `wcb_dependency_graph` | `commit_analysis` | `commit_analysis_tasks` | logs can be nested per analyzed commit |
| PR dependency graph / `wcb_dependency_graph` | `pr_analysis` | `pr_analysis_tasks` | head-vs-base dependency graph diff |

Useful API shapes, when auth/corp proxy permits direct access:

```text
/api/v1/commits/<full_sha>/evaluation/status?run_id=<run_id>
/api/v1/commits/<full_sha>/build/status?run_id=<run_id>
/api/v1/commits/<sha_or_14+char_prefix>/build_status?run_id=<run_id>
/api/v1/commits/<full_sha>/dependency_graph_status
/api/v1/builder_tasks/<id>/details
/api/v1/builder_tasks/<id>/logs
/api/v1/evaluator_tasks/<id>/details
/api/v1/evaluator_tasks/<id>/logs
/api/v1/commit_analysis_tasks/<id>/details
/api/v1/commit_analysis_tasks/<id>/logs
/api/v1/pr_analysis_tasks/<id>/details
/api/v1/pr_analysis_tasks/<id>/logs
```

Status values include `pending`, `running`, `scheduled_retry`, `success`, `failed`, `cancelled`, and `skipped`. Terminal statuses are `success`, `failed`, `cancelled`, and `skipped`.

## Finding the failing WCB task from a PR/check

From a World checkout or PR context, run whichever source has the missing data; if both are needed and your agent harness supports parallel tool calls, fetch them concurrently:

```bash
devx ci status --pr <pr> --zone <zone> --json > /tmp/wcb-ci-status.json
gh pr view <pr> --json statusCheckRollup,headRefOid,url > /tmp/wcb-pr-status.json
```

If you have a GitHub Actions run/job id for the WCB poll job:

```bash
gh run view <gha_run_id> --json jobs,conclusion,headSha,url > /tmp/wcb-gha-run.json
gh run view <gha_run_id> --job <job_id> --log > /tmp/wcb-gha-job.log
rg -n "evaluator_tasks|builder_tasks|commit_analysis_tasks|pr_analysis_tasks|Eval logs|Build logs|Analysis logs|wcb-controller" /tmp/wcb-gha-job.log
```

Typical log URLs look like:

```text
https://wcb-controller.shopifysvc.com/api/v1/evaluator_tasks/<id>/logs
https://wcb-controller.shopifysvc.com/api/v1/builder_tasks/<id>/logs
https://wcb-controller.shopifysvc.com/api/v1/commit_analysis_tasks/<id>/logs
https://wcb-controller.shopifysvc.com/api/v1/pr_analysis_tasks/<id>/logs
```

Use the `<id>` and task type with the GCS paths below.

## Log storage layout

Production logs:

```text
gs://shopify-continuous-build-logs/
```

Staging logs:

```text
gs://shopify-continuous-build-logs-staging/
```

Common production object prefixes:

```text
gs://shopify-continuous-build-logs/evaluator_tasks/<task_id>/<log_run_id>/chunk-*.log
gs://shopify-continuous-build-logs/builder_tasks/<task_id>/<log_run_id>/chunk-*.log
gs://shopify-continuous-build-logs/pr_analysis_tasks/<task_id>/<log_run_id>/chunk-*.log
gs://shopify-continuous-build-logs/commit_analysis_tasks/<task_id>/<log_run_id>/<idx>_<commit_sha>/chunk-*.log
```

Each run also writes a `complete` sentinel when the subprocess exits normally. A task can have multiple `<log_run_id>` directories after release/reclaim/retry; pick the lexicographically latest run id. These log-run ids are timestamp-like claim ids such as `20260602T221238Z_367077146` and are **not** the same as the task/run id column (often a commit SHA).

Worker log chunks are `chunk-00000000.log`, `chunk-00000001.log`, ... and are capped around 256 KiB with periodic flushing. Logs contain WCB APC timestamp markers (`\x1b_wcb;t=<unix_ms>\x07`) plus normal ANSI/SGR color codes.

WCB only processes `shop/world` GitHub events. Push handling ignores Graphite/GT MQ helper refs, `world-migration-history/*`, and tags. PR analysis is created only for `pull_request` actions `opened`, `synchronize`, and `reopened`; missing checks for other event shapes may be expected.

## Fetching logs from GCS

Set variables first:

```bash
TASK_TYPE=evaluator_tasks   # or builder_tasks, commit_analysis_tasks, pr_analysis_tasks
TASK_ID=<id>
BUCKET=shopify-continuous-build-logs
OUT=/tmp/wcb-${TASK_TYPE}-${TASK_ID}
mkdir -p "$OUT"
```

List runs and choose the latest run directory:

```bash
gcloud storage ls "gs://${BUCKET}/${TASK_TYPE}/${TASK_ID}/" > "${OUT}-runs.txt"
```

For evaluator, builder, and PR analysis tasks:

```bash
LOG_RUN_ID=<log_run_id>   # GCS claim timestamp, not API run_id or GHA run id
gcloud storage cp "gs://${BUCKET}/${TASK_TYPE}/${TASK_ID}/${LOG_RUN_ID}/chunk-*.log" "$OUT/" > "${OUT}-copy.txt"
cat "$OUT"/chunk-*.log > "${OUT}.log"
```

For commit analysis tasks, logs may be one level deeper per analyzed commit:

```bash
LOG_RUN_ID=<log_run_id>   # GCS claim timestamp, not API run_id or GHA run id
gcloud storage ls "gs://${BUCKET}/${TASK_TYPE}/${TASK_ID}/${LOG_RUN_ID}/" > "${OUT}-commit-runs.txt"
gcloud storage cp --recursive "gs://${BUCKET}/${TASK_TYPE}/${TASK_ID}/${LOG_RUN_ID}/" "$OUT/" > "${OUT}-copy.txt"
find "$OUT" -name 'chunk-*.log' -print | sort > "${OUT}-chunks.txt"
while IFS= read -r chunk; do cat "$chunk"; done < "${OUT}-chunks.txt" > "${OUT}.log"
```

Clean WCB/ANSI control sequences for searching/quoting:

```bash
perl -pe 's/\e_wcb;t=\d+\a//g; s/\e\[[0-9;]*[A-Za-z]//g' "${OUT}.log" > "${OUT}.clean.log"
```

Search the saved log:

```bash
rg -n -i 'error:|failed|unexpected argument|called with unexpected|not found|cannot|timeout|trace truncated|ifd|no-ifd|merge-base|not a valid commit' "${OUT}.clean.log"
```

If GCS access is unavailable but the dashboard is reachable, use:

```text
https://wcb-controller.shopifysvc.com/dashboard/task/<dashboard_task_type>/<task_id>
```

where `<dashboard_task_type>` comes from the task type mapping table above.

## Interpreting common failures

### Evaluator failure: `unexpected argument '<name>'`

Example:

```text
error: function 'anonymous lambda' called with unexpected argument 'gitd'
```

Usually this is a zone/NixOS module mismatch, not a WCB infrastructure failure. A module factory stopped accepting an argument while `zone.nix` still passes that argument via `nixosModules.module.deps` or another caller still passes it.

Fix by making the module function arguments and the zone-provided deps agree:

- restore the module argument if it is still part of the interface, or
- remove the dep only if no caller/module needs it.

### Evaluator failure: IFD / `no-ifd`

WCB cross-platform evaluation runs `tec architect get-all-targets --filter no-ifd` when evaluating a target platform different from the worker platform. Import From Derivation is disallowed because evaluation must stay cheap and because macOS targets can be evaluated on Linux evaluators. Treat IFD failures as zone/Nix expression issues.

### Builder failure: real derivation build error

Builder workers run roughly:

```text
nix-store --realize <drv> --option cores <n>
```

The builder task details include `drv`, `zone_id`, `zone_path`, `target_name`, platform, status, failure reason, and phase durations. Reproduce by building the same target/derivation on the same platform when possible. Platform-specific failures often mean missing platform conditionals or dependencies.

### Commit / PR analysis failure

Commit analyzer runs:

```text
tec ci analyze-commit --upload --windex-user-agent <agent> <commit_sha>
```

PR analyzer runs:

```text
tec ci analyze-pr --windex-user-agent <agent> --head-sha <head_sha> --base-sha <base_sha>
```

For PR analysis, both head and base commits must be locally available before `tec ci analyze-pr`; otherwise failures can look like `git merge-base ... Not a valid commit name`. For commit analysis on `main`, the worker expands `before..after`, skips non-merge commits, and may create nested per-commit log directories.

### `commit_wait` failures / no logs

Workers check that needed commits are available before running the `tec`/`nix` subprocess that ships logs. If a task fails during commit waiting, there may be no GCS log chunks. Check the task details endpoint/dashboard for phase results and `failure_reason`.

### Noisy Nix context warnings

Warnings like:

```text
Using 'builtins.derivation' to create a derivation named 'nixos-rebuild-after-boot' ... without a proper context
```

may be noisy. Continue to the final `error:` lines in the evaluator log.

### Image build fallback fetch errors

A fallback `Image build` may fail later with unrelated-looking messages such as:

```text
Failed to fetch git repository 'https://github.com/Shopify/ipman.git'
```

Treat that as secondary until the primary WCB evaluator/analyzer/build log is inspected.

## Operational WCB incidents

If the issue looks systemic rather than PR-specific:

- Check the WCB dashboard and recent commits.
- Check Observe dashboard links for WCB / Kafka ingest if available.
- The production controller Kubernetes namespace is `wcb-controller-production`.
- The `WCB Kafka ingest stalled` monitor points at the WCB dashboard, WCB logs, WCB deploys, and Kafka/GDE dashboards.
- Kafka ingest is a hot path in `//system/wcb/controller/internal/jobs/kafka/`; avoid assuming code changes there are safe without reading the source and measuring worst-case event volume.

Data warehouse/Longboat extracts exist for historical/systemic analysis:

```text
sdp_ingest_snapshots_prod__wcb_controller_production.evaluator_tasks
sdp_ingest_snapshots_prod__wcb_controller_production.builder_tasks
sdp_ingest_snapshots_prod__wcb_controller_production.commit_analysis_tasks
sdp_ingest_snapshots_prod__wcb_controller_production.pr_analysis_tasks
```

## Source-reading checklist before changing WCB

Before modifying WCB itself, read the relevant source completely; do not treat this as a requirement to read every WCB file for a small component-local change.

Always start with:

- User docs: Vault CB overview and architecture pages for `shop/world` Continuous Build
- Relevant zone overview: `//system/wcb/controller/README.md`, `//system/wcb/controller/AGENTS.md`, or `//system/wcb/workers/.claude/CLAUDE.md`

Then read the subset matching the change:

- Controller API/status/log changes: `internal/api/handlers/{handlers.go,logs.go,tasks_detail.go,commits.go}`
- Kafka ingest changes: `internal/jobs/kafka/handler.go`, `internal/jobs/kafka/consumer.go`, `internal/jobs/kafka/gde_event.go`
- Worker task/logging changes: `src/commands/{evaluator.rs,builder.rs,commit_analyzer.rs,pr_analyzer.rs}`, `src/process.rs`, `src/clients/tec.rs`
- CI integration changes: `//system/ci/ci-controller/app/services/wcb_polling_service.rb` and `app/lib/wcb/client.rb`
- Dependency graph analysis changes: commit/PR analyzer worker files plus the Windex/TEC call sites they use

Controller invariants:

- `db/schema.sql` is generated; change migrations and regenerate it.
- Controller API must be backwards compatible because controller deploys before workers.
- Kafka event ingest is performance-critical: no synchronous network calls, expensive queries, heavy per-event work, or chatty logging on that path.

Worker invariants:

- Evaluators must send all targets to Windex before deduplicating by drv; Windex indexes `(commit_sha, target_name, zone_id, platform) -> drv`.
- Builders/evaluators/analyzers ship subprocess logs to GCS; direct pre-subprocess failures may have task details but no logs.
- Workers self-update through controller/Windex; set `DISABLE_AUTOUPDATE=1` only for local development.
