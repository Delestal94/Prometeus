"""Depot props for Take My Package (N-135, 2026-09-27).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_depot_props.py

Replaces the boxes and cylinders the depot scripts (`scripts/gameplay/depot/`)
used to build out of code, in the same cartoon line as the train
(`build_rail_crossing.py`): chunky, rounded, flat palette colours, no
realistic textures. The scripts keep every collider, area, animated node and
the batching `depot_kit.gd` does; these GLBs are only what you see, folded
into the batches with `DepotKit.model()` or turned into one mesh with
`DepotKit.merged_mesh()` where a piece moves.

Everything here is authored in GODOT coordinates (x right, y up, z toward the
viewer) with the helpers G()/GS() doing the swap to Blender's Z-up (the glTF
exporter turns it back: Blender -Y is Godot +Z). Metres. Pieces, in
`models/environment/depot/`:

  Roller door (depot_roller_door.gd, door local space: base centre, the
  outside toward -Z):
    sm_env_depot_door_slat.glb          one 6.6 m curtain slat, centred.
    sm_env_depot_door_slat_window.glb   the same with a row of vision panes.
    sm_env_depot_door_bottom_bar.glb    bottom rail with rubber lip, handles.
    sm_env_depot_door_frame.glb         guide rails, drum housing, motor,
                                        striped jambs, bollards, threshold,
                                        push-button box, beacon bracket.
  Racking (depot.gd):
    sm_env_depot_rack_frame.glb         6.3 m pallet-rack upright frame, 1.3
                                        deep along X, base centre; its aisle
                                        side (+X) has the post guard.
    sm_env_depot_rack_beam_level.glb    one 5.6 m bay level: two beams and the
                                        deck, origin at the beam centre (deck
                                        top +0.085, where the pallets sit).
    sm_env_depot_shelf_frame.glb        2.7 m dispatch-shelf end frame, 1.0
                                        deep along X, base centre.
    sm_env_depot_shelf_deck.glb         one 2 m shelf deck, origin at the top
                                        of the deck (packages sit on it).
  Forklift (depot_forklift.gd, forks toward -Z):
    sm_env_depot_forklift_body.glb      chassis, guard, mast, wheels; origin
                                        on the floor under the body.
    sm_env_depot_forklift_carriage.glb  backrest and forks; origin = the
                                        Carriage node (it slides up +Y).
  Conveyor (depot.gd): sm_env_depot_conveyor.glb, 17 m, origin on the floor
    under the middle of the belt; belt top at 0.93 (the scrolling belt and
    its strip curtains stay in code).
  Lights and life (depot.gd):
    sm_env_depot_high_bay_lamp.glb      hanging shade, origin at the hook
                                        (0.65 m above the shade's centre).
    sm_env_depot_tube_fixture.glb       fluorescent trough and its cables,
                                        origin at the trough centre.
    sm_env_depot_ceiling_fan.glb        hub and five paddles, origin at the
                                        hub centre (turns about Y).
    sm_env_depot_wall_clock.glb         clock body, face toward +Z, origin at
                                        the centre of the face.
    sm_env_depot_clock_hand_hour.glb    hands pointing +Y from the spindle
    sm_env_depot_clock_hand_minute.glb  at the origin (they turn about Z).
    sm_env_depot_supply_padding.glb     bubble-wrap roll, base centre.
    sm_env_depot_supply_insurance.glb   clipboard with the stamped policy.

Pass names after "--" to rebuild only some of them:
    blender --background --factory-startup --python build_depot_props.py -- door rack forklift
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from lowpoly_kit import PALETTE, ROOT, clear, export, mat, triangle_count  # noqa: E402


def srgb(hex_code):
    """Palette hex (as in docs/direccion-visual.md) to the linear RGBA the kit uses."""
    out = []
    for i in (0, 2, 4):
        c = int(hex_code[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


PALETTE.update({
    # The depot's own colours (the ones depot*.gd already used, so the
    # rebuilt pieces sit in the same room), plus the UI accents.
    "depot_blue": srgb("2f5d8a"), "depot_orange": srgb("e8772e"),
    "deck_grey": srgb("a9b0b3"), "steel": srgb("59656a"),
    "steel_light": srgb("8a9599"), "housing": srgb("3b4c53"),
    "curtain": srgb("dfe2dc"), "curtain_rib": srgb("b9beb8"),
    "fork_dark": srgb("3b4247"), "warning": srgb("e7be51"),
    "sign_ink": srgb("1e2235"), "paper": srgb("fff6e6"),
    "ui_yellow": srgb("ffc93c"), "danger_red": srgb("d8322b"),
    "ui_mint": srgb("2dd4a3"), "ui_red": srgb("ff5e5b"),
    "fan_blade": srgb("c9ced0"), "door_glass": srgb("2a4550"),
    "bubble": srgb("a6d8ea"), "logo_cardboard": srgb("e0a867"),
    "go_green": srgb("3fbf6a"),
})

OUT = os.path.join(ROOT, "models", "environment", "depot")
REPORT = []
ALONG_X = (0.0, math.pi / 2.0, 0.0)   # cylinder lying along Godot X
ALONG_Z = (math.pi / 2.0, 0.0, 0.0)   # cylinder lying along Godot Z (Blender Y)


def G(x, y, z):
    """Godot point -> Blender point."""
    return (x, -z, y)


def GS(sx, sy, sz):
    """Godot box size -> Blender box size."""
    return (sx, sz, sy)


def done(filename):
    REPORT.append((filename, triangle_count()))
    export(os.path.join(OUT, filename))


def _finish(o, material):
    o.data.materials.append(mat(material))
    return o


def box(name, c, s, material, bevel=0.0, segs=1, yaw=0.0, pitch=0.0, roll=0.0):
    """Box centred at Godot `c`, size `s`; yaw about Y, pitch about X, roll about Z (Godot)."""
    bpy.ops.mesh.primitive_cube_add(location=G(*c))
    o = bpy.context.object
    o.name = name
    o.scale = tuple(v / 2.0 for v in GS(*s))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new("Round", "BEVEL")
        mod.width = bevel
        mod.segments = segs
        mod.limit_method = "NONE"
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.rotation_euler = (pitch, -roll, yaw)
    return _finish(o, material)


def cyl(name, c, r1, depth, material, verts=10, rot=(0, 0, 0), r2=None):
    """Cylinder (cone if r2 given) centred at Godot `c`; vertical unless rot says otherwise."""
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r1 if r2 is None else r2,
                                    depth=depth, location=G(*c))
    o = bpy.context.object
    o.name = name
    o.rotation_euler = rot
    return _finish(o, material)


def ball(name, c, size, material, subdivisions=1):
    """Ellipsoid with Godot radii `size` (x, y, z)."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=G(*c))
    o = bpy.context.object
    o.name = name
    o.scale = GS(*size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(o, material)


def bar(name, a, b, width, material, depth=None):
    """A square bar from Godot point `a` to `b` (bracing, handles, cables)."""
    pa, pb = Vector(G(*a)), Vector(G(*b))
    d = pb - pa
    bpy.ops.mesh.primitive_cube_add(location=(pa + pb) / 2.0)
    o = bpy.context.object
    o.name = name
    o.scale = (width / 2.0, (depth or width) / 2.0, d.length / 2.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    return _finish(o, material)


def rod(name, a, b, radius, material, verts=8):
    """A round rod from Godot point `a` to `b`."""
    pa, pb = Vector(G(*a)), Vector(G(*b))
    d = pb - pa
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius, depth=d.length,
                                    location=(pa + pb) / 2.0)
    o = bpy.context.object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    return _finish(o, material)


def panel(name, points, z0, z1, material):
    """A flat outline in Godot's XY plane (points are (x, y)), from Godot z0 to z1.
    Concave outlines are fine (arrows, clock hands)."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    front = [bm.verts.new(G(x, y, z1)) for x, y in points]
    back = [bm.verts.new(G(x, y, z0)) for x, y in points]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([front[i], front[j], back[j], back[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return _finish(obj, material)


def floor_panel(name, points, y0, y1, material):
    """A flat outline on Godot's floor plane (points are (x, z)), from height y0 to y1."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    top = [bm.verts.new(G(x, y1, z)) for x, z in points]
    bottom = [bm.verts.new(G(x, y0, z)) for x, z in points]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bottom)))
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([top[i], top[j], bottom[j], bottom[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return _finish(obj, material)


def sweep_x(name, profile, x0, x1, material):
    """A convex Godot (z, y) profile swept along X from x0 to x1."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    a = [bm.verts.new(G(x0, y, z)) for z, y in profile]
    b = [bm.verts.new(G(x1, y, z)) for z, y in profile]
    n = len(profile)
    for j in range(n):
        k = (j + 1) % n
        bm.faces.new([a[j], a[k], b[k], b[j]])
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return _finish(obj, material)


def hazard_stripes(prefix, x0, x1, y0, y1, z_front, material, pitch=0.5, slant=1.0):
    """Slanted warning stripes painted on a face looking toward -Z (outside),
    `z_front` its Godot z. The ink base is up to the caller."""
    band = pitch * 0.5
    rise = (x1 - x0) * 0.8 * slant
    y = y0 - abs(rise)
    while y < y1:
        pts = [(x0, y), (x0, y + band), (x1, y + band + rise), (x1, y + rise)]
        clipped = [(px, min(max(py, y0), y1)) for px, py in pts]
        area = abs(sum(clipped[i][0] * clipped[(i + 1) % 4][1] - clipped[(i + 1) % 4][0] * clipped[i][1] for i in range(4)))
        if area > 1e-3 and len({(round(p[0], 4), round(p[1], 4)) for p in clipped}) == 4:
            panel(prefix, clipped, z_front - 0.012, z_front, material)
        y += pitch


def floor_stripes(prefix, x0, x1, z0, z1, y_top, material, pitch=0.5):
    """Slanted warning stripes on the floor between x0..x1, z0..z1."""
    band = pitch * 0.5
    skew = (z1 - z0) * 0.7
    x = x0
    while x + band + skew <= x1 + 1e-6:
        floor_panel(prefix, [(x, z1), (x + band, z1), (x + band + skew, z0), (x + skew, z0)], y_top - 0.012, y_top, material)
        x += pitch


# =============================================================================
# Roller door.
# =============================================================================

DOOR_W, DOOR_H = 6.6, 4.8
SLAT_H = 0.28


def _slat_body():
    half = DOOR_W / 2.0
    # Softly bowed panel: fat in the middle, thin at the joints.
    profile = [(-0.028, -SLAT_H / 2), (0.028, -SLAT_H / 2), (0.04, -0.08), (0.045, 0.0),
               (0.04, 0.08), (0.028, SLAT_H / 2), (-0.028, SLAT_H / 2), (-0.04, 0.08),
               (-0.045, 0.0), (-0.04, -0.08)]
    sweep_x("Slat", profile, -half + 0.04, half - 0.04, "curtain")
    box("SlatRib", (0, SLAT_H / 2 + 0.005, 0), (DOOR_W - 0.08, 0.035, 0.1), "curtain_rib", 0.01)
    for side in (-1.0, 1.0):
        box("SlatShoe", (side * (half - 0.02), 0, 0), (0.08, SLAT_H - 0.02, 0.1), "sign_ink", 0.015)


def door_slat():
    clear()
    _slat_body()
    done("sm_env_depot_door_slat.glb")


def door_slat_window():
    clear()
    _slat_body()
    for i in range(5):
        x = -2.4 + i * 1.2
        box("VisionPaneRim", (x, 0, 0), (0.62, 0.19, 0.1), "sign_ink", 0.03, 2)
        box("VisionPane", (x, 0, 0), (0.52, 0.12, 0.11), "door_glass", 0.02)
    done("sm_env_depot_door_slat_window.glb")


def door_bottom_bar():
    clear()
    box("BottomRail", (0, 0.01, 0), (DOOR_W - 0.04, 0.07, 0.12), "steel_light", 0.02, 2)
    box("RubberLip", (0, -0.035, 0), (DOOR_W - 0.08, 0.04, 0.07), "sign_ink", 0.015)
    for x in (-1.3, 1.3):
        for side in (-1.0, 1.0):
            z = side * 0.1
            box("HandleGrip", (x, 0.03, z), (0.34, 0.05, 0.04), "ui_yellow", 0.018, 2)
            for dx in (-0.15, 0.15):
                box("HandleStem", (x + dx, 0.03, side * 0.07), (0.04, 0.04, 0.05), "ui_yellow")
    done("sm_env_depot_door_bottom_bar.glb")


def door_frame():
    clear()
    half = DOOR_W / 2.0
    top = DOOR_H
    for side in (-1.0, 1.0):
        # Guide rail with a rounded cap and a flared mouth at the bottom.
        box("GuideRail", (side * (half + 0.06), (top + 0.3) / 2, 0), (0.14, top + 0.3, 0.2), "housing", 0.025, 2)
        box("GuideFoot", (side * (half + 0.06), 0.06, 0), (0.22, 0.12, 0.28), "sign_ink", 0.03)
        # Outside jamb: ink board with fat yellow stripes, chevrons meeting in the middle.
        jx = side * (half + 0.3)
        box("Jamb", (jx, top / 2, -0.4), (0.36, top, 0.08), "sign_ink", 0.02)
        hazard_stripes("JambStripe", jx - 0.18, jx + 0.18, 0.05, top - 0.05, -0.44, "warning", 0.5, -side)
        # Bollard: yellow, domed, two ink bands (collider stays in the script).
        bx, bz = side * (half + 0.35), -0.7
        cyl("BollardBase", (bx, 0.03, bz), 0.2, 0.06, "concrete", 12)
        cyl("Bollard", (bx, 0.55, bz), 0.14, 1.0, "warning", 14)
        ball("BollardDome", (bx, 1.05, bz), (0.14, 0.09, 0.14), "warning")
        for y in (0.62, 0.84):
            cyl("BollardBand", (bx, y, bz), 0.146, 0.09, "sign_ink", 14)
    # Drum housing: a fat rounded barrel with yellow end caps and wall brackets.
    hy, hz = top + 0.45, 0.35
    cyl("DrumHousing", (0, hy, hz), 0.46, DOOR_W + 0.5, "housing", 16, ALONG_X)
    box("DrumSkirt", (0, top + 0.12, hz - 0.05), (DOOR_W + 0.5, 0.24, 0.62), "housing", 0.04)
    for side in (-1.0, 1.0):
        x = side * (DOOR_W / 2 + 0.3)
        cyl("DrumCap", (x, hy, hz), 0.5, 0.12, "ui_yellow", 16, ALONG_X)
        cyl("DrumCapBolt", (x + side * 0.07, hy, hz), 0.14, 0.05, "sign_ink", 10, ALONG_X)
    for x in (-2.2, 0.0, 2.2):
        box("DrumBand", (x, hy, hz), (0.08, 0.95, 0.95), "sign_ink", 0.03)
    # Motor on the right end: chunky box, cooling fins, a warning label.
    mx = DOOR_W / 2 + 0.2
    box("Motor", (mx, top + 0.2, 0.95), (0.5, 0.36, 0.34), "steel", 0.05, 2)
    for i in range(3):
        box("MotorFin", (mx - 0.15 + i * 0.15, top + 0.2, 1.13), (0.05, 0.3, 0.04), "sign_ink")
    box("MotorLabel", (mx, top + 0.41, 0.95), (0.3, 0.04, 0.2), "warning", 0.01)
    # Push-button box inside, beside the jamb: yellow, a green and a red button.
    px = half + 0.75
    box("ButtonBox", (px, 1.45, 0.1), (0.24, 0.4, 0.12), "ui_yellow", 0.04, 2)
    for y, colour in ((1.55, "go_green"), (1.36, "danger_red")):
        cyl("Button", (px, y, 0.17), 0.055, 0.05, colour, 10, ALONG_Z)
    box("ButtonConduit", (px, 3.1, 0.07), (0.05, 2.9, 0.05), "housing")
    # Beacon bracket outside, above the right jamb (the lens is the script's).
    bx = half + 0.3
    box("BeaconArm", (bx, top + 0.26, -0.4), (0.08, 0.06, 0.22), "sign_ink")
    cyl("BeaconBase", (bx, top + 0.31, -0.5), 0.1, 0.07, "sign_ink", 12)
    # Threshold: steel plate, ink bands either side with yellow stripes.
    box("Threshold", (0, 0.015, 0), (DOOR_W, 0.03, 0.5), "steel_light", 0.01)
    for zc in (-0.45, 0.45):
        box("ThresholdBand", (0, 0.01, zc), (DOOR_W, 0.02, 0.35), "sign_ink")
        floor_stripes("ThresholdStripe", -half, half, zc - 0.175, zc + 0.175, 0.024, "warning", 0.55)
    done("sm_env_depot_door_frame.glb")


# =============================================================================
# Racking.
# =============================================================================

def rack_frame():
    clear()
    depth, height = 1.3, 6.3
    xs = (-depth / 2, depth / 2)
    for x in xs:
        box("Upright", (x, height / 2, 0), (0.12, height, 0.1), "depot_blue", 0.02)
        box("UprightFoot", (x, 0.015, 0), (0.22, 0.03, 0.2), "sign_ink", 0.01)
        box("UprightCap", (x, height + 0.03, 0), (0.15, 0.06, 0.13), "ui_yellow", 0.025, 2)
    levels = [0.3 + i * 1.2 for i in range(6)]
    for i, y in enumerate(levels):
        bar("Brace", (xs[0], y, 0), (xs[1], y, 0), 0.045, "depot_blue")
        if i + 1 < len(levels):
            a = (xs[0], y) if i % 2 == 0 else (xs[1], y)
            c = (xs[1], levels[i + 1]) if i % 2 == 0 else (xs[0], levels[i + 1])
            bar("Brace", (a[0], a[1], 0), (c[0], c[1], 0), 0.04, "depot_blue")
    # Post guard on the aisle side: a fat yellow boot with an ink band.
    gx = depth / 2 + 0.04
    box("PostGuard", (gx, 0.22, 0), (0.24, 0.44, 0.22), "warning", 0.05, 2)
    box("PostGuardBand", (gx, 0.3, 0), (0.25, 0.08, 0.23), "sign_ink")
    done("sm_env_depot_rack_frame.glb")


def rack_beam_level():
    clear()
    depth, length = 1.3, 5.6
    for x in (-depth / 2, depth / 2):
        box("Beam", (x, 0, 0), (0.07, 0.13, length - 0.12), "depot_orange", 0.02)
        for z in (-length / 2 + 0.1, length / 2 - 0.1):
            box("BeamClip", (x, 0, z), (0.09, 0.17, 0.08), "sign_ink", 0.01)
    box("Deck", (0, 0.0725, 0), (depth - 0.06, 0.025, length - 0.2), "deck_grey", 0.008)
    for i in range(8):
        z = -length / 2 + 0.45 + i * (length - 0.9) / 7
        box("DeckChannel", (0, 0.045, z), (depth, 0.03, 0.06), "steel")
    done("sm_env_depot_rack_beam_level.glb")


def shelf_frame():
    clear()
    depth, height = 1.0, 2.7
    xs = (-depth / 2, depth / 2)
    for x in xs:
        box("Upright", (x, height / 2, 0), (0.08, height, 0.08), "depot_blue", 0.015)
        box("UprightFoot", (x, 0.012, 0), (0.16, 0.024, 0.16), "sign_ink", 0.01)
        cyl("UprightCap", (x, height + 0.03, 0), 0.06, 0.06, "ui_yellow", 10)
        box("CornerGuard", (x, 0.14, 0), (0.13, 0.28, 0.13), "warning", 0.03, 2)
    for y in (0.9, 2.1):
        bar("Brace", (xs[0], y, 0), (xs[1], y, 0), 0.04, "depot_blue")
    bar("Brace", (xs[0], 0.35, 0), (xs[1], 0.9, 0), 0.035, "depot_blue")
    bar("Brace", (xs[1], 0.9, 0), (xs[0], 2.1, 0), 0.035, "depot_blue")
    done("sm_env_depot_shelf_frame.glb")


def shelf_deck():
    clear()
    depth, length = 1.0, 2.0
    for x in (-depth / 2 + 0.02, depth / 2 - 0.02):
        box("DeckBeam", (x, -0.07, 0), (0.05, 0.1, length - 0.08), "depot_orange", 0.015)
    box("Deck", (0, -0.02, 0), (depth - 0.04, 0.04, length - 0.1), "deck_grey", 0.012)
    done("sm_env_depot_shelf_deck.glb")


# =============================================================================
# Forklift: stand-up reach truck, forks toward -Z, operator platform at +Z.
# =============================================================================

def forklift_body():
    clear()
    box("Chassis", (0, 0.45, 0.45), (1.15, 0.55, 1.5), "depot_orange", 0.14, 3)
    box("Bumper", (0, 0.24, 0.45), (1.22, 0.14, 1.56), "sign_ink", 0.05, 2)
    box("FloorMat", (0, 0.73, 0.2), (0.8, 0.02, 0.8), "steel_light", 0.01)
    # Counterweight hood with warning stripes on its back.
    box("Hood", (0, 1.2, 1.0), (1.0, 0.95, 0.34), "depot_orange", 0.1, 2)
    box("HoodStripeBase", (0, 0.98, 1.17), (0.86, 0.26, 0.02), "sign_ink")
    for i in range(4):
        x = -0.36 + i * 0.24
        panel("HoodStripe", [(x - 0.06, 0.86), (x + 0.04, 0.86), (x + 0.12, 1.1), (x + 0.02, 1.1)], 1.17, 1.19, "warning")
    bar("GrabHandle", (-0.38, 1.7, 1.08), (0.38, 1.7, 1.08), 0.05, "ui_yellow")
    for x in (-0.38, 0.38):
        bar("GrabPost", (x, 1.66, 1.08), (x, 1.72, 1.08), 0.05, "ui_yellow")
    box("StepPlate", (0, 0.3, 1.45), (0.9, 0.08, 0.5), "steel_light", 0.03)
    # Badge on each flank: a mint disc with the cardboard-box logo.
    for side in (-1.0, 1.0):
        x = side * 0.585
        cyl("Badge", (x, 0.47, 0.45), 0.17, 0.02, "ui_mint", 14, ALONG_X)
        box("BadgeBox", (x + side * 0.012, 0.45, 0.45), (0.01, 0.14, 0.16), "logo_cardboard")
        box("BadgeTape", (x + side * 0.018, 0.45, 0.45), (0.01, 0.14, 0.035), "ui_yellow")
    # Overhead guard: round tubes, ball corners, a slatted roof.
    for x in (-0.52, 0.52):
        for z in (0.0, 1.15):
            rod("GuardPost", (x, 0.72, z), (x, 2.22, z), 0.045, "sign_ink", 8)
            ball("GuardCorner", (x, 2.22, z), (0.065, 0.065, 0.065), "sign_ink")
    for a, b in (((-0.52, 0.0), (0.52, 0.0)), ((-0.52, 1.15), (0.52, 1.15)),
                 ((-0.52, 0.0), (-0.52, 1.15)), ((0.52, 0.0), (0.52, 1.15))):
        rod("GuardRail", (a[0], 2.22, a[1]), (b[0], 2.22, b[1]), 0.04, "sign_ink", 8)
    for i in range(4):
        box("GuardSlat", (0, 2.23, 0.2 + i * 0.25), (1.02, 0.03, 0.08), "housing")
    cyl("BeaconBase", (0.4, 2.26, 1.05), 0.1, 0.05, "sign_ink", 12)
    # Headlights on the front posts.
    for x in (-0.52, 0.52):
        cyl("HeadlightCase", (x, 1.95, -0.08), 0.1, 0.12, "sign_ink", 12, ALONG_Z)
        cyl("HeadlightLens", (x, 1.95, -0.145), 0.075, 0.02, "lamp", 12, ALONG_Z)
    # Console: a little desk, joystick with a red knob, a mint screen.
    box("Console", (0.28, 1.35, 0.6), (0.32, 0.3, 0.2), "housing", 0.04, 2)
    box("ConsoleScreen", (0.2, 1.45, 0.705), (0.12, 0.08, 0.01), "ui_mint")
    rod("Joystick", (0.34, 1.5, 0.58), (0.34, 1.68, 0.52), 0.025, "sign_ink", 6)
    ball("JoystickKnob", (0.34, 1.7, 0.51), (0.055, 0.055, 0.055), "danger_red")
    # Mast: outer rails, an inner stage, the lift ram and its chains.
    for x in (-0.42, 0.42):
        box("MastRail", (x, 1.55, -0.38), (0.11, 2.9, 0.13), "steel", 0.02)
        box("MastInner", (x * 0.82, 1.6, -0.36), (0.06, 2.7, 0.09), "steel_light", 0.01)
        box("Chain", (x * 0.55, 1.6, -0.4), (0.03, 2.5, 0.03), "sign_ink")
    box("MastHead", (0, 3.02, -0.38), (0.98, 0.12, 0.14), "steel", 0.03)
    box("MastFoot", (0, 0.2, -0.38), (0.98, 0.14, 0.16), "steel", 0.03)
    cyl("LiftRam", (0, 1.4, -0.3), 0.055, 2.3, "steel_light", 10)
    cyl("LiftRamCap", (0, 2.58, -0.3), 0.07, 0.06, "ui_yellow", 10)
    # Wheels: fat tyres, yellow hubs.
    for x in (-0.5, 0.5):
        side = 1.0 if x > 0 else -1.0
        for z in (-0.1, 1.0):
            cyl("Tyre", (x, 0.2, z), 0.2, 0.2, "rubber", 14, ALONG_X)
            cyl("Hub", (x + side * 0.1, 0.2, z), 0.1, 0.04, "ui_yellow", 10, ALONG_X)
            cyl("HubNut", (x + side * 0.125, 0.2, z), 0.035, 0.03, "sign_ink", 6, ALONG_X)
    done("sm_env_depot_forklift_body.glb")


def forklift_carriage():
    clear()
    # Backrest: a frame and a grille, the carriage plate the forks hang on.
    box("CarriagePlate", (0, 0.27, -0.46), (1.0, 0.22, 0.08), "sign_ink", 0.03)
    for x in (-0.48, 0.48):
        box("BackrestSide", (x, 0.6, -0.48), (0.05, 0.66, 0.05), "steel")
    box("BackrestTop", (0, 0.92, -0.48), (1.0, 0.05, 0.05), "steel", 0.015)
    for i in range(5):
        box("BackrestBar", (-0.32 + i * 0.16, 0.62, -0.48), (0.03, 0.6, 0.03), "steel")
    # Forks: an L each, tapered to a thin tip.
    for x in (-0.25, 0.25):
        box("ForkShank", (x, 0.3, -0.47), (0.11, 0.38, 0.05), "fork_dark", 0.01)
        tine = box("ForkTine", (x, 0.14, -1.03), (0.11, 0.05, 1.1), "fork_dark", 0.01)
        for v in tine.data.vertices:
            if v.co.y > 1.5:   # Blender +Y is Godot -Z: the tip end
                v.co.z = 0.14 + (v.co.z - 0.14) * 0.4 - 0.012
        tine.data.update()
        box("ForkHeel", (x, 0.16, -0.5), (0.11, 0.09, 0.09), "fork_dark", 0.02)
    done("sm_env_depot_forklift_carriage.glb")


# =============================================================================
# Conveyor: 17 m, origin under the middle of the belt; the belt runs +X.
# =============================================================================

def conveyor():
    clear()
    length = 17.0
    half = length / 2.0
    inner = half - 0.6   # the portals' inner faces
    box("BedPan", (0, 0.8, 0), (length - 0.4, 0.08, 0.78), "sign_ink", 0.02)
    for z in (-0.43, 0.43):
        box("SideChannel", (0, 0.86, z), (length - 0.4, 0.16, 0.07), "steel", 0.025, 2)
    x = -inner + 0.4
    while x < inner - 0.2:
        for z in (-0.47, 0.47):
            cyl("RollerEnd", (x, 0.88, z), 0.035, 0.02, "steel_light", 6, ALONG_Z)
        x += 1.0
    # Guards: fat yellow rails on stubby posts.
    for z in (-0.49, 0.49):
        box("GuardRail", (0, 1.02, z), (2 * inner - 0.1, 0.1, 0.06), "ui_yellow", 0.03, 2)
        gx = -inner + 1.0
        while gx < inner - 0.5:
            box("GuardPost", (gx, 0.97, z), (0.05, 0.12, 0.05), "sign_ink")
            gx += 2.0
    # Legs: pairs every 2 m with a tie and a cross brace, round feet.
    for i in range(8):
        lx = -7.0 + i * 2.0
        for z in (-0.38, 0.38):
            box("Leg", (lx, 0.4, z), (0.08, 0.78, 0.08), "steel", 0.015)
            cyl("LegFoot", (lx, 0.02, z), 0.07, 0.04, "sign_ink", 8)
        bar("LegTie", (lx, 0.3, -0.38), (lx, 0.3, 0.38), 0.04, "steel")
        bar("LegBrace", (lx, 0.3, -0.38), (lx, 0.74, 0.38), 0.03, "steel")
    # Portals at both ends: a cabinet and a rounded hood, a dark mouth ringed
    # with hazard paint, a warning dome on top.
    for side in (-1.0, 1.0):
        px = side * half
        box("PortalBase", (px, 0.45, 0), (1.2, 0.9, 1.3), "depot_blue", 0.05, 2)
        box("PortalBaseBand", (px, 0.12, 0), (1.22, 0.1, 1.32), "sign_ink", 0.02)
        box("PortalHood", (px, 1.55, 0), (1.2, 1.3, 1.3), "depot_orange", 0.18, 3)
        box("PortalHoodBand", (px, 1.02, 0), (1.24, 0.1, 1.34), "sign_ink", 0.03)
        # Inset in the hood's face; the script's strip curtain hangs just in front (0.61).
        box("PortalMouthRing", (px - side * 0.578, 1.2, 0), (0.035, 0.78, 1.06), "warning", 0.02)
        box("PortalMouth", (px - side * 0.587, 1.2, 0), (0.032, 0.62, 0.9), "sign_ink", 0.01)
        cyl("PortalLampBase", (px, 2.24, 0), 0.14, 0.06, "sign_ink", 12)
        ball("PortalLamp", (px, 2.31, 0), (0.11, 0.1, 0.11), "ui_yellow" if side < 0 else "go_green")
        # Emergency stop on the aisle-facing side (-Z).
        box("EStopBox", (px, 0.72, -0.68), (0.22, 0.22, 0.08), "ui_yellow", 0.03, 2)
        cyl("EStopButton", (px, 0.72, -0.73), 0.07, 0.05, "danger_red", 12, ALONG_Z)
        ball("EStopCap", (px, 0.72, -0.76), (0.075, 0.075, 0.03), "danger_red")
    done("sm_env_depot_conveyor.glb")


# =============================================================================
# Lamps, fan, clock, supplies.
# =============================================================================

def high_bay_lamp():
    clear()
    cyl("Canopy", (0, -0.02, 0), 0.07, 0.04, "sign_ink", 8)
    cyl("Cable", (0, -0.25, 0), 0.012, 0.46, "sign_ink", 5)
    cyl("Neck", (0, -0.46, 0), 0.08, 0.1, "ui_yellow", 10)
    cyl("Shade", (0, -0.65, 0), 0.42, 0.32, "housing", 14, r2=0.12)
    ball("ShadeCap", (0, -0.5, 0), (0.13, 0.05, 0.13), "housing")
    # A ring, not a disc: the glowing bulb disc (the script's) shows through it.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.03, major_segments=14,
                                     minor_segments=4, location=G(0, -0.8, 0))
    _finish(bpy.context.object, "ui_yellow").name = "ShadeRim"
    done("sm_env_depot_high_bay_lamp.glb")


def tube_fixture():
    clear()
    box("Trough", (0, 0.0, 0), (0.22, 0.06, 1.3), "paper", 0.02)
    for side in (-1.0, 1.0):
        box("Reflector", (side * 0.13, -0.03, 0), (0.06, 0.02, 1.28), "fan_blade", roll=side * 0.6)
        box("EndCap", (0, -0.02, side * 0.64), (0.2, 0.08, 0.05), "housing", 0.015)
        cyl("Cable", (0, 1.12, side * 0.5), 0.008, 2.2, "sign_ink", 4)
    done("sm_env_depot_tube_fixture.glb")


def ceiling_fan():
    clear()
    cyl("Motor", (0, 0.0, 0), 0.22, 0.26, "sign_ink", 14)
    cyl("MotorRing", (0, 0.0, 0), 0.235, 0.06, "ui_yellow", 14)
    ball("MotorTop", (0, 0.13, 0), (0.22, 0.08, 0.22), "sign_ink")
    ball("MotorBottom", (0, -0.14, 0), (0.18, 0.08, 0.18), "housing")
    for i in range(5):
        angle = math.tau * i / 5.0
        # Paddle laid along +X, rounded tip, then turned into place.
        pts = [(0.22, -0.1), (1.9, -0.17)]
        for k in range(7):
            a = -math.pi / 2 + math.pi * k / 6
            pts.append((2.12 + math.cos(a) * 0.2, math.sin(a) * 0.2 * 0.9))
        pts += [(1.9, 0.17), (0.22, 0.1)]
        blade = floor_panel("Blade", pts, -0.115, -0.085, "fan_blade")
        blade.rotation_euler = (0.12, 0, angle)
        c, s_ = math.cos(angle), math.sin(angle)

        def turned(r, y):
            # Blender Z-rotation by `angle` of a point on Godot +X: Godot z = -sin.
            return (r * c, y, -r * s_)
        bar("BladeArm", turned(0.12, -0.13), turned(0.5, -0.13), 0.1, "sign_ink", 0.035)
        ball("BladeTipDot", turned(2.05, -0.085), (0.1, 0.02, 0.1), "ui_yellow")
    done("sm_env_depot_ceiling_fan.glb")


def wall_clock():
    clear()
    cyl("BackPlate", (0, 0, -0.03), 0.6, 0.06, "sign_ink", 24, ALONG_Z)
    cyl("Body", (0, 0, 0.0), 0.6, 0.05, "ui_yellow", 24, ALONG_Z)
    cyl("Face", (0, 0, 0.03), 0.55, 0.02, "paper", 24, ALONG_Z)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.57, minor_radius=0.055, major_segments=24,
                                     minor_segments=6, location=G(0, 0, 0.035), rotation=ALONG_Z)
    _finish(bpy.context.object, "ui_yellow").name = "Bezel"
    for hour in range(12):
        a = math.tau * hour / 12.0
        x, y = math.sin(a) * 0.44, math.cos(a) * 0.44
        if hour % 3 == 0:
            box("TickBig", (x, y, 0.043), (0.05, 0.12, 0.01), "sign_ink", roll=-a)
        else:
            cyl("TickDot", (x, y, 0.043), 0.022, 0.01, "sign_ink", 8, ALONG_Z)
    ball("Bell", (0, 0.66, -0.02), (0.1, 0.08, 0.08), "ui_yellow")
    cyl("Spindle", (0, 0, 0.045), 0.035, 0.03, "sign_ink", 10, ALONG_Z)
    done("sm_env_depot_wall_clock.glb")


def _hand(length, width, z0, z1, material, counter=True):
    tip = length
    pts = [(-width * 0.35, -0.08), (width * 0.35, -0.08), (width * 0.35, tip * 0.7),
           (width * 0.9, tip * 0.72), (0.0, tip), (-width * 0.9, tip * 0.72), (-width * 0.35, tip * 0.7)]
    panel("Hand", pts, z0, z1, material)
    if counter:
        panel("HandTail", [(-width * 0.7, -0.14), (width * 0.7, -0.14), (width * 0.35, -0.07), (-width * 0.35, -0.07)], z0, z1, material)


def clock_hand_hour():
    clear()
    _hand(0.28, 0.07, -0.006, 0.004, "sign_ink", False)
    done("sm_env_depot_clock_hand_hour.glb")


def clock_hand_minute():
    clear()
    _hand(0.43, 0.05, 0.005, 0.014, "sign_ink")
    cyl("CentreCap", (0, 0, 0.018), 0.035, 0.012, "danger_red", 10, ALONG_Z)
    done("sm_env_depot_clock_hand_minute.glb")


def supply_padding():
    clear()
    r = 0.19
    cyl("Roll", (0, r, 0), r, 0.46, "bubble", 14, ALONG_X)
    for side in (-1.0, 1.0):
        cyl("RollEnd", (side * 0.232, r, 0), r * 0.92, 0.01, "paper", 14, ALONG_X)
        cyl("RollCore", (side * 0.236, r, 0), 0.05, 0.012, "logo_cardboard", 8, ALONG_X)
    cyl("Tape", (0.0, r, 0), r + 0.008, 0.06, "ui_yellow", 14, ALONG_X)
    for i, (x, a) in enumerate(((-0.15, 0.6), (-0.08, 1.4), (0.1, 0.9), (0.16, 1.9), (-0.14, 2.2), (0.09, 1.6))):
        ball("Bubble", (x, r + math.sin(a) * r, -math.cos(a) * r), (0.03, 0.03, 0.03), "paper", 1)
    done("sm_env_depot_supply_padding.glb")


def supply_insurance():
    clear()
    box("Clipboard", (0, 0.006, 0), (0.24, 0.012, 0.32), "logo_cardboard", 0.01)
    box("Sheet", (0, 0.014, 0.012), (0.2, 0.004, 0.26), "paper")
    for i in range(4):
        box("Line", (-0.02, 0.017, -0.06 + i * 0.045), (0.14, 0.002, 0.012), "steel_light")
    box("Clip", (0, 0.022, -0.15), (0.1, 0.02, 0.04), "sign_ink", 0.006)
    cyl("Stamp", (0.05, 0.017, 0.09), 0.045, 0.004, "ui_red", 12)
    cyl("Pen", (0.13, 0.012, 0.02), 0.01, 0.2, "depot_blue", 6, ALONG_Z)
    done("sm_env_depot_supply_insurance.glb")


BUILDERS = {
    "door": [door_slat, door_slat_window, door_bottom_bar, door_frame],
    "rack": [rack_frame, rack_beam_level, shelf_frame, shelf_deck],
    "forklift": [forklift_body, forklift_carriage],
    "conveyor": [conveyor],
    "lamps": [high_bay_lamp, tube_fixture],
    "fan": [ceiling_fan],
    "clock": [wall_clock, clock_hand_hour, clock_hand_minute],
    "supplies": [supply_padding, supply_insurance],
}
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for group, builders in BUILDERS.items():
    if not ONLY or group in ONLY:
        for builder in builders:
            builder()

print("DEPOT_REPORT")
for name, tris in REPORT:
    print("  %-42s %6d tris" % (name, tris))
