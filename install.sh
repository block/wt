#!/usr/bin/env bash
#
# install.sh — Install worktree-toolkit to ~/.wt/
# ================================================
#
# This script:
#   1. Copies the toolkit to ~/.wt/
#   2. Adds source line to ~/.zshrc or ~/.bashrc
#   3. Runs the context setup flow to configure the first repository
#   4. Optionally sets up nightly cron job to refresh Bazel IDE metadata
#

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Constants
# ═══════════════════════════════════════════════════════════════════════════════

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.wt"

# Source wt-common to get color helpers
. "$SOURCE_DIR/lib/wt-common"

# ═══════════════════════════════════════════════════════════════════════════════
# Functions
# ═══════════════════════════════════════════════════════════════════════════════

# Append a line to a file if the file exists and doesn't already contain it
append_if_missing() {
  local file="$1"
  local line="$2"

  [[ ! -f "$file" ]] && return 0

  # Match both ~ and $HOME variants of the wt.sh source line
  if grep -qE '(source|\.)\s+.*\.wt/wt\.sh' "$file"; then
    echo "  Already configured: $file"
  else
    printf "\n%s\n" "$line" >> "$file"
    echo "  ✓ Updated $file"
  fi
}

# Copy toolkit to installation directory
install_toolkit() {
  echo "Installing worktree-toolkit to $INSTALL_DIR ..."

  # Create install directory
  mkdir -p "$INSTALL_DIR"

  # Copy directories and files
  cp "$SOURCE_DIR/wt.sh" "$INSTALL_DIR/"
  cp -r "$SOURCE_DIR/bin" "$INSTALL_DIR/"
  cp -r "$SOURCE_DIR/lib" "$INSTALL_DIR/"
  cp -r "$SOURCE_DIR/completion" "$INSTALL_DIR/"

  # Make bin scripts executable
  chmod +x "$INSTALL_DIR"/bin/wt-*

  # Make lib/wt-metadata-refresh executable (for cron job)
  [[ -f "$INSTALL_DIR/lib/wt-metadata-refresh" ]] && chmod +x "$INSTALL_DIR"/lib/wt-metadata-refresh

  echo "  ✓ Installed to $INSTALL_DIR"
}

# Configure shell rc files to source wt.sh
configure_shell_rc() {
  local source_line='[[ -f ~/.wt/wt.sh ]] && source ~/.wt/wt.sh'

  echo "Configuring shell..."

  if [[ -f "$HOME/.zshrc" ]]; then
    append_if_missing "$HOME/.zshrc" "$source_line"
  fi

  if [[ -f "$HOME/.bashrc" ]]; then
    append_if_missing "$HOME/.bashrc" "$source_line"
  fi
}


# Set up cron job for metadata refresh
setup_cron_job() {
  local refresh_script="$INSTALL_DIR/lib/wt-metadata-refresh"

  # Skip if refresh script doesn't exist
  if [[ ! -f "$refresh_script" ]]; then
    return 0
  fi

  local log_dir="$HOME/.wt/logs"
  local log_file="$log_dir/metadata-refresh.log"
  local cron_entry="0 2 * * * /bin/zsh -lc '$refresh_script' >> $log_file 2>&1"

  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "  Nightly Metadata Refresh Cron Job"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo
  echo "When most development happens in worktrees, the Bazel IDE metadata in the main"
  echo "repository can become stale (missing new Bazel targets)."
  echo
  echo "This cron job will:"
  echo "  1. Run nightly at 2am"
  echo "  2. Use 'bazel query' to regenerate targets files in Bazel IDE directories"
  echo "  3. Re-export all metadata to the vault"
  echo
  echo "Cron entry:"
  echo "  $cron_entry"
  echo
  echo "Logs: $log_file"
  echo

  if ! prompt_confirm "Install nightly cron job? [Y/n]" "y"; then
    echo "Skipping. You can set this up manually later (see README)."
    return 0
  fi

  # Create log directory
  mkdir -p "$log_dir"
  echo "  ✓ Created log directory: $log_dir"

  # Check if cron job already exists
  if crontab -l 2>/dev/null | grep -qF "wt-metadata-refresh"; then
    echo "  Cron job already exists. Skipping."
  else
    # Add cron job
    (crontab -l 2>/dev/null || true; echo "$cron_entry") | crontab -
    echo "  ✓ Cron job installed (runs nightly at 2am)"
    echo "  ✓ Logs will be written to: $log_file"
  fi

  echo
  echo "  crontab -l        View cron jobs"
  echo "  crontab -e        Edit cron jobs (to modify or remove)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "  Worktree Toolkit Installer"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo
  echo "Source:      $SOURCE_DIR"
  echo "Install to:  $INSTALL_DIR"
  echo

  # Clean up old installation location if present
  if [[ -d "$HOME/.config/wt" ]]; then
    echo "Found old installation at ~/.config/wt"
    echo
    echo "This version uses ~/.wt/ instead."
    echo "Your existing worktrees and code are not affected."
    echo
    if prompt_confirm "Remove old installation? [Y/n]" "y"; then
      rm -rf "$HOME/.config/wt"
      # Update shell rc files to use new path
      for rc_file in "$HOME/.zshrc" "$HOME/.bashrc"; do
        if [[ -f "$rc_file" ]] && grep -q '\.config/wt' "$rc_file"; then
          sed -i.bak 's|\.config/wt|.wt|g' "$rc_file"
          rm -f "$rc_file.bak"
          echo "  ✓ Updated $rc_file"
        fi
      done
      echo "  ✓ Removed old installation"
    fi
    echo
  fi

  install_toolkit
  echo

  configure_shell_rc
  echo

  if prompt_confirm "Run repository context setup? [Y/n]" "y"; then
    echo
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  Repository Setup"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo

    # Source the context setup library (from installed location)
    # Set SCRIPT_DIR so _wt_sync_metadata can find wt-metadata-export
    SCRIPT_DIR="$INSTALL_DIR/bin"
    . "$INSTALL_DIR/lib/wt-context-setup"

    # Run the full context setup flow
    # This handles: repo selection, context naming, path derivation, metadata detection,
    # config file creation, directory creation, migration, and metadata export
    wt_setup_context
    echo

    setup_cron_job
    echo
  else
    echo "  Skipping. Run 'wt context add' later to set up a repository."
    echo
  fi

  cat <<'EOF'
════════════════════════════════════════════════════════════════════════════════
  Installation Complete!
════════════════════════════════════════════════════════════════════════════════

Reload your shell to activate:

    source ~/.zshrc    # or ~/.bashrc

Then run:

    wt help           Show all commands and options
    wt context        Switch between repository contexts

════════════════════════════════════════════════════════════════════════════════
EOF
}

main "$@"
