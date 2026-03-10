#!/usr/bin/env bats

# Integration tests for bin/wt-adopt

setup() {
    load '../test_helper/common'
    setup_test_env

    REPO=$(create_mock_repo_with_remote "$BATS_TEST_TMPDIR/repo")
    create_test_context "test" "$REPO"
    load_test_context "test"
    export WT_METADATA_PATTERNS=""
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Basic adoption
# =============================================================================

@test "adopt worktree by path argument" {
    create_branch "$REPO" "feature-a"
    local wt="$BATS_TEST_TMPDIR/wt/feature-a"
    create_worktree "$REPO" "$wt" "feature-a"
    wt="$(cd "$wt" && pwd -P)"

    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt"
    assert_success
    assert_is_adopted "$wt"
}

@test "adopt worktree by branch name" {
    create_branch "$REPO" "feature-b"
    create_worktree "$REPO" "$WT_WORKTREES_BASE/feature-b" "feature-b"

    run "$TEST_HOME/.wt/bin/wt-adopt" "feature-b"
    assert_success
    assert_is_adopted "$WT_WORKTREES_BASE/feature-b"
}

@test "adopt worktree at CWD" {
    create_branch "$REPO" "feature-c"
    local wt="$BATS_TEST_TMPDIR/wt/feature-c"
    create_worktree "$REPO" "$wt" "feature-c"
    wt="$(cd "$wt" && pwd -P)"

    run bash -c 'cd "'"$wt"'" && "'"$TEST_HOME/.wt/bin/wt-adopt"'"'
    assert_success
    assert_is_adopted "$wt"
}

# =============================================================================
# Idempotency
# =============================================================================

@test "adopt already-adopted worktree is noop (non-interactive)" {
    create_branch "$REPO" "feature-d"
    local wt="$BATS_TEST_TMPDIR/wt/feature-d"
    create_worktree "$REPO" "$wt" "feature-d"
    wt="$(cd "$wt" && pwd -P)"

    # Adopt first time
    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt"
    assert_success

    # Adopt again (stdin from /dev/null = non-interactive)
    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt" < /dev/null
    assert_success
    assert_output --partial "already adopted"
}

# =============================================================================
# Error cases
# =============================================================================

@test "adopt main repo fails with error" {
    run "$TEST_HOME/.wt/bin/wt-adopt" "$REPO"
    assert_failure
    assert_output --partial "Cannot adopt the main repository"
}

@test "adopt non-git-directory fails with error" {
    local tmpdir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$tmpdir"

    run "$TEST_HOME/.wt/bin/wt-adopt" "$tmpdir"
    assert_failure
}

@test "adopt with too many arguments fails" {
    run "$TEST_HOME/.wt/bin/wt-adopt" arg1 arg2
    assert_failure
}

@test "adopt --help shows usage" {
    run "$TEST_HOME/.wt/bin/wt-adopt" --help
    assert_success
    assert_output --partial "Adopt an existing worktree"
}

# =============================================================================
# Worktree location flexibility
# =============================================================================

@test "adopt worktree outside worktrees base directory" {
    create_branch "$REPO" "feature-outside"
    local wt="$BATS_TEST_TMPDIR/elsewhere/feature-outside"
    create_worktree "$REPO" "$wt" "feature-outside"
    wt="$(cd "$wt" && pwd -P)"

    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt"
    assert_success
    assert_is_adopted "$wt"
}

# =============================================================================
# Treatment: metadata import
# =============================================================================

@test "adopt imports metadata when patterns configured" {
    # Patch .conf for metadata patterns
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea"/' \
        "$TEST_HOME/.wt/repos/test.conf"

    # Create branch BEFORE metadata dirs so create_branch's "git add ." doesn't
    # commit .idea (which would remove it from main's working tree on checkout)
    create_branch "$REPO" "feature-meta"

    # Now create metadata dirs and export to vault
    create_metadata_dirs "$REPO" ".idea"
    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y "$REPO" "$WT_IDEA_FILES_BASE"
    assert_success

    # Create worktree and adopt
    local wt="$BATS_TEST_TMPDIR/wt/feature-meta"
    create_worktree "$REPO" "$wt" "feature-meta"
    wt="$(cd "$wt" && pwd -P)"

    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt"
    assert_success
    assert_is_adopted "$wt"
    # Metadata should be present in worktree
    assert [ -d "$wt/.idea" ]
}

# =============================================================================
# Treatment: Bazel symlinks
# =============================================================================

@test "adopt installs Bazel symlinks when present" {
    # Create fake bazel symlinks in main repo
    ln -s "/fake/bazel/output" "$REPO/bazel-out"
    ln -s "/fake/bazel/bin" "$REPO/bazel-bin"

    create_branch "$REPO" "feature-bazel"
    local wt="$BATS_TEST_TMPDIR/wt/feature-bazel"
    create_worktree "$REPO" "$wt" "feature-bazel"
    wt="$(cd "$wt" && pwd -P)"

    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt"
    assert_success
    assert [ -L "$wt/bazel-out" ]
    assert [ -L "$wt/bazel-bin" ]
}
