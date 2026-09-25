#!/usr/bin/env python3
"""Turns a trailer shot's frames into a devlog GIF (tareas de Nacho N-906).

    godot --path do-not-drop --resolution 960x540 res://scenes/tools/trailer_shot.tscn \\
        -- --shot=vuelco --frames=/tmp/vuelco --fps=15
    python3 tools/devlog/make_gif.py /tmp/vuelco art/devlog/2026-09-25_vuelco.gif --fps 15 --width 640

pip install pillow. Frames are PNGs named frame_0000.png... (trailer_shot.gd
--frames); the GIF loops, one shared palette per clip so it doesn't flicker
-- taken from frames spread over the whole clip, not just one (a palette from
the middle frame tinted the first second green when the light changed) --
and is scaled to --width (social sites cap GIFs at a few MB).
"""
import argparse
import glob
import os

from PIL import Image


def shared_palette(frames, samples=8, colors=160):
    """One palette for the clip: quantize a strip of frames from across it."""
    picks = [frames[round(i * (len(frames) - 1) / max(samples - 1, 1))] for i in range(min(samples, len(frames)))]
    width, height = picks[0].size
    strip = Image.new("RGB", (width, height * len(picks)))
    for index, frame in enumerate(picks):
        strip.paste(frame, (0, index * height))
    return strip.quantize(colors=colors, method=Image.Quantize.MEDIANCUT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("frames")
    parser.add_argument("out")
    parser.add_argument("--fps", type=float, default=15.0)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--skip", type=int, default=2, help="frames to drop at the start (the scene settling)")
    args = parser.parse_args()
    paths = sorted(glob.glob(os.path.join(args.frames, "frame_*.png")))[args.skip:]
    if not paths:
        raise SystemExit("no frames in %s" % args.frames)
    frames = []
    for path in paths:
        image = Image.open(path).convert("RGB")
        height = round(image.height * args.width / image.width)
        frames.append(image.resize((args.width, height), Image.LANCZOS))
    palette = shared_palette(frames)
    quantized = [frame.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG) for frame in frames]
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    quantized[0].save(args.out, save_all=True, append_images=quantized[1:], loop=0,
                      duration=round(1000.0 / args.fps), optimize=True)
    print("%s: %d frames, %d KB" % (args.out, len(quantized), os.path.getsize(args.out) // 1024))


if __name__ == "__main__":
    main()
