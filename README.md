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
