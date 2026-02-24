#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PLUGIN_DIR_NAME="wt-intellij-plugin"

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
ZIP_FILE=$(ls build/distributions/wt-intellij-plugin-*.zip 2>/dev/null | head -1)
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

# Find the most recent IntelliJ IDEA directory
IDEA_DIR=$(ls -dt "$JETBRAINS_DIR"/IntelliJIdea* 2>/dev/null | head -1)
if [[ -z "$IDEA_DIR" ]]; then
    echo "Error: No IntelliJ IDEA installation found in $JETBRAINS_DIR" >&2
    exit 1
fi

PLUGINS_DIR="$IDEA_DIR/plugins"
mkdir -p "$PLUGINS_DIR"

echo "IntelliJ plugins dir: $PLUGINS_DIR"

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

# Restart IntelliJ IDEA
case "$PLATFORM" in
    macos)
        IDEA_APP_PATH=$(ps aux | grep -o '/[^[:space:]]*IntelliJ IDEA[^/]*.app' | head -1 || true)
        IDEA_PID=$(pgrep -f "IntelliJ IDEA.*/MacOS/idea" | head -1 || true)
        if [[ -n "$IDEA_PID" && -n "$IDEA_APP_PATH" ]]; then
            echo "Restarting IntelliJ IDEA (pid $IDEA_PID)..."
            kill "$IDEA_PID"
            while kill -0 "$IDEA_PID" 2>/dev/null; do sleep 1; done
            open -a "$IDEA_APP_PATH"
            echo "IntelliJ IDEA restarted."
        else
            echo "IntelliJ IDEA is not running. Launch it manually to use the plugin."
        fi
        ;;
    linux)
        IDEA_PID=$(pgrep -f "idea" 2>/dev/null | head -1)
        if [[ -n "$IDEA_PID" ]]; then
            # Find the binary path before killing
            IDEA_BIN=$(readlink -f "/proc/$IDEA_PID/exe" 2>/dev/null || true)
            echo "Restarting IntelliJ IDEA..."
            kill "$IDEA_PID"
            while kill -0 "$IDEA_PID" 2>/dev/null; do sleep 1; done
            if [[ -n "$IDEA_BIN" && -x "$IDEA_BIN" ]]; then
                nohup "$IDEA_BIN" &>/dev/null &
            else
                # Fall back to common install locations
                for candidate in \
                    /snap/intellij-idea-ultimate/current/bin/idea.sh \
                    /snap/intellij-idea-community/current/bin/idea.sh \
                    "$HOME/.local/share/JetBrains/Toolbox/apps/IDEA-U/ch-0/*/bin/idea.sh" \
                    "$HOME/.local/share/JetBrains/Toolbox/apps/IDEA-C/ch-0/*/bin/idea.sh" \
                    /opt/idea/bin/idea.sh; do
                    # shellcheck disable=SC2086
                    FOUND=$(ls -t $candidate 2>/dev/null | head -1)
                    if [[ -n "$FOUND" && -x "$FOUND" ]]; then
                        nohup "$FOUND" &>/dev/null &
                        break
                    fi
                done
            fi
            echo "IntelliJ IDEA restarted."
        else
            echo "IntelliJ IDEA is not running. Launch it manually to use the plugin."
        fi
        ;;
    windows)
        IDEA_PID=$(tasklist 2>/dev/null | grep -i "idea" | awk '{print $2}' | head -1)
        if [[ -n "$IDEA_PID" ]]; then
            echo "Restarting IntelliJ IDEA..."
            taskkill //PID "$IDEA_PID" //F 2>/dev/null || true
            sleep 3
            # Try common install locations
            for candidate in \
                "$LOCALAPPDATA/Programs/IntelliJ IDEA Ultimate/bin/idea64.exe" \
                "$LOCALAPPDATA/Programs/IntelliJ IDEA Community/bin/idea64.exe" \
                "C:/Program Files/JetBrains/IntelliJ IDEA/bin/idea64.exe"; do
                if [[ -f "$candidate" ]]; then
                    start "" "$candidate" &
                    break
                fi
            done
            echo "IntelliJ IDEA restarted."
        else
            echo "IntelliJ IDEA is not running. Launch it manually to use the plugin."
        fi
        ;;
esac
