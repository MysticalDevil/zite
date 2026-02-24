# Repository Guidelines

## Project Structure & Module Organization
- `src/` holds the library code. Entry point is `src/root.zig`.
- `src/raw/` contains low-level sqlite3 bindings; `src/wrapper/` contains higher-level wrappers.
- `tests/` contains integration tests. `tests/itest.zig` is the test entry module and includes files like `integration_*.zig`.

## Build, Test, and Development Commands
- `zig build` builds the library with default settings.
- `zig build test` runs unit tests for the main `zite` module.
- `zig build itest` runs integration tests from `tests/itest.zig`.
- `zig build itest -Ddiag_enable_in_tests=true` enables sqlite diagnostics during tests.

## Coding Style & Naming Conventions
- Use `zig fmt` on all Zig sources: `zig fmt src tests build.zig`.
- Follow Zig naming conventions:
  - Types/structs: `PascalCase`
  - Functions/vars: `lower_snake_case`
  - Files: `lower_snake_case.zig` (e.g., `integration_findone.zig`)
- Keep modules focused: raw bindings in `src/raw/`, higher-level APIs in `src/wrapper/`.

## Testing Guidelines
- Tests are written with `zig test` via `zig build test` and `zig build itest`.
- Integration tests live in `tests/integration_*.zig` and are pulled into `tests/itest.zig`.
- Name new integration tests as `integration_<feature>.zig` and wire them into `tests/itest.zig`.

## Commit & Pull Request Guidelines
- Commit messages follow a conventional format seen in history:
  - Examples: `feat: add mapper.findMany iterator`, `refactor: split sqlite3 raw bindings and wrapper layer`.
  - Preferred prefixes: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.
- PRs should include:
  - A short summary of changes.
  - Tests run (e.g., `zig build test`, `zig build itest`).
  - Any schema or API behavior changes called out explicitly.

## Dependencies & Local Setup
- Requires system `sqlite3` headers and library (linked via `linkSystemLibrary("sqlite3")` in `build.zig`).
- If sqlite diagnostics are needed for debugging, use `-Ddiag_enable_in_tests=true` in test runs.
