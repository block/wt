#!/usr/bin/env bash
#
# install.sh — Install worktree-toolkit to ~/.config/wt/
# ======================================================
#
# This script:
#   1. Copies the toolkit to ~/.config/wt/
#   2. Adds source line to ~/.zshrc or ~/.bashrc
#   3. Optionally configures environment variables in lib/wt-common
#   4. Creates required directories
#   5. Optionally migrates existing repo to worktree structure
#   6. Optionally syncs .ijwb metadata to the vault
#   7. Optionally sets up nightly cron job to refresh .ijwb metadata
#

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Constants
# ═══════════════════════════════════════════════════════════════════════════════

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.config/wt"

# Source wt-common to get default values and color helpers
. "$SOURCE_DIR/lib/wt-common"

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

# Prompt user for input with a default value
prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local result

  if ! read -rp "$prompt [$default]: " result; then
    # Ctrl-C or EOF
    echo
    exit 1
  fi
  echo "${result:-$default}"
}

# Expand ~ to $HOME in a path
expand_path() {
  local path="$1"
  # Expand ~ at the beginning of the path (e.g., ~/foo -> /home/user/foo)
  case "$path" in
    "~")
      echo "$HOME"
      ;;
    "~/"*)
      echo "${HOME}${path#\~}"
      ;;
    *)
      echo "$path"
      ;;
  esac
}

# Detect the default branch for a repository
# Tries: origin/HEAD, then common branch names
detect_default_branch() {
  local repo="$1"

  # Try to get from origin/HEAD
  local default_branch
  default_branch=$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')

  if [[ -n "$default_branch" ]]; then
    echo "$default_branch"
    return 0
  fi

  # Check for common default branch names
  for branch in main master; do
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null || \
       git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
      echo "$branch"
      return 0
    fi
  done

  # Fallback to main
  echo "main"
}

# Derive all paths from the repository location
# Sets: WT_MAIN_REPO_ROOT, WT_WORKTREES_BASE, WT_ACTIVE_WORKTREE, WT_IDEA_FILES_BASE
derive_paths_from_repo() {
  local repo="$1"
  local repo_name repo_parent

  repo_name="$(basename "$repo")"
  repo_parent="$(dirname "$repo")"

  # The current repo location becomes the symlink location
  WT_ACTIVE_WORKTREE="$repo"

  # Main repo gets "-master" suffix
  WT_MAIN_REPO_ROOT="${repo_parent}/${repo_name}-master"

  # Worktrees base gets "-worktrees" suffix
  WT_WORKTREES_BASE="${repo_parent}/${repo_name}-worktrees"

  # IntelliJ metadata goes to a central location in ~/.config/wt/
  WT_IDEA_FILES_BASE="$HOME/.config/wt/idea-files/${repo_name}"
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
  chmod +x "$INSTALL_DIR"/lib/wt-ijwb-refresh

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

# Prompt user for configuration and write to wt-common
# Uses a user-centric flow: start with which repo to manage, then derive paths
configure_wt_common() {
  local wt_common="$INSTALL_DIR/lib/wt-common"

  if [[ ! -f "$wt_common" ]]; then
    error "wt-common not found at $wt_common"
    return 1
  fi

  # ─────────────────────────────────────────────────────────────────────────────
  # Step 1: Ask which repository to manage
  # ─────────────────────────────────────────────────────────────────────────────
  echo "Which repository do you want to manage with worktrees?"
  echo
  echo "Enter the path to your existing git repository."
  echo "Example: ~/Development/myrepo"
  echo

  local repo_path
  while true; do
    if ! read -rp "Repository path: " repo_path; then
      echo
      exit 1
    fi

    # Handle empty input
    if [[ -z "$repo_path" ]]; then
      echo "Please enter a repository path."
      continue
    fi

    # Expand ~ to $HOME
    repo_path=$(expand_path "$repo_path")

    # Validate it exists
    if [[ ! -d "$repo_path" ]]; then
      error "Directory not found: $repo_path"
      continue
    fi

    # Validate it's a git repository
    if ! git -C "$repo_path" rev-parse --git-dir &>/dev/null; then
      error "Not a git repository: $repo_path"
      continue
    fi

    break
  done

  # Normalize to absolute path
  repo_path="$(cd "$repo_path" && pwd)"

  # ─────────────────────────────────────────────────────────────────────────────
  # Step 2: Auto-detect git info and show confirmation
  # ─────────────────────────────────────────────────────────────────────────────
  echo
  echo "Detected repository:"
  echo "  Path:   $repo_path"

  # Get remote origin URL if available
  local remote_url
  remote_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null || echo "(no remote)")
  echo "  Remote: $remote_url"

  # Detect default branch
  WT_BASE_BRANCH=$(detect_default_branch "$repo_path")
  echo "  Branch: $WT_BASE_BRANCH (default branch)"

  echo

  # ─────────────────────────────────────────────────────────────────────────────
  # Step 3: Derive paths automatically
  # ─────────────────────────────────────────────────────────────────────────────
  derive_paths_from_repo "$repo_path"

  # ─────────────────────────────────────────────────────────────────────────────
  # Step 4: Show derived configuration and allow edits
  # ─────────────────────────────────────────────────────────────────────────────
  echo "Derived configuration:"
  echo
  echo "  The worktree toolkit will set up the following structure:"
  echo
  echo "  ${BOLD}Active symlink:${NC}      $WT_ACTIVE_WORKTREE"
  echo "     Your IDE opens this path. It's a symlink that can point to any worktree."
  echo
  echo "  ${BOLD}Main repository:${NC}     $WT_MAIN_REPO_ROOT"
  echo "     Your current repo will be moved here (the \"master\" worktree)."
  echo
  echo "  ${BOLD}Worktrees directory:${NC} $WT_WORKTREES_BASE"
  echo "     New worktrees will be created here."
  echo
  echo "  ${BOLD}IntelliJ metadata:${NC}   $WT_IDEA_FILES_BASE"
  echo "     Shared .ijwb files for instant project switching."
  echo
  echo "  ${BOLD}Default branch:${NC}      $WT_BASE_BRANCH"
  echo "     Used when creating new worktrees."
  echo

  if prompt_confirm "Use this configuration? [Y/n]" "y"; then
    : # Continue with derived values
  else
    echo
    echo "You can customize each value. Press Enter to keep the default."
    echo

    WT_ACTIVE_WORKTREE=$(prompt_with_default "Active symlink path" "$WT_ACTIVE_WORKTREE")
    WT_MAIN_REPO_ROOT=$(prompt_with_default "Main repository path" "$WT_MAIN_REPO_ROOT")
    WT_WORKTREES_BASE=$(prompt_with_default "Worktrees directory" "$WT_WORKTREES_BASE")
    WT_IDEA_FILES_BASE=$(prompt_with_default "IntelliJ metadata directory" "$WT_IDEA_FILES_BASE")
    WT_BASE_BRANCH=$(prompt_with_default "Default base branch" "$WT_BASE_BRANCH")

    echo
    echo "Final configuration:"
    echo "  WT_ACTIVE_WORKTREE:  $WT_ACTIVE_WORKTREE"
    echo "  WT_MAIN_REPO_ROOT:   $WT_MAIN_REPO_ROOT"
    echo "  WT_WORKTREES_BASE:   $WT_WORKTREES_BASE"
    echo "  WT_IDEA_FILES_BASE:  $WT_IDEA_FILES_BASE"
    echo "  WT_BASE_BRANCH:      $WT_BASE_BRANCH"
    echo
  fi

  # Write to wt-common using sed
  echo "Saving configuration..."
  sed -i.bak \
    -e "s|: \"\${WT_MAIN_REPO_ROOT:=.*}\"|: \"\${WT_MAIN_REPO_ROOT:=\"$WT_MAIN_REPO_ROOT\"}\"|" \
    -e "s|: \"\${WT_WORKTREES_BASE:=.*}\"|: \"\${WT_WORKTREES_BASE:=\"$WT_WORKTREES_BASE\"}\"|" \
    -e "s|: \"\${WT_IDEA_FILES_BASE:=.*}\"|: \"\${WT_IDEA_FILES_BASE:=\"$WT_IDEA_FILES_BASE\"}\"|" \
    -e "s|: \"\${WT_ACTIVE_WORKTREE:=.*}\"|: \"\${WT_ACTIVE_WORKTREE:=\"$WT_ACTIVE_WORKTREE\"}\"|" \
    -e "s|: \"\${WT_BASE_BRANCH:=.*}\"|: \"\${WT_BASE_BRANCH:=\"$WT_BASE_BRANCH\"}\"|" \
    "$wt_common"
  rm -f "$wt_common.bak"
  echo "  ✓ Configuration saved"
}

# Create required directories
create_directories() {
  echo "Creating directories..."

  mkdir -p "$WT_WORKTREES_BASE"
  echo "  ✓ $WT_WORKTREES_BASE"

  mkdir -p "$WT_IDEA_FILES_BASE"
  echo "  ✓ $WT_IDEA_FILES_BASE"

  # Only create parent dir for symlink (the symlink itself is created in migrate_repo)
  local symlink_parent
  symlink_parent="$(dirname "$WT_ACTIVE_WORKTREE")"
  mkdir -p "$symlink_parent"
  echo "  ✓ $symlink_parent (parent for symlink)"
}

# Migrate existing java directory to worktree structure
migrate_repo() {
  if [[ -d "$WT_ACTIVE_WORKTREE" && ! -L "$WT_ACTIVE_WORKTREE" ]]; then
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  Repository Migration"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo
    echo "Found existing directory at: $WT_ACTIVE_WORKTREE"
    echo
    echo "This step will:"
    echo "  1. Move $WT_ACTIVE_WORKTREE → $WT_MAIN_REPO_ROOT"
    echo "  2. Create a symlink $WT_ACTIVE_WORKTREE → $WT_MAIN_REPO_ROOT"
    echo
    echo "This enables the symlink trick: IntelliJ always opens the same path,"
    echo "but the symlink can point to different worktrees for instant switching."
    echo

    if ! prompt_confirm "Migrate repository now? [y/N]" "n"; then
      echo "Skipping migration. You can do this manually later."
      return 0
    fi

    if [[ -e "$WT_MAIN_REPO_ROOT" ]]; then
      error "$WT_MAIN_REPO_ROOT already exists. Cannot migrate."
      return 1
    fi

    echo "Moving $WT_ACTIVE_WORKTREE -> $WT_MAIN_REPO_ROOT ..."
    mv "$WT_ACTIVE_WORKTREE" "$WT_MAIN_REPO_ROOT"

    echo "Creating symlink $WT_ACTIVE_WORKTREE -> $WT_MAIN_REPO_ROOT ..."
    ln -s "$WT_MAIN_REPO_ROOT" "$WT_ACTIVE_WORKTREE"

    echo "  ✓ Migration complete!"

  elif [[ -L "$WT_ACTIVE_WORKTREE" ]]; then
    echo "Active worktree symlink already exists: $WT_ACTIVE_WORKTREE"
    echo "  -> $(readlink "$WT_ACTIVE_WORKTREE")"

  elif [[ ! -e "$WT_ACTIVE_WORKTREE" ]]; then
    if [[ -d "$WT_MAIN_REPO_ROOT" ]]; then
      echo "Creating symlink $WT_ACTIVE_WORKTREE -> $WT_MAIN_REPO_ROOT ..."
      ln -s "$WT_MAIN_REPO_ROOT" "$WT_ACTIVE_WORKTREE"
      echo "  ✓ Symlink created!"
    else
      echo "Note: Neither $WT_ACTIVE_WORKTREE nor $WT_MAIN_REPO_ROOT exists."
      echo "You'll need to clone your repository to $WT_MAIN_REPO_ROOT and create symbolic link manually."
    fi
  fi
}

# Set up cron job for .ijwb refresh
setup_cron_job() {
  local refresh_script="$INSTALL_DIR/lib/wt-ijwb-refresh"
  local log_dir="$HOME/.config/wt/logs"
  local log_file="$log_dir/ijwb-refresh.log"
  local cron_entry="0 2 * * * /bin/zsh -lc '$refresh_script' >> $log_file 2>&1"

  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "  Nightly .ijwb Refresh Cron Job"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo
  echo "When most development happens in worktrees, the .ijwb metadata in the main"
  echo "repository can become stale (missing new Bazel targets)."
  echo
  echo "This cron job will:"
  echo "  1. Run nightly at 2am"
  echo "  2. Use 'bazel query' to regenerate targets files in each .ijwb directory"
  echo "  3. Re-export refreshed metadata to the vault"
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

# Sync .ijwb metadata from main repo to shared location
sync_ijwb() {
  if [[ ! -d "$WT_MAIN_REPO_ROOT" ]]; then
    echo "Skipping .ijwb sync: Main repository not found at $WT_MAIN_REPO_ROOT"
    return 0
  fi

  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "  IntelliJ Metadata Export (.ijwb)"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo
  echo "Scanning for existing IntelliJ Bazel projects..."

  local ijwb_count
  # Use -maxdepth 3 since .ijwb dirs are at service level (e.g., orders/.ijwb)
  ijwb_count=$(find "$WT_MAIN_REPO_ROOT" -maxdepth 3 -type d -name '.ijwb' 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$ijwb_count" -eq 0 ]]; then
    echo "No .ijwb directories found in $WT_MAIN_REPO_ROOT"
    echo
    echo "This is expected if you haven't imported any projects in IntelliJ yet."
    echo "After importing projects, run 'wt ijwb-export' to export metadata."
    return 0
  fi

  echo "Found $ijwb_count .ijwb directories in main repository."
  echo
  echo "This step will:"
  echo "  1. Copy .ijwb directories from: $WT_MAIN_REPO_ROOT"
  echo "  2. Store them in the vault:     $WT_IDEA_FILES_BASE"
  echo
  echo "The vault is a shared location where .ijwb metadata is stored."
  echo "When you create new worktrees, this metadata is automatically installed,"
  echo "avoiding expensive IntelliJ re-imports and re-indexing."
  echo

  if ! prompt_confirm "Export .ijwb metadata to vault? [Y/n]" "y"; then
    echo "Skipping. You can run 'wt ijwb-export' manually later."
    return 0
  fi

  echo
  echo "Exporting .ijwb metadata..."
  # Use -y to skip internal confirmation (installer already prompted)
  "$INSTALL_DIR/bin/wt-ijwb-export" -y "$WT_MAIN_REPO_ROOT" "$WT_IDEA_FILES_BASE"
}

# Print completion message
print_completion() {
  cat <<EOF
════════════════════════════════════════════════════════════════════════════════
  Installation Complete!
════════════════════════════════════════════════════════════════════════════════

Reload your shell to activate:

    source ~/.zshrc    # or ~/.bashrc

Then run:

    wt help           Show all commands and options

To change configuration later, edit:

    $INSTALL_DIR/lib/wt-common

Then re-source your shell config to apply changes.

EOF



  echo "════════════════════════════════════════════════════════════════════════════════"
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

  configure_wt_common
  echo

  create_directories
  echo

  migrate_repo
  echo

  sync_ijwb
  echo

  setup_cron_job
  echo

  print_completion
}

main "$@"
