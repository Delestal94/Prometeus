"""World gates of the continuous map for Take My Package (D-0306, 2026-10-04).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_world_gates.py

Replaces the grey placeholder box of `WorldGate`
(scripts/gameplay/districts/world_gate.gd: 8 x 3 x 0.6 m, pivot at the centre
of its base). The gate keeps its own BoxShape3D collision in code; these are
only what you see. Same cartoon line as build_rail_crossing.py and
build_street_props.py: chunky, rounded, flat palette colours, a joke where it
fits. No text in the geometry (the Label3D "CERRADO / PASO LIBRE" floats at
3.6 m over the middle of the road, so nothing tall sits at x = 0).

Coordinates. Blender is Z up; the glTF exporter turns it into Godot's Y up
with Godot (x, y, z) = Blender (x, z, -y). The road (8 m, |x| <= 4) runs
along X; the vehicle crosses along Godot Z (Blender Y). Origin of every GLB:
centre of the road, on the ground. The closed blockage sits on Godot z = 0
and fits the 8 x 3 x 0.6 m box give or take its hinge post and rest; booths
and cabins stand off the road (|x| > 4.4). Godot rotations below are the
node's own `rotation` (radians in code), relative to the GLB root.

Output, in `models/environment/gates/`:

  sm_env_gate_barrier.glb     (BARRIER: gate_suburbio, gate_puerto)
      Red/white striped boom across the road, the drive post at x = +4.45,
      a fork rest at x = -4.15 and a guard booth at (x 6.3, Godot z -1.3)
      with a parcel waiting on its counter.
      Nodes: "Boom" (origin at the hinge, Godot (4.45, 1.0, 0.0); the arm
      runs toward -X to x = -4.32, counterweight toward +X). OPEN: rotate
      Boom.rotation.z = -PI/2 (-90 deg about its local Godot Z): the tip
      goes straight up, the counterweight swings down to 0.25 m.
      "BarrierPost", "BoomRest", "GuardBooth" stay put.

  sm_env_gate_roadblock.glb   (ROADBLOCK: gate_campo_obra)
      Two striped A-frame barricades closing the road, an amber lamp on each,
      a traffic cone worn as a hat and a forgotten hard hat; four cones off
      the edges and a sand pile with a shovel stuck in it.
      Nodes: "BarricadeLeft" (origin at its base centre, Godot (-2.0, 0, 0))
      and "BarricadeRight" (Godot (2.0, 0, 0)), each 3.7 m wide. OPEN: slide
      BarricadeLeft.position.x -= 5.5 (to -7.5) and BarricadeRight.position.x
      += 5.5 (to +7.5); they clear the cones. "Cones" (four cones at
      |x| = 4.45 and 4.95, origin at the GLB origin) and "SandPile" stay.

  sm_env_gate_checkpoint.glb  (EQUIPMENT: gate_nieve_equipo, gate_volcan_equipo)
      Park ranger post: plank cabin with a gable roof at (x 6.8, Godot z
      -0.4), skis leaning on it, binoculars and a mug on the window sill; a
      big ranger sign on two logs at x = -6.3 with a mountain-and-pine
      plaque; a painted log boom with a padlocked chain and a "no entry"
      disc across the road.
      Nodes: "Boom" (origin at the hinge, Godot (-4.4, 0.95, 0.0); the log
      runs toward +X to x = +4.4). OPEN: Boom.rotation.z = +PI/2 (+90 deg
      about its local Godot Z, the tip goes up). "Door" (origin at its
      hinge, Godot (5.645, 0.0, 0.03); the leaf runs toward Godot -Z on the
      road-facing wall x = 5.7). OPEN: Door.rotation.y = +PI/2 (+90 deg about
      Godot Y swings it out toward the road; a dark doorway shows behind).
      "Board" is the blank cream plate of the big sign (origin at the centre
      of its front face, Godot (-6.3, 1.55, -0.06), facing Godot +Z) if a
      Label3D should go there. "RangerCabin", "RangerSign", "BoomPost",
      "BoomRest" stay put.

  sm_env_gate_sign_coast.glb     (WATER, no collision)
  sm_env_gate_sign_mountain.glb  (ALTITUDE, no collision)
      A sign on two posts, origin at its base centre. "Board" is a blank
      cream 2.0 x 1.0 m plate for the Label3D: origin at the centre of its
      front face, Godot (0, 1.6, 0.0), facing Godot +Z (the side the model
      is seen from; put the Label3D at Board.position + (0, 0, 0.02), not
      billboarded). Everything else is one static mesh "Sign". Coast: a wave with a sailboat riding it on top, a
      seagull on the corner and a life ring on the post. Mountain: snowy
      peaks on top, a little plane flying over them on a wire, snow drifts.

Pass group names after "--" to rebuild only some of them:
    blender --background --factory-startup --python build_world_gates.py -- barrier signs
Groups: barrier, roadblock, checkpoint, signs.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from lowpoly_kit import (PALETTE, ROOT, blob, clear, cone, cube, cylinder,  # noqa: E402
                         export, flat_poly, gable_roof, mat, triangle_count)


def srgb(hex_code):
    """Palette hex (as in docs/direccion-visual.md) to the linear RGBA the kit uses."""
    out = []
    for i in (0, 2, 4):
        c = int(hex_code[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


PALETTE.update({
    # Shared with the train and street props (same hex, same names).
    "danger_red": srgb("d8322b"), "charcoal": srgb("2b2f36"),
    "brass": srgb("e8b43c"), "ui_yellow": srgb("ffc93c"),
    "logo_cardboard": srgb("e0a867"), "loco_blue": srgb("2f6fb5"),
    # New for the gates.
    "booth_white": srgb("eef0e8"),
    "board_cream": srgb("fff6e6"),          # PAPER: the Label3D reads on it
    "ranger_wood": srgb("9a6a3c"), "ranger_dark": srgb("5e3b20"),
    "ranger_green": srgb("3f6b3a"),
    "barricade_orange": srgb("ff9f1c"),     # ORANGE of the UI palette
    "sea": srgb("3a8fc4"), "sea_foam": srgb("e8f6f4"),
    "driftwood": srgb("b9a58a"), "sand": srgb("d9b97a"),
    "doorway": srgb("1e2235"),              # INK
})

OUT = os.path.join(ROOT, "models", "environment", "gates")
REPORT = []
ALONG_X = (0.0, math.pi / 2.0, 0.0)     # cylinder/cone lying along X
ALONG_Y = (math.pi / 2.0, 0.0, 0.0)     # cylinder/cone lying along Y


def done(filename):
    REPORT.append((filename, triangle_count()))
    export(os.path.join(OUT, filename))


# --- Helpers (Blender coordinates) -----------------------------------------

def snapshot():
    return set(o.name for o in bpy.context.scene.objects)


def group(before, name):
    """Joins every object made since `before` into one mesh `name`, with its
    transform applied (origin at the GLB origin)."""
    objs = [o for o in bpy.context.scene.objects if o.name not in before]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def pivot(o, point):
    """Moves `o`'s origin to `point` without moving the mesh."""
    p = Vector(point)
    o.data.transform(Matrix.Translation(-p))
    o.location = p
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


def lathe(name, profile, sides, material, centre=(0.0, 0.0), caps=True):
    """Revolves (radius, z) points about the vertical axis through `centre`;
    a radius of 0 is a single tip vertex."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((centre[0], centre[1], z))])
        else:
            rings.append([bm.verts.new((centre[0] + r * math.cos(k * math.tau / sides),
                                        centre[1] + r * math.sin(k * math.tau / sides), z))
                          for k in range(sides)])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            if len(a) == 1:
                bm.faces.new([a[0], b[k], b[j]])
            elif len(b) == 1:
                bm.faces.new([a[k], a[j], b[0]])
            else:
                bm.faces.new([a[k], a[j], b[j], b[k]])
    if caps:
        if len(rings[0]) > 1:
            bm.faces.new(list(reversed(rings[0])))
        if len(rings[-1]) > 1:
            bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def extrude_x(name, profile, x0, x1, material, y=0.0):
    """A convex (y, z) profile swept along X from x0 to x1."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    a = [bm.verts.new((x0, y + py, pz)) for py, pz in profile]
    b = [bm.verts.new((x1, y + py, pz)) for py, pz in profile]
    count = len(profile)
    for j in range(count):
        k = (j + 1) % count
        bm.faces.new([a[j], a[k], b[k], b[j]])
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def taper_bar(name, x0, x1, h0, h1, d0, d1, material, y=0.0, z=0.0):
    """A box along X whose height/depth go from (h0, d0) at x0 to (h1, d1) at x1."""
    profile = [(-d0 / 2, -h0 / 2), (d0 / 2, -h0 / 2), (d0 / 2, h0 / 2), (-d0 / 2, h0 / 2)]
    obj = extrude_x(name, profile, x0, x1, material, y)
    for v in obj.data.vertices:
        if abs(v.co.x - x1) < 1e-5:
            v.co.y = y + (v.co.y - y) * d1 / d0
            v.co.z = v.co.z * h1 / h0
        v.co.z += z
    obj.data.update()
    return obj


def torus(name, loc, major, minor, material, rot=(0, 0, 0), segments=8, ring=4):
    bpy.ops.mesh.primitive_torus_add(major_segments=segments, minor_segments=ring, major_radius=major,
                                     minor_radius=minor, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat(material))
    return o


def traffic_cone(name, x, y, sides=8, z=0.0, tilt=(0.0, 0.0, 0.0)):
    """A chunky 0.75 m cone; `z`/`tilt` let it sit somewhere else (a hat)."""
    before = snapshot()
    cube(name + "Base", (0, 0, 0.025), (0.42, 0.42, 0.05), "rubber", 0.03)
    body = [(0.18, 0.05), (0.13, 0.32), (0.075, 0.6), (0.04, 0.72), (0.0, 0.74)]
    lathe(name, body, sides, "orange")
    lathe(name + "Band", [(0.152, 0.2), (0.118, 0.38)], sides, "reflector", caps=False)
    lathe(name + "Band", [(0.104, 0.44), (0.082, 0.54)], sides, "reflector", caps=False)
    objs = [o for o in bpy.context.scene.objects if o.name not in before]
    for o in objs:
        o.rotation_euler = tilt
        o.location = Vector(o.location) + Vector((x, y, z))
    return objs


def stripes(name, x0, x1, z0, z1, y, toward, width, gap, slant, material):
    """Diagonal stripe decals on a board face lying in the plane y. `toward`
    is -1 for a face looking at Blender -Y (Godot +Z), +1 for +Y."""
    t = 0.006
    y0 = y - t if toward < 0 else y
    x = x0 + 0.04
    while x + width + slant <= x1 - 0.04:
        flat_poly(name, [(x, z0), (x + width, z0), (x + width + slant, z1), (x + slant, z1)], y0, t, material)
        x += width + gap


def boom_post_cabinet(x, y):
    cube("PostBase", (x, y, 0.08), (0.62, 0.6, 0.16), "concrete", 0.04)
    cube("PostCabinet", (x, y, 0.58), (0.44, 0.4, 0.86), "warning", 0.05)
    for z in (0.36, 0.7):
        cube("PostStripe", (x, y, z), (0.45, 0.41, 0.08), "sign_ink")
    cube("PostCap", (x, y, 1.04), (0.5, 0.46, 0.08), "charcoal", 0.03)


# =============================================================================
# Barrier: striped boom + drive post + guard booth (BARRIER gates)
# =============================================================================

BARRIER_HINGE = (4.45, 0.0, 1.0)     # Blender; Godot (4.45, 1.0, 0.0)


def guard_booth(cx, cy):
    w = 1.6
    cube("BoothPlinth", (cx, cy, 0.08), (1.9, 1.9, 0.16), "concrete", 0.04)
    cube("BoothLower", (cx, cy, 0.61), (w, w, 0.9), "booth_white", 0.04)
    cube("BoothStripe", (cx, cy, 0.9), (w + 0.02, w + 0.02, 0.1), "loco_blue")
    cube("BoothGlass", (cx, cy, 1.6), (w - 0.1, w - 0.1, 1.1), "window")
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cube("BoothPost", (cx + sx * (w / 2 - 0.06), cy + sy * (w / 2 - 0.06), 1.6), (0.13, 0.13, 1.12), "loco_blue")
    for sx, sy, sizex, sizey in ((-1, 0, 0.05, 0.06), (0, -1, 0.06, 0.05), (0, 1, 0.06, 0.05)):
        cube("BoothMullion", (cx + sx * (w / 2 - 0.04), cy + sy * (w / 2 - 0.04), 1.6), (sizex, sizey, 1.1), "loco_blue")
    cube("BoothBand", (cx, cy, 2.29), (w, w, 0.28), "booth_white", 0.04)
    cube("BoothRoof", (cx, cy, 2.5), (w + 0.5, w + 0.5, 0.16), "loco_blue", 0.06)
    cube("BoothRoofCap", (cx, cy, 2.62), (w * 0.6, w * 0.6, 0.1), "loco_blue", 0.03)
    cylinder("BoothLampBase", (cx, cy, 2.7), 0.1, 0.06, "charcoal", 8)
    blob("BoothLamp", (cx, cy, 2.8), (0.1, 0.1, 0.11), "lamp")
    # Door on the far side (+X), glazed top.
    cube("BoothDoor", (cx + w / 2 + 0.01, cy, 1.1), (0.05, 0.72, 1.86), "loco_blue", 0.01)
    cube("BoothDoorGlass", (cx + w / 2 + 0.04, cy, 1.55), (0.02, 0.5, 0.7), "window")
    blob("BoothDoorKnob", (cx + w / 2 + 0.06, cy - 0.26, 1.05), (0.035, 0.035, 0.035), "brass")
    # Counter facing the road with the classic wink: a parcel waiting for us,
    # and the guard's mug (the guard went for more coffee).
    sx = cx - w / 2 - 0.1
    cube("BoothCounter", (sx, cy, 1.1), (0.26, w * 0.9, 0.06), "booth_white", 0.015)
    cube("Parcel", (sx, cy + 0.3, 1.22), (0.2, 0.26, 0.18), "logo_cardboard", 0.01, rot=(0, 0, 0.15))
    cube("ParcelTape", (sx, cy + 0.3, 1.312), (0.2, 0.05, 0.006), "ui_yellow", rot=(0, 0, 0.15))
    cylinder("Mug", (sx, cy - 0.35, 1.18), 0.045, 0.1, "danger_red", 8)
    torus("MugHandle", (sx, cy - 0.41, 1.18), 0.03, 0.01, "danger_red", rot=(math.pi / 2, 0, 0), segments=6, ring=3)
    # A potted plant by the door.
    cylinder("Pot", (cx + 1.05, cy + 0.6, 0.14), 0.13, 0.28, "terracotta", 8)
    blob("PotPlant", (cx + 1.05, cy + 0.6, 0.38), (0.17, 0.17, 0.16), "leaf_light")


def barrier():
    clear()
    hx, hy, hz = BARRIER_HINGE
    before = snapshot()
    boom_post_cabinet(hx, 0.34)
    cylinder("BoomShaft", (hx, 0.1, hz), 0.05, 0.16, "metal", 8, rot=ALONG_Y)
    group(before, "BarrierPost")

    # Fork rest at the far edge of the road.
    before = snapshot()
    rx = -4.15
    cube("RestFoot", (rx, 0, 0.05), (0.34, 0.34, 0.1), "concrete", 0.03)
    cube("RestPost", (rx, 0, 0.47), (0.1, 0.1, 0.8), "sign_white")
    cube("RestBand", (rx, 0, 0.5), (0.11, 0.11, 0.14), "danger_red")
    cube("RestFork", (rx, 0, 0.88), (0.12, 0.26, 0.04), "charcoal")
    for y in (-0.11, 0.11):
        cube("RestProng", (rx, y, 0.95), (0.08, 0.04, 0.14), "charcoal")
    group(before, "BoomRest")

    before = snapshot()
    guard_booth(6.3, 1.3)
    group(before, "GuardBooth")

    # Boom: hub on the hinge, counterweight toward +X, striped arm toward -X.
    before = snapshot()
    cylinder("BoomHub", (hx, 0, hz), 0.15, 0.2, "sign_ink", 12, rot=ALONG_Y)
    cylinder("BoomHubCap", (hx, -0.11, hz), 0.07, 0.03, "warning", 8, rot=ALONG_Y)
    cube("Counterweight", (hx + 0.47, 0, hz), (0.56, 0.24, 0.32), "sign_ink", 0.04)
    cube("CounterweightStripe", (hx + 0.47, 0, hz), (0.12, 0.25, 0.33), "warning")
    tip, start, parts = -4.3, hx - 0.1, 8
    step = (tip - start) / parts
    length = start - tip
    for i in range(parts):
        x0, x1 = start + i * step, start + (i + 1) * step
        t0, t1 = (start - x0) / length, (start - x1) / length
        taper_bar("BoomStripe", x0, x1, 0.17 - 0.06 * t0, 0.17 - 0.06 * t1, 0.12 - 0.04 * t0,
                  0.12 - 0.04 * t1, "danger_red" if i % 2 == 0 else "sign_white", 0.0, hz)
    blob("BoomTip", (tip - 0.02, 0, hz), (0.06, 0.05, 0.06), "danger_red")
    for x in (-1.8, 2.0):
        cube("BoomLampBase", (x, 0, hz + 0.08), (0.12, 0.08, 0.04), "sign_ink")
        blob("BoomLamp", (x, 0, hz + 0.13), (0.06, 0.05, 0.05), "danger_red")
    # A round stop disc hanging off the middle of the arm (both faces).
    cube("DiscHanger", (-0.6, 0, hz - 0.17), (0.04, 0.03, 0.2), "charcoal")
    cylinder("DiscRim", (-0.6, 0, hz - 0.5), 0.28, 0.03, "sign_white", 14, rot=ALONG_Y)
    cylinder("Disc", (-0.6, 0, hz - 0.5), 0.23, 0.045, "danger_red", 14, rot=ALONG_Y)
    cube("DiscBar", (-0.6, 0, hz - 0.5), (0.3, 0.06, 0.07), "sign_white")
    boom = group(before, "Boom")
    pivot(boom, BARRIER_HINGE)
    done("sm_env_gate_barrier.glb")


# =============================================================================
# Roadblock: two A-frame barricades that slide aside + cones (ROADBLOCK)
# =============================================================================

def barricade(name, cx, hat=False, hard_hat=False):
    before = snapshot()
    half = 1.85
    for sx in (-1.0, 1.0):
        x = cx + sx * 1.6
        for sy in (-1.0, 1.0):
            bar("BarricadeLeg", (x, sy * 0.4, 0.0), (x, sy * 0.06, 1.18), 0.07, "charcoal")
            cube("BarricadeFoot", (x, sy * 0.4, 0.03), (0.16, 0.2, 0.06), "rubber", 0.02)
        cube("BarricadeHinge", (x, 0, 1.18), (0.12, 0.2, 0.08), "charcoal", 0.02)
    for z in (0.62, 0.98):
        y = 0.4 - 0.34 * (z / 1.18) + 0.045
        for side in (-1.0, 1.0):
            cube("BarricadeBoard", (cx, side * y, z), (half * 2, 0.04, 0.24), "sign_white")
            stripes("BarricadeStripe", cx - half, cx + half, z - 0.12, z + 0.12, side * (y + 0.02), side,
                    0.3, 0.28, 0.16, "barricade_orange")
    # Amber flasher on one end.
    lx = cx + (1.6 if cx < 0 else -1.6)
    cube("FlasherBracket", (lx, 0, 1.27), (0.08, 0.06, 0.1), "charcoal")
    cylinder("FlasherBody", (lx, 0, 1.38), 0.1, 0.12, "warning", 10, rot=ALONG_Y)
    cylinder("FlasherLens", (lx, -0.065, 1.38), 0.075, 0.02, "lamp", 10, rot=ALONG_Y)
    cylinder("FlasherLens", (lx, 0.065, 1.38), 0.075, 0.02, "lamp", 10, rot=ALONG_Y)
    if hat:
        # Somebody gave the barricade a hat.
        traffic_cone("HatCone", cx - 0.5, 0.0, 8, z=1.21, tilt=(0.0, 0.12, 0.0))
    if hard_hat:
        hx = cx + 0.6
        lathe("HardHat", [(0.15, 1.24), (0.14, 1.3), (0.11, 1.36), (0.06, 1.39), (0.0, 1.4)], 10, "ui_yellow",
              centre=(hx, 0.0))
        cylinder("HardHatBrim", (hx, 0.0, 1.235), 0.19, 0.025, "ui_yellow", 10)
    o = group(before, name)
    pivot(o, (cx, 0.0, 0.0))
    return o


def roadblock():
    clear()
    before = snapshot()
    for x, y in ((-4.45, -0.25), (-4.95, 0.3), (4.45, 0.25), (4.95, -0.3)):
        traffic_cone("Cone", x, y)
    group(before, "Cones")

    # Sand pile with a shovel stuck in it, off the road behind the left side.
    before = snapshot()
    pile = blob("Sand", (-5.9, 1.6, 0.0), (0.75, 0.6, 0.45), "sand", 1)
    for v in pile.data.vertices:
        if v.co.z < 0:
            v.co.z = 0.0
    bar("ShovelHandle", (-5.85, 1.55, 0.25), (-5.6, 1.4, 1.25), 0.045, "ranger_wood")
    cube("ShovelGrip", (-5.58, 1.39, 1.3), (0.16, 0.05, 0.05), "ranger_wood", rot=(0, -0.24, 0))
    cube("ShovelBlade", (-5.89, 1.58, 0.18), (0.24, 0.04, 0.3), "metal", 0.02, rot=(0, -0.24, 0.5))
    group(before, "SandPile")

    barricade("BarricadeLeft", -2.0, hard_hat=True)
    barricade("BarricadeRight", 2.0, hat=True)
    done("sm_env_gate_roadblock.glb")


# =============================================================================
# Checkpoint: park ranger cabin + big sign + log boom (EQUIPMENT gates)
# =============================================================================

CHECK_HINGE = (-4.4, 0.0, 0.95)       # Blender; Godot (-4.4, 0.95, 0.0)
CABIN = (6.8, 0.4)                    # Blender x, y of the cabin centre
CABIN_W, CABIN_D, CABIN_H = 2.2, 2.0, 2.3
DOOR_W, DOOR_H = 0.9, 1.95


def ranger_cabin():
    cx, cy = CABIN
    wall_x = cx - CABIN_W / 2
    cube("CabinPlinth", (cx, cy, 0.09), (CABIN_W + 0.2, CABIN_D + 0.2, 0.18), "stone", 0.04)
    cube("CabinWalls", (cx, cy, 0.18 + CABIN_H / 2), (CABIN_W, CABIN_D, CABIN_H), "ranger_wood", 0.03)
    for z in (0.75, 1.35, 1.95):
        cube("CabinPlank", (cx, cy, z), (CABIN_W + 0.02, CABIN_D + 0.02, 0.04), "ranger_dark")
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cube("CabinCorner", (cx + sx * CABIN_W / 2, cy + sy * CABIN_D / 2, 0.18 + CABIN_H / 2),
                 (0.12, 0.12, CABIN_H), "ranger_dark", 0.02)
    before_roof = snapshot()
    gable_roof("CabinRoof", 0.0, CABIN_W, CABIN_D, 0.62, "ranger_green", "ranger_wood", overhang=0.3, thickness=0.14,
               ridge_material="ranger_dark")
    for o in [o for o in bpy.context.scene.objects if o.name not in before_roof]:
        o.location.x += cx
        o.location.y += cy
        o.location.z += 0.18 + CABIN_H
    # Stovepipe.
    cylinder("Stovepipe", (cx + 0.5, cy + 0.5, 3.35), 0.08, 0.7, "charcoal", 8)
    cone("StovepipeHat", (cx + 0.5, cy + 0.5, 3.75), 0.15, 0.0, 0.12, "charcoal", 8)
    # Doorway (dark) behind the door, with a frame.
    dy = cy
    cube("Doorway", (wall_x - 0.005, dy, 0.18 + DOOR_H / 2), (0.02, DOOR_W, DOOR_H), "doorway")
    for y in (dy - DOOR_W / 2 - 0.05, dy + DOOR_W / 2 + 0.05):
        cube("DoorFrame", (wall_x - 0.015, y, 0.18 + DOOR_H / 2 + 0.03), (0.03, 0.1, DOOR_H + 0.06), "ranger_dark")
    cube("DoorLintel", (wall_x - 0.015, dy, 0.18 + DOOR_H + 0.08), (0.03, DOOR_W + 0.2, 0.1), "ranger_dark")
    cube("DoorStep", (wall_x - 0.25, dy, 0.09), (0.4, DOOR_W + 0.2, 0.18), "stone", 0.03)
    # Window on the face the traffic sees (-Y) with shutters and a sill.
    wy = cy - CABIN_D / 2
    cube("CabinWindow", (cx + 0.15, wy - 0.01, 1.45), (0.8, 0.03, 0.62), "window")
    cube("CabinWindowBar", (cx + 0.15, wy - 0.03, 1.45), (0.05, 0.02, 0.62), "ranger_dark")
    for sx in (-1.0, 1.0):
        cube("Shutter", (cx + 0.15 + sx * 0.6, wy - 0.03, 1.45), (0.38, 0.04, 0.7), "ranger_green", 0.01)
    cube("WindowSill", (cx + 0.15, wy - 0.12, 1.12), (1.0, 0.24, 0.05), "ranger_dark", 0.01)
    cylinder("Mug", (cx + 0.45, wy - 0.12, 1.19), 0.045, 0.1, "sign_white", 8)
    for dx in (-0.06, 0.06):
        cylinder("Binocular", (cx - 0.1 + dx, wy - 0.14, 1.19), 0.04, 0.12, "charcoal", 8, rot=ALONG_Y)
    # Skis and poles leaning on the wall: the equipment you do not have.
    for i, x in enumerate((cx - 0.75, cx - 0.55)):
        bar("Ski", (x, wy - 0.45, 0.02), (x - 0.05, wy - 0.06, 1.75), 0.08, "danger_red" if i == 0 else "loco_blue", 0.025)
        bar("SkiPole", (x + 0.12, wy - 0.38, 0.0), (x + 0.1, wy - 0.06, 1.3), 0.025, "metal")
    # Ranger badge over the door: a pine on a yellow shield.
    # Ranger badge on the gable over the window: a pine on a yellow shield.
    bx, bz = cx, 0.18 + CABIN_H + 0.3
    flat_poly("BadgeShield", [(bx - 0.18, bz + 0.12), (bx + 0.18, bz + 0.12), (bx + 0.18, bz - 0.05), (bx, bz - 0.2),
                              (bx - 0.18, bz - 0.05)], wy - 0.07, 0.03, "ui_yellow", plane="xz")
    flat_poly("BadgePine", [(bx - 0.1, bz - 0.1), (bx + 0.1, bz - 0.1), (bx, bz + 0.08)], wy - 0.08, 0.01,
              "ranger_green", plane="xz")


def pine(cx, y, z0, scale, material):
    pts = [(-0.5, 0.0), (-0.18, 0.0), (-0.36, 0.3), (-0.12, 0.3), (-0.26, 0.58), (0.0, 0.95),
           (0.26, 0.58), (0.12, 0.3), (0.36, 0.3), (0.18, 0.0), (0.5, 0.0)]
    flat_poly("Pine", [(cx + px * scale, z0 + pz * scale) for px, pz in pts], y, 0.03, material)
    flat_poly("PineTrunk", [(cx - 0.05 * scale, z0 - 0.12 * scale), (cx + 0.05 * scale, z0 - 0.12 * scale),
                            (cx + 0.05 * scale, z0), (cx - 0.05 * scale, z0)], y, 0.03, "ranger_dark")


def ranger_sign():
    sx = -6.3
    for x in (sx - 1.15, sx + 1.15):
        cylinder("SignLog", (x, 0.08, 1.35), 0.11, 2.7, "ranger_dark", 8)
        blob("SignLogCap", (x, 0.08, 2.72), (0.11, 0.11, 0.06), "ranger_dark")
    cube("SignFrame", (sx, 0.12, 1.55), (2.5, 0.08, 1.2), "ranger_wood", 0.03)
    # Little gable over the sign.
    for side in (-1.0, 1.0):
        cube("SignRoof", (sx + side * 0.68, 0.12, 2.68), (1.5, 0.4, 0.07), "ranger_green", 0.02, rot=(0, side * 0.32, 0))
    # Plaque on top: snowy mountain and a pine.
    flat_poly("SignPlaque", [(sx - 0.75, 2.12), (sx + 0.75, 2.12), (sx + 0.75, 2.5), (sx - 0.75, 2.5)],
              0.06, 0.06, "ranger_wood")
    flat_poly("PlaqueMountain", [(sx - 0.62, 2.16), (sx - 0.2, 2.47), (sx + 0.08, 2.28), (sx + 0.3, 2.42), (sx + 0.62, 2.16)],
              0.045, 0.02, "mountain_far")
    flat_poly("PlaqueSnow", [(sx - 0.33, 2.375), (sx - 0.2, 2.47), (sx - 0.08, 2.385)], 0.035, 0.012, "mountain_snow")
    pine(sx + 0.48, 0.035, 2.2, 0.26, "ranger_green")
    group_board = snapshot()
    cube("Board", (sx, 0.07, 1.55), (2.2, 0.02, 0.95), "board_cream", 0.005)
    return group_board


def checkpoint():
    clear()
    hx, hy, hz = CHECK_HINGE
    before = snapshot()
    ranger_cabin()
    group(before, "RangerCabin")

    before = snapshot()
    board_before = ranger_sign()
    board = group(board_before, "Board")
    pivot(board, (-6.3, 0.06, 1.55))
    group(before | {"Board"}, "RangerSign")

    before = snapshot()
    cylinder("BoomPostLog", (hx, 0.22, 0.6), 0.13, 1.2, "ranger_dark", 8)
    blob("BoomPostCap", (hx, 0.22, 1.2), (0.13, 0.13, 0.07), "ranger_dark")
    cylinder("BoomPin", (hx, 0.06, hz), 0.04, 0.2, "metal", 6, rot=ALONG_Y)
    cube("BoomPostStone", (hx, 0.22, 0.08), (0.5, 0.5, 0.16), "stone", 0.04)
    group(before, "BoomPost")

    before = snapshot()
    rx = 4.45
    cylinder("RestLog", (rx, 0, 0.42), 0.1, 0.84, "ranger_dark", 8)
    for y in (-0.1, 0.1):
        cube("RestProng", (rx, y, 0.92), (0.08, 0.04, 0.18), "ranger_dark")
    cube("RestReflector", (rx, -0.1, 0.55), (0.1, 0.02, 0.16), "danger_red")
    group(before, "BoomRest")

    # Boom: a painted log from the hinge toward +X, a stone counterweight
    # toward -X, a padlocked chain at the tip and a "no entry" disc.
    before = snapshot()
    blob("BoomHub", (hx, -0.04, hz), (0.13, 0.12, 0.13), "ranger_dark")
    cube("BoomWeight", (hx - 0.32, 0, hz), (0.36, 0.26, 0.3), "concrete", 0.05)
    tip = 4.4
    seg = (tip - (hx + 0.08)) / 7
    for i in range(7):
        x0 = hx + 0.08 + i * seg
        cylinder("BoomLog", (x0 + seg / 2, 0, hz), 0.075, seg, "ui_yellow" if i % 2 == 0 else "ranger_dark", 8, rot=ALONG_X)
    blob("BoomEnd", (tip, 0, hz), (0.04, 0.075, 0.075), "ui_yellow")
    for k in range(3):
        torus("ChainLink", (tip - 0.1, 0, hz - 0.12 - k * 0.09), 0.045, 0.012, "metal",
              rot=(0, math.pi / 2 if k % 2 else 0.0, math.pi / 2), segments=6, ring=3)
    cube("Padlock", (tip - 0.1, 0, hz - 0.43), (0.11, 0.06, 0.1), "brass", 0.015)
    torus("PadlockShackle", (tip - 0.1, 0, hz - 0.37), 0.035, 0.01, "metal", rot=(math.pi / 2, 0, 0), segments=6, ring=3)
    cube("DiscHanger", (0.6, 0, hz - 0.15), (0.04, 0.03, 0.16), "charcoal")
    cylinder("DiscRim", (0.6, 0, hz - 0.46), 0.27, 0.03, "sign_white", 14, rot=ALONG_Y)
    cylinder("Disc", (0.6, 0, hz - 0.46), 0.22, 0.045, "danger_red", 14, rot=ALONG_Y)
    cube("DiscBar", (0.6, 0, hz - 0.46), (0.28, 0.06, 0.07), "sign_white")
    boom = group(before, "Boom")
    pivot(boom, CHECK_HINGE)

    # Door: origin on its hinge (the -Y edge of the doorway), leaf toward +Y.
    before = snapshot()
    wall_x = CABIN[0] - CABIN_W / 2
    hinge = (wall_x - 0.055, CABIN[1] - (DOOR_W - 0.04) / 2, 0.0)   # Blender; Godot (5.645, 0, 0.03)
    cube("DoorLeaf", (wall_x - 0.055, CABIN[1], 0.18 + DOOR_H / 2), (0.05, DOOR_W - 0.04, DOOR_H - 0.03), "ranger_green", 0.015)
    for z in (0.5, 1.2, 1.8):
        cube("DoorBrace", (wall_x - 0.09, CABIN[1], z), (0.02, DOOR_W - 0.1, 0.08), "ranger_dark")
    cylinder("DoorPorthole", (wall_x - 0.088, CABIN[1], 1.6), 0.12, 0.02, "window", 10, rot=ALONG_X)
    blob("DoorKnob", (wall_x - 0.1, CABIN[1] + DOOR_W / 2 - 0.12, 1.05), (0.035, 0.035, 0.035), "brass")
    door = group(before, "Door")
    pivot(door, hinge)
    done("sm_env_gate_checkpoint.glb")


# =============================================================================
# Coast / mountain signs (WATER / ALTITUDE gates, no collision)
# =============================================================================

BOARD_Z = 1.6


def ground_blob(name, loc, size, material):
    """A low mound sitting on the ground (nothing below z = 0)."""
    o = blob(name, loc, size, material)
    for v in o.data.vertices:
        v.co.z = max(v.co.z, 0.0)
    o.data.update()
    return o


def sign_base(post_material):
    for x in (-0.85, 0.85):
        cube("SignPost", (x, 0.12, (BOARD_Z + 0.65) / 2), (0.12, 0.12, BOARD_Z + 0.65), post_material, 0.02)
    cube("BoardFrame", (0, 0.06, BOARD_Z), (2.16, 0.08, 1.16), post_material, 0.03)
    before = snapshot()
    cube("Board", (0, 0.03, BOARD_Z), (2.0, 0.06, 1.0), "board_cream", 0.008)
    board = group(before, "Board")
    pivot(board, (0.0, 0.0, BOARD_Z))
    return board


def sign_coast():
    clear()
    sign_base("driftwood")
    top = BOARD_Z + 0.58
    # A wave rolling along the top that curls over on the right.
    wave = [(-1.05, top - 0.02)]
    for i in range(12):
        x = -1.05 + i * 0.14
        wave.append((x, top + 0.14 + 0.07 * math.sin(i * 1.4)))
    wave += [(0.65, top + 0.25), (0.78, top + 0.38), (0.92, top + 0.44), (1.02, top + 0.4), (1.02, top + 0.32),
             (0.92, top + 0.36), (0.86, top + 0.3), (0.95, top + 0.18), (1.05, top + 0.05), (1.05, top - 0.02)]
    flat_poly("Wave", wave, 0.03, 0.06, "sea")
    flat_poly("WaveFoam", [(0.92, top + 0.445), (1.025, top + 0.405), (1.025, top + 0.32), (0.92, top + 0.36)],
              0.02, 0.012, "sea_foam")
    # Sailboat riding it.
    bx = -0.35
    flat_poly("BoatHull", [(bx - 0.32, top + 0.2), (bx + 0.32, top + 0.2), (bx + 0.22, top + 0.08), (bx - 0.24, top + 0.08)],
              0.0, 0.1, "danger_red")
    cube("BoatMast", (bx, 0.05, top + 0.47), (0.03, 0.03, 0.55), "ranger_dark")
    flat_poly("BoatSail", [(bx - 0.02, top + 0.24), (bx - 0.3, top + 0.24), (bx - 0.02, top + 0.72)], 0.01, 0.04, "sign_white")
    flat_poly("BoatJib", [(bx + 0.03, top + 0.24), (bx + 0.24, top + 0.24), (bx + 0.03, top + 0.6)], 0.01, 0.04, "ui_yellow")
    flat_poly("BoatFlag", [(bx, top + 0.74), (bx + 0.12, top + 0.71), (bx, top + 0.68)], 0.04, 0.02, "danger_red")
    # A seagull resting on the top-left corner of the frame.
    gx, gz = -0.9, BOARD_Z + 0.58
    blob("GullBody", (gx, 0.06, gz + 0.08), (0.11, 0.06, 0.06), "sign_white")
    blob("GullHead", (gx - 0.09, 0.06, gz + 0.15), (0.045, 0.04, 0.045), "sign_white")
    cone("GullBeak", (gx - 0.15, 0.06, gz + 0.145), 0.015, 0.0, 0.05, "warning", 4, rot=(0, -math.pi / 2, 0))
    cube("GullWing", (gx + 0.02, 0.06, gz + 0.1), (0.14, 0.13, 0.03), "concrete", rot=(0, 0.15, 0))
    for dx in (-0.02, 0.02):
        cube("GullLeg", (gx + dx, 0.06, gz + 0.02), (0.01, 0.01, 0.05), "warning")
    # Life ring hanging on the left post (red and white quarters).
    for k in range(4):
        bpy.ops.mesh.primitive_torus_add(major_segments=12, minor_segments=4, major_radius=0.2, minor_radius=0.05,
                                         location=(-0.85, 0.0, 0.85), rotation=(math.pi / 2, 0, 0))
        ring = bpy.context.object
        ring.name = "LifeRing"
        ring.data.materials.append(mat("danger_red" if k % 2 == 0 else "sign_white"))
        bm = bmesh.new()
        bm.from_mesh(ring.data)
        a0, a1 = k * math.tau / 4, (k + 1) * math.tau / 4
        kill = []
        for f in bm.faces:
            c = f.calc_center_median()
            a = math.atan2(c.y, c.x) % math.tau
            if not (a0 <= a < a1):
                kill.append(f)
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        bm.to_mesh(ring.data)
        bm.free()
    cube("LifeRingHook", (-0.85, 0.03, 1.07), (0.04, 0.06, 0.04), "metal")
    for x in (-0.85, 0.85):
        ground_blob("SandMound", (x, 0.12, 0.0), (0.3, 0.25, 0.1), "sand")
    group({"Board"}, "Sign")
    done("sm_env_gate_sign_coast.glb")


def sign_mountain():
    clear()
    sign_base("ranger_dark")
    top = BOARD_Z + 0.58
    flat_poly("Peaks", [(-1.08, top - 0.02), (-0.55, top + 0.6), (-0.25, top + 0.3), (0.2, top + 0.85),
                        (0.6, top + 0.35), (0.8, top + 0.5), (1.08, top - 0.02)], 0.03, 0.06, "mountain_far")
    flat_poly("PeakSnow", [(0.0, top + 0.6), (0.2, top + 0.85), (0.4, top + 0.6), (0.3, top + 0.64),
                           (0.2, top + 0.57), (0.1, top + 0.64)], 0.02, 0.012, "mountain_snow")
    flat_poly("PeakSnow", [(-0.72, top + 0.4), (-0.55, top + 0.6), (-0.4, top + 0.45), (-0.5, top + 0.47),
                           (-0.58, top + 0.41)], 0.02, 0.012, "mountain_snow")
    # A little plane flying over the peaks on a wire.
    px, pz = 0.75, top + 1.0
    cylinder("PlaneWire", (px, 0.06, top + 0.58), 0.008, 0.6, "metal", 4)
    cylinder("PlaneBody", (px, 0.06, pz), 0.07, 0.5, "danger_red", 8, rot=ALONG_X)
    cone("PlaneNose", (px - 0.3, 0.06, pz), 0.07, 0.03, 0.1, "danger_red", 8, rot=(0, -math.pi / 2, 0))
    cube("PlaneWing", (px - 0.03, 0.06, pz + 0.02), (0.16, 0.7, 0.025), "ui_yellow", 0.01)
    cube("PlaneTail", (px + 0.22, 0.06, pz + 0.04), (0.08, 0.26, 0.02), "ui_yellow")
    cube("PlaneFin", (px + 0.23, 0.06, pz + 0.1), (0.08, 0.02, 0.12), "ui_yellow")
    cube("PlaneProp", (px - 0.36, 0.06, pz), (0.02, 0.03, 0.26), "charcoal")
    cube("PlaneWindow", (px - 0.1, -0.005, pz + 0.035), (0.1, 0.02, 0.04), "window")
    # Snow drifts at the posts and a cap on the frame.
    for x in (-0.85, 0.85):
        ground_blob("SnowDrift", (x, 0.12, 0.0), (0.32, 0.26, 0.14), "mountain_snow")
    cube("SnowCap", (-0.3, 0.06, BOARD_Z + 0.6), (1.0, 0.12, 0.05), "mountain_snow", 0.02)
    group({"Board"}, "Sign")
    done("sm_env_gate_sign_mountain.glb")


BUILDERS = {
    "barrier": [barrier],
    "roadblock": [roadblock],
    "checkpoint": [checkpoint],
    "signs": [sign_coast, sign_mountain],
}
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for group_name, builders in BUILDERS.items():
    if not ONLY or group_name in ONLY:
        for builder in builders:
            builder()

print("GATES_REPORT")
for name, tris in REPORT:
    print("  %-40s %6d tris" % (name, tris))
