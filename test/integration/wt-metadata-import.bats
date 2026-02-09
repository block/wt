#!/usr/bin/env bats

# Integration tests for bin/wt-metadata-import

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create mock repo
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")

    # Create test context and load its WT_* variables
    create_test_context "test" "$REPO"
    load_test_context "test"

    # Update .conf directly — scripts re-source wt-common on execution
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea"/' "$TEST_HOME/.wt/repos/test.conf"

    # Create vault with metadata
    mkdir -p "$WT_IDEA_FILES_BASE/.idea"
    echo "config content" > "$WT_IDEA_FILES_BASE/.idea/config.xml"
    echo "workspace" > "$WT_IDEA_FILES_BASE/.idea/workspace.xml"

    # Create worktree for import testing
    create_branch "$REPO" "feature-import"
    WORKTREE="$WT_WORKTREES_BASE/feature-import"
    create_worktree "$REPO" "$WORKTREE" "feature-import"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Basic import tests
# =============================================================================

@test "wt-metadata-import copies metadata with correct contents to worktree" {
    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$WORKTREE"
    assert_success
    # Verify .idea directory and files were copied to worktree
    assert [ -d "$WORKTREE/.idea" ]
    assert [ -f "$WORKTREE/.idea/config.xml" ]
    # Verify content matches vault (setup creates .idea with "config content")
    local content
    content=$(cat "$WORKTREE/.idea/config.xml")
    assert_equal "$content" "config content"
}

# =============================================================================
# Directory structure tests
# =============================================================================

@test "wt-metadata-import preserves nested directory structure" {
    # Add nested structure to vault
    mkdir -p "$WT_IDEA_FILES_BASE/.idea/subdir/deep"
    echo "deep config" > "$WT_IDEA_FILES_BASE/.idea/subdir/deep/config.xml"

    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$WORKTREE"
    assert_success

    # .idea directory must be imported
    [ -d "$WORKTREE/.idea" ] || fail "Expected .idea directory to be imported"

    # Nested structure must be preserved
    [ -f "$WORKTREE/.idea/subdir/deep/config.xml" ] || fail "Expected nested config file"
    local content
    content=$(cat "$WORKTREE/.idea/subdir/deep/config.xml")
    assert_equal "$content" "deep config"
}

# =============================================================================
# Multiple patterns tests
# =============================================================================

@test "wt-metadata-import handles multiple metadata patterns" {
    sed -i.bak 's/WT_METADATA_PATTERNS=".idea"/WT_METADATA_PATTERNS=".idea .ijwb .vscode"/' "$TEST_HOME/.wt/repos/test.conf"

    # Add additional metadata to vault (setup already created .idea)
    mkdir -p "$WT_IDEA_FILES_BASE/.ijwb"
    mkdir -p "$WT_IDEA_FILES_BASE/.vscode"
    echo "ijwb" > "$WT_IDEA_FILES_BASE/.ijwb/config.xml"
    echo "vscode" > "$WT_IDEA_FILES_BASE/.vscode/settings.json"

    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$WORKTREE"
    assert_success

    # Verify each pattern was imported to worktree
    assert [ -d "$WORKTREE/.idea" ]
    assert [ -d "$WORKTREE/.ijwb" ]
    assert [ -d "$WORKTREE/.vscode" ]

    # Verify content was copied correctly
    assert [ -f "$WORKTREE/.idea/config.xml" ]
    assert_equal "$(cat "$WORKTREE/.ijwb/config.xml")" "ijwb"
    assert_equal "$(cat "$WORKTREE/.vscode/settings.json")" "vscode"
}

# =============================================================================
# Symlink handling tests
# =============================================================================

@test "wt-metadata-import resolves symlinks in vault and copies content" {
    # Create a real source directory (simulating what wt-metadata-export creates)
    local real_source="$BATS_TEST_TMPDIR/real-idea"
    mkdir -p "$real_source"
    echo "from real" > "$real_source/config.xml"

    # Make vault .idea a symlink to real source (mimics export behavior)
    rm -rf "$WT_IDEA_FILES_BASE/.idea"
    ln -s "$real_source" "$WT_IDEA_FILES_BASE/.idea"

    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$WORKTREE"
    assert_success

    # Import should resolve the symlink and copy the actual content
    assert [ -d "$WORKTREE/.idea" ]
    assert [ -f "$WORKTREE/.idea/config.xml" ]
    # Content should match the real source (symlink was followed)
    assert_equal "$(cat "$WORKTREE/.idea/config.xml")" "from real"
}

@test "wt-metadata-import handles broken symlinks in vault gracefully" {
    # Create broken symlink in vault
    rm -rf "$WT_IDEA_FILES_BASE/.idea"
    ln -s "/nonexistent/path/that/does/not/exist" "$WT_IDEA_FILES_BASE/.idea"

    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$WORKTREE"
    # Should succeed by skipping the broken symlink
    assert_success
    # Worktree should not have .idea since source was broken
    assert [ ! -d "$WORKTREE/.idea" ]
}

# =============================================================================
# Overwrite behavior tests
# =============================================================================

@test "wt-metadata-import can update existing metadata" {
    # Create existing metadata in worktree with different content
    mkdir -p "$WORKTREE/.idea"
    echo "old content" > "$WORKTREE/.idea/config.xml"

    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$WORKTREE"
    assert_success

    # Vault has .idea with "config content" (created in setup)
    # Import should overwrite existing worktree metadata with vault content
    assert [ -f "$WORKTREE/.idea/config.xml" ]
    local content
    content=$(cat "$WORKTREE/.idea/config.xml")
    assert_equal "$content" "config content"
}

# =============================================================================
# Help and usage tests
# =============================================================================

@test "wt-metadata-import -h/--help shows help" {
    run "$TEST_HOME/.wt/bin/wt-metadata-import" -h
    assert_output --partial "Usage:"

    run "$TEST_HOME/.wt/bin/wt-metadata-import" --help
    assert_output --partial "Usage:"
}

# =============================================================================
# Error handling tests
# =============================================================================

@test "wt-metadata-import fails for non-existent worktree" {
    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "/nonexistent/worktree"
    assert_failure
    assert_output --partial "No such file or directory"
}

@test "wt-metadata-import copies to non-worktree directory" {
    # Import works on any directory, not just git worktrees
    local not_worktree="$BATS_TEST_TMPDIR/not-a-worktree"
    mkdir -p "$not_worktree"

    export WT_METADATA_PATTERNS=".idea"

    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$not_worktree"
    assert_success

    # Verify metadata was actually copied to the non-worktree directory
    assert [ -d "$not_worktree/.idea" ]
    assert [ -f "$not_worktree/.idea/config.xml" ]
    assert_equal "$(cat "$not_worktree/.idea/config.xml")" "config content"
}

# =============================================================================
# Empty vault tests
# =============================================================================

@test "wt-metadata-import handles empty vault gracefully" {
    # Clear vault completely (note: * doesn't match dotfiles, so explicitly remove .idea)
    rm -rf "$WT_IDEA_FILES_BASE"/.idea
    rm -rf "$WT_IDEA_FILES_BASE"/*
    # Clear any existing metadata from worktree (may exist from previous tests)
    rm -rf "$WORKTREE/.idea"

    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$WORKTREE"
    assert_success

    # Verify no metadata directories were created in worktree
    assert [ ! -d "$WORKTREE/.idea" ]
}

@test "wt-metadata-import handles missing pattern in vault" {
    # Configure patterns where one exists (.idea from setup) and one doesn't
    sed -i.bak 's/WT_METADATA_PATTERNS=".idea"/WT_METADATA_PATTERNS=".idea .nonexistent"/' "$TEST_HOME/.wt/repos/test.conf"

    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$WORKTREE"
    assert_success

    # Verify existing pattern (.idea) was still imported
    assert [ -d "$WORKTREE/.idea" ]
    assert [ -f "$WORKTREE/.idea/config.xml" ]
    # Verify nonexistent pattern didn't cause spurious directory creation
    assert [ ! -d "$WORKTREE/.nonexistent" ]
}

# =============================================================================
# Explicit path arguments tests
# =============================================================================

@test "wt-metadata-import accepts explicit source and target" {
    local alt_vault="$BATS_TEST_TMPDIR/alt-vault"
    mkdir -p "$alt_vault/.idea"
    echo "alt content" > "$alt_vault/.idea/config.xml"

    # Usage: wt-metadata-import [source] <target>
    # With two args: first is source (vault), second is target (worktree)
    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$alt_vault" "$WORKTREE"
    assert_success

    # Verify the alt content was copied from explicit source to target
    assert [ -d "$WORKTREE/.idea" ]
    assert [ -f "$WORKTREE/.idea/config.xml" ]
    local content
    content=$(cat "$WORKTREE/.idea/config.xml")
    assert_equal "$content" "alt content"
}

# =============================================================================
# Permission tests
# =============================================================================

@test "wt-metadata-import handles file permissions" {
    chmod 600 "$WT_IDEA_FILES_BASE/.idea/config.xml"

    run "$TEST_HOME/.wt/bin/wt-metadata-import" -y "$WORKTREE"
    assert_success

    # Verify file was actually copied with content preserved
    assert [ -f "$WORKTREE/.idea/config.xml" ]
    assert_equal "$(cat "$WORKTREE/.idea/config.xml")" "config content"
}
