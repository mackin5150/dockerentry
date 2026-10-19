#!/bin/bash
set -Eeuo pipefail

# --------------------------------------------------
# API credentials supplied by Vast environment
# --------------------------------------------------
: "${HF_TOKEN:?HF_TOKEN environment variable is not set}"
: "${CIVITAI_API_TOKEN:?CIVITAI_API_TOKEN environment variable is not set}"

export HF_TOKEN
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
export CIVITAI_API_TOKEN

echo "HF_TOKEN: configured"
echo "CIVITAI_API_TOKEN: configured"

echo "========================================"
echo " Custom ComfyUI provisioning started"
echo "========================================"

export DEBIAN_FRONTEND=noninteractive
export HOME=/root

WORKSPACE="/workspace"
COMFY="/workspace/ComfyUI"

# --------------------------------------------------
# System packages
# --------------------------------------------------
apt-get update
apt-get install --no-install-recommends -y \
    curl wget git fish ncdu ca-certificates lsd rustup nala neovim npm nodejs

# --------------------------------------------------
# Activate Vast's existing Python environment
# --------------------------------------------------
if [ -f /venv/main/bin/activate ]; then
    source /venv/main/bin/activate
else
    echo "WARNING: /venv/main/bin/activate not found; using system Python."
fi

python -m pip install --upgrade pip || true
python -m pip install --upgrade comfy-cli || true

# --------------------------------------------------
# OpenCode / LM Studio headless
# --------------------------------------------------
npm install @openrouter/sdk
npm install @openrouter/agent
npm install @openai/codex@latest
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash || true
curl -fsSL https://opencode.ai/install | bash || true
curl -fsSL https://lmstudio.ai/install.sh | bash || true
export PATH="/root/.local/bin:/root/.lmstudio/bin:/root/.opencode/bin:$PATH"

# --------------------------------------------------
# ComfyUI folders and custom nodes
# --------------------------------------------------
mkdir -p /workspace/.comfy/{inputs,outputs,workflows}
# Ensure both directories exist before attempting git clone/find.
mkdir -p "$COMFY/custom_nodes" "$COMFY/models"
clone_if_missing() {
    URL="$1"
    DIR="$2"
    if [ ! -d "$COMFY/custom_nodes/$DIR/.git" ]; then
        echo "Cloning $DIR"
        git clone "$URL" "$COMFY/custom_nodes/$DIR" || true
    else
        echo "$DIR already installed"
    fi
}

clone_if_missing "https://github.com/DonutsDelivery/ComfyUI-DonutNodes.git" "donutnodes"
clone_if_missing "https://github.com/DemonNCoding/PromptGenerator12Columns.git" "PromptGenerator12Columns"
clone_if_missing "https://github.com/artokun/comfyui-mcp-panel.git" "comfyui-mcp-panel"
clone_if_missing "https://github.com/slahiri/ComfyUI-Workflow-Models-Downloader.git" "ComfyUI-Workflow-Models-Downloader"
clone_if_missing "https://codeberg.org/Gourieff/comfyui-reactor-node.git" "comfyui-reactor-node"
clone_if_missing "https://github.com/BenjaMITM/Enhanced-Civicomfy.git" "Enhanced-Civicomfy"
clone_if_missing "https://github.com/huchukato/ComfyUI-QwenVL-Mod.git" "ComfyUI-QwenVL-Mod"
clone_if_missing "https://github.com/mackin5150/OcclusionMask.git" "OcclusionMask"

# New: discover compatible ONNX image-processing models in models/onnx/.
clone_if_missing "https://github.com/theRealAi/ComfyUI-ONNX.git" "ComfyUI-ONNX"

# Optional: unmaintained SimSwap/Ghost node. May conflict with ReActor dependencies;
# deliberately disabled unless ENABLE_SIMSWAP_NODE=1 in Vast environment.
if [ "${ENABLE_SIMSWAP_NODE:-0}" = "1" ]; then
    clone_if_missing "https://github.com/TaiTair/comfyui-simswap.git" "comfyui-simswap"
fi

# Optional: Kijai LivePortrait (uses different *safetensors* models, NOT OwlMaster ONNX).
# ENABLE_LIVEPORTRAIT_KJ=1 to install separately; its models auto-download on use.
if [ "${ENABLE_LIVEPORTRAIT_KJ:-0}" = "1" ]; then
    clone_if_missing "https://github.com/kijai/ComfyUI-LivePortraitKJ.git" "ComfyUI-LivePortraitKJ"
fi

find "$COMFY/custom_nodes" -maxdepth 2 -name requirements.txt -print0 |
while IFS= read -r -d '' req; do
    echo "Installing $req"
    if command -v uv >/dev/null 2>&1; then
        uv pip install --python /venv/main/bin/python -r "$req" || true
    else
        python -m pip install -r "$req" || true
    fi
done

# --------------------------------------------------
# OwlMaster/AllFilesRope - download & route models
# --------------------------------------------------
# Default: full ~12.2 GB download. Set ROPE_DOWNLOAD=0 to skip on one boot.
if [ "${ROPE_DOWNLOAD:-1}" = "1" ]; then
python -m pip install -q 'huggingface_hub>=0.32,<2' hf_xet
export ROPE_REPO="${ROPE_REPO:-OwlMaster/AllFilesRope}"
export ROPE_REVISION="${ROPE_REVISION:-main}"
export ROPE_INCLUDE_NATIVE_PLUGIN="${ROPE_INCLUDE_NATIVE_PLUGIN:-0}"
export COMFY
python - <<'PY'
import os
import sys
import time
from pathlib import Path
from huggingface_hub import HfApi, hf_hub_download

comfy = Path(os.environ['COMFY']).expanduser().resolve()
models = comfy / 'models'
repo = os.environ.get('ROPE_REPO', 'OwlMaster/AllFilesRope')
revision = os.environ.get('ROPE_REVISION', 'main')
token = os.environ.get('HF_TOKEN') or None
include_native = os.environ.get('ROPE_INCLUDE_NATIVE_PLUGIN', '0') == '1'
archive = models / 'rope_allfiles'
archive.mkdir(parents=True, exist_ok=True)

# Categorize by actual ComfyUI consumer, not by ONNX alone.
upscale = {
    '4x-UltraMix_Smooth.fp16.onnx', '4x-UltraSharp.fp16.onnx',
    'BSRGANx2.fp16.onnx', 'RealESRGAN_x2plus.fp16.onnx',
    'RealESRGAN_x4plus.fp16.onnx', 'realesr-general-x4v3.onnx',
}
restore = {
    'GFPGANv1.4.onnx', 'GPEN-BFR-1024.onnx',
    'GPEN-BFR-2048.onnx', 'GPEN-BFR-256.onnx',
    'GPEN-BFR-512.onnx', 'RestoreFormerPlusPlus.fp16.onnx',
    'RestoreFormerPlusPlus.onnx', 'VQFRv2.onnx', 'codeformer_fp16.onnx',
}
colorize = {
    'ColorizeArtistic.fp16.onnx', 'ColorizeStable.fp16.onnx',
    'ColorizeVideo.fp16.onnx', 'ddcolor.onnx', 'ddcolor_artistic.onnx',
}
live = {
    'appearance_feature_extractor.onnx', 'face_2dpose_106_static.onnx',
    'landmark.onnx', 'motion_extractor.onnx', 'retinaface_det_static.onnx',
    'stitching.onnx', 'stitching_eye.onnx', 'stitching_lip.onnx',
    'warping_spade-fix.onnx', 'warping_spade.onnx',
}
face_detection = {
    '2dfan4.onnx', 'scrfd_2.5g_bnkps.onnx', 'yoloface_8n.onnx',
    'face_landmarks_detector_Nx3x256x256.onnx',
    'face_blendshapes_Nx146x2.onnx',
    'peppapig_teacher_Nx3x256x256.onnx', 'res50.onnx',
}
buffalo = {'1k3d68.onnx', '2d106det.onnx', 'det_10g.onnx', 'w600k_r50.onnx'}
segment = {'occluder.onnx', 'XSeg_model.onnx', 'faceparser_fp16.onnx', 'faceparser_resnet34.onnx'}

n_linked = 0
n_existing = 0
n_conflicts = 0

def link_model(src: Path, dest: Path):
    """Add a relative symlink without overwriting somebody else's model."""
    global n_linked, n_existing, n_conflicts
    src = src.resolve()
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink() and not dest.exists():
        dest.unlink()  # repair stale symlink
    if dest.is_symlink() and dest.resolve() == src:
        n_existing += 1
        return
    if dest.exists() or dest.is_symlink():
        n_conflicts += 1
        print(f'[KEEP] Existing different model: {dest}', flush=True)
        return
    dest.symlink_to(os.path.relpath(src, dest.parent))
    n_linked += 1
    print(f'[LINK] {dest.relative_to(comfy)}', flush=True)


def destinations(file: str):
    """Some files have two consumers; unknown models stay only in archive."""
    p = Path(file)
    name = p.name
    if p.parts[0] == 'liveportrait_onnx':
        if name.endswith('.onnx'):
            yield models / 'liveportrait_onnx' / name
        return
    if name in live:
        # Root-level LivePortrait duplicates are only fallback: nested sources win.
        yield models / 'liveportrait_onnx' / name
    if name == 'inswapper_128.fp16.onnx':
        yield models / 'insightface' / name  # ReActor enumerates .onnx swappers here.
    if name in buffalo:
        yield models / 'insightface' / 'models' / 'buffalo_l' / name
        # NOTE: OwlMaster does not carry genderage.onnx. Pack may be incomplete.
    if name.startswith(('ghost_unet_', 'ghost_arcface_', 'simswap_')) or name in {'arcface_simswap.onnx', '79999_iter.pth'}:
        yield models / 'simswap' / name
    if name in upscale:
        yield models / 'onnx' / 'upscalers' / name
    if name in restore:
        yield models / 'onnx' / 'face_restore' / name
    if name in colorize:
        yield models / 'onnx' / 'colorize' / name
    if name in segment:
        yield models / 'onnx' / 'segmentation' / name
    if name in {'occluder.onnx', 'XSeg_model.onnx'}:
        # This specific node requires its own model path.
        yield comfy / 'custom_nodes' / 'OcclusionMask' / 'models' / name
    if name in face_detection:
        yield models / 'onnx' / 'face_analysis' / name
    if name.endswith('.onnx') and not (
        name in live | upscale | restore | colorize | segment | face_detection | buffalo
        or name == 'inswapper_128.fp16.onnx'
        or name.startswith(('ghost_unet_', 'ghost_arcface_', 'simswap_'))
        or name == 'arcface_simswap.onnx'
    ):
        yield models / 'onnx' / 'other' / name

api = HfApi(token=token)
paths = sorted(
    (name for name in api.list_repo_files(repo_id=repo, revision=revision)
     if name != '.gitattributes' and (include_native or not name.endswith('.so'))),
    key=lambda s: (not s.startswith('liveportrait_onnx/'), s.casefold()),
)
print(f'\nRepo: {repo}@{revision}', flush=True)
print(f'Files to download: {len(paths)}, archive: {archive}', flush=True)
print('WARNING: ~12 GB of models; keep enough free disk. Models do not all share the same loader.', flush=True)

failures = []
for i, remote_name in enumerate(paths, 1):
    print(f'\n[{i}/{len(paths)}] {remote_name}', flush=True)
    for attempt in range(1, 4):
        try:
            local = Path(hf_hub_download(
                repo_id=repo, filename=remote_name, revision=revision,
                local_dir=str(archive), token=token,
            ))
            if not local.is_file() or local.stat().st_size == 0:
                raise RuntimeError('missing or zero-length download')
            for dest in destinations(remote_name):
                link_model(local, dest)
            break
        except Exception as exc:
            print(f'[ERROR] attempt {attempt}: {type(exc).__name__}: {exc}', flush=True)
            if attempt == 3:
                failures.append(remote_name)
            else:
                time.sleep(3 * attempt)

print('\n=== OwlMaster install report ===')
print('Archive:', archive)
print('New links:', n_linked, '| existing links:', n_existing, '| conflicts left untouched:', n_conflicts)
print('Failures:', len(failures))
for f in failures:
    print(' FAILED:', f)
print('LivePortrait ONNX files are staged at models/liveportrait_onnx.')
print('Kijai LivePortrait nodes use separate safetensors weights, NOT these ONNX files.')
print('Generic ComfyUI-ONNX handles image-to-image models only; it does not make every ONNX runnable.')
if failures:
    sys.exit(1)
PY

fi

# --------------------------------------------------
# Previous Hugging Face downloads (authenticated, optional LEGACY_MODELS=0)
# --------------------------------------------------
download_model() {
    URL="$1"
    DEST="$2"
    mkdir -p "$(dirname "$DEST")"
    if [ -s "$DEST" ]; then
        echo "Already present: $DEST"
        return
    fi
    echo "Downloading $(basename "$DEST")"
    curl --fail --location --retry 5 --retry-delay 5 --continue-at - \
        -H "Authorization: Bearer ${HF_TOKEN}" \
        --output "$DEST" "$URL"
}


if [ "${LEGACY_MODELS:-1}" = "1" ]; then
download_model "https://huggingface.co/beznogim666/gonzalomo-krea-2/resolve/main/gonzalomoKrea2_v10.safetensors" "$COMFY/models/checkpoints/krea2.safetensors"
download_model "https://huggingface.co/orcarouter/Qwen3.8-27B-Uncensored-GGUF/resolve/main/Qwen3.8-27B-Uncensored-F16-00001-of-00002.gguf" "$COMFY/models/llm/Qwen3.8-27B-Uncensored-01-of-02.gguf"
download_model "https://huggingface.co/orcarouter/Qwen3.8-27B-Uncensored-GGUF/resolve/main/Qwen3.8-27B-Uncensored-F16-00002-of-00002.gguf" "$COMFY/models/llm/Qwen3.8-27B-Uncensored-02-of-02.gguf"
download_model "https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/v23/Qwen-Rapid-AIO-NSFW-v23.safetensors" "$COMFY/models/checkpoints/qwen-image.safetensors"
download_model "https://huggingface.co/Phr00t/WAN2.2-14B-Rapid-AllInOne/resolve/main/Mega-v12/wan2.2-rapid-mega-aio-nsfw-v12.safetensors" "$COMFY/models/checkpoints/wan22_i2v.safetensors"
download_model "https://huggingface.co/orcarouter/Qwen3.8-27B-Uncensored-GGUF/resolve/main/mmproj-Qwen3.8-27B-Uncensored-f16.gguf" "$COMFY/models/llm/mmproj-Qwen3.8-27B-Uncensored-f16.gguf"
# Removed invalid `download_model ""` call present in original (crashed with set -u).
download_model "https://huggingface.co/zootkitty/nsfw_wan_umt5-xxl_bf16_fixed/resolve/main/nsfw_wan_umt5-xxl_bf16_fixed.safetensors" "$COMFY/models/clip/nsfw-umt5_xxl.safetensors"
fi

# --------------------------------------------------
# Qwen3-VL 8B Aggressive Q8_0 (~8.2 GB) for ComfyUI QwenVL-Mod
# Kept SEPARATE from the ~55 GB Qwen3.8 coding-bot model above.
# Vision support needs BOTH the Q8_0 GGUF and its mmproj (~1.1 GB).
# QwenVL-Mod scans models/LLM/GGUF recursively for local model/projector pairs.
# Set QWEN_VL8_DOWNLOAD=0 to skip on an individual provisioning run.
# --------------------------------------------------
if [ "${QWEN_VL8_DOWNLOAD:-1}" = "1" ]; then
    QWEN_VL8_REPO="https://huggingface.co/HauhauCS/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive/resolve/main"
    QWEN_VL8_DIR="$COMFY/models/LLM/GGUF/HauhauCS/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive"
    download_model "$QWEN_VL8_REPO/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf" \
        "$QWEN_VL8_DIR/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf"
    download_model "$QWEN_VL8_REPO/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive-mmproj-f16.gguf" \
        "$QWEN_VL8_DIR/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive-mmproj-f16.gguf"
fi

# --------------------------------------------------
# LM Studio model
# --------------------------------------------------
if command -v lms >/dev/null 2>&1; then
    lms daemon up || true
    lms get HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF || true
else
    echo "WARNING: lms command not found after install."
fi

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

echo "========================================"
echo " Custom provisioning complete"
echo "========================================"