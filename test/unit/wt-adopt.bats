#!/usr/bin/env bats

# Unit tests for lib/wt-adopt

setup() {
    load '../test_helper/common'
    setup_test_env
    source "$TEST_HOME/.wt/lib/wt-common"
    source "$TEST_HOME/.wt/lib/wt-adopt"

    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")
    create_branch "$REPO" "test-branch"

    WORKTREE="$BATS_TEST_TMPDIR/wt/test-branch"
    create_worktree "$REPO" "$WORKTREE" "test-branch"
    # Normalize path for consistent comparisons
    WORKTREE="$(cd "$WORKTREE" && pwd -P)"

    export WT_MAIN_REPO_ROOT="$REPO"
}

teardown() {
    teardown_test_env
}

# Helper: resolve git dir for a worktree
_resolve_git_dir() {
    local wt_path="$1"
    local git_dir
    git_dir="$(git -C "$wt_path" rev-parse --git-dir)"
    if [[ "$git_dir" != /* ]]; then
        git_dir="$(cd "$wt_path" && cd "$git_dir" && pwd -P)"
    fi
    echo "$git_dir"
}

# =============================================================================
# wt_is_adopted / wt_mark_adopted / wt_unmark_adopted
# =============================================================================

@test "wt_is_adopted returns false for fresh worktree" {
    run wt_is_adopted "$WORKTREE"
    assert_failure
}

@test "wt_mark_adopted creates marker file in correct git-dir location" {
    export WT_CONTEXT_NAME="java"
    wt_mark_adopted "$WORKTREE"

    # Marker should be inside the worktree's git dir, NOT in the working tree
    local git_dir
    git_dir="$(_resolve_git_dir "$WORKTREE")"
    assert [ -f "$git_dir/wt/adopted" ]
    # In a worktree, .git is a file, not a directory — marker should NOT be at .git/wt/adopted
    assert [ ! -d "$WORKTREE/.git/wt" ]
}

@test "wt_mark_adopted writes context name to wt/adopted file" {
    export WT_CONTEXT_NAME="java"
    wt_mark_adopted "$WORKTREE"

    local git_dir
    git_dir="$(_resolve_git_dir "$WORKTREE")"
    local content
    content="$(cat "$git_dir/wt/adopted")"
    assert_equal "$content" "java"
}

@test "wt_mark_adopted uses 'unknown' when WT_CONTEXT_NAME is unset" {
    unset WT_CONTEXT_NAME
    wt_mark_adopted "$WORKTREE"

    local git_dir
    git_dir="$(_resolve_git_dir "$WORKTREE")"
    local content
    content="$(cat "$git_dir/wt/adopted")"
    assert_equal "$content" "unknown"
}

@test "wt_is_adopted returns true after marking" {
    wt_mark_adopted "$WORKTREE"
    run wt_is_adopted "$WORKTREE"
    assert_success
}

@test "wt_unmark_adopted removes marker and wt directory" {
    wt_mark_adopted "$WORKTREE"
    run wt_is_adopted "$WORKTREE"
    assert_success

    wt_unmark_adopted "$WORKTREE"
    run wt_is_adopted "$WORKTREE"
    assert_failure

    # wt/ directory should also be cleaned up
    local git_dir
    git_dir="$(_resolve_git_dir "$WORKTREE")"
    assert [ ! -d "$git_dir/wt" ]
}

@test "wt_mark_adopted is idempotent" {
    export WT_CONTEXT_NAME="java"
    wt_mark_adopted "$WORKTREE"
    wt_mark_adopted "$WORKTREE"
    run wt_is_adopted "$WORKTREE"
    assert_success
}

# =============================================================================
# wt_read_adopted_context
# =============================================================================

@test "wt_read_adopted_context returns context name from wt/adopted" {
    export WT_CONTEXT_NAME="java"
    wt_mark_adopted "$WORKTREE"

    run wt_read_adopted_context "$WORKTREE"
    assert_success
    assert_output "java"
}

@test "wt_read_adopted_context handles empty file (old format backward compat)" {
    local git_dir
    git_dir="$(_resolve_git_dir "$WORKTREE")"
    mkdir -p "$git_dir/wt"
    touch "$git_dir/wt/adopted"

    run wt_read_adopted_context "$WORKTREE"
    assert_success
    assert_output ""
}

@test "wt_read_adopted_context returns 1 when not adopted" {
    run wt_read_adopted_context "$WORKTREE"
    assert_failure
}

# =============================================================================
# Cross-tool: CLI writes, plugin reads
# =============================================================================

@test "cross-tool: wt/adopted is plain text readable by both CLI and plugin" {
    export WT_CONTEXT_NAME="java"
    wt_mark_adopted "$WORKTREE"

    local git_dir
    git_dir="$(_resolve_git_dir "$WORKTREE")"

    # Verify file is simple text: context name followed by newline
    local raw_content
    raw_content="$(cat "$git_dir/wt/adopted")"
    assert_equal "$raw_content" "java"

    # Verify wt_read_adopted_context reads it back
    run wt_read_adopted_context "$WORKTREE"
    assert_success
    assert_output "java"
}

# =============================================================================
# wt_is_main_repo
# =============================================================================

@test "wt_is_main_repo returns true for main repo" {
    run wt_is_main_repo "$REPO"
    assert_success
}

@test "wt_is_main_repo returns false for worktree" {
    run wt_is_main_repo "$WORKTREE"
    assert_failure
}

@test "wt_is_main_repo returns failure for non-git directory" {
    local tmpdir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$tmpdir"
    run wt_is_main_repo "$tmpdir"
    assert_failure
}

# =============================================================================
# wt_seed_files
# =============================================================================

@test "wt_seed_files copies configured files from main repo" {
    echo "7.1.0" > "$REPO/.bazelversion"
    echo "build --disk_cache=/tmp/cache" > "$REPO/user.bazelrc"
    export WT_SEED_FILES=".bazelversion user.bazelrc"

    wt_seed_files "$WORKTREE"

    assert [ -f "$WORKTREE/.bazelversion" ]
    assert [ -f "$WORKTREE/user.bazelrc" ]
    assert_equal "$(cat "$WORKTREE/.bazelversion")" "7.1.0"
}

@test "wt_seed_files skips files missing in main repo" {
    export WT_SEED_FILES="does-not-exist.bazelrc"

    run wt_seed_files "$WORKTREE"
    assert_success
    assert [ ! -e "$WORKTREE/does-not-exist.bazelrc" ]
}

@test "wt_seed_files does not overwrite existing files in worktree" {
    echo "main-repo-content" > "$REPO/user.bazelrc"
    echo "worktree-content" > "$WORKTREE/user.bazelrc"
    export WT_SEED_FILES="user.bazelrc"

    wt_seed_files "$WORKTREE"

    assert_equal "$(cat "$WORKTREE/user.bazelrc")" "worktree-content"
}

@test "wt_seed_files does nothing when WT_SEED_FILES is empty" {
    export WT_SEED_FILES=""

    run wt_seed_files "$WORKTREE"
    assert_success
}

@test "wt_seed_files warns on copy failure and continues with next file" {
    mkdir -p "$REPO/nodir"
    echo "nested" > "$REPO/nodir/seed.conf"
    echo "7.1.0" > "$REPO/.bazelversion"
    # nodir/ does not exist in the worktree, so cp fails for the first file
    export WT_SEED_FILES="nodir/seed.conf .bazelversion"

    run --separate-stderr wt_seed_files "$WORKTREE"
    assert_success
    [[ "$stderr" == *"Could not seed nodir/seed.conf"* ]] || \
        fail "stderr should warn about failed seed, got: $stderr"
    assert [ -f "$WORKTREE/.bazelversion" ]
}

# =============================================================================
# wt_check_adoption_conflicts
# =============================================================================

@test "wt_check_adoption_conflicts returns 1 when no conflicts" {
    export WT_METADATA_PATTERNS=".idea"
    # Empty vault, empty worktree
    mkdir -p "$BATS_TEST_TMPDIR/vault"
    export WT_IDEA_FILES_BASE="$BATS_TEST_TMPDIR/vault"

    run wt_check_adoption_conflicts "$WORKTREE"
    assert_failure  # return 1 = no conflicts
}

@test "wt_check_adoption_conflicts detects metadata from vault scan" {
    export WT_METADATA_PATTERNS=".idea"
    mkdir -p "$BATS_TEST_TMPDIR/vault/.idea"
    export WT_IDEA_FILES_BASE="$BATS_TEST_TMPDIR/vault"

    # Create matching .idea in worktree
    mkdir -p "$WORKTREE/.idea"

    run wt_check_adoption_conflicts "$WORKTREE"
    assert_success  # return 0 = conflicts found
    assert_output --partial ".idea"
}

@test "wt_check_adoption_conflicts detects nested metadata from vault" {
    export WT_METADATA_PATTERNS=".ijwb"
    mkdir -p "$BATS_TEST_TMPDIR/vault/subdir/.ijwb"
    export WT_IDEA_FILES_BASE="$BATS_TEST_TMPDIR/vault"

    # Create matching nested path in worktree
    mkdir -p "$WORKTREE/subdir/.ijwb"

    run wt_check_adoption_conflicts "$WORKTREE"
    assert_success
    assert_output --partial "subdir/.ijwb"
}

@test "wt_check_adoption_conflicts skips metadata not in vault" {
    export WT_METADATA_PATTERNS=".idea"
    # Vault exists but does NOT contain .idea
    mkdir -p "$BATS_TEST_TMPDIR/vault"
    export WT_IDEA_FILES_BASE="$BATS_TEST_TMPDIR/vault"

    # Worktree has .idea but vault doesn't → no conflict
    mkdir -p "$WORKTREE/.idea"

    run wt_check_adoption_conflicts "$WORKTREE"
    assert_failure  # no conflicts
}

@test "wt_check_adoption_conflicts ignores bazel output directories" {
    export WT_METADATA_PATTERNS=""
    export WT_IDEA_FILES_BASE=""

    mkdir -p "$WORKTREE/bazel-out"

    run wt_check_adoption_conflicts "$WORKTREE"
    assert_failure  # no conflicts
}
