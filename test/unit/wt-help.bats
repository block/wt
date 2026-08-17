#!/usr/bin/env bats

# Unit tests for wt_show_help (lib/wt-help) and docs consistency

setup() {
    load '../test_helper/common'
    setup_test_env
    source "$TEST_HOME/.wt/lib/wt-common"
    source "$TEST_HOME/.wt/lib/wt-help"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# wt_show_help content
# =============================================================================

@test "wt help lists the adopt command" {
    run wt_show_help
    assert_success
    assert_output --partial "adopt [worktree|branch]"
}

@test "wt help documents add -b for creating a new branch" {
    run wt_show_help
    assert_success
    assert_output --partial "add -b <branch>"
    assert_output --partial "wt add -b feature/my-feature"
}

@test "wt help add example does not claim bare add creates a new branch" {
    run wt_show_help
    assert_success
    refute_output --partial "# Create worktree for new branch"
    assert_output --partial "# Create worktree for existing branch"
}

@test "wt help mentions the [unadopted] indicator" {
    run wt_show_help
    assert_success
    assert_output --partial "[unadopted]"
}

# =============================================================================
# Docs consistency (README, skill command reference)
# =============================================================================

@test "README documents wt adopt, [unadopted], and wt list --porcelain" {
    grep -q "wt adopt" "$PROJECT_ROOT/README.md"
    grep -q "unadopted" "$PROJECT_ROOT/README.md"
    grep -q -- "--porcelain" "$PROJECT_ROOT/README.md"
}

@test "README documents wt remove --on-dirty and drops the false -y skips-dirty claim" {
    grep -q -- "--on-dirty" "$PROJECT_ROOT/README.md"
    ! grep -q "Auto-remove merged without prompts" "$PROJECT_ROOT/README.md"
}

@test "README env-var defaults match wt-common fallbacks" {
    grep -q '~/.wt/repos/repo/base' "$PROJECT_ROOT/README.md"
    grep -q '~/.wt/repos/repo/worktrees' "$PROJECT_ROOT/README.md"
    grep -q '~/.wt/repos/repo/idea-files' "$PROJECT_ROOT/README.md"
    ! grep -q '~/Development/java-master` | ' "$PROJECT_ROOT/README.md"
}

@test "README documents WT_SKIP_PULL and WT_METADATA_PATTERNS" {
    grep -q "WT_SKIP_PULL" "$PROJECT_ROOT/README.md"
    grep -q "WT_METADATA_PATTERNS" "$PROJECT_ROOT/README.md"
}

@test "README directory structure lists real scripts and no lib/wt-completion" {
    ! grep -q "wt-completion" "$PROJECT_ROOT/README.md"
    grep -q "wt-adopt" "$PROJECT_ROOT/README.md"
    grep -q "wt-context" "$PROJECT_ROOT/README.md"
}

@test "command reference documents wt adopt and wt list --porcelain" {
    local ref="$PROJECT_ROOT/skills/references/command-reference.md"
    grep -q "^## wt adopt" "$ref"
    grep -q -- "--porcelain" "$ref"
    grep -q "unadopted" "$ref"
}
