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
#       * TAB is wrapped:
#            - If the command is `wt-add`, invoke an FZF branch picker.
#            - Otherwise, delegate to the original TAB binding.
#       * Ctrl+X Ctrl+A always invokes the FZF branch picker.
#
#   - If `fzf` is NOT available:
#       * Use normal zsh completion:
#            - wt-add: first arg completes from git branches (WT_MAIN_REPO_ROOT
#              or current repo), plus files.
#            - Other wt-* commands: file completion.
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

# Completion for wt-remove / wt remove: worktree branch names (main repo excluded)
_wt_remove() {
  local context state
  typeset -A opt_args

  _arguments -C \
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

      subcommands=('add:Add a new repository context')

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

# ═══════════════════════════════════════════════════════════════════════════════
# FZF-specific setup (wt-add only — other commands use shared functions above)
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

  # Capture original TAB widget so we can delegate for non-wt-add commands.
  typeset -g WT_ORIG_TAB_WIDGET=""
  {
    local binding
    binding=($(bindkey '^I' 2>/dev/null))
    WT_ORIG_TAB_WIDGET="${binding[2]:-}"
  } 2>/dev/null

  # Dispatcher: if command starts with wt-add, use FZF; otherwise call original TAB binding.
  wt_tab_dispatch() {
    emulate -L zsh -o extended_glob

    local -a words
    words=(${(z)BUFFER})
    local first="${words[1]:-}"

    if [[ "$first" == "wt-add" ]]; then
      wt_fzf_branch_complete
      return
    fi

    if [[ -n "$WT_ORIG_TAB_WIDGET" && "$WT_ORIG_TAB_WIDGET" != "wt_tab_dispatch" ]]; then
      zle "$WT_ORIG_TAB_WIDGET"
    else
      zle complete-word
    fi
  }

  zle -N wt_tab_dispatch

  # Bind TAB to our dispatcher
  bindkey '^I' wt_tab_dispatch

  # Bind Ctrl+X Ctrl+A to always trigger FZF-based branch picker
  bindkey '^X^A' wt_fzf_branch_complete

else
  # Non-FZF: standard completion for wt-add
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

  compdef _wt_add wt-add
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Register standalone wt-* completions
# ═══════════════════════════════════════════════════════════════════════════════

compdef _wt_switch wt-switch
compdef _wt_remove wt-remove
compdef _wt_cd wt-cd
compdef _wt_context wt-context
compdef _wt_metadata_export wt-metadata-export
compdef _wt_metadata_import wt-metadata-import

# ═══════════════════════════════════════════════════════════════════════════════
# Unified `wt` command completion
# ═══════════════════════════════════════════════════════════════════════════════

_wt_completion() {
  # Force reload config to pick up context changes in current shell
  wt_read_config "$HOME/.wt/current" "force" 2>/dev/null || true

  local -a commands
  commands=(
    'add:Create a new worktree for a branch'
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
        switch|cd)              _wt_switch ;;
        remove)                 _wt_remove ;;
        context)                _wt_context ;;
        metadata-export|ijwb-export)  _wt_metadata_export ;;
        metadata-import|ijwb-import)  _wt_metadata_import ;;
      esac
      ;;
  esac
}
compdef _wt_completion wt
