#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

echo "=== Starting Headless AI Stack Provisioning ==="
cd /workspace

# 1. Install Base System Dependencies & Tools
apt-get update && apt-get install -y curl git apt-utils lsd fish ncdu rustup

# 2. Pull Third-Party Application Ecosystems                                                                                                                                echo "--- Installing Core Engines ---"
curl -fsSL https://opencode.ai/install | bash || true
curl -fsSL https://lmstudio.ai/install.sh | bash || true
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash || true

# 3. Setup Python Virtual Environment and Comfy-CLI
echo "--- Setting up Comfy Environment ---"
pip install --upgrade pip
uv pip install comfy-cli

# Initialize ComfyUI layout correctly via native installer to build local directory pathing
#comfy --skip-prompt install --nvidia

# 4. Generate Directory Enforcements & Structural Symlinks                                                                                                                  echo "--- Mapping Directory Infrastructure ---"
mkdir -p /workspace/.comfy/inputs
mkdir -p /workspace/.comfy/outputs
mkdir -p /workspace/.comfy/workflows

mkdir -p /workspace/ComfyUI/input
mkdir -p /workspace/ComfyUI/output
mkdir -p /workspace/ComfyUI/models/workflows
mkdir -p /workspace/ComfyUI/user/default/workflows
mkdir -p /workspace/ComfyUI/models/llm/GGUF/

# FIX 1: Linked directories themselves rather than the internal wildcard context
# Using the folder paths directly ensures Syncthing populates and maps cleanly
ln -sfn /workspace/.comfy/inputs /workspace/ComfyUI/input
ln -sfn /workspace/.comfy/outputs /workspace/ComfyUI/output
ln -sfn /workspace/.comfy/workflows /workspace/ComfyUI/models/workflows                                                                                                     ln -sfn /workspace/.comfy/workflows /workspace/ComfyUI/user/default/workflows
# Add this right after the lms installer finishes in Section 2:
ln -sf $HOME/.lmstudio/bin/lms /usr/local/bin/lms

# 5. Clone Must-Have Essential Custom Nodes
echo "--- Fetching Custom Nodes ---"
cd /workspace/ComfyUI/custom_nodes

# FIX 2: Fixed the double "git clone git clone" typo on the DonutNodes line
git clone https://github.com/DonutsDelivery/ComfyUI-DonutNodes.git donutnodes || true
git clone https://github.com/DemonNCoding/PromptGenerator12Columns.git || true
git clone https://github.com/artokun/comfyui-mcp-panel.git || true
git clone https://github.com/slahiri/ComfyUI-Workflow-Models-Downloader.git || true
git clone https://codeberg.org/Gourieff/comfyui-reactor-node.git || true
git clone https://github.com/BenjaMITM/Enhanced-Civicomfy.git || true
git clone https://github.com/huchukato/ComfyUI-QwenVL-Mod || true

export PATH="$HOME/.lmstudio/bin:$PATH"# Add this right after the lms installer finishes in Section 2:

# 6. Queue Headless Model Downloads via CLI Background Daemons
echo "--- Pre-Caching Core AI Weights ---"
# Start the server daemon natively in the background
lms server start --cors &
sleep 5

# Download primary models sequentially (downloads block synchronously, no sleeps needed)
lms download HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF --quantization IQ4_XS

cd /workspace/ComfyUI/models/checkpoints
curl -L -o krea2.safetensors "https://huggingface.co/beznogim666/gonzalomo-krea-2/resolve/main/gonzalomoKrea2_v10.safetensors"
curl -L -o flux2_klein.safetensors "https://huggingface.co/kkangnom/FLUX.2-klein-9B-Blitz-ComfyUI/resolve/main/DarkBeast-Klein9b-V2-BFS-FP8-ComfyUI.safetensors"
curl -L -o z-image.safetensors "https://huggingface.co/Zillis/moodyPornMix/resolve/main/moodyPornMix/moodyPornMix_zitV9.safetensors"
curl -L -o qwen-image.safetensors "https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/v23/Qwen-Rapid-AIO-NSFW-v23.safetensors"
curl -L -o wan22_i2v.safetensors "https://huggingface.co/Phr00t/WAN2.2-14B-Rapid-AllInOne/resolve/main/Mega-v12/wan2.2-rapid-mega-aio-nsfw-v12.safetensors"

cd /workspace/ComfyUI/models/llm                                                                                                                                            wget -O Qwen3VL-8B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf https://huggingface.co/tripolskypetr/Qwen3VL-Uncensored-Aggressive-GGUF/resolve/main/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf

cd GGUF                                                                                                                                                                     wget -O Qwen3VL-8B-Uncensored-HauhauCS-Balanced-mmproj-f16.gguf https://huggingface.co/tripolskypetr/Qwen3VL-Uncensored-Aggressive-GGUF/resolve/main/Qwen3VL-8B-Uncensored-HauhauCS-Balanced-mmproj-f16.gguf

# Open Wan2.2 Text Encoders / VAE slots
mkdir -p /workspace/ComfyUI/models/clip /workspace/ComfyUI/models/vae
cd /workspace/ComfyUI/models/clip
curl -L -o nsfw-umt5_xxl.safetensors "https://huggingface.co/zootkitty/nsfw_wan_umt5-xxl_bf16_fixed/resolve/main/nsfw_wan_umt5-xxl_bf16_fixed.safetensors"

curl https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish || true                                                                              curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher || truefisher install jorgebucaran/nvm.fish || true

echo "=== Setup Sequence Complete. Syncthing Listening, ComfyUI Ready ==="