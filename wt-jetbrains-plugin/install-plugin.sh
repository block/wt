#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PLUGIN_DIR_NAME="wt-jetbrains-plugin"

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Darwin)  PLATFORM="macos" ;;
    Linux)   PLATFORM="linux" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    *)
        echo "Error: Unsupported OS: $OS" >&2
        exit 1
        ;;
esac

# Build the plugin
echo "Building plugin..."
if [[ "$PLATFORM" == "windows" ]]; then
    ./gradlew.bat buildPlugin
else
    ./gradlew buildPlugin
fi

# Find the built ZIP
ZIP_FILE=$(ls build/distributions/wt-jetbrains-plugin-*.zip 2>/dev/null | head -1)
if [[ -z "$ZIP_FILE" ]]; then
    echo "Error: No plugin ZIP found in build/distributions/" >&2
    exit 1
fi
echo "Built: $ZIP_FILE"

# Find JetBrains config directory based on OS
case "$PLATFORM" in
    macos)
        JETBRAINS_DIR="$HOME/Library/Application Support/JetBrains"
        ;;
    linux)
        JETBRAINS_DIR="$HOME/.config/JetBrains"
        ;;
    windows)
        JETBRAINS_DIR="$APPDATA/JetBrains"
        ;;
esac

if [[ ! -d "$JETBRAINS_DIR" ]]; then
    echo "Error: JetBrains directory not found at $JETBRAINS_DIR" >&2
    exit 1
fi

# Known IDE config directory patterns
IDE_PATTERNS=(
    "IntelliJIdea*"
    "GoLand*"
    "PyCharm*"
    "WebStorm*"
    "CLion*"
    "Rider*"
    "RubyMine*"
    "PhpStorm*"
    "AndroidStudio*"
    "DataGrip*"
    "DataSpell*"
)

# Collect all matching IDE directories (most recent first)
IDE_DIRS=()
for pattern in "${IDE_PATTERNS[@]}"; do
    while IFS= read -r dir; do
        IDE_DIRS+=("$dir")
    done < <(ls -dt "$JETBRAINS_DIR"/$pattern 2>/dev/null)
done

if [[ ${#IDE_DIRS[@]} -eq 0 ]]; then
    echo "Error: No JetBrains IDE installation found in $JETBRAINS_DIR" >&2
    exit 1
fi

# Select IDE directory
if [[ ${#IDE_DIRS[@]} -eq 1 ]]; then
    SELECTED_DIR="${IDE_DIRS[0]}"
else
    echo ""
    echo "Multiple JetBrains IDEs found:"
    for i in "${!IDE_DIRS[@]}"; do
        echo "  $((i + 1)). $(basename "${IDE_DIRS[$i]}")"
    done
    echo ""
    read -rp "Select IDE [1-${#IDE_DIRS[@]}]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#IDE_DIRS[@]} )); then
        echo "Error: Invalid selection" >&2
        exit 1
    fi
    SELECTED_DIR="${IDE_DIRS[$((choice - 1))]}"
fi

PLUGINS_DIR="$SELECTED_DIR/plugins"
mkdir -p "$PLUGINS_DIR"

echo "IDE plugins dir: $PLUGINS_DIR"

# Remove existing version of the plugin
if [[ -d "$PLUGINS_DIR/$PLUGIN_DIR_NAME" ]]; then
    echo "Removing existing plugin..."
    rm -rf "$PLUGINS_DIR/$PLUGIN_DIR_NAME"
fi

# Extract the new version
echo "Installing plugin..."
unzip -qo "$ZIP_FILE" -d "$PLUGINS_DIR"

echo ""
echo "Plugin installed successfully!"
echo "Restart your IDE to activate the plugin."
