# fasttrack

A blazingly fast monorepo task runner written in Zig. Automatically detects your package manager (pnpm, npm, yarn, bun) and orchestrator (nx, turbo, bun), providing a unified CLI for running tasks across your monorepo.

## Features

- ⚡ **Lightning fast** - Built in Zig with zero runtime overhead
- 🔍 **Auto-detection** - Detects nx, turbo, or bun automatically
- 📦 **Package manager agnostic** - Works with pnpm, npm, yarn, or bun
- 🎯 **Affected-only mode** - Run tasks only on changed packages (requires nx or turbo)
- 🔗 **Chainable tasks** - Run multiple checks in a single command
- 🎨 **Colored output** - Beautiful, readable output with status indicators

## Installation

### Build from Source

Requires [Zig](https://ziglang.org) 0.15.0+

```bash
git clone https://github.com/alpercitak/fasttrack
cd fasttrack
zig build-exe src/main.zig -femit-bin=fasttrack
sudo mv fasttrack /usr/local/bin/
```

## Usage

```bash
fasttrack [options]

Options:
  --lint         Run linting
  --test         Run tests
  --format       Run formatter (Prettier)
  --prettier     Alias for --format
  --build        Run build
  --typecheck    Run type checking
  --affected     Only run on affected projects (requires nx/turbo)
  --help, -h     Show help message

Examples:
  fasttrack --lint --test                    # Run lint and test
  fasttrack --format --lint --test --build   # Run all checks sequentially
  fasttrack --lint --affected                # Lint only affected packages
```

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

# Runs: pnpm run test && pnpm run build
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
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0  # Required for --affected to work

      - uses: alpercitak/fasttrack@v0.2.0
        with:
          args: --lint --test --build --affected
```

## How It Works

1. **Auto-detection**: fasttrack checks for `nx.json`, `turbo.json`, and lock files
2. **Command generation**: Based on detected tools, generates appropriate commands
3. **Execution**: Runs the generated command with inherited stdout/stderr
4. **Error handling**: Reports failures with proper exit codes

### Command Mapping

| Input | nx | turbo | bun | none |
|-------|----|----|-----|------|
| `--lint` | `nx run-many -t lint --all` | `turbo run lint` | `bun run lint` | `pnpm run lint` |
| `--lint --affected` | `nx affected -t lint` | `turbo run lint --filter=[origin/main...HEAD]` | (not applicable) | (not applicable) |

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
2. Has `origin/main` branch (or adjust the branch in the source)
3. Is on a different branch than `origin/main`

### Command not executing properly

Run with the generated command visible (it's printed in cyan) and verify it's correct for your monorepo setup.

### Permission denied

Ensure the binary is executable:

```bash
chmod +x /usr/local/bin/fasttrack
```
