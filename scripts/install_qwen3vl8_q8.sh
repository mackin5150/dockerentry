#!/usr/bin/env bash
# Standalone Qwen3-VL-8B Aggressive Q8_0 + vision projector installer.
# Same paths used in provision_with_rope_v2.sh.
set -Eeuo pipefail

COMFY="${COMFY:-/workspace/ComfyUI}"
QWEN_VL8_DIR="$COMFY/models/LLM/GGUF/HauhauCS/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive"
export QWEN_VL8_DIR

if [ -f /venv/main/bin/activate ]; then
    source /venv/main/bin/activate
fi
python -m pip install -q 'huggingface_hub>=0.32,<2' hf_xet
python - <<'PY'
import os
from pathlib import Path
from huggingface_hub import hf_hub_download

repo = 'HauhauCS/Qwen3VL-8B-Uncensored-HauhauCS-Aggressive'
files = [
    'Qwen3VL-8B-Uncensored-HauhauCS-Aggressive-Q8_0.gguf',
    'Qwen3VL-8B-Uncensored-HauhauCS-Aggressive-mmproj-f16.gguf',
]
target = Path(os.environ['QWEN_VL8_DIR'])
target.mkdir(parents=True, exist_ok=True)
for filename in files:
    print(f'Downloading or verifying {filename}', flush=True)
    result = hf_hub_download(repo_id=repo, filename=filename,
                             local_dir=str(target),
                             token=os.getenv('HF_TOKEN') or None)
    print('Ready:', result, flush=True)
print('Qwen3-VL 8B Q8 and mmproj installed for ComfyUI-QwenVL-Mod.')
PY