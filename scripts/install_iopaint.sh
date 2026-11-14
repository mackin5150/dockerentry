#!/usr/bin/env bash
# IOPaint installer for Vast.ai GB10/aarch64. Standalone and provision.sh compatible.
# The original Sanster/IOPaint checkout is left untouched; this uses a modernized fork.
set -Eeuo pipefail

IOPAINT_REPO="${IOPAINT_REPO:-https://github.com/daraskme/IOpaint.git}"
IOPAINT_REF="${IOPAINT_REF:-modernize-2026}"
IOPAINT_HOME="${IOPAINT_HOME:-/workspace/IOPaintModern}"
IOPAINT_MODEL_DIR="${IOPAINT_MODEL_DIR:-/workspace/iopaint-models}"
IOPAINT_VENV="${IOPAINT_VENV:-$IOPAINT_HOME/.venv}"
IOPAINT_DOWNLOAD_SET="${IOPAINT_DOWNLOAD_SET:-all}"  # none | core | all
IOPAINT_PREWARM_PLUGINS="${IOPAINT_PREWARM_PLUGINS:-auto}"
IOPAINT_BUILD_WEB="${IOPAINT_BUILD_WEB:-1}"
IOPAINT_MIN_FREE_GB="${IOPAINT_MIN_FREE_GB:-20}"
IOPAINT_DEVICE="${IOPAINT_DEVICE:-auto}"  # auto | cuda | cpu
IOPAINT_PORT="${IOPAINT_PORT:-8080}"
IOPAINT_HOST="${IOPAINT_HOST:-127.0.0.1}"
IOPAINT_WARMUP_PORT="${IOPAINT_WARMUP_PORT:-18081}"
IOPAINT_WARMUP_TIMEOUT="${IOPAINT_WARMUP_TIMEOUT:-1800}"

case "$IOPAINT_DOWNLOAD_SET" in none|core|all) ;; *) echo '[ERROR] IOPAINT_DOWNLOAD_SET must be none, core or all' >&2; exit 2;; esac
case "$IOPAINT_DEVICE" in auto|cpu|cuda) ;; *) echo '[ERROR] IOPAINT_DEVICE must be auto, cpu or cuda' >&2; exit 2;; esac
case "$IOPAINT_PREWARM_PLUGINS" in auto|0|1) ;; *) echo '[ERROR] IOPAINT_PREWARM_PLUGINS must be auto, 0 or 1' >&2; exit 2;; esac
if [[ "$IOPAINT_PREWARM_PLUGINS" == auto ]]; then
  if [[ "$IOPAINT_DOWNLOAD_SET" == all ]]; then IOPAINT_PREWARM_PLUGINS=1; else IOPAINT_PREWARM_PLUGINS=0; fi
fi

for executable in git python3 curl; do
  command -v "$executable" >/dev/null 2>&1 || { echo "[ERROR] Missing $executable" >&2; exit 1; }
done

mkdir -p "$IOPAINT_MODEL_DIR" "$(dirname "$IOPAINT_HOME")"
# IOPaint uses three download mechanisms; keep every cache on persistent storage.
export XDG_CACHE_HOME="$IOPAINT_MODEL_DIR"
export HF_HOME="$IOPAINT_MODEL_DIR/huggingface"
export TORCH_HOME="$IOPAINT_MODEL_DIR/torch"
export U2NET_HOME="$IOPAINT_MODEL_DIR/u2net"
mkdir -p "$HF_HOME" "$TORCH_HOME" "$U2NET_HOME"

check_space() {
  local free_kb required_kb
  free_kb="$(df -Pk "$IOPAINT_MODEL_DIR" | awk 'NR==2 {print $4}')"
  required_kb=$((IOPAINT_MIN_FREE_GB * 1024 * 1024))
  if [[ -z "$free_kb" || "$free_kb" -lt "$required_kb" ]]; then
    echo "[ERROR] Less than ${IOPAINT_MIN_FREE_GB} GiB free on IOPaint model volume; stopping before it fills." >&2
    return 1
  fi
}

if [[ ! -d "$IOPAINT_HOME/.git" ]]; then
  if [[ -e "$IOPAINT_HOME" && -n "$(ls -A "$IOPAINT_HOME" 2>/dev/null)" ]]; then
    echo "[ERROR] $IOPAINT_HOME exists and is not a git checkout; refusing overwrite." >&2
    exit 1
  fi
  git clone --depth 1 --branch "$IOPAINT_REF" "$IOPAINT_REPO" "$IOPAINT_HOME"
else
  origin="$(git -C "$IOPAINT_HOME" remote get-url origin)"
  if [[ "$origin" != "$IOPAINT_REPO" ]]; then
    echo "[ERROR] Existing checkout uses $origin, not $IOPAINT_REPO; refusing to modify it." >&2
    exit 1
  fi
  echo '[OK] Existing IOPaint source retained (no automatic git pull).'
fi

if [[ ! -x "$IOPAINT_VENV/bin/python" ]]; then
  python3 -m venv "$IOPAINT_VENV"
fi
PYTHON="$IOPAINT_VENV/bin/python"
"$PYTHON" -m pip install -q --upgrade pip uv
UV="$IOPAINT_VENV/bin/uv"

# Isolated CUDA-aware torch: do not touch /venv/main (ComfyUI).
if ! "$PYTHON" -c 'import torch, torchvision' >/dev/null 2>&1; then
  "$UV" pip install --python "$PYTHON" --torch-backend auto torch torchvision
fi
"$UV" pip install --python "$PYTHON" -e "${IOPAINT_HOME}[plugins,web-config]"
IOPAINT_BIN="$IOPAINT_VENV/bin/iopaint"
[[ -x "$IOPAINT_BIN" ]] || { echo '[ERROR] IOPaint executable not installed' >&2; exit 1; }

if [[ "$IOPAINT_DEVICE" == auto ]]; then
  if "$PYTHON" -c 'import torch; assert torch.cuda.is_available()' >/dev/null 2>&1; then
    IOPAINT_DEVICE=cuda
  else
    IOPAINT_DEVICE=cpu
    if command -v nvidia-smi >/dev/null 2>&1; then
      echo '[WARN] NVIDIA GPU found but isolated PyTorch has no working CUDA backend.' >&2
      echo '[WARN] IOPaint can run on CPU; install a compatible aarch64 CUDA PyTorch wheel in the IOPaint venv for GPU.' >&2
    fi
  fi
fi
if [[ "$IOPAINT_DEVICE" == cuda ]]; then
  "$PYTHON" -c 'import torch; assert torch.cuda.is_available(), "CUDA PyTorch unavailable in IOPaint venv"'
fi

# Build the frontend for a source/editable install (an sdist alone may not ship built assets).
if [[ "$IOPAINT_BUILD_WEB" == 1 ]]; then
  command -v npm >/dev/null 2>&1 || { echo '[ERROR] npm needed to build IOPaint web UI' >&2; exit 1; }
  node_major="$(node -p 'process.versions.node.split(".")[0]')"
  if (( node_major < 22 )); then
    echo "[INFO] Found Node $(node -v); installing isolated Node 22 for the IOPaint frontend."
    npm install --prefix "$IOPAINT_HOME/.node22" --no-package-lock --no-save node@22
    export PATH="$IOPAINT_HOME/.node22/node_modules/node/bin:$PATH"
    node_major="$(node -p 'process.versions.node.split(".")[0]')"
    if (( node_major < 22 )); then
      echo '[ERROR] Could not set up Node 22 for the IOPaint frontend' >&2
      exit 1
    fi
  fi
  if [[ -f "$IOPAINT_HOME/web_app/package-lock.json" ]]; then
    npm --prefix "$IOPAINT_HOME/web_app" ci
  else
    npm --prefix "$IOPAINT_HOME/web_app" install
  fi
  npm --prefix "$IOPAINT_HOME/web_app" run build
  if [[ -d "$IOPAINT_HOME/web_app/dist" ]]; then
    mkdir -p "$IOPAINT_HOME/iopaint/web_app"
    cp -a "$IOPAINT_HOME/web_app/dist/." "$IOPAINT_HOME/iopaint/web_app/"
  else
    echo '[ERROR] UI build completed without web_app/dist' >&2; exit 1
  fi
fi

# Each erase model uses IOPaint's own downloader and checksum/cache conventions.
failures=0
fetch_model() {
  local model="$1"
  check_space || return 1
  echo "[MODEL] $model"
  if ! "$IOPAINT_BIN" download --model "$model" --model-dir "$IOPAINT_MODEL_DIR"; then
    echo "[WARN] Could not download model: $model" >&2
    failures=$((failures+1))
  fi
}

if [[ "$IOPAINT_DOWNLOAD_SET" != none ]]; then
  # Also includes cv2, which requires no checkpoint.
  for model in lama ldm zits mat fcf manga cv2 migan; do
    fetch_model "$model"
  done
fi

if [[ "$IOPAINT_DOWNLOAD_SET" == all ]]; then
  # Official maintained list, instead of guessing arbitrary Hugging Face repositories.
  mapfile -t diffusion_models < <("$PYTHON" - <<'PY'
from iopaint.const import DIFFUSION_MODELS, INSTRUCT_PIX2PIX_NAME, KANDINSKY22_NAME
for item in dict.fromkeys([*DIFFUSION_MODELS, INSTRUCT_PIX2PIX_NAME, KANDINSKY22_NAME]):
    print(item)
PY
)
  for model in "${diffusion_models[@]}"; do
    fetch_model "$model"
  done
  # Extra components used by ControlNet/BrushNet. These are repos of weights, not
  # executable standalone diffusion pipelines, so fetch using HF Hub directly.
  mapfile -t auxiliary_models < <("$PYTHON" - <<'PY'
from iopaint import const
names = ('SD_CONTROLNET_CHOICES', 'SD_BRUSHNET_CHOICES', 'SD2_CONTROLNET_CHOICES',
         'SDXL_CONTROLNET_CHOICES', 'SDXL_BRUSHNET_CHOICES')
for item in dict.fromkeys(x for name in names for x in getattr(const, name, [])):
    print(item)
PY
)
  for model in "${auxiliary_models[@]}"; do
    check_space
    echo "[AUX] $model"
    if ! "$PYTHON" - "$model" <<'PY'
import sys
from huggingface_hub import snapshot_download
# Preserve Hugging Face's standard cache layout; future model loads can find it.
snapshot_download(repo_id=sys.argv[1], max_workers=4)
PY
    then
      echo "[WARN] Could not download auxiliary component: $model" >&2
      failures=$((failures+1))
    fi
  done
fi

# Warm all six built-in plugin families at once so their default weights are cached.
# Additional variants (SAM3 gated, BiRefNet choices, etc.) remain on-demand.
if [[ "$IOPAINT_PREWARM_PLUGINS" == 1 ]]; then
  check_space
  warmup_log="$IOPAINT_HOME/iopaint-plugin-warmup.log"
  echo "[INFO] Prewarming plugin default checkpoints; log: $warmup_log"
  "$IOPAINT_BIN" start --host 127.0.0.1 --port "$IOPAINT_WARMUP_PORT" \
    --model lama --device "$IOPAINT_DEVICE" --model-dir "$IOPAINT_MODEL_DIR" \
    --enable-interactive-seg --interactive-seg-device "$IOPAINT_DEVICE" \
    --enable-remove-bg --remove-bg-device "$IOPAINT_DEVICE" \
    --enable-anime-seg \
    --enable-realesrgan --realesrgan-device "$IOPAINT_DEVICE" \
    --enable-gfpgan --gfpgan-device "$IOPAINT_DEVICE" \
    --enable-restoreformer --restoreformer-device "$IOPAINT_DEVICE" \
    > "$warmup_log" 2>&1 &
  warmup_pid=$!
  warmup_ok=0
  for (( elapsed=0; elapsed<IOPAINT_WARMUP_TIMEOUT; elapsed+=5 )); do
    if curl --silent --fail --max-time 2 "http://127.0.0.1:${IOPAINT_WARMUP_PORT}/" >/dev/null; then
      warmup_ok=1; break
    fi
    if ! kill -0 "$warmup_pid" 2>/dev/null; then break; fi
    sleep 5
  done
  kill "$warmup_pid" 2>/dev/null || true
  wait "$warmup_pid" 2>/dev/null || true
  if [[ "$warmup_ok" == 1 ]]; then
    echo '[OK] All plugin families initialized; default model weights were requested.'
  else
    echo "[WARN] Plugin warmup failed or timed out. See $warmup_log" >&2
    failures=$((failures+1))
  fi
fi

# A saved launcher avoids repeating all plugin flags. Local-only bind by default;
# set IOPAINT_HOST=0.0.0.0 explicitly if remote access is intended and secured.
launcher="$IOPAINT_HOME/start-all-plugins.sh"
cat > "$launcher" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
IOPAINT_HOME="${IOPAINT_HOME:-/workspace/IOPaintModern}"
IOPAINT_MODEL_DIR="${IOPAINT_MODEL_DIR:-/workspace/iopaint-models}"
IOPAINT_VENV="${IOPAINT_VENV:-$IOPAINT_HOME/.venv}"
export XDG_CACHE_HOME="$IOPAINT_MODEL_DIR"
export HF_HOME="$IOPAINT_MODEL_DIR/huggingface"
export TORCH_HOME="$IOPAINT_MODEL_DIR/torch"
export U2NET_HOME="$IOPAINT_MODEL_DIR/u2net"
IOPAINT_DEVICE="${IOPAINT_DEVICE:-auto}"
if [[ "$IOPAINT_DEVICE" == auto ]]; then
  if "$IOPAINT_VENV/bin/python" -c 'import torch; assert torch.cuda.is_available()' >/dev/null 2>&1; then
    IOPAINT_DEVICE=cuda
  else
    IOPAINT_DEVICE=cpu
  fi
fi
exec "$IOPAINT_VENV/bin/iopaint" start \
  --host "${IOPAINT_HOST:-127.0.0.1}" --port "${IOPAINT_PORT:-8080}" \
  --model "${IOPAINT_MODEL:-lama}" --model-dir "$IOPAINT_MODEL_DIR" \
  --device "$IOPAINT_DEVICE" \
  --enable-interactive-seg --interactive-seg-device "$IOPAINT_DEVICE" \
  --enable-remove-bg --remove-bg-device "$IOPAINT_DEVICE" \
  --enable-anime-seg \
  --enable-realesrgan --realesrgan-device "$IOPAINT_DEVICE" \
  --enable-gfpgan --gfpgan-device "$IOPAINT_DEVICE" \
  --enable-restoreformer --restoreformer-device "$IOPAINT_DEVICE" \
  "$@"
SH
chmod +x "$launcher"

echo "[OK] IOPaint environment: $IOPAINT_VENV"
echo "[OK] Model cache: $IOPAINT_MODEL_DIR"
echo "[OK] Launch: bash '$launcher'"
echo "[INFO] Download set: $IOPAINT_DOWNLOAD_SET; failures: $failures"
echo '[INFO] Public host binding is disabled by default for safety.'
if (( failures > 0 )); then
  echo "[WARN] Some model or plugin checkpoints could not be cached; rerunning resumes downloads." >&2
  exit 1
fi
