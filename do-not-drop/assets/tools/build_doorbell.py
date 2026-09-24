"""Doorbell panel for the delivery houses (tareas de Nacho N-302, 2026-09-24).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_doorbell.py

A wall plate with a house-number window, an intercom grille, the bell push in
a ring, a name card and four screws. Each part is its own object, and the
names are the contract with delivery_house.gd:

  Plate       the backplate
  NumberPlate the window the house number is written on (a Label3D in Godot),
              lit from behind while the house waits for a box
  Button      the bell push, glowing while the house waits
  ButtonRing, Speaker, NameCard, Screw   detail

Unlike the rest of the kit the origin is the centre of the plate's back,
where it meets the wall (it hangs on a wall, it doesn't stand on the
ground); front on Blender +Y (Godot -Z), metres.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from lowpoly_kit import PALETTE, ROOT, clear, cube, cylinder, export, triangle_count  # noqa: E402

PALETTE.update({
    # Linear values, like the rest of the kit.
    "doorbell_plate": (0.035, 0.05, 0.058, 1),   # #35434a, the old placeholder's colour
    "doorbell_button": (0.79, 0.52, 0.08, 1),    # WARNING #e7be51
})

PLATE = (0.12, 0.028, 0.26)
OUT = os.path.join(ROOT, "models", "environment", "props", "sm_env_prop_doorbell_panel.glb")


def doorbell_panel():
    # 12 cm wide, like a real one: it has to fit between the door frame and
    # the cottage's shutter (a 13.5 cm strip of plain wall).
    clear()
    front = PLATE[1]
    cube("Plate", (0.0, front / 2.0, 0.0), PLATE, "doorbell_plate", 0.007)
    cube("NumberPlate", (0.0, front + 0.004, 0.08), (0.09, 0.008, 0.058), "sign_white", 0.003)
    for z in (0.032, 0.018, 0.004):
        cube("Speaker", (0.0, front + 0.001, z), (0.065, 0.004, 0.006), "sign_ink")
    along_y = (math.pi / 2.0, 0.0, 0.0)
    cylinder("ButtonRing", (0.0, front + 0.006, -0.045), 0.034, 0.012, "metal", 16, along_y)
    cylinder("Button", (0.0, front + 0.012, -0.045), 0.025, 0.024, "doorbell_button", 16, along_y)
    cube("NameCard", (0.0, front + 0.002, -0.1), (0.07, 0.004, 0.018), "sign_white")
    for x in (-0.046, 0.046):
        for z in (-0.116, 0.116):
            cylinder("Screw", (x, front + 0.002, z), 0.006, 0.004, "metal", 6, along_y)
    print("TRIANGLES doorbell_panel", triangle_count())
    export(OUT)


if __name__ == "__main__":
    doorbell_panel()
