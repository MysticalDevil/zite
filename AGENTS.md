# Repository Guidelines

## Project Structure & Module Organization

- `src/` holds the library code. Entry point is `src/root.zig`.
- `src/raw/` contains low-level sqlite3 bindings.
- `src/db/` contains the DB and statement wrappers.
- `src/core/` contains shared types, meta, and SQL utilities.
- `src/orm/` contains mapper and schema helpers.
- `tests/` contains integration tests. `tests/itest.zig` is the test entry module and includes files from `tests/integration/`.
- `examples/` contains runnable usage samples.

## API Stability & Boundaries

- Stable APIs: `Db`, `Stmt`, `mapper`, `schema`, `types`, `errors`.
- Advanced APIs: `raw`, `sqlutil`, `meta` are exposed for power users and may change.

## Build, Test, and Development Commands

- `zig build` builds the library with default settings.
- `zig build test` runs unit tests for the main `zite` module.
- `zig build itest` runs integration tests from `tests/itest.zig`.
- `zig build itest -Ddiag_enable_in_tests=true` enables sqlite diagnostics during tests.

## Coding Style & Naming Conventions

- Use `zig fmt` on all Zig sources: `zig fmt src tests build.zig`.
- Follow Zig naming conventions. Types/structs use `PascalCase`. Functions/vars use `lower_snake_case`. Files use `lower_snake_case.zig` (e.g., `find_one.zig`).
- Keep modules focused: raw bindings in `src/raw/`, ORM in `src/orm/`, DB wrappers in `src/db/`.

## Testing Guidelines

- Tests are written with `zig test` via `zig build test` and `zig build itest`.
- Integration tests live in `tests/integration/*.zig` and are pulled into `tests/itest.zig`.
- Name new integration tests as `tests/integration/<feature>.zig` and wire them into `tests/itest.zig`.

## Commit & Pull Request Guidelines

- Commit messages follow a conventional format seen in history. Examples: `feat: add mapper.findMany iterator`, `refactor: split sqlite3 raw bindings and wrapper layer`. Preferred prefixes: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.
- PRs should include a short summary of changes, tests run (e.g., `zig build test`, `zig build itest`), and any schema or API behavior changes called out explicitly.

## Dependencies & Local Setup

- Requires system `sqlite3` headers and library (linked via `linkSystemLibrary("sqlite3")` in `build.zig`).
- If sqlite diagnostics are needed for debugging, use `-Ddiag_enable_in_tests=true` in test runs.

## Examples

- `examples/orm_basic.zig` shows the ORM mapping flow with `OwnedText/OwnedBlob`.
- `examples/orm_find_many.zig` shows `findMany` iteration.
- `examples/orm_find_one.zig` shows `findOne` with parameters.
- `examples/orm_meta_options.zig` shows `Meta` options (rename/skip/unique).
- `examples/stmt_bind_all.zig` shows `bindAll` with typed params.
- `examples/stmt_basic.zig` shows direct statement usage.
- `examples/README.md` documents how to run the examples.
