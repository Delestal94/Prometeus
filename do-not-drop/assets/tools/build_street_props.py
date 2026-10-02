"""Street and roadside props for Take My Package (N-136 / N-140, 2026-09-27).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_street_props.py

then bake the AO back into the ones that carry it (test_baked_ao.gd):

    blender --background --factory-startup --python do-not-drop/assets/tools/bake_vertex_ao.py -- \
        do-not-drop/assets/models/vehicles/sm_vehicle_parked_hatchback.glb \
        do-not-drop/assets/models/vehicles/sm_vehicle_parked_pickup.glb \
        do-not-drop/assets/models/vehicles/sm_vehicle_tow_crane.glb \
        do-not-drop/assets/models/environment/landmarks/sm_env_landmark_windmill.glb \
        do-not-drop/assets/models/environment/landmarks/sm_env_landmark_water_tower.glb

Rebuilds the oldest low-poly batch (build_lowpoly_glb_assets*.py and the
roadside/yard part of build_lowpoly_refined.py) in the cartoon line of the
train (build_rail_crossing.py) and the depot (build_depot_props.py): chunky,
rounded, flat palette colours, a joke where it fits. Same file names, scale,
pivot and orientation as before, so no scene or script changes:

  Blender coordinates (Z up; the glTF exporter turns them into Godot's Y up,
  Blender +Y becomes Godot -Z, the side Facing.ROAD turns toward the road).
  Origin at the centre of the base, metres.

  vehicles/sm_vehicle_parked_{hatchback,pickup}.glb
      Length along X, nose toward -X, wheels on z = 0, 3.9 x 2.0 m. The front
      lamps are ONE mesh named "Light" with the palette material "lamp"
      (LowpolyMaterials.light_up() and NightFlares look for exactly that and
      split its two lamps); the tail lights are "TailLights" in "danger" and
      stay off. The route turns their bounding box into the collider.
  vehicles/sm_vehicle_tow_crane.glb (N-321, group "crane"): the mud tow
      truck of mud_crane.gd, same size as its old primitives. Unlike the
      parked cars it faces Godot -Z (Blender +Y), 2.6 x 6.0 m, wheels on
      z = 0; the boom leans back over +Z. Named meshes for the script:
      "Beacon" (amber dome, origin at its own centre (0, 2.55, -1.9) in
      Godot, so it spins and pulses in place; material "beacon", emissive),
      "Hook" (origin at its eye, (0, 2.05, 3.6) in Godot: HOOK_LOCAL hangs
      the cable from just under it), "Light" (headlights, "lamp") and
      "TailLights". The chassis sides stay flat and free at |x| = 1.30 around
      y = 1.05 for the "GRUA" Label3D boards. Built so the AO bake's 1 m
      subdivision doesn't blow it up (~2.0k tris, ~2.4k after the bake).
  environment/props/sm_env_prop_street_lamp_refined.glb (and the unused
      sm_env_prop_street_lamp.glb, same model): 4.6 m, arm toward +X.
      Materials "lamp_metal" and "lamp_glass" (the glass is one mesh: it glows
      at night and gets one halo at its centre).
  environment/landmarks/sm_env_landmark_windmill.glb: the sails hang from the
      empty "WindmillRotor" (route_dresser spins it about Godot's local Z =
      Blender +Y); they face +Y, the road.
  environment/landmarks/sm_env_landmark_water_tower.glb
  environment/props/sm_env_prop_{mailbox,milestone,wooden_crate,traffic_cone}.glb
  environment/yard/sm_env_yard_{garden_gnome,doormat}.glb

Pass group names after "--" to rebuild only some of them:
    blender --background --factory-startup --python build_street_props.py -- cars lamp
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from lowpoly_kit import (PALETTE, ROOT, blob, clear, cone, cube, cylinder,  # noqa: E402
                         export, flat_poly, mat, slab, triangle_count)


def srgb(hex_code):
    """Palette hex (as in docs/direccion-visual.md) to the linear RGBA the kit uses."""
    out = []
    for i in (0, 2, 4):
        c = int(hex_code[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


PALETTE.update({
    # Names the game already keys on keep their names; the colours of the
    # ones only these models use are free to move.
    "lamp_metal": srgb("2f4f4c"), "lamp_glass": srgb("f5c46a"),
    "brass": srgb("e8b43c"), "ui_yellow": srgb("ffc93c"),
    "logo_cardboard": srgb("e0a867"), "paper": srgb("fff6e6"),
    "danger_red": srgb("d8322b"), "ink": srgb("1e2235"),
    "water_tank": srgb("7fb7c6"), "tank_roof": srgb("3f6f7d"),
    "crate_board": srgb("dcae6a"), "gnome_coat": srgb("2f6fb5"),
    "gnome_nose": srgb("f08a78"), "boot": srgb("5a3a24"),
})

MODELS = os.path.join(ROOT, "models")
REPORT = []
ALONG_X = (0.0, math.pi / 2.0, 0.0)   # cylinder lying along X
ALONG_Y = (math.pi / 2.0, 0.0, 0.0)   # cylinder lying along Y


def done(*relative):
    REPORT.append((relative[0], triangle_count()))
    for rel in relative:
        export(os.path.join(MODELS, rel))


# --- Helpers (Blender coordinates) -----------------------------------------

def round_edges(o, width, segments=2, angle=40.0):
    """Rounds the sharp edges (above `angle` degrees) of `o` in place."""
    mod = o.modifiers.new("Round", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return o


def lathe(name, profile, sides, material, start=0.0, centre=(0.0, 0.0), caps=True, loop=False):
    """Revolves (radius, z) points about the vertical axis through `centre`.
    A radius of 0 is a single tip vertex; `loop` closes the profile back on
    itself (rings, rims) instead of capping it."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((centre[0], centre[1], z))])
        else:
            rings.append([bm.verts.new((centre[0] + r * math.cos(start + k * math.tau / sides),
                                        centre[1] + r * math.sin(start + k * math.tau / sides), z))
                          for k in range(sides)])
    pairs = list(zip(rings, rings[1:]))
    if loop:
        pairs.append((rings[-1], rings[0]))
    for a, b in pairs:
        if len(a) == 1 and len(b) == 1:
            continue
        for k in range(sides):
            j = (k + 1) % sides
            if len(a) == 1:
                bm.faces.new([a[0], b[k], b[j]])
            elif len(b) == 1:
                bm.faces.new([a[k], a[j], b[0]])
            else:
                bm.faces.new([a[k], a[j], b[j], b[k]])
    if caps and not loop:
        if len(rings[0]) > 1:
            bm.faces.new(list(reversed(rings[0])))
        if len(rings[-1]) > 1:
            bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def tube(name, rings, sides, material):
    """Horizontal rings (x, y, z, radius) stacked into one closed tube; a
    radius of 0 ends it in a tip (a bent gnome hat, a curled pipe)."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    loops = []
    for x, y, z, r in rings:
        if r <= 1e-6:
            loops.append([bm.verts.new((x, y, z))])
        else:
            loops.append([bm.verts.new((x + r * math.cos(k * math.tau / sides), y + r * math.sin(k * math.tau / sides), z))
                          for k in range(sides)])
    for a, b in zip(loops, loops[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            if len(b) == 1:
                bm.faces.new([a[k], a[j], b[0]])
            elif len(a) == 1:
                bm.faces.new([a[0], b[k], b[j]])
            else:
                bm.faces.new([a[k], a[j], b[j], b[k]])
    if len(loops[0]) > 1:
        bm.faces.new(list(reversed(loops[0])))
    if len(loops[-1]) > 1:
        bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def rod(name, a, b, radius, material, verts=6):
    """A round rod from point `a` to `b`."""
    pa, pb = Vector(a), Vector(b)
    d = pb - pa
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius, depth=d.length,
                                    location=(pa + pb) / 2.0)
    o = bpy.context.object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    o.data.materials.append(mat(material))
    return o


def bar(name, a, b, width, material, depth=None):
    """A square bar from point `a` to `b` (legs, braces)."""
    pa, pb = Vector(a), Vector(b)
    d = pb - pa
    bpy.ops.mesh.primitive_cube_add(location=(pa + pb) / 2.0)
    o = bpy.context.object
    o.name = name
    o.scale = (width / 2.0, (depth or width) / 2.0, d.length / 2.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    o.data.materials.append(mat(material))
    return o


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    return o


def arc(cx, cz, radius, a0, a1, steps):
    return [(cx + radius * math.cos(a0 + (a1 - a0) * i / steps), cz + radius * math.sin(a0 + (a1 - a0) * i / steps))
            for i in range(steps + 1)]


def rounded_rect(hx, hy, radius, steps=3):
    pts = []
    for cx, cy, a in ((hx - radius, hy - radius, 0.0), (-hx + radius, hy - radius, math.pi / 2),
                      (-hx + radius, -hy + radius, math.pi), (hx - radius, -hy + radius, math.pi * 1.5)):
        pts += arc(cx, cy, radius, a, a + math.pi / 2, steps)
    return pts


def tuft(x, y, size=1.0, seed=0.0):
    """A little clump of grass: three leaning blades."""
    for k in range(3):
        a = seed + k * math.tau / 3
        cone("GrassTuft", (x + math.cos(a) * 0.025 * size, y + math.sin(a) * 0.025 * size, 0.05 * size),
             0.028 * size, 0.0, 0.11 * size, "grass", 4, rot=(math.sin(a) * 0.35, -math.cos(a) * 0.35, a))


# =============================================================================
# Parked cars (N-136)
# =============================================================================

def _wheel_arch(cx, wheel_r, arch_r, bottom, steps=6):
    """Bottom-edge points of the body over a wheel, front to back."""
    a0 = math.asin((bottom - wheel_r) / arch_r)
    return arc(cx, wheel_r, arch_r, math.pi - a0, a0, steps)


def _wheel(x, side, radius):
    y = side * 0.83
    cylinder("Tyre", (x, y, radius), radius, 0.26, "rubber", 12, rot=ALONG_Y)
    cylinder("Hubcap", (x, side * 0.965, radius), radius * 0.55, 0.04, "sign_white", 8, rot=ALONG_Y)


def _cab_windows(front, back, top, belt, slope_top_x, side_windows, rear_window, paint):
    """Glass on a cab whose windscreen runs from (front, belt) to (slope_top_x, top)."""
    t0, t1 = 0.12, 0.86
    p0 = (front + (slope_top_x - front) * t0, belt + (top - belt) * t0)
    p1 = (front + (slope_top_x - front) * t1, belt + (top - belt) * t1)
    slab("Windshield", p0, p1, 1.34, 0.02, "window", 0.0, 1.0)
    rod("WiperL", (p0[0] + 0.05, -0.45, p0[1] + 0.035), (p0[0] + 0.2, -0.05, p0[1] + 0.2), 0.012, "ink", 4)
    rod("WiperR", (p0[0] + 0.05, 0.2, p0[1] + 0.035), (p0[0] + 0.2, 0.55, p0[1] + 0.2), 0.012, "ink", 4)
    for pts in side_windows:
        flat_poly("SideWindow", pts, 0.795, 0.015, "window")
        flat_poly("SideWindow", pts, -0.81, 0.015, "window")
    rear_window()


def parked_car(kind):
    clear()
    pickup = kind == "pickup"
    paint = "car_red" if pickup else "car_blue"
    radius = 0.4 if pickup else 0.37
    wheel_x = 1.26 if pickup else 1.2
    arch_r = radius + 0.08
    bottom = 0.27

    # Lower body: one side profile, arches cut in, rounded all round.
    if pickup:
        front = [(-1.9, 0.9), (-1.96, 0.74), (-1.97, 0.4), (-1.9, 0.28)]
        rear = [(1.9, 0.28), (1.96, 0.38), (1.96, 0.9), (0.52, 0.9), (0.52, 1.02), (-0.75, 1.03), (-1.55, 0.99)]
    else:
        front = [(-1.86, 0.84), (-1.95, 0.7), (-1.96, 0.4), (-1.88, 0.28)]
        rear = [(1.88, 0.28), (1.95, 0.4), (1.94, 0.97), (1.86, 1.0), (-0.9, 1.0), (-1.5, 0.95)]
    outline = front + _wheel_arch(-wheel_x, radius, arch_r, bottom) + _wheel_arch(wheel_x, radius, arch_r, bottom) + rear
    round_edges(flat_poly("CarBody", outline, -0.9, 1.8, paint), 0.09)

    # Cab: rounded box, glass set into it, pillars in body colour.
    if pickup:
        cab = [(-0.75, 1.0), (0.52, 1.0), (0.52, 1.62), (-0.22, 1.62), (-0.34, 1.57)]
        round_edges(flat_poly("Cabin", cab, -0.8, 1.6, paint), 0.08)
        _cab_windows(-0.75, 0.52, 1.57, 1.0, -0.34,
                     [[(-0.52, 1.08), (0.38, 1.08), (0.38, 1.52), (-0.25, 1.52)]],
                     lambda: cube("RearWindow", (0.53, 0, 1.3), (0.02, 1.1, 0.34), "window", 0.005), paint)
        # Roof light bar with amber lenses (not "lamp": only the headlights glow).
        cube("RoofBeacon", (-0.1, 0, 1.665), (0.22, 1.12, 0.08), "ink", 0.02)
        for y in (-0.39, -0.13, 0.13, 0.39):
            cube("BarLens", (-0.215, y, 1.665), (0.02, 0.18, 0.05), "warning")
        # Bed: walls on the lower body, dark liner, rail caps, cargo.
        for side in (-1.0, 1.0):
            cube("BedWall", (1.24, side * 0.84, 1.0), (1.44, 0.12, 0.22), paint)
            cube("BedRail", (1.24, side * 0.84, 1.12), (1.46, 0.15, 0.035), "guardrail")
        cube("BedFrontWall", (0.57, 0, 1.0), (0.1, 1.56, 0.22), paint)
        cube("Tailgate", (1.9, 0, 1.0), (0.12, 1.56, 0.22), paint)
        cube("TailgateHandle", (1.965, 0, 1.03), (0.02, 0.24, 0.05), "ink")
        cube("BedLiner", (1.24, 0, 0.908), (1.28, 1.56, 0.016), "rubber")
        # The delivery joke: someone else's parcel riding in the back.
        cube("Parcel", (1.5, -0.35, 1.1), (0.4, 0.4, 0.36), "logo_cardboard", rot=(0, 0, 0.25))
        cube("ParcelTape", (1.5, -0.35, 1.285), (0.42, 0.08, 0.012), "ui_yellow", rot=(0, 0, 0.25))
        cylinder("SpareTyre", (1.0, 0.36, 0.99), 0.3, 0.16, "rubber", 12)
        cylinder("SpareHub", (1.0, 0.36, 1.075), 0.15, 0.02, "sign_white", 10)
        # Square chrome grille and square "eyes".
        cube("Grille", (-1.975, 0, 0.6), (0.04, 0.66, 0.26), "guardrail")
        cube("GrilleMesh", (-1.99, 0, 0.6), (0.02, 0.56, 0.18), "ink")
        cube("GrilleBar", (-2.0, 0, 0.6), (0.02, 0.58, 0.035), "guardrail")
        lamps = [cube("LampL", (-1.975, side * 0.6, 0.64), (0.05, 0.26, 0.16), "lamp") for side in (-1.0, 1.0)]
        for side in (-1.0, 1.0):
            cube("LampBezel", (-1.955, side * 0.6, 0.64), (0.04, 0.3, 0.2), "guardrail")
        tails = [cube("Tail", (1.965, side * 0.72, 0.72), (0.04, 0.18, 0.24), "danger") for side in (-1.0, 1.0)]
        door_front, door_back, belt = -0.7, 0.46, 1.0
        mirror_x = -0.45
        cube("Bumper", (-1.98, 0, 0.3), (0.2, 1.9, 0.18), "guardrail", 0.05)
        cube("RearBumper", (1.97, 0, 0.3), (0.16, 1.86, 0.14), "guardrail", 0.04)
        cube("RearPlate", (1.965, 0, 0.56), (0.01, 0.36, 0.12), "sign_white")
        rod("TowBall", (2.05, 0, 0.3), (2.12, 0, 0.3), 0.035, "guardrail", 6)
    else:
        # Bubbly cab with a raked hatch at the back.
        cab = [(-0.85, 0.99), (1.9, 0.99), (1.88, 1.2), (1.5, 1.62), (0.05, 1.66), (-0.25, 1.56)]
        round_edges(flat_poly("Cabin", cab, -0.8, 1.6, paint), 0.09)
        _cab_windows(-0.85, 1.9, 1.56, 0.99, -0.25,
                     [[(-0.6, 1.06), (0.5, 1.06), (0.5, 1.54), (-0.1, 1.54)],
                      [(0.64, 1.06), (1.78, 1.06), (1.78, 1.2), (1.46, 1.54), (0.64, 1.56)]],
                     lambda: slab("RearWindow", (1.823, 1.263), (1.557, 1.557), 1.3, 0.02, "window", 0.0, -1.0), paint)
        # Two-tone roof, rails and a little ducktail spoiler.
        cube("Roof", (0.75, 0, 1.648), (1.4, 1.46, 0.05), "sign_white", rot=(0, 0.028, 0))
        for side in (-1.0, 1.0):
            rod("RoofRail", (0.1, side * 0.62, 1.73), (1.35, side * 0.62, 1.71), 0.025, "ink", 6)
            for x in (0.15, 1.3):
                cube("RailFoot", (x, side * 0.62, 1.69), (0.06, 0.05, 0.06), "ink")
        cube("Spoiler", (1.52, 0, 1.64), (0.3, 1.36, 0.05), paint, rot=(0, 0.25, 0))
        rod("Antenna", (1.3, -0.45, 1.64), (1.36, -0.45, 1.8), 0.008, "ink", 4)
        cone("AntennaBall", (1.36, -0.45, 1.81), 0.03, 0.0, 0.06, "ui_yellow", 5)
        # Round "eyes" and a smiling grille: the cartoon face of the car.
        lamps = [cylinder("LampL", (-1.965, side * 0.6, 0.6), 0.13, 0.06, "lamp", 10, rot=ALONG_X) for side in (-1.0, 1.0)]
        for side in (-1.0, 1.0):
            cylinder("LampBezel", (-1.95, side * 0.6, 0.6), 0.165, 0.05, "guardrail", 10, rot=ALONG_X)
        smile = [(0.34 * t, 0.5 + 0.035 * t * t) for t in (-1.0, -0.5, 0.0, 0.5, 1.0)]
        smile += [(0.28 * t, 0.43 - 0.09 * (1.0 - t * t)) for t in (1.0, 0.5, 0.0, -0.5, -1.0)]
        flat_poly("Grille", smile, -1.995, 0.05, "ink", plane="yz")
        tails = [cube("Tail", (1.955, side * 0.7, 0.82), (0.04, 0.2, 0.24), "danger") for side in (-1.0, 1.0)]
        door_front, door_back, belt = -0.72, 0.62, 0.99
        mirror_x = -0.55
        cube("Bumper", (-1.96, 0, 0.3), (0.18, 1.86, 0.16), "guardrail", 0.05)
        cube("RearBumper", (1.96, 0, 0.3), (0.16, 1.86, 0.16), "guardrail", 0.05)
        cube("RearPlate", (1.957, 0, 0.6), (0.01, 0.36, 0.11), "sign_white")
        rod("Exhaust", (1.9, -0.55, 0.22), (2.05, -0.55, 0.22), 0.04, "ink", 6)
    cube("FrontPlate", (-2.086 if pickup else -2.052, 0, 0.3), (0.01, 0.36, 0.1), "sign_white")

    # One mesh for both headlights (NightFlares splits it into two halos).
    join(lamps, "Light")
    join(tails, "TailLights")

    # Doors, handles, mirrors.
    for side in (-1.0, 1.0):
        y = side * 0.903
        for x in (door_front, door_back):
            cube("DoorSeam", (x, y, 0.64), (0.015, 0.01, 0.66), "ink")
        cube("DoorHandle", (door_back - 0.14, side * 0.905, belt - 0.12), (0.14, 0.02, 0.04), "ink")
        cube("Mirror", (mirror_x, side * 0.89, belt + 0.1), (0.13, 0.16, 0.11), paint, 0.02)
        cube("MirrorGlass", (mirror_x + 0.066, side * 0.9, belt + 0.1), (0.005, 0.12, 0.08), "window")
    for x in (-wheel_x, wheel_x):
        for side in (-1.0, 1.0):
            _wheel(x, side, radius)
    done("vehicles/sm_vehicle_parked_%s.glb" % kind)


def hatchback():
    parked_car("hatchback")


def pickup():
    parked_car("pickup")


# =============================================================================
# Street lamp (N-140): the village's, repeated dozens of times a route
# =============================================================================

def street_lamp():
    clear()
    lathe("LampBase", [(0.3, 0.0), (0.3, 0.1), (0.17, 0.2), (0.15, 0.5), (0.19, 0.56), (0.19, 0.64), (0.11, 0.7)],
          8, "lamp_metal", start=math.pi / 8)
    cylinder("BaseRing", (0, 0, 0.6), 0.2, 0.05, "brass", 8)
    cone("Pole", (0, 0, 2.43), 0.095, 0.06, 3.5, "lamp_metal", 8)
    cylinder("Collar", (0, 0, 4.12), 0.085, 0.08, "brass", 8)
    cone("Finial", (0, 0, 4.42), 0.06, 0.0, 0.28, "brass", 6)
    blob("FinialBall", (0, 0, 4.29), (0.05, 0.05, 0.05), "brass", 1)
    # Swan-neck arm and a curl under it.
    neck = [(0.05, 3.9), (0.12, 4.18), (0.28, 4.36), (0.5, 4.43), (0.72, 4.41), (0.9, 4.33)]
    for (x0, z0), (x1, z1) in zip(neck, neck[1:]):
        rod("Arm", (x0, 0, z0), (x1, 0, z1), 0.034, "lamp_metal", 6)
    bpy.ops.mesh.primitive_torus_add(major_segments=8, minor_segments=3, major_radius=0.15, minor_radius=0.022,
                                     location=(0.235, 0, 4.16), rotation=ALONG_Y)
    curl = bpy.context.object
    curl.name = "ArmCurl"
    curl.data.materials.append(mat("lamp_metal"))
    rod("Hanger", (0.92, 0, 4.36), (0.92, 0, 4.22), 0.02, "brass", 6)
    # Lantern: a hexagonal roof, one glass body (glows at night), a drip cap.
    c = (0.92, 0.0)
    lathe("LanternRoof", [(0.0, 4.27), (0.06, 4.24), (0.27, 4.07), (0.27, 4.02), (0.0, 4.02)], 6, "lamp_metal", centre=c)
    lathe("LampGlass", [(0.0, 4.02), (0.2, 4.02), (0.14, 3.68), (0.0, 3.68)], 6, "lamp_glass", centre=c)
    lathe("LanternBottom", [(0.0, 3.7), (0.165, 3.7), (0.165, 3.66), (0.07, 3.6), (0.0, 3.56)], 6, "lamp_metal", centre=c)
    cone("Drop", (0.92, 0, 3.52), 0.035, 0.0, 0.08, "brass", 6, rot=(math.pi, 0, 0))
    done("environment/props/sm_env_prop_street_lamp_refined.glb", "environment/props/sm_env_prop_street_lamp.glb")


# =============================================================================
# Landmarks (N-140): read by silhouette from far away
# =============================================================================

def windmill():
    clear()
    face = math.pi / 2 - math.pi / 8   # a flat face of the octagon toward +Y (the road)
    lathe("MillPlinth", [(2.3, 0.0), (2.2, 1.0)], 8, "stone", start=face)
    lathe("MillTower", [(2.05, 0.9), (1.3, 9.3)], 8, "plaster", start=face)
    lathe("GalleryDeck", [(2.4, 3.85), (2.4, 4.0)], 8, "wood", start=face)
    lathe("GalleryRail", [(2.33, 4.66), (2.43, 4.66), (2.43, 4.74), (2.33, 4.74)], 8, "wood", start=face, loop=True)
    for k in range(8):
        a = face + k * math.tau / 8
        cube("GalleryPost", (math.cos(a) * 2.38, math.sin(a) * 2.38, 4.36), (0.08, 0.08, 0.72), "wood")
    for k in range(0, 8, 2):
        a = face + (k + 0.5) * math.tau / 8
        rod("GalleryStrut", (math.cos(a) * 1.8, math.sin(a) * 1.8, 3.2), (math.cos(a) * 2.3, math.sin(a) * 2.3, 3.88), 0.05, "wood", 4)
    # Door and windows on the flat faces (apothem = r cos 22.5 deg).
    cube("MillDoor", (0, 1.86, 1.75), (0.9, 0.14, 1.5), "barn_red")
    flat_poly("MillDoorTop", arc(0.0, 2.5, 0.45, 0.0, math.pi, 6), 1.79, 0.14, "barn_red")
    cube("DoorFrame", (0, 1.84, 1.75), (1.06, 0.12, 1.6), "wood")
    cube("DoorKnob", (0.3, 1.94, 1.7), (0.08, 0.06, 0.08), "brass")
    for heading, z in ((math.pi / 2, 6.3), (0.0, 3.0), (math.pi, 3.0), (0.0, 6.6)):
        apothem = (2.05 - (z - 0.9) * 0.75 / 8.4) * math.cos(math.pi / 8)
        out = (math.cos(heading), math.sin(heading))
        rot = (0, 0, heading - math.pi / 2)
        for name, depth, size, material in (("WindowFrame", 0.0, (0.7, 0.14, 0.8), "sign_white"),
                                            ("Window", 0.02, (0.5, 0.14, 0.6), "window"),
                                            ("WindowCross", 0.035, (0.06, 0.14, 0.6), "sign_white")):
            cube(name, (out[0] * (apothem + depth), out[1] * (apothem + depth), z), size, material, rot=rot)
    # Onion cap with a wooden rim and a weather-vane finial.
    lathe("CapRim", [(1.55, 9.15), (1.55, 9.4)], 8, "wood", start=face)
    lathe("MillCap", [(1.5, 9.4), (1.62, 9.8), (1.45, 10.5), (0.95, 11.15), (0.32, 11.55), (0.0, 11.65)], 8, "roof", start=face)
    rod("VaneRod", (0, 0, 11.6), (0, 0, 12.5), 0.04, "metal", 6)
    cylinder("VaneBall", (0, 0, 12.1), 0.12, 0.16, "brass", 6)
    flat_poly("Vane", [(-0.05, 12.3), (0.55, 12.25), (0.7, 12.4), (0.55, 12.55), (-0.05, 12.5)], -0.02, 0.04, "metal")
    # Rotor: an axle out of the cap, four lattice sails in an X.
    hub_z, sail_y = 9.75, 2.12
    rod("Axle", (0, 1.1, hub_z), (0, 2.05, hub_z), 0.2, "wood", 8)
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 2.1, hub_z))
    rotor = bpy.context.object
    rotor.name = "WindmillRotor"  # spin this node around its local Z in Godot (Blender +Y)
    parts = [cylinder("RotorHub", (0, 2.2, hub_z), 0.36, 0.3, "metal", 8, rot=ALONG_Y),
             cone("HubNose", (0, 2.44, hub_z), 0.22, 0.0, 0.2, "danger", 8, rot=(-math.pi / 2, 0, 0))]
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        d = (math.cos(a), math.sin(a))
        p = (-math.sin(a), math.cos(a))

        def at(r, s, y):
            return (d[0] * r + p[0] * s, y, hub_z + d[1] * r + p[1] * s)
        parts.append(bar("SailArm", at(0.2, 0, sail_y + 0.06), at(4.95, 0, sail_y + 0.06), 0.16, "wood"))
        parts.append(cube("Sail", at(2.95, 0.5, sail_y - 0.03), (3.7, 0.04, 0.84), "sign_white", rot=(0, -a, 0)))
        parts.append(bar("SailEdge", at(1.0, 0.94, sail_y + 0.02), at(4.85, 0.94, sail_y + 0.02), 0.07, "wood"))
        for r in (1.1, 2.95, 4.8):
            parts.append(bar("SailSlat", at(r, 0.0, sail_y + 0.02), at(r, 0.96, sail_y + 0.02), 0.06, "wood"))
    for part in parts:
        part.parent = rotor
        part.matrix_parent_inverse = rotor.matrix_world.inverted()
    done("environment/landmarks/sm_env_landmark_windmill.glb")


def water_tower():
    clear()
    base, top = 2.3, 1.55
    legs = [(sx, sy) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    for sx, sy in legs:
        bar("TowerLeg", (sx * base, sy * base, 0.0), (sx * top, sy * top, 9.9), 0.24, "metal")
        cube("Footing", (sx * base, sy * base, 0.15), (0.6, 0.6, 0.3), "concrete")

    def leg_at(sx, sy, z):
        t = z / 9.9
        return (sx * (base + (top - base) * t), sy * (base + (top - base) * t), z)
    for k in range(4):
        (ax, ay), (bx, by) = legs[k], legs[(k + 1) % 4]
        bar("TowerRing", leg_at(ax, ay, 5.0), leg_at(bx, by, 5.0), 0.12, "metal")
        for z0, z1 in ((0.4, 5.0), (5.0, 9.6)):
            bar("TowerBrace", leg_at(ax, ay, z0), leg_at(bx, by, z1), 0.07, "guardrail")
            bar("TowerBrace", leg_at(bx, by, z0), leg_at(ax, ay, z1), 0.07, "guardrail")
    rod("Riser", (0, 0, 0.0), (0, 0, 9.8), 0.22, "metal", 8)
    # Tank: bowl bottom, walls, cone roof; a flat face of the 16-gon toward
    # +Y carries the cardboard-box logo.
    face = math.pi / 2 - math.pi / 16
    lathe("TankBowl", [(0.0, 9.5), (0.5, 9.55), (2.2, 9.95), (2.62, 10.4)], 16, "water_tank", start=face, caps=False)
    lathe("Tank", [(2.62, 10.4), (2.62, 12.9)], 16, "water_tank", start=face, caps=False)
    lathe("TankRoof", [(2.62, 12.9), (2.8, 12.97), (1.2, 13.75), (0.0, 14.15)], 16, "tank_roof", start=face, caps=False)
    lathe("TankBand", [(2.64, 12.1), (2.64, 12.45)], 16, "mint", start=face, caps=False)
    cone("TankFinial", (0, 0, 14.3), 0.16, 0.0, 0.4, "brass", 6)
    apothem = 2.62 * math.cos(math.pi / 16)
    cube("LogoBox", (0, apothem + 0.02, 11.25), (0.78, 0.03, 0.66), "logo_cardboard")
    cube("LogoTape", (0, apothem + 0.04, 11.25), (0.16, 0.02, 0.66), "ui_yellow")
    cube("LogoLid", (0, apothem + 0.04, 11.47), (0.78, 0.02, 0.04), "ink")
    # Catwalk ring with posts and a rail, and the ladder up to it.
    lathe("Catwalk", [(2.85, 10.1), (2.85, 10.22)], 16, "metal", start=face)
    lathe("CatwalkRail", [(2.84, 10.95), (2.84, 11.03)], 16, "guardrail", start=face, caps=False)
    for k in range(8):
        a = k * math.tau / 8
        cube("RailPost", (math.cos(a) * 2.82, math.sin(a) * 2.82, 10.6), (0.06, 0.06, 0.8), "guardrail")
    # Straight up the +X face to the catwalk, held off the rings.
    for side in (-0.22, 0.22):
        bar("LadderRail", (2.9, side, 0.1), (2.9, side, 11.0), 0.05, "guardrail")
    for z in (5.0, 9.6):
        face_x = base + (top - base) * z / 9.9
        bar("LadderStay", (face_x, 0, z), (2.9, 0, z), 0.06, "guardrail")
    for k in range(7):
        z = 0.9 + k * 1.4
        rod("LadderRung", (2.9, -0.22, z), (2.9, 0.22, z), 0.022, "guardrail", 4)
    done("environment/landmarks/sm_env_landmark_water_tower.glb")


# =============================================================================
# Roadside furniture (N-140)
# =============================================================================

def mailbox():
    clear()
    cube("PostBase", (0, 0, 0.05), (0.24, 0.24, 0.1), "concrete", 0.02)
    cube("Post", (0, -0.02, 0.62), (0.1, 0.1, 1.08), "wood", 0.015, rot=(0.03, 0, 0))
    cube("MailboxShelf", (0, -0.01, 1.145), (0.24, 0.5, 0.05), "wood", 0.01)
    rod("Brace", (0, -0.02, 0.86), (0, 0.18, 1.12), 0.022, "wood", 4)
    profile = [(-0.15, 1.17), (0.15, 1.17)] + arc(0.0, 1.3, 0.15, 0.0, math.pi, 8)
    round_edges(flat_poly("Mailbox", profile, -0.26, 0.5, "car_blue"), 0.02)
    # Door hanging open on its bottom hinge, a parcel poking out.
    door_pts = [(x * 1.06, z - 1.17 + 0.0) for x, z in [(-0.15, 1.17), (0.15, 1.17)] + arc(0.0, 1.3, 0.15, 0.0, math.pi, 8)]
    door = join([flat_poly("MailboxDoor", door_pts, 0.0, 0.03, "car_blue"),
                 cube("DoorHandle", (0, 0.04, 0.26), (0.08, 0.03, 0.03), "ui_yellow")], "MailboxDoor")
    door.location = (0, 0.24, 1.17)
    door.rotation_euler = (-0.75, 0, 0)
    cube("Parcel", (0.01, 0.25, 1.235), (0.17, 0.22, 0.12), "logo_cardboard", rot=(0.12, 0, 0.18))
    cube("ParcelTape", (0.01, 0.25, 1.297), (0.18, 0.04, 0.01), "ui_yellow", rot=(0.12, 0, 0.18))
    # Flag up: you've got mail.
    rod("FlagPin", (0.15, -0.12, 1.3), (0.18, -0.12, 1.3), 0.02, "brass", 6)
    cube("FlagStaff", (0.172, -0.12, 1.42), (0.015, 0.035, 0.3), "danger")
    flat_poly("Flag", [(-0.14, 1.47), (0.02, 1.47), (0.02, 1.58), (-0.14, 1.58)], 0.165, 0.015, "danger", plane="yz")
    cube("NamePlate", (-0.152, -0.02, 1.3), (0.01, 0.26, 0.07), "sign_white")
    for k in range(3):
        cube("NameInk", (-0.158, -0.1 + k * 0.08, 1.3), (0.005, 0.05, 0.02), "ink")
    tuft(0.13, 0.1, 1.0, 0.3)
    tuft(-0.12, -0.12, 0.8, 1.1)
    done("environment/props/sm_env_prop_mailbox.glb")


def milestone():
    clear()
    cube("MilestoneBase", (0, 0, 0.03), (0.46, 0.3, 0.06), "concrete", 0.015)
    body = [(-0.18, 0.06), (0.18, 0.06), (0.18, 0.72)] + arc(0.0, 0.72, 0.18, 0.0, math.pi, 8)[1:-1] + [(-0.18, 0.72)]
    round_edges(flat_poly("Milestone", body, -0.1, 0.2, "plaster"), 0.025)
    cap = [(-0.187, 0.66), (0.187, 0.66)] + arc(0.0, 0.72, 0.187, 0.0, math.pi, 8)
    round_edges(flat_poly("MilestoneTop", cap, -0.107, 0.214, "danger"), 0.015)
    cube("MilestonePlate", (0, 0.1, 0.42), (0.26, 0.012, 0.2), "sign_white", 0.004)
    # "12" in chunky segment digits.
    ink = [((-0.05, 0.42), (0.022, 0.13)),                       # 1
           ((0.05, 0.475), (0.07, 0.022)), ((0.075, 0.447), (0.022, 0.06)),
           ((0.05, 0.42), (0.07, 0.022)), ((0.025, 0.393), (0.022, 0.06)),
           ((0.05, 0.365), (0.07, 0.022))]
    for (x, z), (w, h) in ink:
        # Seen from the road (+Y) Blender +X is on the left: mirror X.
        cube("MilestoneNumber", (-x, 0.108, z), (w, 0.006, h), "ink")
    tuft(0.2, 0.12, 1.0, 0.2)
    tuft(-0.21, 0.1, 0.8, 1.3)
    tuft(0.05, -0.16, 0.9, 2.0)
    done("environment/props/sm_env_prop_milestone.glb")


def wooden_crate():
    clear()
    cube("CrateCore", (0, 0, 0.45), (0.82, 0.82, 0.84), "trunk")
    lean = [0.02, -0.015, 0.01]
    for k, z in enumerate((0.2, 0.45, 0.7)):
        for side in (-1.0, 1.0):
            cube("Plank", (0, side * 0.425, z), (0.76, 0.03, 0.22), "crate_board", rot=(0, lean[k] * side, 0))
            cube("Plank", (side * 0.425, 0, z), (0.03, 0.76, 0.22), "crate_board", rot=(lean[(k + 1) % 3] * side, 0, 0))
    for k, y in enumerate((-0.25, 0.0, 0.25)):
        cube("LidPlank", (0, y, 0.88), (0.78, 0.23, 0.03), "crate_board", rot=(0, 0, lean[k]))
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cube("CrateCorner", (sx * 0.42, sy * 0.42, 0.45), (0.1, 0.1, 0.9), "wood")
    for z in (0.06, 0.84):
        for side in (-1.0, 1.0):
            cube("CrateBand", (0, side * 0.445, z), (0.76, 0.05, 0.1), "wood")
            cube("CrateBand", (side * 0.445, 0, z), (0.05, 0.76, 0.1), "wood")
    for side in (-1.0, 1.0):
        cube("LidRail", (0, side * 0.42, 0.895), (0.76, 0.06, 0.03), "wood")
    brace = math.atan2(0.62, 0.72)
    for side in (-1.0, 1.0):
        cube("CrateBrace", (0, side * 0.45, 0.45), (0.95, 0.04, 0.09), "wood", rot=(0, -brace * side, 0))
        cube("CrateBrace", (side * 0.45, 0, 0.45), (0.04, 0.95, 0.09), "wood", rot=(brace * side, 0, 0))
    # "This way up" arrows and a shipping label, on the road-facing sides.
    arrow = [(-0.025, 0.0), (0.025, 0.0), (0.025, 0.1), (0.06, 0.1), (0.0, 0.17), (-0.06, 0.1), (-0.025, 0.1)]
    for dx in (-0.27, -0.13):
        flat_poly("CrateStencil", [(x + dx, z + 0.56) for x, z in arrow], 0.44, 0.006, "ink")
        flat_poly("CrateStencil", [(x - dx, z + 0.56) for x, z in arrow], -0.446, 0.006, "ink")
    cube("CrateLabel", (0.2, 0.442, 0.26), (0.22, 0.008, 0.15), "paper")
    cube("LabelStripe", (0.2, 0.447, 0.3), (0.22, 0.006, 0.04), "danger")
    done("environment/props/sm_env_prop_wooden_crate.glb")


def traffic_cone():
    clear()
    round_edges(cube("ConeBase", (0, 0, 0.03), (0.5, 0.5, 0.06), "rubber"), 0.05, 2, 30.0)
    cylinder("ConeFoot", (0, 0, 0.07), 0.215, 0.03, "orange", 16)
    body = [(0.2, 0.06), (0.165, 0.3), (0.115, 0.54), (0.068, 0.74), (0.05, 0.77), (0.0, 0.78)]
    lathe("Cone", body, 16, "orange")

    def radius_at(z):
        for (r0, z0), (r1, z1) in zip(body, body[1:]):
            if z0 <= z <= z1:
                return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
        return body[-1][0]
    for z0, z1 in ((0.28, 0.38), (0.5, 0.58)):
        lathe("ConeBand", [(radius_at(z0) + 0.006, z0), (radius_at(z1) + 0.006, z1)], 16, "reflector", caps=False)
    done("environment/props/sm_env_prop_traffic_cone.glb")


# =============================================================================
# Porch and garden (N-140)
# =============================================================================

def garden_gnome():
    """Faces +Y (Godot -Z, the road), like the model it replaces."""
    clear()
    base = cylinder("GnomeBase", (0, 0, 0.02), 0.12, 0.04, "moss", 8)
    base.scale = (1.0, 0.85, 1.0)
    for sx in (-1.0, 1.0):
        blob("GnomeBoot", (sx * 0.045, 0.02, 0.06), (0.04, 0.06, 0.03), "boot", 1)
    lathe("GnomeBody", [(0.075, 0.06), (0.095, 0.12), (0.09, 0.2), (0.07, 0.26), (0.0, 0.28)], 8, "gnome_coat")
    cylinder("GnomeBelt", (0, 0, 0.15), 0.097, 0.025, "ink", 8)
    cube("GnomeBuckle", (0, 0.096, 0.15), (0.03, 0.01, 0.025), "brass")
    # Hugging a parcel: every garden has one waiting for us.
    cube("GnomeParcel", (0, 0.1, 0.2), (0.1, 0.07, 0.08), "logo_cardboard", 0.005, rot=(0, 0, 0.1))
    cube("GnomeParcelTape", (0, 0.1, 0.242), (0.02, 0.072, 0.004), "ui_yellow", rot=(0, 0, 0.1))
    for sx in (-1.0, 1.0):
        rod("GnomeArm", (sx * 0.075, 0.0, 0.25), (sx * 0.06, 0.08, 0.2), 0.022, "gnome_coat", 6)
        blob("GnomeHand", (sx * 0.055, 0.1, 0.2), (0.022, 0.022, 0.022), "skin_gnome", 1)
    blob("GnomeFace", (0, 0.01, 0.325), (0.065, 0.06, 0.06), "skin_gnome", 1)
    blob("GnomeNose", (0, 0.07, 0.325), (0.026, 0.026, 0.024), "gnome_nose", 1)
    for sx in (-1.0, 1.0):
        cube("GnomeEye", (sx * 0.026, 0.058, 0.347), (0.013, 0.008, 0.018), "ink")
        blob("GnomeCheek", (sx * 0.04, 0.045, 0.31), (0.016, 0.01, 0.012), "gnome_nose", 1)
    beard = cone("GnomeBeard", (0, 0.04, 0.24), 0.07, 0.0, 0.14, "sign_white", 8, rot=(math.pi + 0.25, 0, 0))
    beard.scale = (1.0, 0.6, 1.0)
    cylinder("GnomeMoustache", (0, 0.062, 0.3), 0.018, 0.09, "sign_white", 6, rot=ALONG_X)
    # A tall floppy hat whose tip flops over the back.
    rings = []
    for i in range(7):
        t = i / 6.0
        rings.append((0.0, -0.12 * t * t, 0.372 + 0.23 * math.sin(t * 1.2) / math.sin(1.2), 0.074 * (1.0 - t)))
    tube("GnomeHat", rings[:-1] + [(0.0, -0.14, 0.58, 0.0)], 8, "danger")
    cylinder("GnomeHatBrim", (0, 0, 0.375), 0.078, 0.022, "danger", 8)
    blob("GnomeBobble", (0, -0.145, 0.575), (0.02, 0.02, 0.02), "sign_white", 1)
    tuft(0.09, -0.06, 0.6, 0.4)
    done("environment/yard/sm_env_yard_garden_gnome.glb")


def doormat():
    """The house's door is toward -Y (Godot +Z); the visitor stands at +Y,
    so the smile's eyes sit toward -Y and it reads upright from the step."""
    clear()
    flat_poly("Doormat", rounded_rect(0.45, 0.275, 0.07), 0.0, 0.022, "trunk", plane="xy")
    flat_poly("DoormatField", rounded_rect(0.39, 0.215, 0.05), 0.02, 0.006, "cardboard", plane="xy")
    for sx in (-1.0, 1.0):
        flat_poly("SmileEye", arc(sx * 0.1, -0.07, 0.035, 0.0, math.tau, 8)[:-1], 0.024, 0.006, "mint", plane="xy")
    outer = arc(0.0, -0.03, 0.17, math.pi * 0.15, math.pi * 0.85, 6)
    inner = arc(0.0, -0.03, 0.12, math.pi * 0.85, math.pi * 0.15, 6)
    flat_poly("Smile", outer + inner, 0.024, 0.006, "mint", plane="xy")
    done("environment/yard/sm_env_yard_doormat.glb")


# =============================================================================
# Tow crane (N-321.1): the comic wrecker that drags a bogged van out of the mud
# =============================================================================

PALETTE.update({
    # The colours mud_crane.gd used for its primitives, so nothing shifts.
    "crane_yellow": srgb("e0a526"), "crane_cream": srgb("f0efe6"),
    "crane_dark": srgb("2b2f33"), "crane_red": srgb("c43b2b"),
    "beacon": srgb("ffb020"),
})

## Godot frame of the crane (mud_crane.gd): HOOK_LOCAL is (0, 2.1, 3.6), the
## script hangs the cable 0.5 lower. In Blender that is (0, -3.6, z).
CRANE_HOOK_EYE = (0.0, -3.6, 2.05)
CRANE_BEACON = (0.0, 1.9, 2.55)


def _snapshot():
    return set(o.name for o in bpy.context.scene.objects)


def _group(before, name):
    """Joins every object made since `before` into one mesh `name`, with its
    transform applied (origin at the crane's base centre)."""
    objs = [o for o in bpy.context.scene.objects if o.name not in before]
    o = join(objs, name)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def _pivot(o, point):
    """Moves `o`'s origin to `point` without moving the mesh."""
    p = Vector(point)
    o.data.transform(Matrix.Translation(-p))
    o.location = p


def _pane_yz(name, p0, p1, width, material, inset=(0.1, 0.9), out=0.015):
    """A thin pane (glass) along the line p0 -> p1 in the YZ plane, `width`
    across X, nudged `out` along the normal that points up/forward."""
    dy, dz = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dy, dz)
    ny, nz = dz / length, -dy / length
    if nz < 0.0 and ny < 0.0:
        ny, nz = -ny, -nz
    a = (p0[0] + dy * inset[0], p0[1] + dz * inset[0])
    b = (p0[0] + dy * inset[1], p0[1] + dz * inset[1])
    centre = (0.0, (a[0] + b[0]) / 2.0 + ny * out, (a[1] + b[1]) / 2.0 + nz * out)
    return cube(name, centre, (width, length * (inset[1] - inset[0]), 0.03), material,
                rot=(math.atan2(dz, dy), 0.0, 0.0))


def _mesh(name, verts, faces, material, facing=None):
    """A mesh straight from vertex and face lists. Closed meshes get outward
    normals; a loose decal face is turned toward `facing` (Godot culls the
    back of a face)."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if facing is not None:
        for f in bm.faces:
            if f.normal.dot(Vector(facing)) < 0.0:
                f.normal_flip()
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def _drop_faces(obj, direction):
    """Deletes the faces of `obj` that face `direction` (hidden caps)."""
    rot = obj.matrix_world.to_3x3()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    gone = [f for f in bm.faces if (rot @ f.normal).dot(Vector(direction)) > 0.9]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()


def _chassis_block(name, columns, top, half, chamfer, strips, material):
    """The chassis as rings swept along Y, one per (y, z_bottom) column, with
    a chamfer on the two top edges. Built so no face or diagonal is longer
    than bake_vertex_ao.py's SUBDIVIDE (1 m): a flat_poly side cap is
    triangulated into long fans the baker then cuts into hundreds of
    slivers. The flat underside (never seen) is left open; the wheel-arch
    undersides stay closed."""
    verts, faces, rings = [], [], []
    for y, zb in columns:
        ring = []
        for i in range(strips + 1):
            ring.append(len(verts))
            verts.append((-half + 2.0 * half * i / strips, y, zb))
        ring.append(len(verts))
        verts.append((half, y, top - chamfer))
        for i in range(strips + 1):
            ring.append(len(verts))
            verts.append((half - chamfer - 2.0 * (half - chamfer) * i / strips, y, top))
        ring.append(len(verts))
        verts.append((-half, y, top - chamfer))
        rings.append(ring)
    n = len(rings[0])
    for (ya, za), (yb, zb), a, b in zip(columns, columns[1:], rings, rings[1:]):
        open_bottom = za <= columns[0][1] + 1e-4 and zb <= columns[0][1] + 1e-4
        for k in range(n):
            if open_bottom and k < strips:
                continue
            j = (k + 1) % n
            faces.append((a[k], a[j], b[j], b[k]))
    for ring in (rings[0], rings[-1]):
        bottom_pts = ring[:strips + 1]
        top_pts = list(reversed(ring[strips + 2:2 * strips + 3]))
        for i in range(strips):
            faces.append((bottom_pts[i], bottom_pts[i + 1], top_pts[i + 1], top_pts[i]))
        faces.append((bottom_pts[0], top_pts[0], ring[-1]))
        faces.append((bottom_pts[-1], ring[strips + 1], top_pts[-1]))
    return _mesh(name, verts, faces, material)


def _disc(name, centre, radius, sides, material, facing, axis="x"):
    """A single flat polygon (hubcap, lamp bezel) across `axis`, facing `facing`."""
    cx, cy, cz = centre
    pts = []
    for k in range(sides):
        a, b = math.cos(k * math.tau / sides) * radius, math.sin(k * math.tau / sides) * radius
        pts.append((cx, cy + a, cz + b) if axis == "x" else (cx + a, cy, cz + b))
    return _mesh(name, pts, [tuple(range(sides))], material, facing)


def tow_crane():
    """Cab-over wrecker in Blender coordinates: nose toward +Y (Godot -Z),
    boom and hook toward -Y (Godot +Z), wheels on z = 0. The chassis sides
    stay flat at |x| = 1.30 between y -1.25 and 1.25, z 0.55-1.2: Godot pins
    the "GRUA" Label3D boards there."""
    clear()
    wheel_r, wheel_y, wheel_x = 0.5, 2.0, 1.3
    bottom, top, half = 0.5, 1.28, 1.30

    # --- Chassis: swept rings with both wheel arches, chamfered top ---------
    before = _snapshot()
    columns = [(-3.0, bottom)]
    for cy in (-wheel_y, wheel_y):
        columns += [(y, max(bottom, z)) for y, z in arc(cy, wheel_r, 0.6, math.pi, 0.0, 5)]
        if cy < 0.0:
            columns += [(-0.84, bottom), (-0.28, bottom), (0.28, bottom), (0.84, bottom)]
    columns += [(3.0, bottom)]
    _chassis_block("ChassisBody", columns, top, half, 0.07, 5, "crane_yellow")
    # Dark mudguards over the arches.
    for side in (-1.0, 1.0):
        for cy in (-wheel_y, wheel_y):
            ring = arc(cy, wheel_r, 0.7, math.pi, 0.0, 4) + arc(cy, wheel_r, 0.62, 0.0, math.pi, 4)
            flat_poly("Mudguard", ring, 1.2 if side > 0 else -1.6, 0.4, "crane_dark", plane="yz")
    # Front: red bumper, plate, smiling grille, lamp bezels (the face).
    cube("Bumper", (0, 3.1, 0.6), (2.7, 0.3, 0.35), "crane_red")
    cube("FrontPlate", (0, 3.255, 0.6), (0.4, 0.01, 0.12), "sign_white")
    smile = [(0.38 * t, 1.05 + 0.04 * t * t) for t in (-1.0, -0.5, 0.0, 0.5, 1.0)]
    smile += [(0.3 * t, 0.97 - 0.1 * (1.0 - t * t)) for t in (1.0, 0.5, 0.0, -0.5, -1.0)]
    flat_poly("Grille", smile, 2.99, 0.03, "crane_dark", plane="xz")
    for side in (-1.0, 1.0):
        _disc("LampBezel", (side * 0.82, 3.005, 0.98), 0.17, 8, "guardrail", (0.0, 1.0, 0.0), axis="y")
    # Rear: black bumper with yellow hazard stripes, tail-light housing, plate.
    cube("RearBumper", (0, -3.1, 0.62), (2.5, 0.2, 0.28), "ink")
    for i in range(6):
        x0 = -1.12 + i * 0.38
        _mesh("HazardStripe", [(x0, -3.205, 0.5), (x0 + 0.16, -3.205, 0.5), (x0 + 0.34, -3.205, 0.74),
                               (x0 + 0.18, -3.205, 0.74)], [(0, 1, 2, 3)], "crane_yellow", (0.0, -1.0, 0.0))
    cube("RearPlate", (0, -3.005, 1.02), (0.4, 0.01, 0.12), "sign_white")
    # Folded stabiliser legs behind the rear wheels, mudflaps, a cab step.
    for side in (-1.0, 1.0):
        cube("OutriggerBeam", (side * 1.2, -2.72, 0.42), (0.5, 0.22, 0.18), "crane_dark")
        cube("OutriggerLeg", (side * 1.42, -2.72, 0.6), (0.14, 0.14, 0.62), "crane_dark")
        cube("OutriggerPad", (side * 1.42, -2.72, 0.22), (0.3, 0.3, 0.06), "crane_red")
        cube("Mudflap", (side * 1.25, -2.56, 0.32), (0.36, 0.03, 0.38), "rubber")
        cube("Step", (side * 1.26, 1.33, 0.4), (0.24, 0.26, 0.05), "guardrail")
        rod("StepHanger", (side * 1.26, 1.33, 0.42), (side * 1.2, 1.33, 0.52), 0.02, "crane_dark", 4)
    # The joke: a rubber duck on the tail, keeping an eye on whoever is towed.
    lathe("DuckBody", [(0.0, 1.28), (0.12, 1.29), (0.14, 1.36), (0.09, 1.44), (0.0, 1.45)], 6, "ui_yellow",
          centre=(-0.85, -2.68))
    lathe("DuckHead", [(0.0, 1.44), (0.07, 1.47), (0.075, 1.54), (0.0, 1.6)], 6, "ui_yellow", centre=(-0.85, -2.8))
    cone("DuckBeak", (-0.85, -2.9, 1.51), 0.035, 0.0, 0.08, "orange", 4, rot=(math.pi / 2.0, 0, 0))
    for sx in (-1.0, 1.0):
        cube("DuckEye", (-0.85 + sx * 0.035, -2.868, 1.55), (0.014, 0.01, 0.02), "ink")
    _group(before, "Chassis")

    # --- Cab: rounded cab-over box with raked windscreen ---------------------
    before = _snapshot()
    cab = [(0.95, 1.25), (2.92, 1.25), (2.92, 1.75), (2.6, 2.4), (0.95, 2.4)]
    round_edges(flat_poly("CabShell", cab, -1.15, 2.3, "crane_cream", plane="yz"), 0.1, 1)
    _pane_yz("Windshield", (2.92, 1.75), (2.6, 2.4), 1.9, "window", (0.08, 0.92))
    for sx in (-1.0, 1.0):
        rod("Wiper", (sx * 0.2 - 0.25, 2.9, 1.83), (sx * 0.2 - 0.05, 2.78, 2.07), 0.012, "ink", 4)
    for x in (1.15, -1.165):
        flat_poly("SideWindow", [(1.3, 1.82), (2.68, 1.82), (2.48, 2.28), (1.3, 2.28)], x, 0.015, "window", plane="yz")
    cube("RearWindow", (0, 0.945, 1.98), (1.5, 0.02, 0.36), "window")
    for side in (-1.0, 1.0):
        cube("DoorSeam", (side * 1.152, 1.18, 1.75), (0.012, 0.015, 0.95), "crane_dark")
        cube("DoorHandle", (side * 1.155, 1.35, 1.68), (0.02, 0.16, 0.04), "crane_dark")
        rod("MirrorArm", (side * 1.12, 2.62, 2.0), (side * 1.4, 2.72, 2.04), 0.02, "crane_dark", 4)
        cube("Mirror", (side * 1.42, 2.72, 1.94), (0.07, 0.12, 0.3), "crane_dark")
        _mesh("CabStripe", [(side * 1.152, 1.0, 1.38), (side * 1.152, 2.9, 1.38), (side * 1.152, 2.9, 1.46),
                            (side * 1.152, 1.0, 1.46)], [(0, 1, 2, 3)], "crane_red", (side, 0.0, 0.0))
    cylinder("BeaconBase", (0, 1.9, 2.43), 0.25, 0.06, "crane_dark", 8)
    _group(before, "Cab")

    # --- Wheels -----------------------------------------------------------------
    before = _snapshot()
    for side in (-1.0, 1.0):
        for y in (-wheel_y, wheel_y):
            tyre = cylinder("Tyre", (side * wheel_x, y, wheel_r), wheel_r, 0.45, "rubber", 12, rot=ALONG_X)
            _drop_faces(tyre, (-side, 0.0, 0.0))  # the inner side sits in the wheel well
            _disc("Hub", (side * (wheel_x + 0.23), y, wheel_r), 0.26, 8, "crane_yellow", (side, 0.0, 0.0))
            cylinder("HubNut", (side * (wheel_x + 0.25), y, wheel_r), 0.08, 0.04, "crane_dark", 4, rot=ALONG_X)
    _group(before, "Wheels")

    # --- Boom: turret, pivot tower, two-stage boom, ram, winch, sheave -------
    before = _snapshot()
    root, tip = Vector((0.0, 0.4, 1.75)), Vector((0.0, -3.36, 2.72))
    cylinder("Turret", (0, 0.35, 1.33), 0.55, 0.12, "crane_yellow", 8)
    cube("PivotTower", (0, 0.4, 1.5), (0.5, 0.5, 0.45), "crane_dark", 0.03)
    rod("PivotPin", (-0.3, 0.4, 1.75), (0.3, 0.4, 1.75), 0.06, "guardrail", 6)
    mid = root + (tip - root) * 0.62
    bar("BoomOuter", root, mid, 0.42, "crane_dark")
    bar("BoomInner", root + (tip - root) * 0.55, tip, 0.32, "guardrail")
    # Hydraulic ram from the deck to the boom's belly.
    ram_top = root + (tip - root) * 0.55 - Vector((0.0, 0.0, 0.2))
    ram_base = Vector((0.0, -0.95, 1.3))
    cube("RamMount", (0, -0.95, 1.31), (0.3, 0.3, 0.08), "crane_dark")
    rod("RamBarrel", ram_base, ram_base + (ram_top - ram_base) * 0.6, 0.1, "crane_red", 8)
    rod("RamRod", ram_base + (ram_top - ram_base) * 0.55, ram_top, 0.05, "guardrail", 6)
    # Winch drum riding the boom root, cable wound on it.
    drum = Vector((0.0, 0.15, 2.12))
    for sx in (-1.0, 1.0):
        bar("WinchCheek", (sx * 0.27, 0.15, 1.92), (sx * 0.27, 0.15, 2.2), 0.05, "crane_dark", 0.32)
        cylinder("WinchFlange", (sx * 0.22, drum.y, drum.z), 0.2, 0.04, "crane_red", 8, rot=ALONG_X)
    cylinder("WinchDrum", tuple(drum), 0.16, 0.4, "ink", 8, rot=ALONG_X)
    # Sheave at the tip: the cable runs over it and drops to the hook.
    sheave = Vector((0.0, -3.36, 2.78))
    cylinder("Sheave", tuple(sheave), 0.24, 0.14, "crane_yellow", 10, rot=ALONG_X)
    for sx in (-1.0, 1.0):
        cube("SheavePlate", (sx * 0.1, -3.32, 2.72), (0.03, 0.4, 0.3), "crane_dark")
    rod("SheavePin", (-0.13, -3.36, 2.78), (0.13, -3.36, 2.78), 0.05, "guardrail", 6)
    rod("Cable", (0.0, drum.y, drum.z + 0.17), (0.0, sheave.y, sheave.z + 0.245), 0.02, "ink", 3)
    eye = Vector(CRANE_HOOK_EYE)
    rod("CableDrop", (0.0, eye.y, sheave.z), (0.0, eye.y, eye.z + 0.09), 0.02, "ink", 4)
    _group(before, "Boom")

    # --- Lights -----------------------------------------------------------------
    # Headlights: ONE mesh "Light" in "lamp" (LowpolyMaterials lights it at night).
    lamps = [cylinder("Lamp", (side * 0.82, 3.035, 0.98), 0.13, 0.04, "lamp", 8, rot=ALONG_Y) for side in (-1.0, 1.0)]
    join(lamps, "Light")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tails = [cube("Tail", (side * 0.95, -3.02, 1.02), (0.3, 0.04, 0.16), "danger") for side in (-1.0, 1.0)]
    join(tails, "TailLights")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # --- Beacon: amber dome, origin at its own centre so it spins in place ---
    bx, by, bz = CRANE_BEACON
    beacon = lathe("Beacon", [(0.0, bz - 0.12), (0.19, bz - 0.12), (0.19, bz + 0.04), (0.15, bz + 0.12),
                              (0.08, bz + 0.17), (0.0, bz + 0.18)], 8, "beacon", centre=(bx, by))
    principled = next(n for n in mat("beacon").node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    principled.inputs["Emission Color"].default_value = PALETTE["beacon"]
    principled.inputs["Emission Strength"].default_value = 1.5
    _pivot(beacon, CRANE_BEACON)

    # --- Hook: red, origin at the eye it hangs from ---------------------------
    before = _snapshot()
    ex, ey, ez = CRANE_HOOK_EYE
    bpy.ops.mesh.primitive_torus_add(major_segments=6, minor_segments=4, major_radius=0.07, minor_radius=0.025,
                                     location=(ex, ey, ez), rotation=ALONG_Y)
    bpy.context.object.data.materials.append(mat("crane_red"))
    # A chunky flat "J" (cartoon hook) facing the towed van behind, so it
    # reads as a hook from there; it opens toward -X.
    cx, cz = ex - 0.13, ez - 0.37
    tip = -math.pi - 0.55
    outer = [(ex + 0.04, ez - 0.08), (ex + 0.04, cz)] + arc(cx, cz, 0.17, 0.0, tip, 5)[1:]
    inner = arc(cx, cz, 0.09, tip, 0.0, 4)[:-1] + [(ex - 0.04, cz), (ex - 0.04, ez - 0.08)]
    point = [(cx + 0.12 * math.cos(tip), cz + 0.12 * math.sin(tip) + 0.03)]
    flat_poly("HookBody", outer + point + inner, ey - 0.04, 0.08, "crane_red", plane="xz")
    hook = _group(before, "Hook")
    _pivot(hook, CRANE_HOOK_EYE)

    done("vehicles/sm_vehicle_tow_crane.glb")


BUILDERS = {
    "cars": [hatchback, pickup],
    "crane": [tow_crane],
    "lamp": [street_lamp],
    "landmarks": [windmill, water_tower],
    "roadside": [mailbox, milestone, wooden_crate, traffic_cone],
    "yard": [garden_gnome, doormat],
}
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for group, builders in BUILDERS.items():
    if not ONLY or group in ONLY:
        for builder in builders:
            builder()

print("STREET_REPORT")
for name, tris in REPORT:
    print("  %-58s %6d tris" % (name, tris))
