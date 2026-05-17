---
name: rust
description: Use whenever creating, scaffolding, or modifying Rust projects; choosing Rust dependencies; designing Rust CLIs; setting up logging/tracing; handling Rust errors and diagnostics; or working with Cargo workspaces/crates.
---

# Rust Project Defaults

Use these conventions for Rust work unless the repository already has a stronger local convention or the user asks otherwise.

## Baseline project shape

- Use **Rust Edition 2024** for new crates.
- Prefer a **Cargo workspace** when there is more than one crate.
- Use the **shallow bin pattern**:
  - Library crates contain real behavior, domain types, parsing, validation, and tests.
  - Binary crates contain argument parsing, process setup, logging/diagnostic setup, and calls into the library.
  - Keep `main.rs` thin. If it grows substantial logic, move that logic into the library.
- Public library APIs should be reusable without the CLI.
- Do not introduce async runtimes by default. Add Tokio/async executors only when async is central to the program. For one-shot async setup, prefer a smaller bridge such as `pollster` when appropriate.

## Standard dependencies

For most non-trivial Rust projects, prefer these from day 0:

```toml
[dependencies]
camino = { version = "1", features = ["serde1"] }
clap = { version = "4", features = ["derive", "env"] }
miette = { version = "7", features = ["fancy"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
serde_yaml = "0.9"
thiserror = "2"
tracing = "0.1"
tracing-log = "0.2"
tracing-subscriber = { version = "0.3", features = ["env-filter", "fmt"] }

[dev-dependencies]
rstest = "0.26"
```

Use these when the need appears, not preemptively:

- `derive_more` — when writing boilerplate derives/conversions/display wrappers.
- `enum-as-inner` — when enum accessors would otherwise be handwritten.
- `bytemuck` — for safe buffer casts / POD data, especially GPU or binary formats.
- `pollster` — for small blocking bridges around async APIs.
- `image` — for image encoding/decoding.
- `tracing-chrome`, `tracing-flame`, `tracing-tracy` — for profiler/export targets.

Do not hand-roll functionality that one of the encouraged crates provides unless there is a specific reason.

## CLI conventions

- Use `clap` derive APIs: `Parser`, `Subcommand`, `Args`, and `ValueEnum`.
- Prefer typed arguments over stringly parsing.
- If an enum is both CLI-facing and domain-relevant, define it in the library and derive `ValueEnum` there when that does not pollute the abstraction.
- Keep stdout for primary command output. Use tracing/logging for diagnostics.
- Add verbosity/filter controls early. Prefer `RUST_LOG`/`EnvFilter` compatibility and a CLI override when useful.
- Avoid `println!`/`eprintln!` for diagnostics. Intentional stdout output is fine for command results.

## Tracing, logging, and profiling

- Use `tracing` from the start.
- Initialize `tracing-subscriber` in the binary before doing real work.
- Install `tracing-log` so crates using `log` are captured by the tracing subscriber.
- Use `#[tracing::instrument]` on meaningful functions, but skip large/noisy arguments:

```rust
#[tracing::instrument(skip(world, grid), fields(width = grid.width(), height = grid.height()))]
fn run_simulation(world: &World, grid: &Grid) -> miette::Result<Grid> {
    // ...
}
```

- Use spans around expensive phases: parsing, validation, shader/code generation, IO, compilation, simulation, rendering.
- For future performance work, prefer optional exporter features rather than baking in a single profiler:
  - `tracing-chrome` for Chrome/Perfetto JSON traces.
  - `tracing-flame` for folded span data/flamegraphs.
  - `tracing-tracy` for interactive profiling.
- For `wgpu`, remember that wgpu commonly emits diagnostics through `log` and uses the `profiling` crate internally. Bridge `log` into tracing, and consider `profiling/profile-with-tracing` when trying to capture wgpu profiling scopes.

## Errors and diagnostics

- Use `thiserror` for typed library errors.
- Use `miette` for user-facing diagnostics from day 0, especially for source/config files.
- Prefer `miette::Result` at CLI boundaries.
- Avoid `anyhow` in libraries. If a project already uses `anyhow`, keep it at application boundaries only.
- For parse errors, carry enough context for nice diagnostics:
  - file/path if available,
  - source text when feasible,
  - source span/offset,
  - stable diagnostic code.

Example pattern:

```rust
#[derive(Debug, thiserror::Error, miette::Diagnostic)]
#[error("invalid cell value `{value}`")]
#[diagnostic(code(worldsim::invalid_cell_value))]
pub struct InvalidCellValue {
    pub value: char,
    #[label("this character is not a valid cell")]
    pub span: miette::SourceSpan,
    #[source_code]
    pub source: miette::NamedSource<String>,
}
```

## Serde and file formats

- Use `serde` for structured data. Do not ad-hoc parse JSON/YAML.
- Standardize on `serde_json` for JSON and `serde_yaml` for YAML unless the project requires another format crate.
- Keep wire/config structs close to the format boundary. Convert into validated domain structs after parsing.
- Use `#[serde(deny_unknown_fields)]` for user-authored config when rejecting typos is better than forward compatibility.
- Prefer explicit validation after deserialization over encoding every invariant into serde attributes.

## Paths and filesystem

- Use `camino::Utf8Path` and `Utf8PathBuf` for project-facing paths.
- Convert to `std::path::Path` only at OS/library boundaries via `.as_std_path()`.
- CLI path arguments should generally be `Utf8PathBuf`.
- Include paths in diagnostics and tracing fields.

## Testing and verification

- Put most tests in the library crate.
- Use `rstest` for table-driven tests by default; its `#[case(...)]` support is worth standardizing on.
- Test parsers/codecs with round trips and malformed input.
- Use snapshot tests for generated code or rich diagnostics when textual output matters.
- Before reporting done, run the strongest practical checks for the repo, usually:

```bash
cargo fmt --check
cargo clippy --all-targets --all-features
cargo test --all-targets --all-features
```

If the repo has a different command set (`just`, `xtask`, Nix checks), follow the repo convention.

## Dependency discipline

- Prefer small, established crates over local boilerplate.
- Do not add dependencies speculatively. Add them when they remove real boilerplate, improve diagnostics, or establish a project-wide pattern.
- Be deliberate with feature flags; avoid pulling large optional stacks into libraries by default.
- Keep profiling/export integrations optional unless the user explicitly wants them always on.
