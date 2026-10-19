#!/usr/bin/env bash
# OwlMaster/AllFilesRope model downloader + ComfyUI model router.
# Run AFTER activating the same Python environment that ComfyUI uses.
# Bash-compatible; all downloads are resumable through huggingface_hub.
set -Eeuo pipefail

COMFY="${COMFY:-/workspace/ComfyUI}"
ROPE_REPO="${ROPE_REPO:-OwlMaster/AllFilesRope}"
ROPE_REVISION="${ROPE_REVISION:-main}"
ROPE_INCLUDE_NATIVE_PLUGIN="${ROPE_INCLUDE_NATIVE_PLUGIN:-0}"
export COMFY ROPE_REPO ROPE_REVISION ROPE_INCLUDE_NATIVE_PLUGIN

mkdir -p "$COMFY/models" "$COMFY/custom_nodes"
python -m pip install -q 'huggingface_hub>=0.32,<2' hf_xet

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