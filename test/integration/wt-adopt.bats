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
    assert_output --partial "--redo"
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

# =============================================================================
# Conflict safety
# =============================================================================

@test "adopt aborts non-interactive when worktree has existing metadata" {
    # Set up patterns and vault
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea"/' \
        "$TEST_HOME/.wt/repos/test.conf"
    create_branch "$REPO" "conflict-abort"
    create_metadata_dirs "$REPO" ".idea"
    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y "$REPO" "$WT_IDEA_FILES_BASE"
    assert_success

    # Create worktree and add pre-existing .idea with known content
    local wt="$BATS_TEST_TMPDIR/wt/conflict-abort"
    create_worktree "$REPO" "$wt" "conflict-abort"
    wt="$(cd "$wt" && pwd -P)"
    mkdir -p "$wt/.idea"
    echo "original-content" > "$wt/.idea/my-config.xml"

    # Non-interactive: should abort
    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt" < /dev/null
    assert_failure
    assert_output --partial "existing files"

    # Original .idea should be preserved
    assert [ -f "$wt/.idea/my-config.xml" ]
    assert_equal "$(cat "$wt/.idea/my-config.xml")" "original-content"

    # Should NOT be adopted
    refute_is_adopted "$wt"
}

@test "adopt with --force overwrites existing metadata" {
    # Set up patterns and vault
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea"/' \
        "$TEST_HOME/.wt/repos/test.conf"
    create_branch "$REPO" "conflict-force"
    create_metadata_dirs "$REPO" ".idea"
    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y "$REPO" "$WT_IDEA_FILES_BASE"
    assert_success

    # Create worktree and add pre-existing .idea
    local wt="$BATS_TEST_TMPDIR/wt/conflict-force"
    create_worktree "$REPO" "$wt" "conflict-force"
    wt="$(cd "$wt" && pwd -P)"
    mkdir -p "$wt/.idea"
    echo "will-be-replaced" > "$wt/.idea/old.xml"

    # --force should succeed
    run "$TEST_HOME/.wt/bin/wt-adopt" --force "$wt"
    assert_success
    assert_is_adopted "$wt"
    # .idea should be replaced with vault contents
    assert [ -d "$wt/.idea" ]
}

@test "adopt proceeds when no conflicts exist" {
    # No metadata patterns, no vault content — clean worktree
    create_branch "$REPO" "no-conflict"
    local wt="$BATS_TEST_TMPDIR/wt/no-conflict"
    create_worktree "$REPO" "$wt" "no-conflict"
    wt="$(cd "$wt" && pwd -P)"

    # Non-interactive should succeed (no conflicts)
    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt" < /dev/null
    assert_success
    assert_is_adopted "$wt"
}

# =============================================================================
# --redo flag
# =============================================================================

@test "--redo re-runs treatment on adopted worktree" {
    create_branch "$REPO" "redo-test"
    local wt="$BATS_TEST_TMPDIR/wt/redo-test"
    create_worktree "$REPO" "$wt" "redo-test"
    wt="$(cd "$wt" && pwd -P)"

    # First adopt
    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt"
    assert_success
    assert_is_adopted "$wt"

    # Re-run with --redo --force
    run "$TEST_HOME/.wt/bin/wt-adopt" --redo --force "$wt"
    assert_success
    assert_output --partial "Re-running adoption treatment"
    assert_is_adopted "$wt"
}

@test "--redo on unadopted worktree just adopts" {
    create_branch "$REPO" "redo-unadopted"
    local wt="$BATS_TEST_TMPDIR/wt/redo-unadopted"
    create_worktree "$REPO" "$wt" "redo-unadopted"
    wt="$(cd "$wt" && pwd -P)"

    run "$TEST_HOME/.wt/bin/wt-adopt" --redo "$wt"
    assert_success
    assert_is_adopted "$wt"
}

@test "already adopted without --redo shows info and hint" {
    create_branch "$REPO" "hint-test"
    local wt="$BATS_TEST_TMPDIR/wt/hint-test"
    create_worktree "$REPO" "$wt" "hint-test"
    wt="$(cd "$wt" && pwd -P)"

    # First adopt
    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt"
    assert_success

    # Run again without --redo
    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt"
    assert_success
    assert_output --partial "already adopted"
    assert_output --partial "--redo"
}

@test "--redo without --force still checks conflicts on re-run" {
    # Set up patterns and vault
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea"/' \
        "$TEST_HOME/.wt/repos/test.conf"
    create_branch "$REPO" "redo-conflict"
    create_metadata_dirs "$REPO" ".idea"
    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y "$REPO" "$WT_IDEA_FILES_BASE"
    assert_success

    # Create worktree, adopt with --force (first time)
    local wt="$BATS_TEST_TMPDIR/wt/redo-conflict"
    create_worktree "$REPO" "$wt" "redo-conflict"
    wt="$(cd "$wt" && pwd -P)"
    run "$TEST_HOME/.wt/bin/wt-adopt" --force "$wt"
    assert_success
    assert_is_adopted "$wt"

    # Now .idea exists in worktree (from vault import).
    # --redo without --force in non-interactive → should abort due to conflict
    run "$TEST_HOME/.wt/bin/wt-adopt" --redo "$wt" < /dev/null
    assert_failure
    assert_output --partial "existing files"
}

@test "--force on already adopted re-runs treatment" {
    create_branch "$REPO" "force-redo"
    local wt="$BATS_TEST_TMPDIR/wt/force-redo"
    create_worktree "$REPO" "$wt" "force-redo"
    wt="$(cd "$wt" && pwd -P)"

    # First adopt
    run "$TEST_HOME/.wt/bin/wt-adopt" "$wt"
    assert_success

    # --force alone on already-adopted should also re-run
    run "$TEST_HOME/.wt/bin/wt-adopt" --force "$wt"
    assert_success
    assert_output --partial "Re-running adoption treatment"
}

# =============================================================================
# Keep existing files option
# =============================================================================

@test "adopt keep preserves existing metadata but installs bazel symlinks" {
    # Set up patterns and vault
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea"/' \
        "$TEST_HOME/.wt/repos/test.conf"
    create_branch "$REPO" "keep-test"
    create_metadata_dirs "$REPO" ".idea"
    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y "$REPO" "$WT_IDEA_FILES_BASE"
    assert_success

    # Create fake bazel symlinks in main repo
    ln -s "/fake/bazel/output" "$REPO/bazel-out"

    # Create worktree with pre-existing .idea containing known content
    local wt="$BATS_TEST_TMPDIR/wt/keep-test"
    create_worktree "$REPO" "$wt" "keep-test"
    wt="$(cd "$wt" && pwd -P)"
    mkdir -p "$wt/.idea"
    echo "my-precious-config" > "$wt/.idea/workspace.xml"

    # Use expect(1) to simulate a TTY so the interactive prompt appears.
    # This sends "k" when the O/K/A prompt is shown.
    run expect -c '
        spawn "'"$TEST_HOME/.wt/bin/wt-adopt"'" "'"$wt"'"
        expect "Choose"
        send "k\r"
        expect eof
        catch wait result
        exit [lindex $result 3]
    '
    assert_success
    assert_is_adopted "$wt"

    # .idea should have the ORIGINAL content (not vault)
    assert [ -f "$wt/.idea/workspace.xml" ]
    assert_equal "$(cat "$wt/.idea/workspace.xml")" "my-precious-config"

    # Bazel symlinks should still be installed
    assert [ -L "$wt/bazel-out" ]
}
