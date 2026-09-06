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
    curl wget git fish ncdu ca-certificates

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
curl -fsSL https://opencode.ai/install | bash || true
curl -fsSL https://lmstudio.ai/install.sh | bash || true
export PATH="/root/.local/bin:/root/.lmstudio/bin:/root/.opencode/bin:$PATH"

# --------------------------------------------------
# ComfyUI folders
# --------------------------------------------------
mkdir -p \
    "$COMFY/input" \
    "$COMFY/output" \
    "$COMFY/models/checkpoints" \
    "$COMFY/models/clip" \
    "$COMFY/models/vae" \
    "$COMFY/models/llm/GGUF" \
    "$COMFY/user/default/workflows" \
    "$COMFY/custom_nodes"

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
# Hugging Face download helper (authenticated)
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

download_model "https://huggingface.co/beznogim666/gonzalomo-krea-2/resolve/main/gonzalomoKrea2_v10.safetensors" "$COMFY/models/checkpoints/krea2.safetensors"
download_model "https://huggingface.co/kkangnom/FLUX.2-klein-9B-Blitz-ComfyUI/resolve/main/DarkBeast-Klein9b-V2-BFS-FP8-ComfyUI.safetensors" "$COMFY/models/checkpoints/flux2_klein.safetensors"
download_model "https://huggingface.co/Zillis/moodyPornMix/resolve/main/moodyPornMix/moodyPornMix_zitV9.safetensors" "$COMFY/models/checkpoints/z-image.safetensors"
download_model "https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/v23/Qwen-Rapid-AIO-NSFW-v23.safetensors" "$COMFY/models/checkpoints/qwen-image.safetensors"
download_model "https://huggingface.co/Phr00t/WAN2.2-14B-Rapid-AllInOne/resolve/main/Mega-v12/wan2.2-rapid-mega-aio-nsfw-v12.safetensors" "$COMFY/models/checkpoints/wan22_i2v.safetensors"
download_model "https://huggingface.co/tripolskypetr/Qwen3VL-Uncensored-Aggressive-GGUF/resolve/main/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf" "$COMFY/models/llm/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
download_model "https://huggingface.co/tripolskypetr/Qwen3VL-Uncensored-Aggressive-GGUF/resolve/main/Qwen3VL-8B-Uncensored-HauhauCS-Balanced-mmproj-f16.gguf" "$COMFY/models/llm/GGUF/Qwen3VL-8B-Uncensored-HauhauCS-Balanced-mmproj-f16.gguf"
download_model "https://huggingface.co/zootkitty/nsfw_wan_umt5-xxl_bf16_fixed/resolve/main/nsfw_wan_umt5-xxl_bf16_fixed.safetensors" "$COMFY/models/clip/nsfw-umt5_xxl.safetensors"

# --------------------------------------------------
# LM Studio model
# --------------------------------------------------
if command -v lms >/dev/null 2>&1; then
    lms daemon up || true
    lms get HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF || true
else
    echo "WARNING: lms command not found after install."
fi

echo "========================================"
echo " Custom provisioning complete"
echo "========================================"
