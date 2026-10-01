"""Generate S-311 concept variations with the local ComfyUI image-to-image API.

Uses only Python's standard library. Retains the official Z-Image Turbo sampler
settings and conditions its latent on the explicitly authorized imagegen draft.
Saves the complete submitted workflow and prompt ID before waiting for output.
Use --resume PROMPT_ID to fetch an already queued result without generating again.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time
import urllib.parse
import urllib.request
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from comfy_generate import build_workflow, _request  # noqa: E402


PROMPT = (
    "A clean studio reference board of continuous translucent milky gelatin figures. "
    "Preserve the supplied board's exact composition, fourteen full-body figures, "
    "silhouettes, colors, poses and spherical featureless heads. "
    "Top row: Delgada front, side and back; Flaca front, side and back; "
    "short broad extreme; tall fine extreme. Bottom row: six identical Delgada "
    "front views in lavender milk, strawberry pink, lime, grape, orange and sky blue. "
    "Every arm ends in one smooth rounded mitten mass with one inward thumb lobe. "
    "Every leg continues smoothly into a rounded flat-bottomed foot. "
    "All surfaces are uninterrupted soft jelly with tiny bubbles, dense pale rims, "
    "clear transmission and rectangular studio-window highlights. "
    "White background and pale soft contact shadows."
)


def upload_image(source: Path) -> str:
    boundary = "----ComfyGuided" + uuid.uuid4().hex
    filename = "s311_guided_" + source.name
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; "
        f"filename=\"{filename}\"\r\nContent-Type: image/png\r\n\r\n"
    ).encode() + source.read_bytes()
    body += (
        f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"type\"\r\n\r\ninput"
        f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue"
        f"\r\n--{boundary}--\r\n"
    ).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:8188/upload/image", data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=60) as response:
        result = json.load(response)
    return "/".join(part for part in (result.get("subfolder", ""), result["name"]) if part)


def guided_workflow(uploaded: str, seed: int, denoise: float) -> dict:
    workflow = build_workflow(PROMPT, 1664, 960, seed, "s311_guided")
    workflow["source"] = {"class_type": "LoadImage", "inputs": {"image": uploaded}}
    workflow["resize"] = {
        "class_type": "ImageScale", "inputs": {
            "image": ["source", 0], "upscale_method": "lanczos",
            "width": 1664, "height": 960, "crop": "disabled",
        },
    }
    workflow["latent"] = {
        "class_type": "VAEEncode", "inputs": {"pixels": ["resize", 0], "vae": ["vae", 0]},
    }
    workflow["sample"]["inputs"]["denoise"] = denoise
    return workflow


def fetch_result(prompt_id: str, target: Path, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        history = json.loads(_request(f"/history/{prompt_id}"))
        if prompt_id in history:
            entry = history[prompt_id]
            if entry.get("status", {}).get("status_str") == "error":
                raise RuntimeError(json.dumps(entry["status"].get("messages", []))[:4000])
            images = entry.get("outputs", {}).get("save", {}).get("images", [])
            if not images:
                raise RuntimeError(f"Prompt {prompt_id} completed without an image")
            target.write_bytes(_request("/view?" + urllib.parse.urlencode(images[0])))
            print(f"Saved {target}", flush=True)
            return True
        time.sleep(1.5)
    print(f"Still queued: {prompt_id}; resume with --resume {prompt_id}", flush=True)
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).with_name("concept_sheet_guidance_v3.png"))
    parser.add_argument("--out", type=Path, default=Path(__file__).with_name("comfy") / "guidance_v3")
    parser.add_argument("--seeds", type=int, nargs="+", default=[311071, 311072, 311073])
    parser.add_argument("--denoise", type=float, default=0.15)
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--resume", help="Retrieve this existing prompt; requires exactly one --seeds value")
    args = parser.parse_args()
    if not 0.15 <= args.denoise <= 0.25:
        parser.error("This guided study is restricted to denoise 0.15–0.25")
    if args.resume and len(args.seeds) != 1:
        parser.error("--resume requires exactly one --seeds value")
    args.out.mkdir(parents=True, exist_ok=True)
    uploaded = upload_image(args.source) if not args.resume else None
    for seed in args.seeds:
        target = args.out / f"concept_guided_seed{seed}.png"
        if args.resume:
            prompt_id = args.resume
        else:
            workflow = guided_workflow(uploaded, seed, args.denoise)
            queued = json.loads(_request("/prompt", {"prompt": workflow, "client_id": str(uuid.uuid4())}))
            prompt_id = queued["prompt_id"]
            manifest = {
                "seed": seed, "denoise": args.denoise, "prompt_id": prompt_id,
                "source": str(args.source), "prompt": PROMPT, "workflow": workflow,
            }
            target.with_suffix(".json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            print(f"Queued seed={seed} denoise={args.denoise} prompt_id={prompt_id}", flush=True)
        if not fetch_result(prompt_id, target, args.timeout):
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
