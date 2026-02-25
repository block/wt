#!/usr/bin/env bats

# Unit tests for lib/wt-common

setup() {
    load '../test_helper/common'
    setup_test_env

    # Source the library under test
    source "$TEST_HOME/.wt/lib/wt-common"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Tests for echoerr()
# =============================================================================

@test "echoerr outputs message to stderr" {
    run --separate-stderr echoerr "test message"
    assert_success
    assert_output ""  # stdout should be empty
    assert_equal "$stderr" "test message"
}

@test "echoerr handles empty message" {
    run --separate-stderr echoerr ""
    assert_success
    assert_output ""
    assert_equal "$stderr" ""
}

# =============================================================================
# Tests for error(), success(), warn(), info()
# =============================================================================

@test "error() outputs error message to stderr" {
    run --separate-stderr error "something went wrong"
    assert_success
    assert_output ""  # stdout should be empty
    [[ "$stderr" == *"something went wrong"* ]] || fail "stderr should contain message, got: $stderr"
    [[ "$stderr" == *"Error:"* ]] || fail "stderr should contain 'Error:' prefix, got: $stderr"
}

@test "success() outputs success message" {
    run success "operation completed"
    assert_success
    assert_output --partial "operation completed"
}

@test "warn() outputs warning message to stderr" {
    run --separate-stderr warn "be careful"
    assert_success
    assert_output ""  # stdout should be empty
    [[ "$stderr" == *"be careful"* ]] || fail "stderr should contain message, got: $stderr"
    [[ "$stderr" == *"⚠"* ]] || fail "stderr should contain warning symbol, got: $stderr"
}

@test "info() outputs info message" {
    run info "here is some info"
    assert_success
    assert_output --partial "here is some info"
}

# =============================================================================
# Tests for wt_source()
# =============================================================================

@test "wt_source loads library from LIB_DIR" {
    # Create a test library file
    echo 'TEST_LIB_LOADED=true' > "$TEST_HOME/.wt/lib/test-lib"

    export LIB_DIR="$TEST_HOME/.wt/lib"
    wt_source "test-lib"

    assert_equal "$TEST_LIB_LOADED" "true"
}

@test "wt_source fails for non-existent library" {
    export LIB_DIR="$TEST_HOME/.wt/lib"
    run wt_source "nonexistent-lib"
    assert_failure
}

# =============================================================================
# Tests for wt_has_uncommitted_changes()
# =============================================================================

@test "wt_has_uncommitted_changes returns true for repo with unstaged changes" {
    local repo
    repo=$(create_mock_repo)
    make_repo_dirty "$repo"

    run wt_has_uncommitted_changes "$repo"
    assert_success
}

@test "wt_has_uncommitted_changes returns true for repo with staged changes" {
    local repo
    repo=$(create_mock_repo)
    make_repo_dirty "$repo"
    stage_changes "$repo"

    run wt_has_uncommitted_changes "$repo"
    assert_success
}

@test "wt_has_uncommitted_changes returns false for clean repo" {
    local repo
    repo=$(create_mock_repo)

    run wt_has_uncommitted_changes "$repo"
    assert_failure
}

# =============================================================================
# Tests for wt_uncommitted_summary()
# =============================================================================

@test "wt_uncommitted_summary returns empty for clean repo" {
    local repo
    repo=$(create_mock_repo)

    run wt_uncommitted_summary "$repo"
    assert_success
    assert_output ""
}

@test "wt_uncommitted_summary counts unstaged and untracked changes" {
    local repo
    repo=$(create_mock_repo)
    echo "change1" >> "$repo/file.txt"
    echo "new file" > "$repo/newfile.txt"

    run wt_uncommitted_summary "$repo"
    assert_success
    # Should show "N modified N untracked" format
    assert_output --partial "modified"
    assert_output --partial "untracked"
}

@test "wt_uncommitted_summary counts staged changes" {
    local repo
    repo=$(create_mock_repo)
    echo "change1" >> "$repo/file.txt"
    stage_changes "$repo"

    run wt_uncommitted_summary "$repo"
    assert_success
    assert_output --partial "staged"
}

# =============================================================================
# Tests for wt_get_linked_worktree()
# =============================================================================

@test "wt_get_linked_worktree returns empty when WT_ACTIVE_WORKTREE not set" {
    unset WT_ACTIVE_WORKTREE

    run wt_get_linked_worktree
    assert_success
    assert_output ""
}

@test "wt_get_linked_worktree returns empty when symlink doesn't exist" {
    export WT_ACTIVE_WORKTREE="$TEST_HOME/nonexistent"

    run wt_get_linked_worktree
    assert_success
    assert_output ""
}

@test "wt_get_linked_worktree returns empty when path is not a symlink" {
    mkdir -p "$TEST_HOME/not-a-symlink"
    export WT_ACTIVE_WORKTREE="$TEST_HOME/not-a-symlink"

    run wt_get_linked_worktree
    assert_success
    assert_output ""
}

@test "wt_get_linked_worktree resolves symlink target" {
    local repo
    repo=$(create_mock_repo)
    ln -s "$repo" "$TEST_HOME/active"
    export WT_ACTIVE_WORKTREE="$TEST_HOME/active"

    run wt_get_linked_worktree
    assert_success
    # wt_get_linked_worktree uses pwd -P to return physical path
    # so we need to compare against normalized path (handles macOS /var -> /private/var)
    local expected_physical_path
    expected_physical_path="$(cd "$repo" && pwd -P)"
    assert_output "$expected_physical_path"
}

# =============================================================================
# Tests for wt_format_worktree()
# =============================================================================

@test "wt_format_worktree shows [main] for main repo" {
    local repo
    repo=$(create_mock_repo)

    # wt_format_worktree args: <worktree_path> [main_repo_abs] [linked_worktree] [verbose]
    run wt_format_worktree "$repo" "$repo" ""
    assert_success
    assert_output --partial "[main]"
}

@test "wt_format_worktree shows [linked] for active worktree" {
    local repo
    repo=$(create_mock_repo)
    local wt_path="$BATS_TEST_TMPDIR/worktree1"
    create_branch "$repo" "feature-1"
    create_worktree "$repo" "$wt_path" "feature-1"

    # wt_format_worktree args: <worktree_path> [main_repo_abs] [linked_worktree] [verbose]
    run wt_format_worktree "$wt_path" "$repo" "$wt_path"
    assert_success
    assert_output --partial "[linked]"
}

@test "wt_format_worktree shows branch name" {
    local repo
    repo=$(create_mock_repo)

    run wt_format_worktree "$repo" "" ""
    assert_success
    # Should show (main) as that's the branch
    assert_output --partial "(main)"
}

# =============================================================================
# Tests for prompt_confirm()
# =============================================================================

@test "prompt_confirm accepts y/Y and rejects n/N/empty" {
    # Accepts lowercase and uppercase 'y'
    run bash -c 'source "'"$TEST_HOME/.wt/lib/wt-common"'" && echo "y" | prompt_confirm "Continue?"'
    assert_success
    run bash -c 'source "'"$TEST_HOME/.wt/lib/wt-common"'" && echo "Y" | prompt_confirm "Continue?"'
    assert_success

    # Rejects lowercase and uppercase 'n'
    run bash -c 'source "'"$TEST_HOME/.wt/lib/wt-common"'" && echo "n" | prompt_confirm "Continue?"'
    assert_failure
    run bash -c 'source "'"$TEST_HOME/.wt/lib/wt-common"'" && echo "N" | prompt_confirm "Continue?"'
    assert_failure

    # Rejects empty input (no default)
    run bash -c 'source "'"$TEST_HOME/.wt/lib/wt-common"'" && echo "" | prompt_confirm "Continue?"'
    assert_failure
}

# =============================================================================
# Tests for wt_read_git_config()
# =============================================================================

# --- Core behavior ---

@test "wt_read_git_config reads all required keys from local git config" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"

    # Clear variables that were set when wt-common was sourced in setup()
    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    wt_read_git_config

    # mainRepoRoot is auto-derived from git-common-dir
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
    assert_equal "$WT_WORKTREES_BASE" "/worktrees"
    assert_equal "$WT_IDEA_FILES_BASE" "/idea"
    assert_equal "$WT_BASE_BRANCH" "develop"
}

@test "wt_read_git_config does nothing outside a git repo" {
    local non_git_dir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$non_git_dir"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$non_git_dir"
    wt_read_git_config

    assert_equal "${WT_MAIN_REPO_ROOT:-}" ""
    assert_equal "${WT_WORKTREES_BASE:-}" ""
    assert_equal "${WT_IDEA_FILES_BASE:-}" ""
    assert_equal "${WT_BASE_BRANCH:-}" ""
}

@test "wt_read_git_config does nothing when no wt keys are set" {
    local repo
    repo=$(create_mock_repo)

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    run --separate-stderr wt_read_git_config

    assert_success
    assert_equal "$stderr" ""
    assert_equal "${WT_MAIN_REPO_ROOT:-}" ""
}

@test "wt_read_git_config supersedes env variables" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "from-git"

    export WT_BASE_BRANCH="from-env"
    export WT_MAIN_REPO_ROOT="/env-main"
    export WT_WORKTREES_BASE="/env-wt"
    export WT_IDEA_FILES_BASE="/env-idea"

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_BASE_BRANCH" "from-git"
    # mainRepoRoot auto-derived, supersedes env
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
}

# --- Validation ---

@test "wt_read_git_config warns on partial config and applies nothing" {
    local repo
    repo=$(create_mock_repo)

    # Set only one of three required keys
    set_wt_git_config "$repo" "wt.baseBranch" "develop"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    run --separate-stderr bash -c '
        source "'"$TEST_HOME/.wt/lib/wt-common"'"
        wt_read_git_config
        echo "WT_BASE_BRANCH=${WT_BASE_BRANCH:-UNSET}"
        echo "WT_MAIN_REPO_ROOT=${WT_MAIN_REPO_ROOT:-UNSET}"
    '

    assert_success
    [[ "$stderr" == *"incomplete git local config"* ]] || fail "Expected partial config warning, got: $stderr"
    [[ "$stderr" == *"wt.worktreesBase"* ]] || fail "Expected missing key name in warning, got: $stderr"
}

@test "wt_read_git_config warns listing specific missing keys" {
    local repo
    repo=$(create_mock_repo)

    # Set 1 of 3 required keys (baseBranch present, worktreesBase + ideaFilesBase missing)
    set_wt_git_config "$repo" "wt.baseBranch" "develop"

    cd "$repo"
    run --separate-stderr bash -c '
        source "'"$TEST_HOME/.wt/lib/wt-common"'"
        wt_read_git_config
    '

    assert_success
    [[ "$stderr" == *"wt.worktreesBase"* ]] || fail "Expected wt.worktreesBase in missing list, got: $stderr"
    [[ "$stderr" == *"wt.ideaFilesBase"* ]] || fail "Expected wt.ideaFilesBase in missing list, got: $stderr"
    # These should NOT be listed as missing
    [[ "$stderr" != *"wt.mainRepoRoot"* ]] || fail "wt.mainRepoRoot should not be listed as missing (it is auto-derived)"
    [[ "$stderr" != *"wt.baseBranch"* ]] || fail "wt.baseBranch should not be listed as missing"
}

@test "wt_read_git_config requires all three core keys" {
    local repo
    repo=$(create_mock_repo)

    # Set 2 of 3 required keys (missing ideaFilesBase)
    set_wt_git_config "$repo" \
        "wt.worktreesBase" "/worktrees" \
        "wt.baseBranch" "develop"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    run --separate-stderr bash -c '
        source "'"$TEST_HOME/.wt/lib/wt-common"'"
        wt_read_git_config
        echo "MAIN=${WT_MAIN_REPO_ROOT:-UNSET}"
    '

    assert_success
    [[ "$stderr" == *"incomplete git local config"* ]] || fail "Expected partial config warning, got: $stderr"
    [[ "$stderr" == *"wt.ideaFilesBase"* ]] || fail "Expected wt.ideaFilesBase in missing list, got: $stderr"
}

# --- Optional keys ---

@test "wt_read_git_config applies optional keys when required keys are present" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"
    set_wt_git_config "$repo" \
        "wt.activeWorktree" "/active/wt" \
        "wt.metadataPatterns" ".idea .ijwb .vscode"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH
    unset WT_ACTIVE_WORKTREE WT_METADATA_PATTERNS

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_ACTIVE_WORKTREE" "/active/wt"
    assert_equal "$WT_METADATA_PATTERNS" ".idea .ijwb .vscode"
}

@test "wt_read_git_config handles values with spaces" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"
    set_wt_git_config "$repo" "wt.metadataPatterns" ".idea .ijwb .vscode"

    unset WT_METADATA_PATTERNS

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_METADATA_PATTERNS" ".idea .ijwb .vscode"
}

# --- Case insensitivity ---

@test "wt_read_git_config is case-insensitive for key names" {
    local repo
    repo=$(create_mock_repo)

    # git config normalizes section names to lowercase but preserves
    # subsection case. For our flat wt.* keys, git stores them lowercase.
    # We test by writing directly to .git/config with mixed case section.
    git -C "$repo" config --local "wt.WorktreesBase" "/worktrees"
    git -C "$repo" config --local "wt.ideafilesbase" "/idea"
    git -C "$repo" config --local "wt.BaseBranch" "develop"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_WORKTREES_BASE" "/worktrees"
    assert_equal "$WT_IDEA_FILES_BASE" "/idea"
    assert_equal "$WT_BASE_BRANCH" "develop"
}

# --- Worktree support ---

@test "wt_read_git_config reads config from worktree" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"

    # Create a worktree
    create_branch "$repo" "feature-wt"
    local wt_path="$BATS_TEST_TMPDIR/wt-feature"
    create_worktree "$repo" "$wt_path" "feature-wt"

    unset WT_MAIN_REPO_ROOT WT_WORKTREES_BASE WT_IDEA_FILES_BASE WT_BASE_BRANCH

    cd "$wt_path"
    wt_read_git_config

    # mainRepoRoot auto-derived via git-common-dir resolves to the main repo,
    # even when CWD is inside a worktree
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
    assert_equal "$WT_WORKTREES_BASE" "/worktrees"
    assert_equal "$WT_IDEA_FILES_BASE" "/idea"
    assert_equal "$WT_BASE_BRANCH" "develop"
}

# --- Precedence integration tests ---

@test "git local config takes precedence over .conf file" {
    local repo
    repo=$(create_mock_repo)

    # Set up .conf file via context system
    create_test_context "myctx" "$repo"

    # Set git config with different values
    set_wt_git_config_required "$repo" "/git-wt" "/git-idea" "git-branch"

    # Clear all variables, then load in the correct order
    wt_clear_config_vars

    cd "$repo"
    wt_read_git_config
    wt_read_config "$TEST_HOME/.wt/current" 2>/dev/null || true

    # Git config should win — mainRepoRoot auto-derived, rest from git config
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
    assert_equal "$WT_WORKTREES_BASE" "/git-wt"
    assert_equal "$WT_IDEA_FILES_BASE" "/git-idea"
    assert_equal "$WT_BASE_BRANCH" "git-branch"
}

@test "conf file fills gaps not covered by git config" {
    local repo
    repo=$(create_mock_repo)

    # Set up .conf file with all values
    create_test_context "myctx" "$repo"

    # Set all 3 required git config keys but no optional keys
    set_wt_git_config_required "$repo" "/git-wt" "/git-idea" "git-branch"

    # Clear all variables, then load in order
    wt_clear_config_vars

    cd "$repo"
    wt_read_git_config
    wt_read_config "$TEST_HOME/.wt/current" 2>/dev/null || true

    # Git config wins for required keys
    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
    assert_equal "$WT_BASE_BRANCH" "git-branch"

    # .conf file fills optional keys (WT_ACTIVE_WORKTREE is set in the .conf)
    local norm_test_home
    norm_test_home="$(cd "$TEST_HOME" && pwd -P)"
    assert_equal "$WT_ACTIVE_WORKTREE" "$norm_test_home/active"
}

@test "partial git config falls back to .conf entirely" {
    local repo
    repo=$(create_mock_repo)

    # Set up .conf file with all values
    create_test_context "myctx" "$repo"

    # Set only 1 of 3 required git config keys (incomplete)
    set_wt_git_config "$repo" "wt.baseBranch" "git-branch"

    # Clear all variables, then load in order
    wt_clear_config_vars

    cd "$repo"
    wt_read_git_config 2>/dev/null
    wt_read_config "$TEST_HOME/.wt/current" 2>/dev/null || true

    # Since git config was incomplete, .conf values should be used
    local norm_repo_path
    norm_repo_path="$(cd "$repo" && pwd -P)"
    assert_equal "$WT_MAIN_REPO_ROOT" "$norm_repo_path"
    assert_equal "$WT_BASE_BRANCH" "main"
}

# --- Auto-derivation and explicit override of mainRepoRoot ---

@test "wt_read_git_config auto-derives mainRepoRoot from git-common-dir" {
    local repo
    repo=$(create_mock_repo)

    # Only set the 3 required keys, no wt.mainRepoRoot
    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"

    unset WT_MAIN_REPO_ROOT

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
}

@test "wt_read_git_config explicit mainRepoRoot overrides auto-derivation" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"
    set_wt_git_config "$repo" "wt.mainRepoRoot" "/custom/repo/root"

    unset WT_MAIN_REPO_ROOT

    cd "$repo"
    wt_read_git_config

    assert_equal "$WT_MAIN_REPO_ROOT" "/custom/repo/root"
}

@test "wt_read_git_config auto-derives mainRepoRoot correctly from worktree" {
    local repo
    repo=$(create_mock_repo)

    set_wt_git_config_required "$repo" "/worktrees" "/idea" "develop"

    create_branch "$repo" "feature-derive"
    local wt_path="$BATS_TEST_TMPDIR/wt-derive"
    create_worktree "$repo" "$wt_path" "feature-derive"

    unset WT_MAIN_REPO_ROOT

    # CWD is the worktree, but mainRepoRoot should resolve to the main repo
    cd "$wt_path"
    wt_read_git_config

    assert_equal "$WT_MAIN_REPO_ROOT" "$repo"
}

