#!/usr/bin/env bash

# Shared setup, teardown, and assertion helpers for all BATS tests.

# Require BATS 1.5.0+ for run --separate-stderr flag
bats_require_minimum_version 1.5.0

# Project root (where wt.sh, lib/, bin/ are located)
# Compute this first as it's needed for loading bats helpers
_compute_project_root() {
    # Handle different directory depths (unit/, integration/, e2e/)
    local dir="$BATS_TEST_DIRNAME"
    while [[ "$dir" != "/" && ! -f "$dir/wt.sh" ]]; do
        dir="$(dirname "$dir")"
    done
    echo "$dir"
}

PROJECT_ROOT="$(_compute_project_root)"

# Load bats helpers from test_helper directory
load "${PROJECT_ROOT}/test/test_helper/bats-support/load"
load "${PROJECT_ROOT}/test/test_helper/bats-assert/load"

# Create isolated test environment
# Sets up a fake $HOME with .wt directory structure
setup_test_env() {
    mkdir -p "$BATS_TEST_TMPDIR/home"
    # Use pwd -P to resolve macOS symlinks (e.g., /var -> /private/var) for consistent path comparisons
    export TEST_HOME="$(cd "$BATS_TEST_TMPDIR/home" && pwd -P)"
    export HOME="$TEST_HOME"
    export OLD_PATH="$PATH"

    mkdir -p "$TEST_HOME/.wt/lib"
    mkdir -p "$TEST_HOME/.wt/bin"
    mkdir -p "$TEST_HOME/.wt/repos"

    # Copy lib files
    cp "$PROJECT_ROOT"/lib/* "$TEST_HOME/.wt/lib/" 2>/dev/null || true

    # Copy bin files
    cp "$PROJECT_ROOT"/bin/* "$TEST_HOME/.wt/bin/" 2>/dev/null || true

    # Add bin to PATH and set standard env vars used by all tests
    export PATH="$TEST_HOME/.wt/bin:$PATH"
    export _WT_ROOT="$TEST_HOME/.wt"
    export LIB_DIR="$TEST_HOME/.wt/lib"
}

# Teardown test environment
teardown_test_env() {
    export PATH="$OLD_PATH"
    unset TEST_HOME
    unset _WT_ROOT
}

# Create a mock git repository
# Usage: create_mock_repo [path]
# Returns: normalized absolute path to created repository
create_mock_repo() {
    local repo_path="${1:-$BATS_TEST_TMPDIR/mock_repo}"
    mkdir -p "$repo_path"
    (
        cd "$repo_path"
        git init --initial-branch=main
        git config user.email "test@example.com"
        git config user.name "Test User"
        echo "initial content" > file.txt
        git add file.txt
        git commit -m "Initial commit"
    ) >/dev/null 2>&1
    # Return normalized path for consistent comparisons
    (cd "$repo_path" && pwd -P)
}

# Create a mock git repository with a remote
# Usage: create_mock_repo_with_remote [path]
# Returns: normalized absolute path to created repository
create_mock_repo_with_remote() {
    local repo_path="${1:-$BATS_TEST_TMPDIR/mock_repo}"
    local bare_path="$BATS_TEST_TMPDIR/bare_repo"

    # Create bare repo as "remote"
    mkdir -p "$bare_path"
    (
        cd "$bare_path"
        git init --bare --initial-branch=main
    ) >/dev/null 2>&1

    # Create working repo
    mkdir -p "$repo_path"
    (
        cd "$repo_path"
        git init --initial-branch=main
        git config user.email "test@example.com"
        git config user.name "Test User"
        echo "initial content" > file.txt
        git add file.txt
        git commit -m "Initial commit"
        git remote add origin "$bare_path"
        git push -u origin main
    ) >/dev/null 2>&1

    # Return normalized path for consistent comparisons
    (cd "$repo_path" && pwd -P)
}

# Create a branch in a repository
# Usage: create_branch <repo_path> <branch_name>
create_branch() {
    local repo_path="$1"
    local branch_name="$2"
    (
        cd "$repo_path"
        git checkout -b "$branch_name"
        echo "branch content" > "branch_file_${branch_name}.txt"
        git add .
        git commit -m "Add file for $branch_name"
        git checkout main
    ) >/dev/null 2>&1
}

# Create a worktree in a repository
# Usage: create_worktree <repo_path> <worktree_path> <branch_name>
# Note: worktree_path should be an absolute path for consistent comparisons
create_worktree() {
    local repo_path="$1"
    local worktree_path="$2"
    local branch_name="$3"

    # Ensure worktree parent directory exists and normalize path
    mkdir -p "$(dirname "$worktree_path")"
    local norm_parent
    norm_parent="$(cd "$(dirname "$worktree_path")" && pwd -P)"
    local norm_worktree_path="$norm_parent/$(basename "$worktree_path")"

    (
        cd "$repo_path"
        git worktree add "$norm_worktree_path" "$branch_name"
    ) >/dev/null 2>&1
}

# Create a test context configuration and set it as current
# Usage: create_test_context <context_name> <repo_path>
create_test_context() {
    local name="$1"
    local repo_path="$2"
    local repos_dir="$TEST_HOME/.wt/repos"

    local norm_repo_path norm_repos_dir norm_test_home
    norm_repo_path="$(cd "$repo_path" 2>/dev/null && pwd -P)"
    # Ensure repos dir exists before normalizing
    mkdir -p "$repos_dir"
    norm_repos_dir="$(cd "$repos_dir" && pwd -P)"
    norm_test_home="$(cd "$TEST_HOME" && pwd -P)"

    mkdir -p "$norm_repos_dir/$name/worktrees"
    mkdir -p "$norm_repos_dir/$name/idea-files"

    cat > "$norm_repos_dir/$name.conf" <<EOF
WT_MAIN_REPO_ROOT="$norm_repo_path"
WT_WORKTREES_BASE="$norm_repos_dir/$name/worktrees"
WT_ACTIVE_WORKTREE="$norm_test_home/active"
WT_IDEA_FILES_BASE="$norm_repos_dir/$name/idea-files"
WT_BASE_BRANCH="main"
WT_METADATA_PATTERNS=""
EOF

    # Also set this as the current context
    echo "$name" > "$norm_test_home/.wt/current"
}

# Load context configuration into environment
# Usage: load_test_context <context_name>
load_test_context() {
    local name="$1"
    local config_path="$TEST_HOME/.wt/repos/$name.conf"
    if [[ -f "$config_path" ]]; then
        source "$config_path"
        export WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_ACTIVE_WORKTREE WT_IDEA_FILES_BASE WT_BASE_BRANCH WT_METADATA_PATTERNS
    fi
}

# Make changes to a repository (make it dirty)
# Usage: make_repo_dirty <repo_path>
make_repo_dirty() {
    local repo_path="$1"
    echo "uncommitted change" >> "$repo_path/file.txt"
}

# Stage changes in a repository
# Usage: stage_changes <repo_path>
stage_changes() {
    local repo_path="$1"
    (cd "$repo_path" && git add -A) >/dev/null 2>&1
}

# Create metadata directories in a repository
# Usage: create_metadata_dirs <repo_path> [patterns...]
create_metadata_dirs() {
    local repo_path="$1"
    shift
    local patterns=("$@")

    if [[ ${#patterns[@]} -eq 0 ]]; then
        patterns=(".idea" ".ijwb")
    fi

    for pattern in "${patterns[@]}"; do
        mkdir -p "$repo_path/$pattern"
        echo "config" > "$repo_path/$pattern/config.xml"
    done
}

# Assert that a symlink points to expected target
# Usage: assert_symlink_target <symlink_path> <expected_target>
assert_symlink_target() {
    local symlink_path="$1"
    local expected_target="$2"

    assert [ -L "$symlink_path" ]
    local actual_target
    actual_target="$(readlink "$symlink_path")"
    assert_equal "$actual_target" "$expected_target"
}

# Assert that a path is a valid git worktree
# Usage: assert_is_worktree <path>
#
# Worktrees have .git as a FILE containing "gitdir:" reference.
# Main repos have .git as a DIRECTORY - this distinction validates true worktrees.
assert_is_worktree() {
    local path="$1"
    assert [ -d "$path" ]
    assert [ -f "$path/.git" ]
    assert grep -q "^gitdir:" "$path/.git"
}

# Skip test if not running in bash
skip_if_not_bash() {
    if [[ -z "$BASH_VERSION" ]]; then
        skip "Test requires bash"
    fi
}

# Skip test if git is not available
skip_if_no_git() {
    if ! command -v git &>/dev/null; then
        skip "Test requires git"
    fi
}
