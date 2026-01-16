---
marp: true
theme: uncover
paginate: true
class: invert
style: |
  section {
    font-family: 'IBM Plex Sans', -apple-system, BlinkMacSystemFont, sans-serif;
    font-size: 28px;
  }
  h1 {
    font-size: 1.6em;
  }
  h2 {
    font-size: 1.3em;
  }
  h3 {
    font-size: 1.1em;
  }
  code {
    font-family: 'IBM Plex Mono', 'SF Mono', monospace;
    font-size: 0.85em;
  }
  pre {
    font-size: 0.9em;
  }
  section.center {
    text-align: center;
    justify-content: center;
  }
  table {
    margin: 0 auto;
    font-size: 0.9em;
  }
  th, td {
    padding: 0.3em 1.2em;
  }
  .wide-table th, .wide-table td {
    min-width: 250px;
  }
  .small-table {
    font-size: 0.7em;
  }
  ul {
    text-align: left;
  }
  ul.no-bullets {
    list-style: none;
    padding-left: 5em;
  }
---

# Instant IntelliJ Context Switching for Parallel Branch Development

---

# AI Agents Are Changing How We Code

<br>

<ul class="no-bullets">
<li>🤖 Cursor, Claude, Goose — AI is writing code</li>
<li>📈 Teams adopting AI for faster development</li>
<li>🔀 Each agent task = separate branch</li>
</ul>

<!-- ---

# Git Worktrees: Quick Refresher

<br>

<ul class="no-bullets">
<li>✓ Multiple working directories, one repository</li>
<li>✓ Shared .git history</li>
<li>✓ Each branch checked out simultaneously</li>
</ul>

<br>

### Perfect primitive for parallel development -->

---

# Git Worktrees: Multiply AI Efficiency

<br>

```
┌─────────┐  ┌─────────┐  ┌─────────┐
│ Agent 1 │  │ Agent 2 │  │ Agent 3 │
│ task-A  │  │ task-B  │  │ task-C  │
└────┬────┘  └────┬────┘  └────┬────┘
     │            │            │
     ▼            ▼            ▼
 worktree-A   worktree-B   worktree-C
```

<br>

### True parallelism within one repository

---

# The Bottleneck: Context Switching

<div class="small-table">

| feature-A | feature-B | feature-C |
|:---------:|:---------:|:---------:|
| 🔄 code review | ⏳ CI running | 💬 waiting feedback |
| **blocked** | **blocked** | **blocked** |

</div>

<ul class="no-bullets">
<li>🤖 AI generates changes in parallel</li>
<li>👨‍💻 Engineer to <b>verify</b> changes before pushing upstream</li>
<li>🔄 Or pick up the next unblocked task</li>
</ul>

### Context switching should be instant — but it isn't

---

# Git supports parallel branches.

# IntelliJ doesn't.

---

# IntelliJ sees each worktree as a separate project

<br>

```
Open worktree  →  Bazel import  →  Index rebuild
```

<br>

<ul class="no-bullets">
<li>❌ Navigate through the bazel import menu to create the project</li>
<li>❌ Full Bazel sync + indexing every time</li>
<li>❌ Minutes of wait time per new worktrea creation</li>
</ul>

<br>

### The parallelism you gained is eaten by IDE friction


---

# What does IntelliJ handle well?

<div class="small-table">

| feature-A | feature-B | feature-C |
|:---------:|:---------:|:---------:|
| **✓ current** | ⏳ blocked | 💬 blocked |

</div>

```bash
$ git checkout feature-B    # Same directory, files change
```

<ul class="no-bullets">
  <li>✓ Reuses existing .ijwb metadata</li>
  <li>→ ✓ Incremental refresh</li>
  <li>→ <b>Seconds, not minutes</b></li>
</ul>

<br>

### What if switching worktrees looked like a checkout?

---

# The Trick: A Symlink

<ul class="no-bullets">
  <li>IntelliJ always opens <b><i>the same path</i></b>:</li>
</ul>

```
~/Development/java  ──(symlink)──►  java-worktrees/feature-A  ✓
```
<ul class="no-bullets">
  <li>Switch worktree = update symlink:</li>
</ul>

```
~/Development/java  ──(symlink)──►  java-worktrees/feature-B  ✓
```

| What happens | IntelliJ sees |
|:-------------|:--------------|
| Symlink target changes | "Same project, files changed" |
| Result | **Incremental refresh (seconds)** |

---

# The Catch: Metadata Requirements

<ul class="no-bullets">
  <li>IntelliJ needs `.ijwb` metadata in every worktree</li>
  <li>> No metadata = No project recognition</li>
</ul>

<br>

## Solution: A Metadata Vault

<ul class="no-bullets">
  <li><b>Export:</b> .ijwb from main repo → vault (symlinks)</li>
  <li><b>Import:</b> vault → every new worktree (copies)</li>
</ul>

<br>

### Also: Bazel output symlinks (bazel-out, bazel-bin) shared across worktrees

<!-- ---

# Architecture

```
~/Development/

├── java ─────────────────►  java-worktrees/feature-A
│   (symlink)                   ↑ IntelliJ opens this path

├── java-master/                Main repo (stays on master)

├── java-worktrees/             Parallel worktrees
│   ├── feature-A/                 Each has .ijwb + bazel symlinks
│   ├── feature-B/
│   └── agent/task-123/

└── idea-project-files/         Metadata vault
    └── **/.ijwb/                  Symlinks to main repo
``` -->

---

# Demo

---

# Demo: Core Workflow

```bash
# List all worktrees (* = currently linked)
wt list

# Create worktree for new branch (auto-imports metadata)
wt add -b feature/demo

# Switch IntelliJ's view (< 1 second)
wt switch feature/demo

# Navigate to worktree
wt cd feature/demo

# Cleanup all merged branches
wt remove --merged
```

---

# What wt add -b Does

<br>

<ul class="no-bullets">
<li>1. Stashes uncommitted changes (if any)</li>
<li>2. Switches to master, pulls latest</li>
<li>3. Creates new branch + worktree</li>
<li>4. Imports .ijwb metadata from vault</li>
<li>5. Creates bazel-out/bazel-bin symlinks</li>
<li>6. Restores original branch + stash</li>
</ul>

<br>

### One command → ready for IntelliJ

---

# Back to AI Agents

```
┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
│ Agent 1 │  │ Agent 2 │  │ Agent 3 │  │  Human  │
│  auth   │  │   api   │  │  perf   │  │ review  │
└────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘
     └────────────┴────────────┴────────────┘
                       │
                       ▼
            ┌─────────────────────┐
            │  Parallel Worktrees │
            └─────────────────────┘
```

Human reviews any agent's work: `wt switch agent/auth`

**Instant context switch.** No waiting.

---

# Results

<br>

<div class="wide-table">

|  | Before | After |
|--|:------:|:-----:|
| **Time per switch** | Minutes | **< 1 sec** |
| **Context switching** | Expensive | **Free** |
| **Development style** | One branch | **True parallel** |

</div>

---

# Get Started

```bash
$ git clone https://github.com/block/wt.git
$ cd wt
$ ./install.sh
$ source ~/.zshrc   # Reload shell
$ wt help           # See all commands
```

---


# Questions?

