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

# =============================================================================
# wt_is_adopted / wt_mark_adopted / wt_unmark_adopted
# =============================================================================

@test "wt_is_adopted returns false for fresh worktree" {
    run wt_is_adopted "$WORKTREE"
    assert_failure
}

@test "wt_mark_adopted creates marker file in correct git-dir location" {
    wt_mark_adopted "$WORKTREE"

    # Marker should be inside the worktree's git dir, NOT in the working tree
    local git_dir
    git_dir="$(git -C "$WORKTREE" rev-parse --git-dir)"
    if [[ "$git_dir" != /* ]]; then
        git_dir="$(cd "$WORKTREE" && cd "$git_dir" && pwd -P)"
    fi
    assert [ -f "$git_dir/wt/adopted" ]
    # In a worktree, .git is a file, not a directory — marker should NOT be at .git/wt/adopted
    assert [ ! -d "$WORKTREE/.git/wt" ]
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
    git_dir="$(git -C "$WORKTREE" rev-parse --git-dir)"
    if [[ "$git_dir" != /* ]]; then
        git_dir="$(cd "$WORKTREE" && cd "$git_dir" && pwd -P)"
    fi
    assert [ ! -d "$git_dir/wt" ]
}

@test "wt_mark_adopted is idempotent" {
    wt_mark_adopted "$WORKTREE"
    wt_mark_adopted "$WORKTREE"
    run wt_is_adopted "$WORKTREE"
    assert_success
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
# wt_install_bazel_symlinks
# =============================================================================

@test "wt_install_bazel_symlinks copies symlinks from main repo" {
    # Create fake bazel symlinks in main repo
    ln -s "/fake/bazel/output" "$REPO/bazel-out"
    ln -s "/fake/bazel/bin" "$REPO/bazel-bin"

    wt_install_bazel_symlinks "$WORKTREE"

    assert [ -L "$WORKTREE/bazel-out" ]
    assert [ -L "$WORKTREE/bazel-bin" ]
    local target
    target="$(readlink "$WORKTREE/bazel-out")"
    assert_equal "$target" "/fake/bazel/output"
}

@test "wt_install_bazel_symlinks skips missing symlinks" {
    # Main repo has no bazel symlinks
    wt_install_bazel_symlinks "$WORKTREE"

    assert [ ! -L "$WORKTREE/bazel-out" ]
    assert [ ! -L "$WORKTREE/bazel-bin" ]
}
