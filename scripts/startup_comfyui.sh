#!/usr/bin/env bash
set -Eeuo pipefail

# Configure ComfyUI's input/output/workflow folders to use persistent storage.
# Safe to run on every startup; does not remove existing user files.
# Overrides: COMFY_DIR=/workspace/ComfyUI, COMFY_PERSIST_DIR=/workspace/.comfy

COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
COMFY_PERSIST_DIR="${COMFY_PERSIST_DIR:-/workspace/.comfy}"

if [[ ! -d "$COMFY_DIR" ]]; then
    printf '[ERROR] ComfyUI directory not found: %s\n' "$COMFY_DIR" >&2
    exit 1
fi

for folder in inputs outputs workflows; do
    mkdir -p -- "$COMFY_PERSIST_DIR/$folder"
done

link_persistent_dir() {
    local source="$1" target="$2" backup item name
    mkdir -p -- "$(dirname -- "$source")" "$target"

    # Already correct: nothing changes on subsequent starts.
    if [[ -L "$source" ]] && \
       [[ "$(readlink -f -- "$source")" == "$(readlink -f -- "$target")" ]]; then
        printf '[SKIP] %s already links to %s\n' "$source" "$target"
        return 0
    fi

    if [[ -e "$source" || -L "$source" ]]; then
        backup="${source}.pre-persistence-$(date +%Y%m%d%H%M%S)-$$"
        mv -- "$source" "$backup"
        printf '[BACKUP] Moved old path: %s\n' "$backup"

        # Move files into persistent storage when names do not conflict.
        # Never overwrite existing persistent data. Preserve conflicts in backup.
        if [[ -d "$backup" && ! -L "$backup" ]]; then
            shopt -s nullglob dotglob
            for item in "$backup"/*; do
                name="${item##*/}"
                if [[ -e "$target/$name" || -L "$target/$name" ]]; then
                    printf '[KEEP] Name collision; original remains in %s\n' "$item"
                else
                    mv -- "$item" "$target/"
                    printf '[MOVE] %s -> %s/\n' "$name" "$target"
                fi
            done
            shopt -u nullglob dotglob
            if rmdir -- "$backup" 2>/dev/null; then
                printf '[OK] All original items moved into persistent storage\n'
            else
                printf '[BACKUP] Unmerged files remain at %s\n' "$backup"
            fi
        fi
    fi

    ln -s -- "$target" "$source"
    printf '[LINK] %s -> %s\n' "$source" "$target"
}

link_persistent_dir "$COMFY_DIR/input" "$COMFY_PERSIST_DIR/inputs"
link_persistent_dir "$COMFY_DIR/output" "$COMFY_PERSIST_DIR/outputs"
# Kept for compatibility with the layout in the existing user setup.
link_persistent_dir "$COMFY_DIR/models/workflows" "$COMFY_PERSIST_DIR/workflows"
# ComfyUI saves UI workflows here; the models path alone is not sufficient.
link_persistent_dir "$COMFY_DIR/user/default/workflows" "$COMFY_PERSIST_DIR/workflows"

printf '[OK] ComfyUI persistent paths are configured.\n'
