# Contributing to Worktree Toolkit

Thanks for your interest in contributing!

## Prerequisites

**Required:**
- Bash 4.0+
- Git

**Optional:**
- [fzf](https://github.com/junegunn/fzf) — enables interactive branch picker in shell completions

## Local Development

1. Clone the repo:
   ```bash
   git clone https://github.com/block/wt.git
   cd wt
   ```

2. Source the entry point in your shell:
   ```bash
   source wt.sh
   ```

3. Test commands:
   ```bash
   wt help
   ```

## Code Style

- Follow existing patterns in the codebase
- Keep scripts POSIX-compatible where possible (bash 4+ features are fine)
- Use meaningful variable names
- Add `--help` support for new commands

## Testing

Tests are not yet implemented. Contributions to add [bats-core](https://github.com/bats-core/bats-core) tests are welcome!

## Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test locally by sourcing `wt.sh` and running commands
5. Commit with a clear message
6. Open a pull request

## Questions?

Open an issue if you have questions or want to discuss a feature before implementing.
