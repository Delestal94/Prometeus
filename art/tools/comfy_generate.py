"""Generate images with the local ComfyUI + Z-Image Turbo, no MCP needed.

Mirrors the official ComfyUI template `image_z_image_turbo_int8`: 8 steps,
CFG 1, res_multistep/simple, AuraFlow shift 3, zeroed negative. The model is
distilled for exactly those values -- raising steps or CFG makes it worse.

    python art/tools/comfy_generate.py --prompt "..." --width 1344 --height 768 \
        --seeds 1 2 3 4 --out art/concept/menu --prefix menu_bg

Requires ComfyUI running (`comfy launch --background`) on 127.0.0.1:8188.
Only the standard library is used, so any Python 3.10+ works.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

SERVER = "http://127.0.0.1:8188"
UNET = "z_image_turbo_int8_convrot.safetensors"
CLIP = "qwen_3_4b_fp8_mixed.safetensors"
VAE = "ae.safetensors"


def build_workflow(prompt: str, width: int, height: int, seed: int, prefix: str) -> dict:
    return {
        "unet": {"class_type": "UNETLoader", "inputs": {"unet_name": UNET, "weight_dtype": "default"}},
        "shift": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["unet", 0], "shift": 3}},
        "clip": {"class_type": "CLIPLoader", "inputs": {"clip_name": CLIP, "type": "lumina2", "device": "default"}},
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": VAE}},
        "pos": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["clip", 0], "text": prompt}},
        "neg": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["pos", 0]}},
        "latent": {"class_type": "EmptySD3LatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "sample": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["shift", 0], "positive": ["pos", 0], "negative": ["neg", 0],
                "latent_image": ["latent", 0], "seed": seed, "steps": 8, "cfg": 1.0,
                "sampler_name": "res_multistep", "scheduler": "simple", "denoise": 1.0,
            },
        },
        "decode": {"class_type": "VAEDecode", "inputs": {"samples": ["sample", 0], "vae": ["vae", 0]}},
        "save": {"class_type": "SaveImage", "inputs": {"images": ["decode", 0], "filename_prefix": prefix}},
    }


def _request(path: str, payload: dict | None = None) -> bytes:
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(SERVER + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read()


def generate(prompt: str, width: int, height: int, seed: int, prefix: str, out_dir: Path) -> list[Path]:
    workflow = build_workflow(prompt, width, height, seed, prefix)
    queued = json.loads(_request("/prompt", {"prompt": workflow, "client_id": str(uuid.uuid4())}))
    prompt_id = queued["prompt_id"]
    deadline = time.time() + 900  # first run also loads ~12 GB of weights
    while time.time() < deadline:
        history = json.loads(_request(f"/history/{prompt_id}"))
        if prompt_id in history:
            entry = history[prompt_id]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise RuntimeError(json.dumps(status.get("messages", []))[:2000])
            saved: list[Path] = []
            for output in entry.get("outputs", {}).values():
                for image in output.get("images", []):
                    query = urllib.parse.urlencode(image)
                    target = out_dir / f"{prefix}_seed{seed}.png"
                    target.write_bytes(_request(f"/view?{query}"))
                    saved.append(target)
            return saved
        time.sleep(1.5)
    raise TimeoutError(f"ComfyUI did not finish prompt {prompt_id}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--width", type=int, default=1024)
    parser.add_argument("--height", type=int, default=1024)
    parser.add_argument("--seeds", type=int, nargs="*", help="one image per seed (random if omitted)")
    parser.add_argument("--count", type=int, default=1, help="random seeds to use when --seeds is omitted")
    parser.add_argument("--out", type=Path, default=Path("art/concept"))
    parser.add_argument("--prefix", default="img")
    args = parser.parse_args()

    if args.width % 64 or args.height % 64:
        parser.error("width and height must be multiples of 64")
    args.out.mkdir(parents=True, exist_ok=True)
    seeds = args.seeds or [random.randrange(2**48) for _ in range(args.count)]
    for seed in seeds:
        started = time.time()
        for path in generate(args.prompt, args.width, args.height, seed, args.prefix, args.out):
            print(f"{path}  seed={seed}  {time.time() - started:.1f}s", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
