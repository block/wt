# completion/wt.zsh
# ==================
# Zsh completion for both the unified `wt` command and standalone `wt-*` scripts.
#
# Behavior:
#   - Always:
#       * Source wt-common (if present) to get WT_MAIN_REPO_ROOT, etc.
#       * Provide completion for wt-* commands and the unified `wt` command.
#
#   - If `fzf` is available:
#       * Ctrl+X Ctrl+A invokes an FZF branch picker.
#
#   - Always:
#       * Normal zsh completion:
#            - wt-add: first arg completes from git branches (WT_MAIN_REPO_ROOT
#              or current repo), plus files.
#            - Other wt-* commands: dedicated completers.
#
# This file is designed for personal use.

# --- Load shared config (wt-common) if available ---
if [[ -r "$HOME/.wt/lib/wt-common" ]]; then
  source "$HOME/.wt/lib/wt-common"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Helper functions
# ═══════════════════════════════════════════════════════════════════════════════

# --- Helper: resolve which repo to use for branch completion ---
# Priority:
#   1. WT_MAIN_REPO_ROOT if set and a git repo.
#   2. Current directory if inside a git repo.
#   3. Non-zero status (no output) otherwise.
_wt_resolve_repo() {
  # Use git -C to correctly handle worktrees and non-standard .git layouts.
  if [[ -n ${WT_MAIN_REPO_ROOT:-} ]] && git -C "$WT_MAIN_REPO_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
    print -r -- "$WT_MAIN_REPO_ROOT"
    return 0
  fi

  if git rev-parse --is-inside-work-tree &>/dev/null; then
    # Show the repository root; callers should treat this as the repo path.
    git rev-parse --show-toplevel 2>/dev/null
    return 0
  fi

  return 1
}

# --- Helper: get branch names from resolved repo ---
_wt_branch_list() {
  local repo
  repo=$(_wt_resolve_repo) || return

  git -C "$repo" branch --format='%(refname:short)' 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
# Shared completion functions (used by both `wt-*` and `wt` subcommands)
# ═══════════════════════════════════════════════════════════════════════════════

# Completion for wt-switch / wt switch: worktree branch names
_wt_switch() {
  local context state
  typeset -A opt_args

  _arguments -C \
    '1:worktree:->worktree' && return 0

  case "$state" in
    worktree)
      local -a branches
      branches=("${(f)$(wt_worktree_branch_list)}")

      if (( ${#branches[@]} > 0 )); then
        _describe 'branch names' branches
      fi
      ;;
  esac
}

# Completion for wt-adopt / wt adopt: flags + worktree branch names (main repo excluded)
_wt_adopt() {
  local context state
  typeset -A opt_args

  _arguments -C \
    '--force[Skip conflict checks]' \
    '--redo[Re-run adoption treatment]' \
    '(-h --help)'{-h,--help}'[Show help]' \
    '1:worktree:->worktree' && return 0

  case "$state" in
    worktree)
      local -a branches
      branches=("${(f)$(wt_worktree_branch_list exclude_main)}")

      if (( ${#branches[@]} > 0 )); then
        _describe 'branch names' branches
      fi
      ;;
  esac
}

# Completion for wt-remove / wt remove: worktree branch names (main repo excluded)
_wt_remove() {
  local context state
  typeset -A opt_args

  _arguments -C \
    '(-y --yes)'{-y,--yes}'[Skip confirmation prompt]' \
    '(-b --branch)'{-b,--branch}'[Also delete the git branch]' \
    '--merged[Remove all worktrees with merged branches]' \
    '--on-dirty=[Dirty worktree policy]:mode:(warn skip remove)' \
    '*:worktree:->worktree' && return 0

  case "$state" in
    worktree)
      local -a branches
      branches=("${(f)$(wt_worktree_branch_list exclude_main)}")

      if (( ${#branches[@]} > 0 )); then
        _describe 'branch names' branches
      fi
      ;;
  esac
}

# Completion for wt-cd / wt cd: worktree branch names
_wt_cd() {
  local context state
  typeset -A opt_args

  _arguments -C \
    '1:worktree:->worktree' && return 0

  case "$state" in
    worktree)
      local -a branches
      branches=("${(f)$(wt_worktree_branch_list)}")

      if (( ${#branches[@]} > 0 )); then
        _describe 'branch names' branches
      fi
      ;;
  esac
}

# Completion for wt-list / wt list: flags
_wt_list() {
  _arguments \
    '(-v --verbose)'{-v,--verbose}'[Show dirty/ahead/behind status]' \
    '--porcelain[Machine-readable output]' \
    '(-h --help)'{-h,--help}'[Show help]'
}

# Completion for wt-context / wt context
_wt_context() {
  local context state
  typeset -A opt_args

  _arguments -C \
    '(-l --list)'{-l,--list}'[List all contexts]' \
    '(-h --help)'{-h,--help}'[Show help]' \
    '1:context or subcommand:->first' \
    '*:args:->args' && return 0

  case "$state" in
    first)
      local -a contexts subcommands
      local repos_dir="$HOME/.wt/repos"

      subcommands=(
        'add:Add a new repository context'
        'remove:Remove a context and clean up all wt config'
      )

      if [[ -d "$repos_dir" ]]; then
        for conf in "$repos_dir"/*.conf(N); do
          [[ -f "$conf" ]] || continue
          local name="${conf:t:r}"
          contexts+=("$name")
        done
      fi

      _describe 'subcommands' subcommands
      if (( ${#contexts[@]} > 0 )); then
        _describe 'contexts' contexts
      fi
      ;;
    args)
      if [[ "${words[2]}" == "add" ]]; then
        _files -/
      elif [[ "${words[2]}" == "remove" ]]; then
        local -a rm_contexts rm_opts
        rm_opts=(
          '-y:Skip confirmation prompt'
          '--yes:Skip confirmation prompt'
        )
        local repos_dir="$HOME/.wt/repos"
        if [[ -d "$repos_dir" ]]; then
          for conf in "$repos_dir"/*.conf(N); do
            [[ -f "$conf" ]] || continue
            local name="${conf:t:r}"
            rm_contexts+=("$name")
          done
        fi
        if (( ${#rm_contexts[@]} > 0 )); then
          _describe 'contexts' rm_contexts
        fi
        _describe 'options' rm_opts
      fi
      ;;
  esac
}

# Completion for wt-metadata-export / wt metadata-export: directories
_wt_metadata_export() {
  _arguments -C \
    '1:source directory:_files -/' \
    '2:target directory:_files -/'
}

# Completion for wt-metadata-import / wt metadata-import: worktrees and directories
_wt_metadata_import() {
  local context state
  typeset -A opt_args

  _arguments -C \
    '1:source or target:->first' \
    '2:target worktree:->worktree' && return 0

  case "$state" in
    first|worktree)
      local -a worktrees
      worktrees=(${(f)$(_wt_worktree_list)})

      if (( ${#worktrees[@]} > 0 )); then
        _describe 'worktrees' worktrees || _files -/
      else
        _files -/
      fi
      ;;
  esac
}

# Completion for wt-add: branch names plus files
_wt_add() {
  emulate -L zsh -o extended_glob

  local context state
  typeset -A opt_args

  _arguments -C \
    '(-b --branch)'{-b,--branch}'[Create new branch]:branch name:->branch' \
    '1:branch or path:->first' \
    '*:files:_files' && return 0

  case "$state" in
    branch|first)
      local -a branches
      branches=("${(f)$(_wt_branch_list)}")

      if (( ${#branches[@]} > 0 )); then
        _describe 'branches' branches || _files
      else
        _files
      fi
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# FZF-specific setup (optional Ctrl+X Ctrl+A branch picker; TAB is left untouched)
# ═══════════════════════════════════════════════════════════════════════════════

if (( $+commands[fzf] )); then
  # FZF-based branch picker widget
  wt_fzf_branch_complete() {
    emulate -L zsh -o extended_glob

    local branches branch
    branches="$(_wt_branch_list)"

    if [[ -z "$branches" ]]; then
      # No repo or no branches -> fall back to normal completion
      zle complete-word
      return
    fi

    branch=$(print -r -- "$branches" | fzf --height 50% --reverse --prompt='wt-add branch > ')
    [[ -z "$branch" ]] && return  # user cancelled

    # Insert the branch at the cursor position, preserving existing arguments
    if [[ -n "$LBUFFER" && "$LBUFFER" != *[[:space:]] ]]; then
      LBUFFER+=" "
    fi
    LBUFFER+="$branch "
    BUFFER="$LBUFFER$RBUFFER"
    CURSOR=${#LBUFFER}
  }

  zle -N wt_fzf_branch_complete

  # Bind Ctrl+X Ctrl+A to trigger FZF-based branch picker
  bindkey '^X^A' wt_fzf_branch_complete
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Unified `wt` command completion
# ═══════════════════════════════════════════════════════════════════════════════

_wt_completion() {
  # Force reload config to pick up context changes in current shell
  wt_read_config --force || true

  local -a commands
  commands=(
    'add:Create a new worktree for a branch'
    'adopt:Adopt an existing worktree into wt management'
    'switch:Switch the active worktree symlink'
    'remove:Remove a worktree'
    'list:List all worktrees with status'
    'cd:Change directory to a worktree'
    'context:Switch repository context'
    'metadata-export:Export project metadata to vault'
    'metadata-import:Import project metadata into worktree'
    'ijwb-export:Export .ijwb metadata to vault (legacy alias)'
    'ijwb-import:Import .ijwb metadata into worktree (legacy alias)'
    'help:Show help message'
  )

  local context state
  typeset -A opt_args

  _arguments -C \
    '1:command:->command' \
    '*::args:->args' && return 0

  case "$state" in
    command)
      _describe 'command' commands
      ;;
    args)
      case "${words[1]}" in
        add)
          # Simple branch completion for `wt add`
          local -a branches
          branches=("${(f)$(git branch -a 2>/dev/null | sed 's/^[* ]*//' | sed 's|remotes/origin/||')}")
          (( ${#branches[@]} > 0 )) && _describe 'branch' branches
          ;;
        adopt)                  _wt_adopt ;;
        switch|cd)              _wt_switch ;;
        remove)                 _wt_remove ;;
        list)                   _wt_list ;;
        context)                _wt_context ;;
        metadata-export|ijwb-export)  _wt_metadata_export ;;
        metadata-import|ijwb-import)  _wt_metadata_import ;;
      esac
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# Register completions (only when compinit has made compdef available)
# ═══════════════════════════════════════════════════════════════════════════════

if (( $+functions[compdef] )); then
  compdef _wt_add wt-add
  compdef _wt_adopt wt-adopt
  compdef _wt_switch wt-switch
  compdef _wt_remove wt-remove
  compdef _wt_cd wt-cd
  compdef _wt_list wt-list
  compdef _wt_context wt-context
  compdef _wt_metadata_export wt-metadata-export
  compdef _wt_metadata_import wt-metadata-import
  compdef _wt_completion wt
fi
