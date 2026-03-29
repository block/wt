# Installation

## Checking if `wt` is installed

Run:
```bash
wt list
```

If this produces output (a list of worktrees or a "no contexts" message), `wt` is installed. If you get `command not found`, it needs to be installed.

### Fallback check

If `wt` is not found, check if it's installed but the shell hasn't been reloaded:
```bash
ls ~/.wt/wt.sh
```

If the file exists, the user just needs to reload their shell: `source ~/.zshrc` (or open a new terminal).

## Installing the CLI

Present these steps to the user and offer to run them. Do **not** install silently.

### Prerequisites

- git
- bash or zsh
- macOS or Linux

### Steps

```bash
# 1. Clone the repository
git clone git@github.com:block/wt.git ~/.wt/repos/wt/base

# 2. Run the installer (interactive)
cd ~/.wt/repos/wt/base
./install.sh

# 3. Reload shell
source ~/.zshrc   # or: source ~/.bash_profile
```

The installer will:
1. Copy the toolkit to `~/.wt/`
2. Add `source ~/.wt/wt.sh` to your shell rc file (`.zshrc` / `.bashrc`)
3. Prompt for repository context setup (which repo to manage)
4. Optionally set up a nightly metadata refresh cron job

### Post-install verification

```bash
wt list          # Should show worktrees (or prompt to set up a context)
wt help          # Should show the full help text
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `wt: command not found` | Shell not reloaded after install | Run `source ~/.zshrc` or open a new terminal |
| `wt list` shows nothing | No repository context configured | Run `wt context add` to set up the first repo |
| `wt` hangs on first run | Large repo, first-time git operations | Normal — wait for git to finish. Subsequent runs will be fast. |

## JetBrains Plugin (optional)

### When to suggest

Suggest the plugin if the user is working in a JetBrains IDE project. Indicators:
- `.idea/` directory exists in the repo
- `.ijwb/` directory exists in the repo
- User mentions IntelliJ, IDEA, Android Studio, CLion, or WebStorm

### What it provides

Native worktree management inside the IDE:
- Create, switch, remove, and adopt worktrees from the IDE
- Uses the same `~/.wt/` configuration as the CLI
- Automatic symlink switching for instant context switches (no re-import needed)

### Install steps

From the wt repo clone:
```bash
cd wt-jetbrains-plugin
./gradlew buildPlugin
```

Then in the IDE: **Settings > Plugins > gear icon > Install Plugin from Disk...** and select `build/distributions/wt-jetbrains-plugin-*.zip`.

### Requirements

- JetBrains IDE **2025.3+**
- macOS or Linux

Do **not** install the plugin unprompted. Mention it exists and ask if the user wants it.
