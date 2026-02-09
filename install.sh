#!/usr/bin/env bash
#
# install.sh — Install worktree-toolkit to ~/.wt/
# ================================================
#
# This script:
#   1. Copies the toolkit to ~/.wt/
#   2. Adds source line to ~/.zshrc or ~/.bashrc
#   3. Optionally configures environment variables in lib/wt-common
#   4. Creates required directories
#   5. Optionally migrates existing repo to worktree structure
#   6. Optionally syncs project metadata to the vault
#   7. Optionally sets up nightly cron job to refresh Bazel IDE metadata
#

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Constants
# ═══════════════════════════════════════════════════════════════════════════════

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.wt"

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
  local repo_name

  repo_name="$(basename "$repo")"

  # The current repo location becomes the symlink location
  WT_ACTIVE_WORKTREE="$repo"

  # All worktree data goes to ~/.wt/repos/<name>/
  WT_MAIN_REPO_ROOT="$HOME/.wt/repos/${repo_name}/base"

  # Worktrees directory
  WT_WORKTREES_BASE="$HOME/.wt/repos/${repo_name}/worktrees"

  # Project metadata (IntelliJ, VS Code, etc.)
  WT_IDEA_FILES_BASE="$HOME/.wt/repos/${repo_name}/idea-files"
}

# Detect which known metadata patterns exist in a repository
# Args: $1 = repo path
# Outputs: space-separated list of detected patterns
# Note: Deduplicates by finding top-level metadata dirs only
#       (e.g., if .ijwb contains .idea, only .ijwb is reported)
detect_metadata_patterns() {
  local repo="$1"
  local all_paths=()

  # Find all metadata directories for all known patterns
  for entry in "${WT_KNOWN_METADATA[@]}"; do
    local pattern="${entry%%:*}"
    while IFS= read -r path; do
      [[ -n "$path" ]] && all_paths+=("$path")
    done < <(find -L "$repo" -maxdepth 5 -type d -name "$pattern" 2>/dev/null)
  done

  # No metadata found
  if [[ ${#all_paths[@]} -eq 0 ]]; then
    return
  fi

  # Sort paths (shorter paths come first)
  local sorted_paths
  sorted_paths=$(printf '%s\n' "${all_paths[@]}" | sort)

  # Deduplicate: keep only top-level metadata dirs
  local kept_paths=()
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    local dominated=false

    for kept in "${kept_paths[@]}"; do
      if [[ "$path" == "$kept/"* ]]; then
        dominated=true
        break
      fi
    done

    if [[ "$dominated" == "false" ]]; then
      kept_paths+=("$path")
    fi
  done <<< "$sorted_paths"

  # Extract unique pattern names from kept paths
  local patterns=()
  for path in "${kept_paths[@]}"; do
    local pattern
    pattern="$(basename "$path")"
    # Add to patterns if not already present
    local found=false
    for p in ${patterns[@]+"${patterns[@]}"}; do
      [[ "$p" == "$pattern" ]] && found=true && break
    done
    [[ "$found" == "false" ]] && patterns+=("$pattern")
  done

  echo "${patterns[*]}"
}

# Get description for a metadata pattern
# Args: $1 = pattern
get_pattern_description() {
  local pattern="$1"
  for entry in "${WT_KNOWN_METADATA[@]}"; do
    if [[ "${entry%%:*}" == "$pattern" ]]; then
      echo "${entry#*:}"
      return
    fi
  done
  echo "$pattern"
}

# Interactive selection of metadata patterns to preserve
# Args: $1 = repo path
# Sets: WT_METADATA_PATTERNS
select_metadata_patterns() {
  local repo="$1"

  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "  Project Metadata Detection"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo
  echo "Scanning repository for IDE/editor project metadata..."
  echo

  local detected
  detected=$(detect_metadata_patterns "$repo")

  if [[ -z "$detected" ]]; then
    echo "No known project metadata found in repository."
    echo
    echo "Known patterns that can be preserved:"
    for entry in "${WT_KNOWN_METADATA[@]}"; do
      local pattern="${entry%%:*}"
      local desc="${entry#*:}"
      echo "  $pattern - $desc"
    done
    echo
    echo "You can manually add patterns to WT_METADATA_PATTERNS in wt-common later."
    WT_METADATA_PATTERNS=""
    return 0
  fi

  echo "Detected project metadata:"
  echo

  # Convert to array for selection
  local -a detected_arr
  read -ra detected_arr <<< "$detected"
  local -a selected=()

  # Display each detected pattern with checkbox
  local i=1
  for pattern in "${detected_arr[@]}"; do
    local desc
    desc=$(get_pattern_description "$pattern")
    echo "  $i) [x] $pattern - $desc"
    selected+=("$pattern")
    ((i++))
  done

  echo
  echo "All detected patterns are selected by default."
  echo "Enter numbers to toggle (e.g., '1 3'), 'a' for all, 'n' for none, or Enter to confirm:"
  echo

  while true; do
    local input
    if ! read -rp "> " input; then
      echo
      exit 1
    fi

    # Empty input = confirm current selection
    if [[ -z "$input" ]]; then
      break
    fi

    case "$input" in
      a|A|all)
        selected=("${detected_arr[@]}")
        ;;
      n|N|none)
        selected=()
        ;;
      *)
        # Toggle specified numbers
        for num in $input; do
          if [[ "$num" =~ ^[0-9]+$ ]] && ((num >= 1 && num <= ${#detected_arr[@]})); then
            local idx=$((num - 1))
            local pattern="${detected_arr[$idx]}"
            # Check if already selected
            local found=0
            local new_selected=()
            for s in ${selected[@]+"${selected[@]}"}; do
              if [[ "$s" == "$pattern" ]]; then
                found=1
              else
                new_selected+=("$s")
              fi
            done
            if ((found)); then
              # Assign empty or populated array safely
              if [[ ${#new_selected[@]} -gt 0 ]]; then
                selected=("${new_selected[@]}")
              else
                selected=()
              fi
            else
              selected+=("$pattern")
            fi
          fi
        done
        ;;
    esac

    # Redisplay with current selection
    echo
    i=1
    for pattern in "${detected_arr[@]}"; do
      local desc
      desc=$(get_pattern_description "$pattern")
      local mark=" "
      for s in ${selected[@]+"${selected[@]}"}; do
        [[ "$s" == "$pattern" ]] && mark="x"
      done
      echo "  $i) [$mark] $pattern - $desc"
      ((i++))
    done
    echo
    echo "Enter numbers to toggle, 'a' for all, 'n' for none, or Enter to confirm:"
  done

  # Safely handle empty array (${arr[*]} on empty array is fine, but be explicit)
  if [[ ${#selected[@]} -gt 0 ]]; then
    WT_METADATA_PATTERNS="${selected[*]}"
  else
    WT_METADATA_PATTERNS=""
  fi

  echo
  if [[ -n "$WT_METADATA_PATTERNS" ]]; then
    echo "Selected patterns: $WT_METADATA_PATTERNS"
  else
    echo "No patterns selected."
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
  chmod +x "$INSTALL_DIR"/lib/wt-metadata-refresh

  echo "  ✓ Installed to $INSTALL_DIR"
}

# Configure shell rc files to source wt.sh
configure_shell_rc() {
  local source_line='[[ -f "$HOME/.wt/wt.sh" ]] && source "$HOME/.wt/wt.sh"'

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
  echo "  ${BOLD}Project metadata:${NC}    $WT_IDEA_FILES_BASE"
  echo "     Shared IDE/editor metadata for instant project switching."
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
    WT_IDEA_FILES_BASE=$(prompt_with_default "Project metadata directory" "$WT_IDEA_FILES_BASE")
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

  # ─────────────────────────────────────────────────────────────────────────────
  # Step 5: Detect and select project metadata to preserve
  # ─────────────────────────────────────────────────────────────────────────────
  echo
  select_metadata_patterns "$repo_path"

  # Write to wt-common using sed
  echo
  echo "Saving configuration..."
  sed -i.bak \
    -e "s|: \"\${WT_MAIN_REPO_ROOT:=.*}\"|: \"\${WT_MAIN_REPO_ROOT:=\"$WT_MAIN_REPO_ROOT\"}\"|" \
    -e "s|: \"\${WT_WORKTREES_BASE:=.*}\"|: \"\${WT_WORKTREES_BASE:=\"$WT_WORKTREES_BASE\"}\"|" \
    -e "s|: \"\${WT_IDEA_FILES_BASE:=.*}\"|: \"\${WT_IDEA_FILES_BASE:=\"$WT_IDEA_FILES_BASE\"}\"|" \
    -e "s|: \"\${WT_ACTIVE_WORKTREE:=.*}\"|: \"\${WT_ACTIVE_WORKTREE:=\"$WT_ACTIVE_WORKTREE\"}\"|" \
    -e "s|: \"\${WT_BASE_BRANCH:=.*}\"|: \"\${WT_BASE_BRANCH:=\"$WT_BASE_BRANCH\"}\"|" \
    -e "s|: \"\${WT_METADATA_PATTERNS:=.*}\"|: \"\${WT_METADATA_PATTERNS:=\"$WT_METADATA_PATTERNS\"}\"|" \
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

    # Use a temp directory to handle nested structures (e.g., moving ~/java to ~/java/base)
    local temp_dir="${WT_ACTIVE_WORKTREE}.wt-migrate-$$-$(date +%s)"

    echo "Moving $WT_ACTIVE_WORKTREE -> $temp_dir (temporary) ..."
    mv "$WT_ACTIVE_WORKTREE" "$temp_dir"

    # Create parent directory for destination if needed
    mkdir -p "$(dirname "$WT_MAIN_REPO_ROOT")"

    echo "Moving $temp_dir -> $WT_MAIN_REPO_ROOT ..."
    mv "$temp_dir" "$WT_MAIN_REPO_ROOT"

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

# Set up cron job for metadata refresh
setup_cron_job() {
  local refresh_script="$INSTALL_DIR/lib/wt-metadata-refresh"
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

  # Check for old cron job (wt-ijwb-refresh) and offer to migrate
  if crontab -l 2>/dev/null | grep -qF "wt-ijwb-refresh"; then
    echo "  Found old cron job (wt-ijwb-refresh)."
    echo "  Replacing with new cron job (wt-metadata-refresh)..."
    # Remove old entry and add new one
    (crontab -l 2>/dev/null | grep -vF "wt-ijwb-refresh"; echo "$cron_entry") | crontab -
    echo "  ✓ Cron job migrated to wt-metadata-refresh"
    echo "  ✓ Logs will be written to: $log_file"
  elif crontab -l 2>/dev/null | grep -qF "wt-metadata-refresh"; then
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

# Sync project metadata from main repo to shared location
sync_metadata() {
  if [[ ! -d "$WT_MAIN_REPO_ROOT" ]]; then
    echo "Skipping metadata sync: Main repository not found at $WT_MAIN_REPO_ROOT"
    return 0
  fi

  # Check if any patterns are configured
  if [[ -z "${WT_METADATA_PATTERNS:-}" ]]; then
    echo "Skipping metadata sync: No patterns configured"
    return 0
  fi

  echo "════════════════════════════════════════════════════════════════════════════════"
  echo "  Project Metadata Export"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo
  echo "Scanning for existing project metadata..."
  echo "Patterns: $WT_METADATA_PATTERNS"
  echo

  # Count total metadata directories found
  local total_count=0
  for pattern in $WT_METADATA_PATTERNS; do
    local count
    count=$(find -L "$WT_MAIN_REPO_ROOT" -maxdepth 5 -type d -name "$pattern" 2>/dev/null | wc -l | tr -d ' ')
    if [[ $count -gt 0 ]]; then
      echo "  Found $count '$pattern' directories"
      total_count=$((total_count + count))
    fi
  done

  if [[ $total_count -eq 0 ]]; then
    echo "No project metadata directories found in $WT_MAIN_REPO_ROOT"
    echo
    echo "This is expected if you haven't set up any IDE projects yet."
    echo "After setting up projects, run 'wt metadata-export' to export metadata."
    return 0
  fi

  echo
  echo "This step will:"
  echo "  1. Link metadata directories from: $WT_MAIN_REPO_ROOT"
  echo "  2. Store links in the vault:       $WT_IDEA_FILES_BASE"
  echo
  echo "The vault is a shared location where metadata is stored."
  echo "When you create new worktrees, this metadata is automatically installed."
  echo

  if ! prompt_confirm "Export metadata to vault? [Y/n]" "y"; then
    echo "Skipping. You can run 'wt metadata-export' manually later."
    return 0
  fi

  echo
  echo "Exporting metadata..."
  # Use -y to skip internal confirmation (installer already prompted)
  "$INSTALL_DIR/bin/wt-metadata-export" -y "$WT_MAIN_REPO_ROOT" "$WT_IDEA_FILES_BASE"
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

  sync_metadata
  echo

  setup_cron_job
  echo

  print_completion
}

main "$@"
