#!/usr/bin/env bats

# Integration tests for bin/wt-metadata-export

setup() {
    load '../test_helper/common'
    setup_test_env

    # Create mock repo with metadata
    REPO=$(create_mock_repo "$BATS_TEST_TMPDIR/repo")

    # Create test context and load its WT_* variables
    create_test_context "test" "$REPO"
    load_test_context "test"

    # Create vault directory
    mkdir -p "$WT_IDEA_FILES_BASE"

    # Update .conf directly — scripts re-source wt-common on execution
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Basic export tests
# =============================================================================

@test "wt-metadata-export creates symlinks pointing to source for single pattern" {
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea"/' "$TEST_HOME/.wt/repos/test.conf"
    create_metadata_dirs "$REPO" ".idea"

    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y
    assert_success

    # Check symlink was created in vault and points to source
    assert [ -L "$WT_IDEA_FILES_BASE/.idea" ]
    local target
    target=$(readlink "$WT_IDEA_FILES_BASE/.idea")
    assert_equal "$target" "$REPO/.idea"
}

@test "wt-metadata-export handles multiple patterns" {
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea .ijwb .vscode"/' "$TEST_HOME/.wt/repos/test.conf"
    create_metadata_dirs "$REPO" ".idea" ".ijwb" ".vscode"

    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y
    assert_success

    # Verify symlinks were created for each pattern
    assert [ -L "$WT_IDEA_FILES_BASE/.idea" ]
    assert [ -L "$WT_IDEA_FILES_BASE/.ijwb" ]
    assert [ -L "$WT_IDEA_FILES_BASE/.vscode" ]

    # Verify symlinks point to correct targets
    assert_equal "$(readlink "$WT_IDEA_FILES_BASE/.idea")" "$REPO/.idea"
    assert_equal "$(readlink "$WT_IDEA_FILES_BASE/.ijwb")" "$REPO/.ijwb"
    assert_equal "$(readlink "$WT_IDEA_FILES_BASE/.vscode")" "$REPO/.vscode"
}

# =============================================================================
# Empty/missing patterns tests
# =============================================================================

@test "wt-metadata-export warns when no patterns configured" {
    # Ensure no patterns are configured
    sed -i.bak 's/WT_METADATA_PATTERNS=".*/WT_METADATA_PATTERNS=""/' "$TEST_HOME/.wt/repos/test.conf"
    export WT_METADATA_PATTERNS=""

    run "$TEST_HOME/.wt/bin/wt-metadata-export"
    # Should succeed (no-op when no patterns)
    assert_success
    # Should warn about no patterns
    assert_output --partial "No metadata patterns configured"
}

@test "wt-metadata-export handles missing metadata directories gracefully" {
    # Update context config with patterns
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea .ijwb"/' "$TEST_HOME/.wt/repos/test.conf"
    # Don't create the directories - they don't exist in the repo

    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y
    assert_success

    # Verify no symlinks were created since source directories don't exist
    assert [ ! -L "$WT_IDEA_FILES_BASE/.idea" ]
    assert [ ! -L "$WT_IDEA_FILES_BASE/.ijwb" ]
}

# =============================================================================
# Symlink behavior tests
# =============================================================================

@test "wt-metadata-export preserves directory structure via symlink" {
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea"/' "$TEST_HOME/.wt/repos/test.conf"
    mkdir -p "$REPO/.idea/subdir"
    echo "config" > "$REPO/.idea/subdir/config.xml"

    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y
    assert_success

    # Verify symlink exists
    assert [ -L "$WT_IDEA_FILES_BASE/.idea" ]

    # Source structure should be preserved and accessible through symlink
    assert [ -f "$REPO/.idea/subdir/config.xml" ]
    assert [ -f "$WT_IDEA_FILES_BASE/.idea/subdir/config.xml" ]
}

# =============================================================================
# Update/overwrite tests
# =============================================================================

@test "wt-metadata-export updates existing symlinks" {
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea"/' "$TEST_HOME/.wt/repos/test.conf"
    create_metadata_dirs "$REPO" ".idea"

    # First export
    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y
    assert_success
    assert [ -L "$WT_IDEA_FILES_BASE/.idea" ]

    # Modify source by adding new file
    echo "updated" > "$REPO/.idea/updated.xml"

    # Second export (re-export)
    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y
    assert_success

    # Symlink should still exist and point to source
    assert [ -L "$WT_IDEA_FILES_BASE/.idea" ]
    local target
    target=$(readlink "$WT_IDEA_FILES_BASE/.idea")
    assert_equal "$target" "$REPO/.idea"

    # Updated content should be accessible through symlink
    assert [ -f "$WT_IDEA_FILES_BASE/.idea/updated.xml" ]
    assert_equal "$(cat "$WT_IDEA_FILES_BASE/.idea/updated.xml")" "updated"
}

# =============================================================================
# Help and usage tests
# =============================================================================

@test "wt-metadata-export -h/--help shows help" {
    run "$TEST_HOME/.wt/bin/wt-metadata-export" -h
    assert_output --partial "Usage:"

    run "$TEST_HOME/.wt/bin/wt-metadata-export" --help
    assert_output --partial "Usage:"
}

# =============================================================================
# Explicit path arguments tests
# =============================================================================

@test "wt-metadata-export accepts explicit source and target paths" {
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea"/' "$TEST_HOME/.wt/repos/test.conf"

    local alt_source="$BATS_TEST_TMPDIR/alt-source"
    local alt_target="$BATS_TEST_TMPDIR/alt-target"
    mkdir -p "$alt_source"
    mkdir -p "$alt_target"
    create_metadata_dirs "$alt_source" ".idea"

    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y "$alt_source" "$alt_target"
    assert_success

    # Verify symlink was created pointing to source
    assert [ -L "$alt_target/.idea" ]
    assert_equal "$(readlink "$alt_target/.idea")" "$alt_source/.idea"
}

# =============================================================================
# Nested path deduplication tests
# =============================================================================

@test "wt-metadata-export deduplicates nested paths" {
    sed -i.bak 's/WT_METADATA_PATTERNS=""/WT_METADATA_PATTERNS=".idea .ijwb"/' "$TEST_HOME/.wt/repos/test.conf"

    # Create nested structure: .ijwb inside .idea (edge case)
    # Deduplication should only export .idea (outer), not the nested .ijwb
    mkdir -p "$REPO/.idea/.ijwb"
    echo "config" > "$REPO/.idea/config.xml"
    echo "nested" > "$REPO/.idea/.ijwb/config.xml"

    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y
    assert_success

    # Only the outer .idea should be symlinked (deduplication removes nested)
    assert [ -L "$WT_IDEA_FILES_BASE/.idea" ]
    # The nested .ijwb should NOT have a separate symlink at vault root
    # (it's inside .idea, so accessible via .idea symlink, but not separately exported)
    assert [ ! -L "$WT_IDEA_FILES_BASE/.ijwb" ]

    # Content should still be accessible through the .idea symlink
    assert [ -f "$WT_IDEA_FILES_BASE/.idea/config.xml" ]
    assert [ -f "$WT_IDEA_FILES_BASE/.idea/.ijwb/config.xml" ]
}

# =============================================================================
# Error handling tests
# =============================================================================

@test "wt-metadata-export fails for non-existent source directory" {
    export WT_METADATA_PATTERNS=".idea"

    run "$TEST_HOME/.wt/bin/wt-metadata-export" -y "/nonexistent/source/path" "$WT_IDEA_FILES_BASE"
    assert_failure
    assert_output --partial "does not exist"
}
