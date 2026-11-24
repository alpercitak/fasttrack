# fasttrack

![Zig](https://img.shields.io/badge/zig--0.15.2-000000?style=flat-square&logo=zig&logoColor=F7A41D)
![Release](https://img.shields.io/github/v/tag/alpercitak/fasttrack?include_prereleases&style=flat-square&color=2ea44f&label=release)
![Build](https://img.shields.io/github/actions/workflow/status/alpercitak/fasttrack/build-release.yaml?style=flat-square&label=&color=2ea44f)
![License](https://img.shields.io/badge/MIT-2ea44f?style=flat-square)

A blazingly fast monorepo task runner written in Zig. Automatically detects your package manager (pnpm, npm, yarn, bun) and orchestrator (nx or turbo), providing a unified CLI for running tasks across your monorepo.

## Features

- ⚡ **Lightning fast** - Built in Zig with zero runtime overhead
- 🔍 **Auto-detection** - Detects nx or turbo automatically
- 📦 **Package manager agnostic** - Works with pnpm, npm, yarn, or bun
- 🎯 **Affected-only mode** - Run tasks only on changed packages (requires nx or turbo)
- 🔗 **Chainable tasks** - Run multiple checks in a single command
- 🎨 **Colored output** - Beautiful, readable output with status indicators

## Installation

### Build from Source

Requires [Zig](https://ziglang.org) 0.15.x

```bash
git clone https://github.com/alpercitak/fasttrack
cd fasttrack
zig build-exe src/main.zig -femit-bin=fasttrack
sudo mv fasttrack /usr/local/bin/
```

## Usage

```bash
fasttrack [options]

Tasks:
  --lint         Run linting
  --test         Run tests
  --format       Run formatter (alias: --prettier)
  --build        Run build
  --typecheck    Run type checking

Options:
  --affected     Only run on affected projects (requires nx/turbo)
  --base=<ref>   Base git ref for --affected (default: origin/main)
  --parallel     Run tasks in parallel
  --quiet        Hide task output (only show status lines)
  --verbose      Show CI/branch detection details
  --help, -h     Show help message

Environment Variables:
  FASTTRACK_BASE    Override default base ref (--base takes precedence)

Examples:
  fasttrack --lint --test                    # Run lint and test
  fasttrack --format --lint --test --build   # Run all checks sequentially
  fasttrack --lint --affected                # Lint only affected packages
  fasttrack --lint --test --parallel         # Run lint and test at the same time
```

Tasks always run in the fixed order format → lint → typecheck → test → build. A failing task does not stop the
following ones, but fasttrack exits with code `1` if any task failed. Unknown options or no task at all exit with
code `2`.

With `--parallel` and nx or turbo, all tasks go to the orchestrator in a single call (for example
`nx run-many -t lint test build --all` or `turbo run lint test build`), so it schedules them, uses its cache and keeps
the output of each task together. Without an orchestrator, each package script starts in its own process at the same
time, and their output may interleave.

## Integration with Monorepos

### In nx Monorepo

```bash
# Run formatting on all packages
fasttrack --format

# Run tests only on packages changed since last commit
fasttrack --test --affected

# Full CI pipeline
fasttrack --format --lint --typecheck --test --build
```

### In Turbo Monorepo

```bash
# Same commands work automatically!
fasttrack --build --affected

# Since turbo is detected, it uses turbo filter automatically
# Equivalent to: turbo run build --filter=[origin/main...HEAD]
```

### In Single-Package Repository

```bash
# Works just as well
fasttrack --test --build

# Runs: pnpm run test, then pnpm run build
```

## GitHub Actions Integration

### Direct Binary Download

```yaml
name: CI

on: [push, pull_request]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0  # Required for --affected to work

      - uses: alpercitak/fasttrack@v0
        with:
          args: --lint --test --build --affected
```

`@v0` resolves to the newest `v0.x.y` release. Pin an exact release (e.g. `@v0.2.2`) for fully reproducible builds.

When running on the base branch itself (e.g. a push to `main`), `--affected` compares against `HEAD~1`, which only
covers the last commit. To cover every commit in a push, pass the previous head explicitly:

```yaml
      - uses: alpercitak/fasttrack@v0
        with:
          args: --test --affected --base=${{ github.event.before }}
```

## How It Works

1. **Auto-detection**: fasttrack checks for `nx.json`, `turbo.json`, and lock files
2. **Command generation**: Based on detected tools, generates appropriate commands
3. **Execution**: Runs the generated command with inherited stdout/stderr (use `--quiet` to hide it)
4. **Error handling**: Reports why each task failed and exits non-zero

### Command Mapping

| Input | nx | turbo | none |
|-------|----|-------|------------|
| `--lint` | `<exec> nx run-many -t lint --all` | `<exec> turbo run lint` | `<manager> run lint` |
| `--lint --affected` | `<exec> nx affected -t lint --base=origin/main` | `<exec> turbo run lint --filter=[origin/main...HEAD]` | (not applicable) |

`<exec>` is `pnpm`, `yarn`, `npx` or `bunx` depending on the detected package manager (from `pnpm-lock.yaml`,
`yarn.lock`, `bun.lock`/`bun.lockb`, otherwise npm).

## Performance

- **Startup**: <10ms (no JVM/Node overhead)
- **Command generation**: <1ms
- **Execution**: Identical to running commands directly

fasttrack adds negligible overhead compared to running tools directly.

## License

MIT

## Troubleshooting

### `--affected` not detecting changes

Ensure your repository:
1. Has commits (not a fresh repo)
2. Has the base ref available locally (`origin/main` by default; change it with `--base=<ref>` or `FASTTRACK_BASE`)
3. Was checked out with enough history (`fetch-depth: 0` in `actions/checkout`)

Run with `--verbose` to see the detected CI, branch and base ref.

### Command not executing properly

The generated command is printed in cyan before it runs; verify it's correct for your monorepo setup.

### Permission denied

Ensure the binary is executable:

```bash
chmod +x /usr/local/bin/fasttrack
```
