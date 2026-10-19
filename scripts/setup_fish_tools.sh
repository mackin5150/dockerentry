#!/usr/bin/env bash
# Optional, non-interactive Fish shell setup for Vast.ai provisioning.
# Run this last. Failures are logged but do not abort the provisioning script.
# Requires fish, git, and curl (already installed earlier by provision.sh).

setup_fish_tools() {
    echo "========================================"
    echo " Fish extras: Oh My Fish / Fisher / nvm.fish / Pure"
    echo "========================================"
    if ! command -v fish >/dev/null 2>&1; then
        echo "[WARN] fish is not installed; skipping Fish extras."
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "[WARN] curl is not installed; skipping Fish extras."
        return 0
    fi

    # OMF: NEVER pipe the installer into an interactive Fish process during boot.
    # '--noninteractive --yes' avoids prompts / interactive fish session replacement.
    if [ -d "$HOME/.local/share/omf" ] && [ -d "$HOME/.config/omf" ]; then
        echo "[SKIP] Oh My Fish already installed"
    else
        local omf_installer
        omf_installer="$(mktemp /tmp/omf-install.XXXXXX)" || {
            echo "[WARN] Could not allocate OMF installer temp file"; return 0;
        }
        if curl -fLsS --retry 3 --connect-timeout 15 --max-time 90 \
            'https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install' \
            -o "$omf_installer"; then
            if timeout 240 fish "$omf_installer" --noninteractive --yes </dev/null; then
                echo "[OK] Oh My Fish installed"
            else
                echo "[WARN] OMF installer failed or timed out; continuing"
            fi
        else
            echo "[WARN] Could not download OMF installer; continuing"
        fi
        rm -f -- "$omf_installer"
    fi

    # Fisher: install a real autoloaded function, rather than piping into 'source'
    # from Bash. Close stdin to avoid Fisher hanging in headless provisioning.
    local fisher_file="$HOME/.config/fish/functions/fisher.fish"
    mkdir -p "$(dirname "$fisher_file")"
    if [ ! -s "$fisher_file" ]; then
        if ! curl -fLsS --retry 3 --connect-timeout 15 --max-time 90 \
            'https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish' \
            -o "$fisher_file"; then
            rm -f -- "$fisher_file"
            echo "[WARN] Could not download Fisher; skipping nvm.fish and Pure"
            return 0
        fi
    else
        echo "[SKIP] Fisher function already present"
    fi

    # fish_plugins can already contain user plugins. 'fisher update' restores
    # that list before adding requested plugins. Feed /dev/null to avoid a
    # non-TTY hang reported in Fisher headless installations.
    if timeout 300 fish -c '
        if test -s "$HOME/.config/fish/fish_plugins"
            fisher update
        else
            fisher install jorgebucaran/fisher
        end
        fisher install jorgebucaran/nvm.fish pure-fish/pure
    ' </dev/null; then
        echo "[OK] Fisher + nvm.fish + Pure prompt configured"
    else
        echo "[WARN] Fisher/plugin install failed or timed out; continuing"
    fi

    echo "[INFO] Fish extras finished; default/login shell was not changed."
    return 0
}

# Important: do not let shell-prompt setup crash GPU provisioning.
setup_fish_tools || echo "[WARN] Fish extras had an unexpected failure; continuing"