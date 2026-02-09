# Testing the Worktree Toolkit

This directory contains the full test suite for `wt`, built on [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Test Directory Structure

```
test/
├── README.md                # This file
├── bats/                    # BATS core (git submodule)
├── test_helper/
│   ├── common.bash          # Shared setup, teardown, helpers, custom assertions
│   ├── bats-assert/         # Assertion library (git submodule)
│   └── bats-support/        # Support library (git submodule)
├── unit/                    # Library function tests (lib/wt-*)
│   ├── wt-common.bats       # Output helpers, git helpers, prompt, config loading
│   ├── wt-context.bats      # Context CRUD, listing, switching, config loading
│   └── wt-context-setup.bats # Path expansion, branch detection, path derivation, metadata detection
├── integration/             # Per-command script tests (bin/wt-*)
│   ├── wt-add.bats          # Worktree creation (existing branch, -b, path traversal, state restore)
│   ├── wt-cd.bats           # Path output, validation, spaces in paths
│   ├── wt-context.bats      # Context listing, switching, add subcommand
│   ├── wt-list.bats         # Worktree listing, indicators, verbose mode
│   ├── wt-metadata-export.bats  # Symlink creation, deduplication, patterns
│   ├── wt-metadata-import.bats  # Copy behavior, symlink resolution, overwrite
│   ├── wt-remove.bats       # Removal, main repo protection, --merged, dirty handling
│   └── wt-switch.bats       # Symlink switching, safety (non-symlink protection)
└── e2e/                     # Full workflow tests
    └── workflow.bats         # Lifecycle, multi-worktree, context switching, error recovery
```

## Running Tests

### Prerequisites

- Bash 4.0+
- Git

No installation needed — BATS and its helper libraries are included as git submodules.

### Initialize submodules (first time only)

```bash
git submodule update --init --recursive
```

### Run all tests

```bash
./test/bats/bin/bats test/unit/ test/integration/ test/e2e/
```

### Run a specific test layer

```bash
./test/bats/bin/bats test/unit/            # Library functions only
./test/bats/bin/bats test/integration/     # Per-command scripts
./test/bats/bin/bats test/e2e/             # Full workflows
```

### Run a single test file

```bash
./test/bats/bin/bats test/unit/wt-common.bats
./test/bats/bin/bats test/integration/wt-add.bats
```

### Run a single test by name

```bash
./test/bats/bin/bats test/unit/wt-common.bats --filter "echoerr outputs"
```

## Test Infrastructure

### Isolation model

Every test runs in a fully isolated environment:

- `setup_test_env()` creates a temporary `$HOME` under `$BATS_TEST_TMPDIR/home`
- All `~/.wt/` state (configs, libs, bins) is copied fresh from the project root
- `$PATH` is prepended with the test `bin/` directory
- `$HOME`, `$LIB_DIR`, and `$_WT_ROOT` are overridden
- `teardown_test_env()` restores the original `$PATH`

BATS automatically cleans up `$BATS_TEST_TMPDIR` after each test. No test can affect another or leave persistent side effects.

### Test helper (`test/test_helper/common.bash`)

The shared helper provides:

**Environment setup:**
- `setup_test_env` / `teardown_test_env` — Isolated `$HOME` with `.wt/` structure
- `create_test_context <name> <repo_path>` — Create a context `.conf` file and set it as current
- `load_test_context <name>` — Source the `.conf` and export all `WT_*` variables

**Git helpers:**
- `create_mock_repo [path]` — Initialize a git repo with one commit, return normalized path
- `create_mock_repo_with_remote [path]` — Same but with a bare "remote" repo and `origin` configured
- `create_branch <repo> <name>` — Create a branch with a commit, return to `main`
- `create_worktree <repo> <path> <branch>` — Create a git worktree at normalized path
- `make_repo_dirty <repo>` — Append to `file.txt` to create uncommitted changes
- `stage_changes <repo>` — `git add -A`

**Metadata helpers:**
- `create_metadata_dirs <repo> [patterns...]` — Create `.idea`, `.ijwb`, etc. with a `config.xml`

**Custom assertions:**
- `assert_symlink_target <path> <expected>` — Verify a symlink exists and points to the expected target
- `assert_is_worktree <path>` — Verify a path is a git worktree (has `.git` file with `gitdir:`)

### Unit vs. integration vs. e2e

| Layer | What it tests | How it works |
|---|---|---|
| **Unit** (`test/unit/`) | Individual library functions from `lib/` | Sources the library directly, calls functions, checks return values and output |
| **Integration** (`test/integration/`) | Each `bin/wt-*` script end-to-end | Runs the script as a subprocess via `run "$TEST_HOME/.wt/bin/wt-add" ...`, checks exit codes, output, and filesystem state |
| **E2E** (`test/e2e/`) | Multi-step workflows across multiple commands | Chains multiple commands (add → switch → work → remove) and verifies the system stays consistent throughout |

### How scripts find their config in tests

Each `bin/wt-*` script re-sources `wt-common` on startup using its own `LIB_DIR` (derived from `SCRIPT_DIR/../lib`). Since tests copy all files to `$TEST_HOME/.wt/`, the scripts find the test copies of `lib/wt-common` and `lib/wt-context`, which then read the test context config from `$TEST_HOME/.wt/repos/<name>.conf`.

This means **updating `WT_METADATA_PATTERNS` requires editing the `.conf` file** (via `sed`), not just exporting the environment variable — the script will overwrite the export when it re-sources `wt-common`.

## Writing New Tests

### Adding a test to an existing file

Each `.bats` file is organized with section headers. Add your test to the appropriate section:

```bash
@test "wt-add handles my new edge case" {
    # Arrange: set up state
    create_branch "$REPO" "my-branch"

    # Act: run the command
    run "$TEST_HOME/.wt/bin/wt-add" "my-branch"

    # Assert: check outcomes
    assert_success
    assert_is_worktree "$WT_WORKTREES_BASE/my-branch"
}
```

### Adding a new unit test file

For a new library (e.g., `lib/wt-foo`):

```bash
#!/usr/bin/env bats

# Unit tests for lib/wt-foo

setup() {
    load '../test_helper/common'
    setup_test_env

    # Source the library under test (and its dependencies)
    source "$TEST_HOME/.wt/lib/wt-common"
    source "$TEST_HOME/.wt/lib/wt-foo"
}

teardown() {
    teardown_test_env
}

@test "my_function returns expected value" {
    run my_function "input"
    assert_success
    assert_output "expected"
}
```

### Adding a new integration test file

For a new command (e.g., `bin/wt-foo`):

```bash
#!/usr/bin/env bats

# Integration tests for bin/wt-foo

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create mock repo and context
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")
    create_test_context "test" "$REPO"
    load_test_context "test"
}

teardown() {
    teardown_test_env
}

@test "wt-foo does the thing" {
    run "$TEST_HOME/.wt/bin/wt-foo" --flag arg
    assert_success
    assert_output --partial "expected text"
}
```

### Tips

- **Use `run --separate-stderr`** when testing commands that send UI to stderr and data to stdout (e.g., `wt-cd`). Captures `$output` (stdout) and `$stderr` separately.
- **Use `run bash -c 'echo "input" | command'`** to test interactive prompts (e.g., confirmation dialogs).
- **Edit `.conf` via `sed`** to change `WT_METADATA_PATTERNS` — environment exports are overwritten when scripts re-source `wt-common`.
- **Always check filesystem state**, not just output text. For example, after `wt-add`, verify the worktree directory exists, has a `.git` file, and is on the correct branch.
- **Use `assert_is_worktree`** instead of just `assert [ -d "$path" ]` — it validates the `.git` file contains a `gitdir:` reference, which distinguishes true worktrees from regular directories or main repos.
- **Normalize paths with `pwd -P`** when comparing against `git worktree list` output or `wt_get_linked_worktree` results.
