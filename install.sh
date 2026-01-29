#!/usr/bin/env bash
#
# install.sh — Install worktree-toolkit to ~/.config/wt/
# ======================================================
#
# This script:
#   1. Copies the toolkit to ~/.config/wt/
#   2. Adds source line to ~/.zshrc or ~/.bashrc
#   3. Runs the full context setup flow for a repository
#   4. Optionally sets up nightly cron job for metadata refresh
#

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Constants
# ═══════════════════════════════════════════════════════════════════════════════

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.config/wt"

# Source wt-common to get default values and color helpers
. "$SOURCE_DIR/lib/wt-common"

# Source wt-context-setup for the full context setup flow
. "$SOURCE_DIR/lib/wt-context-setup"

# ═══════════════════════════════════════════════════════════════════════════════
# Functions
# ═══════════════════════════════════════════════════════════════════════════════

# Append a line to a file if the file exists and doesn't already contain it
append_if_missing() {
  local file="$1"
  local line="$2"

  [[ ! -f "$file" ]] && return 0

  if ! grep -Fxq "$line" "$file"; then
    printf "\n%s\n" "$line" >> "$file"
    echo "  ✓ Updated $file"
  else
    echo "  Already configured: $file"
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

  # Make lib/wt-ijwb-refresh executable (for cron job)
  [[ -f "$INSTALL_DIR/lib/wt-ijwb-refresh" ]] && chmod +x "$INSTALL_DIR"/lib/wt-ijwb-refresh

  echo "  ✓ Installed to $INSTALL_DIR"
}

# Configure shell rc files to source wt.sh
configure_shell_rc() {
  local source_line='[[ -f "$HOME/.config/wt/wt.sh" ]] && source "$HOME/.config/wt/wt.sh"'

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
  local refresh_script="$INSTALL_DIR/lib/wt-ijwb-refresh"

  # Skip if refresh script doesn't exist
  if [[ ! -f "$refresh_script" ]]; then
    return 0
  fi

  local log_dir="$HOME/.config/wt/logs"
  local log_file="$log_dir/ijwb-refresh.log"
  local cron_entry="0 2 * * * /bin/zsh -lc '$refresh_script' >> $log_file 2>&1"

  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "  Nightly Metadata Refresh Cron Job"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo
  echo "When most development happens in worktrees, the project metadata in the main"
  echo "repository can become stale."
  echo
  echo "This cron job will:"
  echo "  1. Run nightly at 2am"
  echo "  2. Refresh metadata in each configured context"
  echo
  echo "Cron entry:"
  echo "  $cron_entry"
  echo
  echo "Logs: $log_file"
  echo

  if ! prompt_confirm "Install nightly cron job? [Y/n]" "y"; then
    echo "Skipping. You can set this up manually later."
    return 0
  fi

  # Create log directory
  mkdir -p "$log_dir"
  echo "  ✓ Created log directory: $log_dir"

  # Check if cron job already exists
  if crontab -l 2>/dev/null | grep -qF "wt-ijwb-refresh"; then
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

# Print completion message
print_completion() {
  local context_name="${CURRENT_CONTEXT_NAME:-}"

  cat <<EOF
════════════════════════════════════════════════════════════════════════════════
  Installation Complete!
════════════════════════════════════════════════════════════════════════════════

Reload your shell to activate:

    source ~/.zshrc    # or ~/.bashrc

Then run:

    wt help           Show all commands and options
    wt list           Show worktrees for current context
EOF

  if [[ -n "$context_name" ]]; then
    cat <<EOF

Current context: $context_name

To add more repositories later:

    wt context add    Add another repository context

To switch between repositories:

    wt context        Interactive context selection
    wt context <name> Switch to named context

Context configuration:

    $HOME/.config/wt/repos/$context_name.conf
EOF
  fi

  cat <<EOF

════════════════════════════════════════════════════════════════════════════════
EOF
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

  install_toolkit
  echo

  configure_shell_rc
  echo

  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "  Repository Setup"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo

  # Run the full context setup flow
  # (prompts for repo, name, shows config, creates dirs, migrates, syncs metadata)
  wt_setup_context
  echo

  setup_cron_job
  echo

  print_completion
}

main "$@"
