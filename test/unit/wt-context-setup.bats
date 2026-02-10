#!/usr/bin/env bats

# Unit tests for lib/wt-context-setup

setup() {
    load '../test_helper/common'
    setup_test_env

    # Source the libraries under test
    source "$TEST_HOME/.wt/lib/wt-common"
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

