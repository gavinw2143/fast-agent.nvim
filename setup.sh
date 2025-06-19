#!/usr/bin/env bash
set -euo pipefail

# Parse options
SKIP_ROOT=0
for arg in "$@"; do
    case "$arg" in
        --no-root)
            SKIP_ROOT=1
            ;;
    esac
done

prompt_root() {
    if [ "$SKIP_ROOT" -eq 1 ]; then
        return 1
    fi
    read -r -p "$1 [y/N] " ans
    case "$ans" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

# Install OS level dependencies
if command -v apt-get >/dev/null; then
    echo "Detected apt based system"
    if prompt_root "Run apt-get to install packages?"; then
        sudo apt-get update
        sudo apt-get install -y neovim luarocks git curl
    else
        echo "Skipping apt-get step"
    fi
elif command -v brew >/dev/null; then
    echo "Detected macOS with Homebrew"
    brew update
    brew install neovim luarocks git curl
else
    echo "Please install neovim, luarocks, git and curl using your OS package manager." >&2
fi

# Install Lua testing dependencies
if command -v luarocks >/dev/null; then
    if prompt_root "Install LuaRocks modules with sudo?"; then
        sudo luarocks install --lua-version=5.1 busted || true
        # Required for the Neo4j storage adapter
        sudo luarocks install --lua-version=5.1 neo4j || true
    else
        echo "Skipping LuaRocks step"
    fi
fi

# Fetch Neovim dependency for the plugin
PLUGIN_PATH="$HOME/.local/share/nvim/site/pack/deps/start"
mkdir -p "$PLUGIN_PATH"
if [ ! -d "$PLUGIN_PATH/plenary.nvim" ]; then
    git clone --depth 1 https://github.com/nvim-lua/plenary.nvim.git "$PLUGIN_PATH/plenary.nvim" || true
fi
