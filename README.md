# dockerentry

Provisioning scripts for a Vast.ai ComfyUI environment.

## Main script

`provision.sh` runs the existing tool installs and ComfyUI custom-node setup, and now includes:
- OwlMaster/AllFilesRope ONNX models, with non-destructive routing into ComfyUI model directories.
- HauhauCS Qwen3-VL 8B **Q8_0** GGUF and its vision projector for ComfyUI-QwenVL-Mod.
- The existing two-shard ~55 GB Qwen3.8 27B F16 coding-bot GGUF downloads (not replaced).
- A **final**, noninteractive Fish setup for Oh My Fish, Fisher, nvm.fish and Pure Fish.

It is designed for `/workspace/ComfyUI` with Python in `/venv/main`, and requires the `HF_TOKEN` and `CIVITAI_API_TOKEN` environment variables for the main script.

Optional environment switches:
- `ROPE_DOWNLOAD=0`: skip the OwlMaster model set.
- `QWEN_VL8_DOWNLOAD=0`: skip Qwen3-VL 8B + mmproj.
- `LEGACY_MODELS=0`: skip pre-existing checkpoint/55 GB coding model downloads.
- `ENABLE_SIMSWAP_NODE=1`: opt into the older SimSwap custom node (may conflict with ReActor).
- `ENABLE_LIVEPORTRAIT_KJ=1`: opt into the LivePortraitKJ node (uses safetensors, not the OwlMaster ONNX models).

The full default model download can be tens of GB. Ensure sufficient persistent storage before running.

## IOPaint on GB10 / aarch64

`provision.sh` now calls `scripts/install_iopaint.sh` near the end (even when Vast downloaded only `provision.sh`). The installer creates a **separate virtual environment** for IOPaint, so IOPaint's modern PyTorch/diffusers/transformers packages do not replace ComfyUI's packages in `/venv/main`.

The original `/workspace/IOPaint` checkout is not modified. The installer clones the 2026-modernized [daraskme/IOpaint fork](https://github.com/daraskme/IOpaint) at branch `modernize-2026` into `/workspace/IOPaintModern`. It builds the frontend (using an isolated Node 22 when required) and installs its six built-in plugin families: Segment Anything, RemoveBG, anime segmentation, RealESRGAN, GFPGAN and RestoreFormer, plus web-config.

**Default provisioning:** `IOPAINT_INSTALL=1` and `IOPAINT_DOWNLOAD_SET=all`. The `all` set attempts all registered erase models, listed diffusion/guided-editing models, ControlNet/BrushNet auxiliary repositories, and a warmup of the six plugin families' default weights. These downloads can be **well over 100 GiB**, depending on the model repositories. A 20 GiB free-space guard stops new downloads before the volume is exhausted. Some repositories can be unavailable, gated, or incompatible; errors are reported rather than silently treated as success.

For a smaller boot or for reruns, use:

```bash
# Full installer, outside of a complete provision run
cd /workspace/dockerentry
bash scripts/install_iopaint.sh

# Core erase checkpoints only, skip the huge diffusion set
IOPAINT_DOWNLOAD_SET=core bash scripts/install_iopaint.sh

# Install application and all plugin dependencies, without prefetching models
IOPAINT_DOWNLOAD_SET=none bash scripts/install_iopaint.sh

# Disable IOPaint entirely during a full provision
IOPAINT_INSTALL=0 bash provision.sh
```

To start the web UI with **all six plugins enabled**:

```bash
bash /workspace/IOPaintModern/start-all-plugins.sh
```

The server binds to `127.0.0.1:8080` by default. Use an SSH tunnel to access it remotely; do not expose port 8080 publicly without authentication. To change a start model: `IOPAINT_MODEL=mat bash /workspace/IOPaintModern/start-all-plugins.sh`.

Settings: `IOPAINT_HOME`, `IOPAINT_MODEL_DIR`, `IOPAINT_VENV`, `IOPAINT_DEVICE` (`auto|cuda|cpu`), `IOPAINT_MIN_FREE_GB`, `IOPAINT_PREWARM_PLUGINS` (`0|1|auto`), `IOPAINT_BUILD_WEB`, `IOPAINT_HOST`, `IOPAINT_PORT`, and `IOPAINT_DOWNLOAD_SET` (`none|core|all`). The downloaded weights live under `/workspace/iopaint-models` by default, including the Hugging Face, Torch and RemoveBG caches. If you pass custom home/model paths, pass them to the launcher too.

**Scope:** `all` means IOPaint's documented/built-in model registries, not every third-party model on Hugging Face or every selectable variant of the plugin models. Extra plugin variants download when selected; gated models (for example SAM3) require acceptance of their license and Hugging Face authentication. An IOPaint CUDA torch wheel for GB10/aarch64 depends on wheel availability; the installer warns if it can only use CPU rather than assuming GPU acceleration.

## Standalone installers

Use these **instead of rerunning provisioning** when applying a single change to an already-configured Vast instance:

```bash
cd /workspace
git clone https://github.com/mackin5150/dockerentry.git
cd dockerentry
bash scripts/rope_models_only.sh
bash scripts/install_qwen3vl8_q8.sh
bash scripts/setup_fish_tools.sh
```

The Rope and Qwen installers are resumable and can skip files already present; Fish tool installation is best-effort and does not change the login shell. The Rope script requires that the same Python environment used by ComfyUI is active. If needed, run `source /venv/main/bin/activate` first.

`setup_fish_tools.sh` runs last in the full provisioner to avoid interactive installers interrupting provisioning.

## Important notes

- ONNX files are **organized for compatible consumers**; placing a file in a folder does not guarantee that a particular custom node can run that ONNX architecture.
- The Qwen3-VL GGUF needs the paired `mmproj` for vision. The older 27B GGUF remains dedicated to the local coding workflow.
- Large model weights and authentication secrets are not committed to this repository.
- Shell syntax checks have passed; full GPU provisioning and downloading have not been validated on a running Vast instance.
