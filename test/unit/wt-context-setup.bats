#!/usr/bin/env bats

# Unit tests for lib/wt-context-setup

setup() {
    load '../test_helper/common'
    setup_test_env

    # Source the libraries under test
    source "$TEST_HOME/.wt/lib/wt-common"
    source "$TEST_HOME/.wt/lib/wt-adopt"
    source "$TEST_HOME/.wt/lib/wt-context"
    source "$TEST_HOME/.wt/lib/wt-context-setup"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Tests for WT_KNOWN_METADATA patterns
# =============================================================================

@test "WT_KNOWN_METADATA array is defined" {
    assert [ -n "${WT_KNOWN_METADATA[*]:-}" ]
}

@test "WT_KNOWN_METADATA has exactly 20 entries" {
    assert_equal "${#WT_KNOWN_METADATA[@]}" "20"
}

@test "WT_KNOWN_METADATA contains expected patterns" {
    for expected in ".idea" ".ijwb"; do
        local found=false
        for pattern in "${WT_KNOWN_METADATA[@]}"; do
            if [[ "$pattern" == "${expected}:"* ]]; then
                found=true
                break
            fi
        done
        assert [ "$found" = true ]
    done
}

# =============================================================================
# Tests for _wt_expand_path()
# =============================================================================

@test "_wt_expand_path expands ~ to HOME" {
    run _wt_expand_path "~/some/path"
    assert_success
    assert_output "$HOME/some/path"
}

@test "_wt_expand_path leaves absolute paths unchanged" {
    run _wt_expand_path "/absolute/path"
    assert_success
    assert_output "/absolute/path"
}

@test "_wt_expand_path leaves relative paths unchanged" {
    run _wt_expand_path "relative/path"
    assert_success
    assert_output "relative/path"
}

@test "_wt_expand_path handles path with only ~" {
    run _wt_expand_path "~"
    assert_success
    assert_output "$HOME"
}

@test "_wt_expand_path handles empty string" {
    run _wt_expand_path ""
    assert_success
    assert_output ""
}

# =============================================================================
# Tests for _wt_detect_default_branch()
# =============================================================================

@test "_wt_detect_default_branch returns main for repo with main branch" {
    local repo
    repo=$(create_mock_repo)

    run _wt_detect_default_branch "$repo"
    assert_success
    assert_output "main"
}

@test "_wt_detect_default_branch returns master for repo with master branch" {
    local repo="$BATS_TEST_TMPDIR/master_repo"
    mkdir -p "$repo"
    (
        cd "$repo"
        git init --initial-branch=master
        git config user.email "test@example.com"
        git config user.name "Test User"
        echo "initial" > file.txt
        git add file.txt
        git commit -m "Initial commit"
    ) >/dev/null 2>&1

    run _wt_detect_default_branch "$repo"
    assert_success
    assert_output "master"
}

@test "_wt_detect_default_branch handles repo with remote" {
    local repo
    repo=$(create_mock_repo_with_remote)

    run _wt_detect_default_branch "$repo"
    assert_success
    # Should return main (the default branch)
    assert_output "main"
}

# =============================================================================
# Tests for _wt_derive_paths()
# =============================================================================

@test "_wt_derive_paths sets expected variables" {
    local repo
    repo=$(create_mock_repo)

    # Call the function - sets WT_* global variables
    _wt_derive_paths "$repo" "my-context"

    # Check that variables are set with correct values
    # WT_MAIN_REPO_ROOT is derived to ~/.wt/repos/<context>/base
    [[ "$WT_MAIN_REPO_ROOT" == *"my-context/base"* ]] || fail "WT_MAIN_REPO_ROOT should contain 'my-context/base', got: $WT_MAIN_REPO_ROOT"
    [[ "$WT_WORKTREES_BASE" == *"my-context/worktrees"* ]] || fail "WT_WORKTREES_BASE should contain 'my-context/worktrees', got: $WT_WORKTREES_BASE"
    [[ "$WT_IDEA_FILES_BASE" == *"my-context/idea-files"* ]] || fail "WT_IDEA_FILES_BASE should contain 'my-context/idea-files', got: $WT_IDEA_FILES_BASE"
    # WT_ACTIVE_WORKTREE is set to the original repo path (where symlink will be)
    assert_equal "$WT_ACTIVE_WORKTREE" "$repo"
}

# =============================================================================
# Tests for _wt_detect_metadata_patterns()
# =============================================================================

@test "_wt_detect_metadata_patterns finds .idea directory" {
    local repo
    repo=$(create_mock_repo)
    create_metadata_dirs "$repo" ".idea"

    run _wt_detect_metadata_patterns "$repo"
    assert_success
    assert_output --partial ".idea"
}

@test "_wt_detect_metadata_patterns finds .ijwb directory" {
    local repo
    repo=$(create_mock_repo)
    create_metadata_dirs "$repo" ".ijwb"

    run _wt_detect_metadata_patterns "$repo"
    assert_success
    assert_output --partial ".ijwb"
}

@test "_wt_detect_metadata_patterns finds multiple directories" {
    local repo
    repo=$(create_mock_repo)
    create_metadata_dirs "$repo" ".idea" ".ijwb" ".vscode"

    run _wt_detect_metadata_patterns "$repo"
    assert_success
    assert_output --partial ".idea"
    assert_output --partial ".ijwb"
    assert_output --partial ".vscode"
}

@test "_wt_detect_metadata_patterns returns empty for repo without metadata" {
    local repo
    repo=$(create_mock_repo)

    run _wt_detect_metadata_patterns "$repo"
    assert_success
    # Should return empty output when no metadata directories exist
    assert_output ""
}

# =============================================================================
# Tests for _wt_get_pattern_description()
# =============================================================================

@test "_wt_get_pattern_description returns description for known pattern" {
    run _wt_get_pattern_description ".idea"
    assert_success
    # Should return the description from WT_KNOWN_METADATA
    assert_output "JetBrains IDEs (IntelliJ, WebStorm, PyCharm, etc.)"
}

@test "_wt_get_pattern_description returns pattern for unknown pattern" {
    run _wt_get_pattern_description ".unknown-pattern"
    assert_success
    # Should return the pattern itself as fallback for unknown patterns
    assert_output ".unknown-pattern"
}

# =============================================================================
# Tests for _wt_create_directories()
# =============================================================================

@test "_wt_create_directories creates worktrees directory" {
    # _wt_create_directories uses global WT_* variables
    export WT_WORKTREES_BASE="$BATS_TEST_TMPDIR/worktrees"
    export WT_IDEA_FILES_BASE="$BATS_TEST_TMPDIR/idea-files"
    export WT_ACTIVE_WORKTREE="$BATS_TEST_TMPDIR/active/symlink"

    _wt_create_directories

    assert [ -d "$WT_WORKTREES_BASE" ]
    assert [ -d "$WT_IDEA_FILES_BASE" ]
}

@test "_wt_create_directories is idempotent" {
    export WT_WORKTREES_BASE="$BATS_TEST_TMPDIR/worktrees"
    export WT_IDEA_FILES_BASE="$BATS_TEST_TMPDIR/idea-files"
    export WT_ACTIVE_WORKTREE="$BATS_TEST_TMPDIR/active/symlink"

    # Create once
    _wt_create_directories

    # Create again (should not fail)
    run _wt_create_directories
    assert_success
}

# =============================================================================
# Tests for _wt_update_worktree_pointers()
# =============================================================================

@test "_wt_update_worktree_pointers updates .git files after repo move" {
    # Create a repo with a worktree
    local repo
    repo=$(create_mock_repo "$BATS_TEST_TMPDIR/original-repo")
    create_branch "$repo" "feat-branch"
    local wt_path="$BATS_TEST_TMPDIR/wt-feat"
    create_worktree "$repo" "$wt_path" "feat-branch"
    wt_path="$(cd "$wt_path" && pwd -P)"

    # Verify initial .git pointer uses old path
    local dot_git_content
    dot_git_content="$(cat "$wt_path/.git")"
    assert_equal "$dot_git_content" "gitdir: ${repo}/.git/worktrees/wt-feat"

    # Simulate migration: move repo to new location
    local new_repo="$BATS_TEST_TMPDIR/new-location"
    mv "$repo" "$new_repo"

    # Run the pointer update
    run _wt_update_worktree_pointers "$new_repo"
    assert_success

    # .git file should now point to the new location
    dot_git_content="$(cat "$wt_path/.git")"
    assert_equal "$dot_git_content" "gitdir: ${new_repo}/.git/worktrees/wt-feat"

    # Verify git operations work
    run git -C "$wt_path" status
    assert_success
}

@test "_wt_update_worktree_pointers is no-op without worktrees" {
    local repo
    repo=$(create_mock_repo "$BATS_TEST_TMPDIR/no-wt-repo")

    # Should succeed silently when there are no worktrees
    run _wt_update_worktree_pointers "$repo"
    assert_success
}

@test "_wt_update_worktree_pointers handles multiple worktrees" {
    local repo
    repo=$(create_mock_repo "$BATS_TEST_TMPDIR/multi-wt-repo")

    create_branch "$repo" "branch-a"
    create_branch "$repo" "branch-b"
    local wt_a="$BATS_TEST_TMPDIR/wt-a"
    local wt_b="$BATS_TEST_TMPDIR/wt-b"
    create_worktree "$repo" "$wt_a" "branch-a"
    create_worktree "$repo" "$wt_b" "branch-b"
    wt_a="$(cd "$wt_a" && pwd -P)"
    wt_b="$(cd "$wt_b" && pwd -P)"

    # Move repo
    local new_repo="$BATS_TEST_TMPDIR/moved-multi"
    mv "$repo" "$new_repo"

    run _wt_update_worktree_pointers "$new_repo"
    assert_success

    # Both worktrees should be updated
    local content_a content_b
    content_a="$(cat "$wt_a/.git")"
    content_b="$(cat "$wt_b/.git")"
    assert_equal "$content_a" "gitdir: ${new_repo}/.git/worktrees/wt-a"
    assert_equal "$content_b" "gitdir: ${new_repo}/.git/worktrees/wt-b"
}

@test "_wt_update_worktree_pointers unadopted mode skips adopted worktrees" {
    local repo
    repo=$(create_mock_repo "$BATS_TEST_TMPDIR/adopt-skip-repo")

    create_branch "$repo" "branch-adopted"
    create_branch "$repo" "branch-unadopted"
    local wt_adopted="$BATS_TEST_TMPDIR/wt-adopted"
    local wt_unadopted="$BATS_TEST_TMPDIR/wt-unadopted"
    create_worktree "$repo" "$wt_adopted" "branch-adopted"
    create_worktree "$repo" "$wt_unadopted" "branch-unadopted"
    wt_adopted="$(cd "$wt_adopted" && pwd -P)"
    wt_unadopted="$(cd "$wt_unadopted" && pwd -P)"

    # Mark one worktree as adopted
    wt_mark_adopted "$wt_adopted"

    # Move repo
    local new_repo="$BATS_TEST_TMPDIR/moved-adopt-skip"
    mv "$repo" "$new_repo"

    run _wt_update_worktree_pointers "$new_repo" "unadopted"
    assert_success

    # Unadopted worktree should be updated
    local content_unadopted
    content_unadopted="$(cat "$wt_unadopted/.git")"
    assert_equal "$content_unadopted" "gitdir: ${new_repo}/.git/worktrees/wt-unadopted"

    # Adopted worktree should NOT be updated (still has old path)
    local content_adopted
    content_adopted="$(cat "$wt_adopted/.git")"
    assert_equal "$content_adopted" "gitdir: ${repo}/.git/worktrees/wt-adopted"
}

@test "_wt_update_worktree_pointers adopted mode only updates worktrees adopted by context" {
    local repo
    repo=$(create_mock_repo "$BATS_TEST_TMPDIR/adopt-ctx-repo")

    create_branch "$repo" "branch-ctx-a"
    create_branch "$repo" "branch-ctx-b"
    create_branch "$repo" "branch-unadopted"
    local wt_ctx_a="$BATS_TEST_TMPDIR/wt-ctx-a"
    local wt_ctx_b="$BATS_TEST_TMPDIR/wt-ctx-b"
    local wt_unadopted="$BATS_TEST_TMPDIR/wt-ctx-unadopted"
    create_worktree "$repo" "$wt_ctx_a" "branch-ctx-a"
    create_worktree "$repo" "$wt_ctx_b" "branch-ctx-b"
    create_worktree "$repo" "$wt_unadopted" "branch-unadopted"
    wt_ctx_a="$(cd "$wt_ctx_a" && pwd -P)"
    wt_ctx_b="$(cd "$wt_ctx_b" && pwd -P)"
    wt_unadopted="$(cd "$wt_unadopted" && pwd -P)"

    # Mark worktrees as adopted by different contexts
    export WT_CONTEXT_NAME="ctx-a"
    wt_mark_adopted "$wt_ctx_a"
    export WT_CONTEXT_NAME="ctx-b"
    wt_mark_adopted "$wt_ctx_b"
    unset WT_CONTEXT_NAME

    # Move repo
    local new_repo="$BATS_TEST_TMPDIR/moved-adopt-ctx"
    mv "$repo" "$new_repo"

    run _wt_update_worktree_pointers "$new_repo" "adopted" "ctx-a"
    assert_success

    # Only the worktree adopted by ctx-a should be updated
    local content_a
    content_a="$(cat "$wt_ctx_a/.git")"
    assert_equal "$content_a" "gitdir: ${new_repo}/.git/worktrees/wt-ctx-a"

    # Worktree adopted by ctx-b should NOT be updated
    local content_b
    content_b="$(cat "$wt_ctx_b/.git")"
    assert_equal "$content_b" "gitdir: ${repo}/.git/worktrees/wt-ctx-b"

    # Unadopted worktree should NOT be updated
    local content_unadopted
    content_unadopted="$(cat "$wt_unadopted/.git")"
    assert_equal "$content_unadopted" "gitdir: ${repo}/.git/worktrees/wt-ctx-unadopted"
}

@test "_wt_update_worktree_pointers all mode updates everything" {
    local repo
    repo=$(create_mock_repo "$BATS_TEST_TMPDIR/all-mode-repo")

    create_branch "$repo" "branch-adopted"
    create_branch "$repo" "branch-unadopted"
    local wt_adopted="$BATS_TEST_TMPDIR/wt-all-adopted"
    local wt_unadopted="$BATS_TEST_TMPDIR/wt-all-unadopted"
    create_worktree "$repo" "$wt_adopted" "branch-adopted"
    create_worktree "$repo" "$wt_unadopted" "branch-unadopted"
    wt_adopted="$(cd "$wt_adopted" && pwd -P)"
    wt_unadopted="$(cd "$wt_unadopted" && pwd -P)"

    wt_mark_adopted "$wt_adopted"

    # Move repo
    local new_repo="$BATS_TEST_TMPDIR/moved-all-mode"
    mv "$repo" "$new_repo"

    run _wt_update_worktree_pointers "$new_repo" "all"
    assert_success

    # Both should be updated
    local content_adopted content_unadopted
    content_adopted="$(cat "$wt_adopted/.git")"
    content_unadopted="$(cat "$wt_unadopted/.git")"
    assert_equal "$content_adopted" "gitdir: ${new_repo}/.git/worktrees/wt-all-adopted"
    assert_equal "$content_unadopted" "gitdir: ${new_repo}/.git/worktrees/wt-all-unadopted"
}

