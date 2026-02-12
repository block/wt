#!/usr/bin/env bats

# Unit tests for wt.sh

setup() {
    load '../test_helper/common'
    setup_test_env
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Tests for _WT_ROOT consistency
# =============================================================================

@test "_WT_ROOT default in wt.sh matches INSTALL_DIR in install.sh" {
    # Extract the default path from wt.sh: _WT_ROOT="${_WT_ROOT:-$HOME/.wt}"
    local wt_line
    wt_line=$(grep '_WT_ROOT=.*HOME' "$PROJECT_ROOT/wt.sh" | head -1)
    # Pull out the $HOME/... portion
    local wt_path
    wt_path=$(echo "$wt_line" | sed 's/.*\(\$HOME\/[^}"]*\).*/\1/')

    # Extract INSTALL_DIR from install.sh: INSTALL_DIR="$HOME/.wt"
    local install_line
    install_line=$(grep 'INSTALL_DIR=.*HOME' "$PROJECT_ROOT/install.sh" | head -1)
    local install_path
    install_path=$(echo "$install_line" | sed 's/.*"\(\$HOME\/[^"]*\)".*/\1/')

    [ -n "$wt_path" ]
    [ -n "$install_path" ]
    [ "$wt_path" = "$install_path" ]
}
