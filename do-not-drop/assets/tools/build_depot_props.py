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

N-319.2 kit (2026-09-30, the redesigned depot, section "N-319.2 kit" below):
front toward Godot -Z, base centre on the floor; wall pieces with their back
on z = 0 and the origin on the floor under them; ceiling pieces at their hook
or axis. Groups: ceiling (bell lamp, linear tube, ducts, cable tray), dispatch
(desk), bay (bollard, column guard, wheel chock and stop, door light), logistics
(roll cages, flat cartons, wrapped pallet, sorting table, rolling ladder), office
(stair, railing, blind, window frame), cage (mesh panel, service window), safety
(extinguisher, cabinets, panel, first aid, time clock, recycling, water, wet
floor, pictogram sign), breakroom (fridge, kitchenette), workshop (scissor lift,
compressor, workbench). It also draws textures/depot/tx_depot_cage_mesh_256.png
and tx_depot_pictograms_512.png.

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
    # ~15 % lighter than housing / steel: the drum and the forklift mast
    # read almost black against the racking otherwise.
    "drum": srgb("50666f"), "mast_steel": srgb("6d7b81"),
    "wood": srgb("b08a5a"), "tape_brown": srgb("c98a45"),
    "foam_blue": srgb("7fa7b5"), "foam_orange": srgb("e8772e"),
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
    cyl("DrumHousing", (0, hy, hz), 0.46, DOOR_W + 0.5, "drum", 16, ALONG_X)
    box("DrumSkirt", (0, top + 0.12, hz - 0.05), (DOOR_W + 0.5, 0.24, 0.62), "drum", 0.04)
    # Sign board on the drum's face: depot.gd writes the exit sign on it, in
    # front of the drum, so it reads from right under the door too.
    # Tilted 0.3 rad (top toward the room) so it faces whoever stands under it.
    tilt = 0.3
    box("SignBoardRim", (0, hy, 0.855), (DOOR_W + 0.1, 0.72, 0.04), "ui_yellow", 0.03, 2, pitch=tilt)
    box("SignBoard", (0, hy - 0.02 * math.sin(tilt), 0.855 + 0.02 * math.cos(tilt)), (DOOR_W - 0.06, 0.58, 0.02), "sign_ink", 0.01, pitch=tilt)
    for x in (-2.4, 2.4):
        box("SignBracket", (x, hy, 0.78), (0.1, 0.3, 0.12), "sign_ink")
    for side in (-1.0, 1.0):
        x = side * (DOOR_W / 2 + 0.3)
        cyl("DrumCap", (x, hy, hz), 0.5, 0.12, "ui_yellow", 16, ALONG_X)
        cyl("DrumCapBolt", (x + side * 0.07, hy, hz), 0.14, 0.05, "sign_ink", 10, ALONG_X)
    for x in (-3.0, 3.0):
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
        box("MastRail", (x, 1.55, -0.38), (0.11, 2.9, 0.13), "mast_steel", 0.02)
        box("MastInner", (x * 0.82, 1.6, -0.36), (0.06, 2.7, 0.09), "steel_light", 0.01)
        box("Chain", (x * 0.55, 1.6, -0.4), (0.03, 2.5, 0.03), "sign_ink")
    box("MastHead", (0, 3.02, -0.38), (0.98, 0.12, 0.14), "mast_steel", 0.03)
    box("MastFoot", (0, 0.2, -0.38), (0.98, 0.14, 0.16), "mast_steel", 0.03)
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


# =============================================================================
# Shop goods, packing table, pallet jack (depot.gd _build_shop / _build_staging).
# =============================================================================

def shop_tape_roll():
    """Packing tape standing on its edge, facing +Z. Base centre."""
    clear()
    r = 0.11
    cyl("Tape", (0, r, 0), r, 0.08, "tape_brown", 14, ALONG_Z)
    for z in (-0.041, 0.041):
        cyl("Core", (0, r, z), 0.06, 0.004, "logo_cardboard", 10, ALONG_Z)
        cyl("Hole", (0, r, z * 1.05), 0.045, 0.004, "sign_ink", 8, ALONG_Z)
    box("TapeTail", (0, 0.055, 0.0), (0.07, 0.06, 0.078), "tape_brown", 0.01, pitch=0.5)
    done("sm_env_depot_shop_tape_roll.glb")


def _foam_pack(colour, filename):
    """A shrink-wrapped stack of foam sheets, 0.45 x 0.3 x 0.4. Base centre."""
    clear()
    for i in range(3):
        box("FoamSheet", (0, 0.05 + i * 0.1, 0), (0.45 - (i % 2) * 0.02, 0.095, 0.4), colour, 0.03, 2)
    box("Band", (0, 0.15, 0), (0.1, 0.305, 0.405), "paper", 0.01)
    box("Label", (0, 0.2, 0.203), (0.08, 0.06, 0.004), "sign_ink")
    done(filename)


def shop_foam_blue():
    _foam_pack("foam_blue", "sm_env_depot_shop_foam_blue.glb")


def shop_foam_orange():
    _foam_pack("foam_orange", "sm_env_depot_shop_foam_orange.glb")


def packing_table():
    """2.4 x 1.0 m bench, top at 0.93, with a cardboard sheet, a tape gun and a
    label roll on it and flat-packed boxes on the shelf below. Base centre."""
    clear()
    box("Top", (0, 0.9, 0), (2.4, 0.06, 1.0), "wood", 0.02, 2)
    box("TopEdge", (0, 0.855, -0.49), (2.36, 0.05, 0.03), "depot_orange")
    for x in (-1.1, 1.1):
        for z in (-0.4, 0.4):
            box("Leg", (x, 0.44, z), (0.07, 0.86, 0.07), "steel", 0.015)
            cyl("Foot", (x, 0.015, z), 0.05, 0.03, "sign_ink", 8)
        bar("LegTie", (x, 0.2, -0.4), (x, 0.2, 0.4), 0.05, "steel")
    box("LowerShelf", (0, 0.22, 0), (2.2, 0.03, 0.8), "deck_grey", 0.01)
    for i in range(4):
        box("FlatBox", (-0.5 + i * 0.03, 0.255 + i * 0.022, 0.02 * i), (0.9, 0.02, 0.6), "logo_cardboard", yaw=0.04 * i)
    # On top: a sheet of cardboard, the tape gun, a roll of labels.
    box("CardboardSheet", (0.3, 0.935, -0.1), (0.7, 0.01, 0.5), "logo_cardboard", yaw=-0.15)
    box("TapeGunBody", (0.75, 0.99, 0.1), (0.1, 0.1, 0.2), "danger_red", 0.02)
    rod("TapeGunGrip", (0.75, 0.97, 0.18), (0.75, 1.1, 0.24), 0.025, "sign_ink", 6)
    cyl("TapeGunRoll", (0.75, 1.04, 0.05), 0.07, 0.06, "tape_brown", 10, ALONG_X)
    cyl("LabelRoll", (1.0, 1.01, -0.3), 0.08, 0.07, "paper", 12, ALONG_Z)
    cyl("LabelCore", (1.0, 1.01, -0.3), 0.03, 0.075, "ui_mint", 8, ALONG_Z)
    done("sm_env_depot_packing_table.glb")


def pallet_jack():
    """Hand pallet truck: forks toward -Z, handle up at +Z, origin at the
    base of the pump (the forks run to z = -1.25)."""
    clear()
    for x in (-0.225, 0.225):
        box("Fork", (x, 0.08, -0.7), (0.16, 0.08, 1.15), "depot_orange", 0.02)
        box("ForkTip", (x, 0.06, -1.3), (0.14, 0.05, 0.08), "depot_orange", 0.02)
        cyl("LoadRoller", (x, 0.04, -1.18), 0.035, 0.1, "sign_ink", 8, ALONG_X)
    box("Chassis", (0, 0.16, 0), (0.6, 0.2, 0.25), "depot_orange", 0.05, 2)
    cyl("PumpBody", (0, 0.36, 0.05), 0.09, 0.3, "sign_ink", 10)
    cyl("PumpCap", (0, 0.52, 0.05), 0.1, 0.04, "ui_yellow", 10)
    for x in (-0.12, 0.12):
        cyl("SteerWheel", (x, 0.09, 0.1), 0.09, 0.07, "rubber", 12, ALONG_X)
        cyl("SteerHub", (x, 0.09, 0.1), 0.04, 0.075, "ui_yellow", 8, ALONG_X)
    rod("Handle", (0, 0.5, 0.08), (0, 1.25, 0.3), 0.025, "sign_ink", 8)
    rod("HandleBar", (-0.17, 1.28, 0.31), (0.17, 1.28, 0.31), 0.03, "sign_ink", 8)
    for x in (-0.17, 0.17):
        rod("HandleSide", (x, 1.28, 0.31), (0, 1.13, 0.26), 0.02, "sign_ink", 6)
    ball("Lever", (0.06, 1.24, 0.33), (0.035, 0.035, 0.035), "danger_red")
    done("sm_env_depot_pallet_jack.glb")


# =============================================================================
# N-319.2 kit (2026-09-30): the redesigned depot's props.
#
# Conventions for everything below: base centre on the floor, metres, the
# FRONT toward Godot -Z (where the player reads it from). Wall pieces have
# their back on the wall plane z = 0 and stand out toward -Z; their origin is
# on the floor under them, so they sit at the height they are mounted at
# (the constructor only has to put them on the wall). Ceiling pieces (lamps,
# ducts, tray) are the exception: origin at their hanging point or axis.
# Materials are palette names so DepotKit batches them with the rest; the only
# new ones are see-through (film, lamp_halo), textured (cage_mesh,
# sign_pictogram), lit (lamp_disc) or switched by the game (signal_red,
# signal_green, sign_plate).
# =============================================================================

import numpy as np  # noqa: E402

PALETTE.update({
    "film": srgb("dff0f4"),          # stretch film, alpha 0.35 with sheen
    "lamp_halo": srgb("fff1cf"),     # glow ring around a lamp disc, alpha 0.35
    "cage_mesh": srgb("b4bfc4"),     # the supplies cage's diamond mesh (alpha texture)
    "sign_plate": srgb("2f9e5b"),    # pictogram sign's plate; the game tints it
    "sign_pictogram": srgb("ffffff"),
    "signal_red": srgb("ff3b30"), "signal_green": srgb("35d46a"),
    "lamp_disc": srgb("fff1cf"),     # a lamp's glowing disc or diffuser (emissive)
})
TEX_DIR = os.path.join(ROOT, "textures", "depot")


def _principled(m):
    return next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def _enum(owner, prop, wanted):
    ids = [i.identifier for i in owner.bl_rna.properties[prop].enum_items]
    return wanted if wanted in ids else None


def _see_through(m, alpha, roughness=0.25):
    p = _principled(m)
    p.inputs["Alpha"].default_value = alpha
    p.inputs["Roughness"].default_value = roughness
    m.roughness = roughness
    m.use_backface_culling = False
    method = _enum(m, "surface_render_method", "BLENDED")
    if method:
        m.surface_render_method = method


def _glowing(m, strength):
    p = _principled(m)
    p.inputs["Emission Color"].default_value = m.diffuse_color
    p.inputs["Emission Strength"].default_value = strength


def _textured(m, image, clip=True):
    """Base colour and alpha from `image`, alpha clipped (glTF MASK) via a Round node."""
    p = _principled(m)
    nodes, links = m.node_tree.nodes, m.node_tree.links
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    links.new(tex.outputs["Color"], p.inputs["Base Color"])
    if clip:
        rnd = nodes.new("ShaderNodeMath")
        rnd.operation = _enum(rnd, "operation", "ROUND")
        links.new(tex.outputs["Alpha"], rnd.inputs[0])
        links.new(rnd.outputs[0], p.inputs["Alpha"])
    m.use_backface_culling = False
    method = _enum(m, "surface_render_method", "DITHERED")
    if method:
        m.surface_render_method = method


def _save_image(name, rgba, path):
    """rgba: float array (h, w, 4), row 0 at the TOP (as in the PNG)."""
    h, w = rgba.shape[:2]
    img = bpy.data.images.get(name) or bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(rgba[::-1]).astype(np.float32).ravel())
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


# --- Textures, drawn here so they rebuild with the models -------------------

def _cage_mesh_texture():
    """One 25 cm diamond of chain-link wire per UV unit, 256 px, alpha = wire."""
    n = 256
    v, u = (np.mgrid[0:n, 0:n] + 0.5) / n
    d1 = np.abs((u + v) - np.round(u + v)) / math.sqrt(2.0)
    d2 = np.abs((u - v) - np.round(u - v)) / math.sqrt(2.0)
    d = np.minimum(d1, d2)
    alpha = np.clip((0.024 - d) / 0.006 + 0.5, 0.0, 1.0)
    shade = 0.9 + 0.1 * np.clip(1.0 - d / 0.024, 0.0, 1.0)   # a touch of roundness on the wire
    rgba = np.stack([shade, shade, shade, alpha], axis=-1)
    return _save_image("tx_depot_cage_mesh_256", rgba, os.path.join(TEX_DIR, "tx_depot_cage_mesh_256.png"))


PICTOGRAMS = ["helmet", "vest", "speed", "exit", "extinguisher", "first_aid",
              "assembly", "forklift", "hands", "no_smoking", "electric", "evacuation"]


def _pictogram_atlas():
    """512 px atlas, 4 x 4 cells of 128 px, the 12 PICTOGRAMS in reading order
    (cell k: column k % 4, row k // 4 from the top). White flat shapes on
    transparent; drawn 4x larger and averaged down for clean edges."""
    ss = 4
    cell = 128 * ss
    alpha = np.zeros((4 * cell, 4 * cell), dtype=np.float32)
    yy, xx = (np.mgrid[0:cell, 0:cell] + 0.5) / cell

    def poly(pts):
        inside = np.zeros((cell, cell), dtype=bool)
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]
            xj, yj = pts[j]
            cross = ((yi > yy) != (yj > yy)) & (xx < (xj - xi) * (yy - yi) / (yj - yi + 1e-12) + xi)
            inside ^= cross
            j = i
        return inside

    def rect(x0, y0, x1, y1):
        return (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1)

    def disc(cx, cy, r):
        return (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r

    def ring(cx, cy, r, w):
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        return (d <= r) & (d >= r - w)

    def line(a, b, w):
        ax, ay = a
        bx, by = b
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        nx, ny = -dy / length * w / 2, dx / length * w / 2
        return poly([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)]) | disc(ax, ay, w / 2) | disc(bx, by, w / 2)

    def figure(head, hip, parts, w=0.075):
        m = disc(head[0], head[1], 0.075)
        for a, b in parts:
            m |= line(a, b, w)
        return m

    shapes = {}
    shapes["helmet"] = ((disc(0.5, 0.62, 0.3) & (yy <= 0.62)) | rect(0.12, 0.6, 0.88, 0.7)) & ~rect(0.47, 0.34, 0.53, 0.6)
    shapes["vest"] = poly([(0.3, 0.14), (0.42, 0.14), (0.5, 0.36), (0.58, 0.14), (0.7, 0.14), (0.84, 0.3),
                           (0.79, 0.88), (0.21, 0.88), (0.16, 0.3)]) & ~rect(0.0, 0.54, 1.0, 0.6) & ~rect(0.0, 0.7, 1.0, 0.76) & ~rect(0.49, 0.36, 0.51, 0.9)
    shapes["speed"] = ((ring(0.5, 0.64, 0.4, 0.08) & (yy <= 0.66)) | line((0.5, 0.64), (0.72, 0.4), 0.07) | disc(0.5, 0.64, 0.08)
                       | rect(0.1, 0.72, 0.9, 0.8))
    shapes["exit"] = ((rect(0.6, 0.12, 0.9, 0.88) & ~rect(0.67, 0.19, 0.83, 0.88))
                      | poly([(0.08, 0.44), (0.36, 0.44), (0.36, 0.3), (0.58, 0.5), (0.36, 0.7), (0.36, 0.56), (0.08, 0.56)]))
    shapes["extinguisher"] = (rect(0.38, 0.34, 0.62, 0.88) | disc(0.5, 0.34, 0.12) | rect(0.43, 0.14, 0.57, 0.26)
                              | line((0.57, 0.18), (0.76, 0.14), 0.05)
                              | line((0.43, 0.2), (0.26, 0.28), 0.05) | line((0.26, 0.28), (0.22, 0.6), 0.05))
    shapes["first_aid"] = rect(0.39, 0.14, 0.61, 0.86) | rect(0.14, 0.39, 0.86, 0.61)
    assembly = disc(0.5, 0.5, 0.07) | rect(0.43, 0.56, 0.57, 0.68) | disc(0.37, 0.53, 0.05) | disc(0.63, 0.53, 0.05)
    assembly |= rect(0.33, 0.58, 0.41, 0.66) | rect(0.59, 0.58, 0.67, 0.66)
    for tip, base_a, base_b in (((0.5, 0.3), (0.4, 0.1), (0.6, 0.1)), ((0.5, 0.8), (0.4, 0.95), (0.6, 0.95)),
                                ((0.24, 0.55), (0.05, 0.45), (0.05, 0.65)), ((0.76, 0.55), (0.95, 0.45), (0.95, 0.65))):
        assembly |= poly([tip, base_a, base_b])
    shapes["assembly"] = assembly
    shapes["forklift"] = ((rect(0.14, 0.5, 0.6, 0.76) | (rect(0.2, 0.24, 0.5, 0.52) & ~rect(0.26, 0.3, 0.46, 0.5))
                          | rect(0.62, 0.12, 0.68, 0.8) | rect(0.68, 0.74, 0.92, 0.8) | disc(0.27, 0.8, 0.1) | disc(0.52, 0.8, 0.1))
                          & ~disc(0.27, 0.8, 0.035) & ~disc(0.52, 0.8, 0.035))
    hands = rect(0.3, 0.46, 0.7, 0.8) | disc(0.5, 0.8, 0.2) & (yy >= 0.7)
    for i, x in enumerate((0.33, 0.43, 0.53, 0.63)):
        top = (0.2, 0.14, 0.16, 0.24)[i]
        hands |= line((x + 0.035, top), (x + 0.035, 0.5), 0.075)
    hands |= line((0.3, 0.62), (0.16, 0.42), 0.08)
    shapes["hands"] = hands & (yy <= 0.92)
    shapes["no_smoking"] = (ring(0.5, 0.5, 0.42, 0.08) | line((0.22, 0.22), (0.78, 0.78), 0.08)
                            | (rect(0.2, 0.46, 0.66, 0.56) & ~line((0.22, 0.22), (0.78, 0.78), 0.16)) | rect(0.69, 0.46, 0.8, 0.56))
    shapes["electric"] = ((poly([(0.5, 0.08), (0.94, 0.88), (0.06, 0.88)]) & ~poly([(0.5, 0.22), (0.83, 0.81), (0.17, 0.81)]))
                          | poly([(0.54, 0.3), (0.38, 0.6), (0.49, 0.6), (0.44, 0.78), (0.62, 0.5), (0.51, 0.5), (0.58, 0.3)]))
    shapes["evacuation"] = (figure((0.34, 0.2), None, [((0.32, 0.3), (0.26, 0.56)), ((0.26, 0.56), (0.4, 0.7)),
                                                        ((0.4, 0.7), (0.34, 0.88)), ((0.26, 0.56), (0.14, 0.74)),
                                                        ((0.14, 0.74), (0.06, 0.74)), ((0.3, 0.36), (0.44, 0.46)),
                                                        ((0.3, 0.36), (0.16, 0.44))])
                            | poly([(0.52, 0.44), (0.74, 0.44), (0.74, 0.3), (0.95, 0.52), (0.74, 0.74), (0.74, 0.6), (0.52, 0.6)]))
    for k, name in enumerate(PICTOGRAMS):
        col, row = k % 4, k // 4
        alpha[row * cell:(row + 1) * cell, col * cell:(col + 1) * cell] = shapes[name].astype(np.float32)
    small = alpha.reshape(512, ss, 512, ss).mean(axis=(1, 3))
    rgba = np.stack([np.ones_like(small)] * 3 + [small], axis=-1)
    return _save_image("tx_depot_pictograms_512", rgba, os.path.join(TEX_DIR, "tx_depot_pictograms_512.png"))


def _special_materials():
    _see_through(mat("film"), 0.35, 0.18)
    _see_through(mat("lamp_halo"), 0.35, 0.5)
    _glowing(mat("lamp_halo"), 1.0)
    _glowing(mat("lamp_disc"), 1.5)
    _textured(mat("cage_mesh"), _cage_mesh_texture())
    _textured(mat("sign_pictogram"), _pictogram_atlas())


# --- Helpers ----------------------------------------------------------------

def tube(name, pts, radius, material, sides=8, caps=True):
    """A round tube through Godot points (rails, cables, ducts, hoses)."""
    P = [Vector(G(*p)) for p in pts]
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    rings = []
    a_prev = None
    n = len(P)
    for i in range(n):
        if i == 0:
            t = (P[1] - P[0]).normalized()
        elif i == n - 1:
            t = (P[-1] - P[-2]).normalized()
        else:
            t = ((P[i + 1] - P[i]).normalized() + (P[i] - P[i - 1]).normalized()).normalized()
        if a_prev is None:
            ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            a = t.cross(ref).normalized()
        else:
            a = (a_prev - t * a_prev.dot(t)).normalized()
        b = t.cross(a)
        scale = 1.0
        if 0 < i < n - 1:
            scale = 1.0 / max((P[i + 1] - P[i]).normalized().dot(t), 0.6)
        rings.append([bm.verts.new(P[i] + (a * math.cos(k * math.tau / sides) + b * math.sin(k * math.tau / sides)) * radius * scale)
                      for k in range(sides)])
        a_prev = a
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(sides):
            m = (k + 1) % sides
            bm.faces.new([r0[k], r0[m], r1[m], r1[k]])
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return _finish(obj, material)


def arc(cx, cz, r, a0, a1, steps, y=0.0):
    """Points on a horizontal arc (Godot XZ) around (cx, cz), angles from +X toward +Z."""
    return [(cx + math.cos(a0 + (a1 - a0) * i / steps) * r, y, cz + math.sin(a0 + (a1 - a0) * i / steps) * r)
            for i in range(steps + 1)]


def quad(name, corners, uvs, material):
    """One UV-mapped face through four Godot points (front = counter-clockwise side)."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    face = bm.faces.new([bm.verts.new(G(*p)) for p in corners])
    for loop, t in zip(face.loops, uvs):
        loop[uv].uv = t
    bm.to_mesh(mesh)
    bm.free()
    return _finish(obj, material)


def mesh_quad(name, x0, x1, y0, y1, z, cell=0.25):
    """A cage-mesh sheet in the XY plane at depth z, one texture repeat per 25 cm diamond."""
    return quad(name, [(x1, y0, z), (x0, y0, z), (x0, y1, z), (x1, y1, z)],
                [(0, 0), ((x1 - x0) / cell, 0), ((x1 - x0) / cell, (y1 - y0) / cell), (0, (y1 - y0) / cell)], "cage_mesh")


def open_shell(name, c, s, material):
    """A box with no top or bottom (film around a stack)."""
    bpy.ops.mesh.primitive_cube_add(location=G(*c))
    o = bpy.context.object
    o.name = name
    o.scale = tuple(v / 2.0 for v in GS(*s))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.normal.z) > 0.9], context="FACES_ONLY")
    bm.to_mesh(o.data)
    bm.free()
    return _finish(o, material)


def clip_floor(o):
    """Cuts `o` at the floor (Godot y = 0) and caps the cut: stringers and
    legs that lean into the floor stop on it instead of poking through."""
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    o.rotation_mode = "XYZ"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0),
                           plane_no=(0, 0, 1), clear_inner=True)
    bmesh.ops.holes_fill(bm, edges=bm.edges[:], sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


def join_named(name, objects):
    """Joins `objects` into one named object (a node the game looks up)."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    return joined


def pallet(y0=0.0):
    """Euro-ish pallet 1.2 (X) x 1.0 (Z) x 0.144, from height y0."""
    for z in (-0.44, 0.0, 0.44):
        box("PalletRunner", (0, y0 + 0.011, z), (1.2, 0.022, 0.12), "wood")
        box("PalletBlock", (0, y0 + 0.066, z), (1.16, 0.09, 0.1), "wood")
    for i in range(5):
        box("PalletBoard", (0, y0 + 0.133, -0.43 + i * 0.215), (1.2, 0.022, 0.13), "wood", 0.006)
    return y0 + 0.144


def parcel(c, s, colour="logo_cardboard", yaw=0.0):
    box("Parcel", c, s, colour, 0.015, yaw=yaw)
    box("ParcelTape", (c[0], c[1] + s[1] / 2 + 0.002, c[2]), (s[0] + 0.004, 0.004, 0.06), "tape_brown", yaw=yaw)


def wall_back(name, w, h, y0, material="sign_ink", t=0.02):
    """A thin backing plate on the wall (z 0 .. -t), bottom at y0."""
    return box(name, (0, y0 + h / 2, -t / 2), (w, h, t), material, 0.005)


# =============================================================================
# Ceiling: bell lamp, linear tube, ducts, cable tray.
# =============================================================================

def bay_lamp_bell():
    """Round high-bay bell on a chain. Origin at the ceiling hook; the shade's
    rim is 1.05 m under it. `LampDisc` (emissive `lamp_disc`) and `LampHalo`
    (emissive, alpha 0.35) are separate nodes so the game can dim them. The
    guard under the disc is a ring on three spokes (`GuardRing`, `GuardSpoke`)."""
    clear()
    cyl("Hook", (0, -0.02, 0), 0.06, 0.04, "sign_ink", 8)
    for i in range(6):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.035, minor_radius=0.009, major_segments=6, minor_segments=3,
                                         location=G(0, -0.07 - i * 0.065, 0),
                                         rotation=(math.pi / 2, 0, (i % 2) * math.pi / 2))
        _finish(bpy.context.object, "sign_ink").name = "ChainLink"
    cyl("Driver", (0, -0.5, 0), 0.15, 0.12, "housing", 12)
    for i in range(6):
        a = i * math.pi / 6
        box("DriverFin", (0, -0.5, 0), (0.36, 0.1, 0.02), "housing", yaw=a)
    cyl("Neck", (0, -0.6, 0), 0.1, 0.08, "ui_yellow", 12)
    cyl("Shade", (0, -0.82, 0), 0.5, 0.36, "depot_blue", 16, r2=0.16)
    cyl("ShadeInside", (0, -0.99, 0), 0.47, 0.02, "paper", 16)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.5, minor_radius=0.035, major_segments=16, minor_segments=4,
                                     location=G(0, -1.01, 0))
    _finish(bpy.context.object, "ui_yellow").name = "ShadeRing"
    disc = cyl("LampDisc", (0, -1.02, 0), 0.34, 0.02, "lamp_disc", 16)
    disc.name = "LampDisc"
    # Halo: a flat annulus just under the rim, wider than the shade.
    mesh = bpy.data.meshes.new("LampHalo")
    halo = bpy.data.objects.new("LampHalo", mesh)
    bpy.context.collection.objects.link(halo)
    bm = bmesh.new()
    inner = [bm.verts.new(G(math.cos(a) * 0.36, -1.035, math.sin(a) * 0.36)) for a in [i * math.tau / 16 for i in range(16)]]
    outer = [bm.verts.new(G(math.cos(a) * 0.78, -1.035, math.sin(a) * 0.78)) for a in [i * math.tau / 16 for i in range(16)]]
    for i in range(16):
        j = (i + 1) % 16
        bm.faces.new([inner[i], inner[j], outer[j], outer[i]])
    for f in bm.faces:
        if f.normal.z > 0:
            f.normal_flip()
    bm.to_mesh(mesh)
    bm.free()
    _finish(halo, "lamp_halo")
    # Guard: a ring on three spokes at 120 degrees out to the rim (N-319, iter 3).
    # It used to be an X, which from below read as a "forbidden" cross.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.27, minor_radius=0.013, major_segments=12, minor_segments=3,
                                     location=G(0, -1.05, 0))
    _finish(bpy.context.object, "sign_ink").name = "GuardRing"
    cyl("GuardHub", (0, -1.05, 0), 0.035, 0.024, "sign_ink", 8)
    for i in range(3):
        a = math.pi / 2 + i * math.tau / 3
        box("GuardSpoke", (math.cos(a) * 0.25, -1.05, math.sin(a) * 0.25), (0.5, 0.02, 0.02), "sign_ink", yaw=-a)
    done("sm_env_depot_bay_lamp_bell.glb")


def tube_linear():
    """1.5 m LED batten on two cables. Origin at the body's centre, runs along Z."""
    clear()
    box("Body", (0, 0, 0), (0.13, 0.07, 1.5), "curtain", 0.02)
    box("Diffuser", (0, -0.04, 0), (0.09, 0.02, 1.42), "lamp_disc", 0.008)
    for side in (-1.0, 1.0):
        box("EndCap", (0, 0, side * 0.76), (0.14, 0.08, 0.03), "housing", 0.01)
        cyl("Cable", (0, 0.65, side * 0.55), 0.007, 1.26, "sign_ink", 4)
        cyl("Clamp", (0, 0.045, side * 0.55), 0.02, 0.03, "steel_light", 6)
    done("sm_env_depot_tube_linear.glb")


DUCT_R = 0.225


def _duct_band(c, rot):
    cyl("DuctBand", c, DUCT_R + 0.012, 0.05, "steel_light", 16, rot)


def _duct_hanger(x, z):
    bpy.ops.mesh.primitive_torus_add(major_radius=DUCT_R + 0.02, minor_radius=0.012, major_segments=12, minor_segments=3,
                                     location=G(x, 0, z), rotation=(0, math.pi / 2, 0))
    _finish(bpy.context.object, "sign_ink").name = "HangerStrap"
    cyl("HangerRod", (x, DUCT_R + 0.45, z), 0.01, 0.9, "sign_ink", 4)


def duct_straight():
    """3 m round duct (45 cm), along X, origin on its axis at the middle.
    Two pieces end to end tile at 3 m."""
    clear()
    cyl("Duct", (0, 0, 0), DUCT_R, 3.0, "fan_blade", 16, ALONG_X)
    for x in (-1.47, 0.0, 1.47):
        _duct_band((x, 0, 0), ALONG_X)
    for x in (-0.9, 0.9):
        _duct_hanger(x, 0)
    done("sm_env_depot_duct_straight.glb")


def duct_elbow():
    """90-degree elbow: one port faces -X at (-0.9, 0, 0), the other +Z at
    (0, 0, 0.9); origin where the two axes cross (bend radius 0.5)."""
    clear()
    rb = 0.5
    pts = [(-0.9, 0, 0)] + arc(-rb, rb, rb, -math.pi / 2, 0.0, 6) + [(0, 0, 0.9)]
    tube("Duct", pts, DUCT_R, "fan_blade", 16)
    _duct_band((-0.87, 0, 0), ALONG_X)
    _duct_band((0, 0, 0.87), ALONG_Z)
    c = arc(-rb, rb, rb, -math.pi / 2, 0.0, 2)[1]
    cyl("HangerRod", (c[0], DUCT_R + 0.45, c[2]), 0.01, 0.9, "sign_ink", 4)
    box("HangerSaddle", (c[0], DUCT_R + 0.01, c[2]), (0.2, 0.03, 0.2), "sign_ink", yaw=math.pi / 4)
    done("sm_env_depot_duct_elbow.glb")


def cable_tray():
    """3 m ladder tray along X with four cables in muted colours, hung on
    threaded rods. Origin at the tray's bottom centre; tiles at 3 m."""
    clear()
    for z in (-0.2, 0.2):
        box("TrayRail", (0, 0.05, z), (3.0, 0.1, 0.025), "steel_light", 0.008)
        box("TrayLip", (0, 0.1, z - 0.012 * (1 if z > 0 else -1)), (3.0, 0.015, 0.04), "steel_light")
    for i in range(10):
        box("TrayRung", (-1.35 + i * 0.3, 0.01, 0), (0.04, 0.02, 0.4), "steel_light")
    for i, (colour, r) in enumerate((("sign_ink", 0.026), ("housing", 0.022), ("tape_brown", 0.02), ("mast_steel", 0.024))):
        z = -0.13 + i * 0.085
        cyl("Cable", (0, 0.02 + r, z), r, 3.0, colour, 6, ALONG_X)
    for x in (-1.0, 1.0):
        box("Trapeze", (x, -0.02, 0), (0.05, 0.04, 0.55), "sign_ink")
        for z in (-0.25, 0.25):
            cyl("Rod", (x, 0.4, z), 0.009, 0.84, "sign_ink", 4)
    done("sm_env_depot_cable_tray.glb")


# =============================================================================
# Dispatch desk.
# =============================================================================

def dispatch_desk():
    """1.6 x 0.8 desk, top at 0.76; the operator sits at -Z (the monitor
    faces -Z). Tube legs, a drawer pedestal at +X, keyboard, barcode scanner
    in its cradle, clipboard, mug. Base centre."""
    clear()
    box("Top", (0, 0.74, 0), (1.6, 0.04, 0.8), "wood", 0.015)
    box("TopEdge", (0, 0.74, -0.4), (1.6, 0.045, 0.02), "sign_ink")
    for x in (-0.74,):
        for z in (-0.33, 0.33):
            tube("Leg", [(x, 0.0, z), (x, 0.72, z)], 0.025, "steel", 8)
        tube("LegFoot", [(x, 0.025, -0.36), (x, 0.025, 0.36)], 0.025, "steel", 8)
    box("ModestyPanel", (-0.05, 0.47, 0.37), (1.3, 0.4, 0.02), "steel_light", 0.006)
    # Drawer pedestal.
    px = 0.52
    box("Pedestal", (px, 0.36, 0.0), (0.46, 0.7, 0.72), "depot_blue", 0.02)
    for i, y in enumerate((0.58, 0.38, 0.15)):
        h = 0.16 if i < 2 else 0.24
        box("Drawer", (px, y, -0.365), (0.42, h, 0.02), "depot_blue", 0.008)
        box("DrawerPull", (px, y + h * 0.25, -0.385), (0.14, 0.025, 0.025), "ui_yellow", 0.008)
    # Monitor: rounded housing, stand and a UI on screen (faces -Z).
    mx, mz = -0.15, 0.2
    box("MonitorFoot", (mx, 0.77, mz), (0.26, 0.02, 0.18), "sign_ink", 0.008)
    box("MonitorNeck", (mx, 0.9, mz + 0.03), (0.06, 0.26, 0.04), "sign_ink", 0.01)
    box("MonitorHousing", (mx, 1.08, mz), (0.6, 0.38, 0.06), "sign_ink", 0.03)
    box("Screen", (mx, 1.085, mz - 0.031), (0.53, 0.3, 0.004), "screen")
    box("ScreenBar", (mx, 1.215, mz - 0.034), (0.53, 0.04, 0.003), "ui_mint")
    for i in range(3):
        box("ScreenRow", (mx - 0.08, 1.15 - i * 0.055, mz - 0.034), (0.32, 0.022, 0.003), "paper")
    box("ScreenBadge", (mx + 0.17, 1.1, mz - 0.034), (0.1, 0.1, 0.003), "ui_yellow")
    # Keyboard and mouse.
    box("Keyboard", (mx, 0.772, -0.12), (0.44, 0.022, 0.15), "housing", 0.008, pitch=-0.05)
    box("Keys", (mx, 0.785, -0.12), (0.4, 0.008, 0.11), "steel_light")
    box("Mouse", (mx + 0.32, 0.772, -0.12), (0.06, 0.025, 0.1), "housing", 0.012)
    # Barcode scanner standing in its cradle.
    sx, sz = 0.42, 0.0
    box("Cradle", (sx, 0.78, sz), (0.1, 0.04, 0.12), "sign_ink", 0.01)
    rod("ScannerGrip", (sx, 0.78, sz + 0.02), (sx, 0.92, sz - 0.02), 0.022, "sign_ink", 6)
    box("ScannerHead", (sx, 0.95, sz - 0.05), (0.08, 0.07, 0.14), "ui_yellow", 0.02, pitch=0.35)
    box("ScannerWindow", (sx, 0.93, sz - 0.12), (0.06, 0.04, 0.01), "signal_red", pitch=0.35)
    # Clipboard and mug.
    box("Clipboard", (0.12, 0.765, -0.2), (0.24, 0.012, 0.32), "logo_cardboard", 0.004, yaw=0.25)
    box("ClipSheet", (0.12, 0.773, -0.21), (0.2, 0.004, 0.26), "paper", yaw=0.25)
    box("Clip", (0.155, 0.778, -0.07), (0.09, 0.016, 0.035), "sign_ink", yaw=0.25)
    cyl("Mug", (-0.62, 0.81, -0.05), 0.045, 0.1, "ui_red", 10)
    cyl("MugCoffee", (-0.62, 0.855, -0.05), 0.038, 0.012, "sign_ink", 10)
    done("sm_env_depot_dispatch_desk.glb")


# =============================================================================
# Truck bay: bollard, column guard, wheel chock and stop, door light.
# =============================================================================

def bollard():
    """1.1 m steel bollard, rounded cap, base plate with four bolts."""
    clear()
    box("BasePlate", (0, 0.012, 0), (0.34, 0.024, 0.34), "steel", 0.008)
    for x in (-0.12, 0.12):
        for z in (-0.12, 0.12):
            cyl("Bolt", (x, 0.034, z), 0.022, 0.024, "steel_light", 6)
    cyl("Post", (0, 0.54, 0), 0.11, 1.03, "warning", 14)
    ball("Cap", (0, 1.05, 0), (0.112, 0.075, 0.112), "warning", 2)
    for y in (0.66, 0.86):
        cyl("Band", (0, y, 0), 0.115, 0.09, "sign_ink", 14)
    done("sm_env_depot_bollard.glb")


def column_guard():
    """U-shaped guard for a 0.36 x 0.30 wall column: the open side toward
    +Z (the wall), 0.8 m tall, two ink bands. Origin under the column's centre."""
    clear()
    t, h = 0.1, 0.8
    ix, iz = 0.21, 0.17   # inner half sizes (column + clearance)
    box("GuardFront", (0, h / 2, -iz - t / 2), (2 * (ix + t), h, t), "warning", 0.03)
    for side in (-1.0, 1.0):
        box("GuardSide", (side * (ix + t / 2), h / 2, 0.0), (t, h, 2 * iz), "warning", 0.03)
    for y in (0.3, 0.6):
        box("BandFront", (0, y, -iz - t / 2), (2 * (ix + t) + 0.01, 0.1, t + 0.01), "sign_ink")
        for side in (-1.0, 1.0):
            box("BandSide", (side * (ix + t / 2), y, 0.0), (t + 0.01, 0.1, 2 * iz), "sign_ink")
    done("sm_env_depot_column_guard.glb")


def wheel_chock():
    """Rubber wheel chock, tall face toward -Z (where the tyre sits), with a
    yellow cord handle. Base centre."""
    clear()
    profile = [(-0.13, 0.0), (0.15, 0.0), (0.15, 0.03), (-0.08, 0.17), (-0.13, 0.17)]
    sweep_x("Chock", profile, -0.1, 0.1, "sign_ink")
    for x in (-0.06, 0.0, 0.06):
        box("Rib", (x, 0.1, 0.035), (0.02, 0.025, 0.22), "sign_ink", pitch=-0.55)
    box("ChockStripe", (0, 0.172, -0.105), (0.2, 0.006, 0.05), "warning")
    tube("Cord", [(-0.05, 0.17, -0.1), (-0.04, 0.26, -0.12), (0.04, 0.26, -0.12), (0.05, 0.17, -0.1)], 0.01, "ui_yellow", 6)
    done("sm_env_depot_wheel_chock.glb")


def wheel_stop():
    """1.8 m floor wheel stop along X, rubber with yellow blocks, two bolts. Base centre."""
    clear()
    profile = [(-0.09, 0.0), (0.09, 0.0), (0.06, 0.1), (-0.06, 0.1)]
    sweep_x("Stop", profile, -0.9, 0.9, "sign_ink")
    for i in range(5):
        x = -0.72 + i * 0.36
        sweep_x("StopStripe", [(-0.092, 0.0), (0.092, 0.0), (0.062, 0.102), (-0.062, 0.102)], x - 0.09, x + 0.09, "warning")
    for x in (-0.54, 0.54):
        cyl("Bolt", (x, 0.1, 0), 0.025, 0.012, "steel_light", 6)
    done("sm_env_depot_wheel_stop.glb")


def door_light():
    """Signal light by the roller door: red X on top, green arrow below, as
    separate nodes `DoorLightRed` / `DoorLightGreen` (materials signal_red /
    signal_green) the game switches on. Back on the wall, faces -Z; origin
    on the wall plane under the bracket (the housing spans 0.05 .. 0.6)."""
    clear()
    wall_back("Bracket", 0.3, 0.62, 0.02, "steel")
    box("Housing", (0, 0.33, -0.1), (0.28, 0.56, 0.16), "sign_ink", 0.03)
    for y in (0.46, 0.2):
        cyl("LensBack", (0, y, -0.182), 0.105, 0.01, "housing", 16, ALONG_Z)
        box("Visor", (0, y + 0.115, -0.22), (0.25, 0.02, 0.1), "sign_ink", 0.008, pitch=-0.15)
    # Red X.
    w, a = 0.028, 0.075
    xs = [(0, w), (a - w, a), (a, a - w), (w, 0), (a, -a + w), (a - w, -a), (0, -w), (-a + w, -a), (-a, -a + w), (-w, 0), (-a, a - w), (-a + w, a)]
    red = panel("DoorLightRed", [(x, y + 0.46) for x, y in xs], -0.192, -0.186, "signal_red")
    red.name = "DoorLightRed"
    arrow = [(0.0, 0.29), (0.075, 0.21), (0.03, 0.21), (0.03, 0.12), (-0.03, 0.12), (-0.03, 0.21), (-0.075, 0.21)]
    green = panel("DoorLightGreen", arrow, -0.192, -0.186, "signal_green")
    green.name = "DoorLightGreen"
    done("sm_env_depot_door_light.glb")


# =============================================================================
# Logistics: roll cage, flat cardboard, wrapped pallet, sorting table, ladder.
# =============================================================================

def _roll_cage():
    w, d, h = 0.8, 0.7, 1.75
    hx, hz = w / 2, d / 2
    box("Base", (0, 0.16, 0), (w, 0.05, d), "depot_blue", 0.015)
    for x in (-hx, hx):
        box("BaseRail", (x, 0.14, 0), (0.04, 0.06, d), "depot_blue")
    for x in (-hx + 0.08, hx - 0.08):
        for z in (-hz + 0.08, hz - 0.08):
            box("CasterFork", (x, 0.1, z), (0.05, 0.06, 0.06), "sign_ink")
            cyl("Caster", (x, 0.055, z), 0.055, 0.035, "rubber", 10, ALONG_X)
    for x in (-hx, hx):
        for z in (-hz, hz):
            tube("Post", [(x, 0.18, z), (x, h, z)], 0.018, "steel_light", 6)
    tube("TopRail", [(-hx, h, -hz), (-hx, h, hz), (hx, h, hz), (hx, h, -hz)], 0.018, "steel_light", 6)
    tube("MidRail", [(-hx, 0.95, -hz), (-hx, 0.95, hz), (hx, 0.95, hz), (hx, 0.95, -hz)], 0.014, "steel_light", 6)
    mesh_quad("CageBack", -hx, hx, 0.19, h, hz)
    for side in (-1.0, 1.0):
        quad("CageSide", [(side * hx, 0.19, -hz), (side * hx, 0.19, hz), (side * hx, h, hz), (side * hx, h, -hz)],
             [(0, 0), (d / 0.25, 0), (d / 0.25, (h - 0.19) / 0.25), (0, (h - 0.19) / 0.25)], "cage_mesh")
    box("Strap", (0, 1.15, -hz - 0.01), (w + 0.02, 0.05, 0.012), "ui_yellow")
    for x in (-hx, hx):
        box("StrapBuckle", (x, 1.15, -hz - 0.012), (0.04, 0.07, 0.03), "sign_ink")


def roll_cage():
    """Roll cage 0.8 x 0.7 x 1.75, open front toward -Z, empty. Base centre."""
    clear()
    _roll_cage()
    done("sm_env_depot_roll_cage.glb")


def roll_cage_loaded():
    """The same roll cage with a load of parcels."""
    clear()
    _roll_cage()
    y = 0.185
    parcel((-0.18, y + 0.16, 0.08), (0.38, 0.32, 0.5))
    parcel((0.19, y + 0.13, 0.05), (0.36, 0.26, 0.56), "tape_brown")
    parcel((0.18, y + 0.26 + 0.12, 0.1), (0.34, 0.24, 0.4), "logo_cardboard", 0.1)
    parcel((-0.17, y + 0.32 + 0.1, 0.12), (0.36, 0.2, 0.42), "tape_brown", -0.08)
    parcel((-0.05, y + 0.52 + 0.13, 0.05), (0.52, 0.26, 0.5), "logo_cardboard", 0.05)
    parcel((0.2, y + 0.78 + 0.09, 0.15), (0.3, 0.18, 0.3), "tape_brown", -0.2)
    done("sm_env_depot_roll_cage_loaded.glb")


def flat_cardboard_stack():
    """A pallet of flat-packed cartons with two yellow straps. Base centre."""
    clear()
    y = pallet()
    for i in range(10):
        box("FlatCarton", (0.01 * ((i * 7) % 3 - 1), y + 0.015 + i * 0.03, 0.01 * ((i * 5) % 3 - 1)), (1.12, 0.028, 0.92),
            "logo_cardboard" if i % 3 else "tape_brown", 0.004, yaw=0.015 * ((i * 3) % 3 - 1))
    top = y + 0.31
    for x in (-0.35, 0.35):
        box("Strap", (x, y + 0.155, 0), (0.05, 0.32, 0.94), "ui_yellow")
        box("StrapTop", (x, top, 0), (0.05, 0.006, 0.94), "ui_yellow")
    box("Label", (0, y + 0.2, -0.465), (0.2, 0.12, 0.004), "paper")
    done("sm_env_depot_flat_cardboard_stack.glb")


def pallet_wrapped():
    """A pallet of parcels in stretch film: the parcels, then `FilmShell`
    (material `film`, alpha 0.35 with sheen) as a separate node. Base centre."""
    clear()
    y = pallet()
    layer_h = (0.42, 0.38, 0.3)
    for L, h in enumerate(layer_h):
        cols = [(-0.3, -0.25), (0.3, -0.25), (-0.3, 0.25), (0.3, 0.25)]
        for i, (x, z) in enumerate(cols):
            if L == 2 and i == 3:
                continue
            colour = "logo_cardboard" if (i + L) % 2 == 0 else "tape_brown"
            parcel((x, y + h / 2, z), (0.58, h - 0.01, 0.48), colour)
        y += h
    y0 = 0.144
    open_shell("FilmShell", (0, y0 + (y - y0 - 0.25) / 2 + 0.02, 0), (1.22, y - y0 - 0.25, 1.02), "film")
    box("Label", (0.25, 0.144 + 0.55, -0.515), (0.2, 0.14, 0.004), "paper")
    box("LabelStripe", (0.25, 0.144 + 0.6, -0.518), (0.2, 0.03, 0.004), "ui_red")
    done("sm_env_depot_pallet_wrapped.glb")


def sorting_table():
    """2.0 x 0.9 sorting and packing table, top at 0.9, front toward -Z: a
    stretch-film roll on its stand, tape, a tape gun, parcels on the back
    shelf and flat cartons underneath. Base centre."""
    clear()
    box("Top", (0, 0.88, 0), (2.0, 0.05, 0.9), "deck_grey", 0.015)
    box("TopEdge", (0, 0.855, -0.45), (2.0, 0.05, 0.03), "depot_orange", 0.01)
    for x in (-0.94, 0.94):
        for z in (-0.4, 0.4):
            tube("Leg", [(x, 0.0, z), (x, 0.86, z)], 0.028, "depot_blue", 8)
            cyl("Foot", (x, 0.012, z), 0.045, 0.024, "sign_ink", 8)
    box("LowerShelf", (0, 0.22, 0), (1.9, 0.03, 0.82), "deck_grey", 0.008)
    for i in range(5):
        box("FlatCarton", (-0.3 + i * 0.02, 0.25 + i * 0.022, 0.0), (1.0, 0.02, 0.7), "logo_cardboard", yaw=0.03 * i)
    # Back upright with a shelf.
    for x in (-0.94, 0.94):
        tube("Upright", [(x, 0.9, 0.42), (x, 1.62, 0.42)], 0.025, "depot_blue", 8)
    box("Shelf", (0, 1.4, 0.3), (1.95, 0.03, 0.3), "deck_grey", 0.008)
    box("ShelfLip", (0, 1.43, 0.155), (1.95, 0.04, 0.015), "depot_orange")
    box("Crossbar", (0, 1.62, 0.42), (1.9, 0.04, 0.04), "depot_blue")
    parcel((-0.6, 1.415 + 0.1, 0.3), (0.3, 0.2, 0.24))
    parcel((-0.25, 1.415 + 0.08, 0.3), (0.26, 0.16, 0.22), "tape_brown")
    for i in range(3):
        cyl("TapeRoll", (0.3 + i * 0.13, 1.415 + 0.05, 0.3), 0.055, 0.05, "tape_brown", 10)
    # Stretch-film roll on a spindle at the left end.
    fx, fz = -0.82, 0.12
    box("FilmStandBase", (fx, 0.915, fz), (0.2, 0.02, 0.2), "sign_ink", 0.006)
    cyl("FilmRoll", (fx, 0.925 + 0.22, fz), 0.085, 0.42, "film", 12)
    cyl("FilmRollCore", (fx, 0.925 + 0.22, fz), 0.03, 0.48, "logo_cardboard", 8)
    ball("FilmRollTip", (fx, 0.925 + 0.47, fz), (0.02, 0.02, 0.02), "sign_ink")
    box("FilmTail", (fx + 0.13, 0.95, fz - 0.05), (0.2, 0.005, 0.3), "film", yaw=0.4)
    # On top: a parcel being packed, a tape gun, a label roll.
    parcel((0.05, 0.905 + 0.14, -0.05), (0.44, 0.28, 0.34))
    box("TapeGunBody", (0.55, 0.955, -0.1), (0.1, 0.1, 0.2), "danger_red", 0.02)
    rod("TapeGunGrip", (0.55, 0.93, -0.02), (0.55, 1.05, 0.03), 0.025, "sign_ink", 6)
    cyl("TapeGunRoll", (0.55, 1.0, -0.14), 0.07, 0.06, "tape_brown", 10, ALONG_X)
    cyl("LabelRoll", (0.82, 0.975, -0.25), 0.07, 0.07, "paper", 12, ALONG_Z)
    cyl("LabelCore", (0.82, 0.975, -0.25), 0.028, 0.075, "ui_mint", 8, ALONG_Z)
    done("sm_env_depot_sorting_table.glb")


def rolling_ladder():
    """Warehouse rolling ladder: five steps climbing toward +Z to a 1.25 m
    platform with a hand-rail cage; wheels at the back. Base centre of the
    footprint (0.8 x 1.6); the first step is at the -Z end."""
    clear()
    w, run, steps, top = 0.62, 0.23, 5, 1.25
    z0 = -0.8
    rise = top / steps
    for side in (-1.0, 1.0):
        x = side * (w / 2 + 0.03)
        clip_floor(bar("Stringer", (x, 0.0, z0), (x, top, z0 + run * steps), 0.04, "depot_blue", 0.1))
        clip_floor(bar("BackLeg", (x, 0.0, 0.75), (x, top, 0.5), 0.045, "depot_blue", 0.05))
        bar("Brace", (x, 0.35, z0 + 0.35), (x, 0.35, 0.72), 0.03, "depot_blue")
        tube("HandRail", [(x, 0.95, z0), (x, top + 0.95, z0 + run * steps), (x, top + 0.95, 0.72), (x, top, 0.72)],
             0.022, "ui_yellow", 8)
        cyl("Foot", (x, 0.015, z0 + 0.02), 0.035, 0.03, "rubber", 8)
        cyl("Wheel", (x, 0.06, 0.72), 0.06, 0.04, "rubber", 10, ALONG_X)
    tube("BackRail", [(-(w / 2 + 0.03), top + 0.95, 0.72), ((w / 2 + 0.03), top + 0.95, 0.72)], 0.022, "ui_yellow", 8)
    for i in range(steps):
        z = z0 + (i + 1) * run
        y = (i + 1) * rise
        if i == steps - 1:
            box("Platform", (0, y - 0.02, z + 0.25), (w, 0.04, 0.55), "steel_light", 0.008)
            box("PlatformNose", (0, y - 0.005, z - 0.02), (w, 0.03, 0.04), "warning")
        else:
            box("Tread", (0, y - 0.02, z - run / 2), (w, 0.04, run), "steel_light", 0.008)
            box("TreadNose", (0, y - 0.005, z - run + 0.02), (w, 0.03, 0.04), "warning")
    done("sm_env_depot_rolling_ladder.glb")


# =============================================================================
# Office and mezzanine: stair, railing, blind, window frame.
# =============================================================================

STAIR_RISE, STAIR_RUN, STAIR_STEPS, STAIR_W = 2.9, 4.6, 16, 1.0


def stair():
    """The mezzanine stair: 16 steps, 2.9 m up over a 4.6 m run toward +Z,
    1.0 m wide, C-channel stringers and a round hand rail each side. Origin
    on the floor at the middle of the first riser (z = 0); the last tread is
    level with the deck at z = 4.6. Matches depot_zones.gd _build_stair()."""
    clear()
    run = STAIR_RUN / STAIR_STEPS
    rise = STAIR_RISE / STAIR_STEPS
    L = math.hypot(STAIR_RUN, STAIR_RISE)
    ny, nz = STAIR_RUN / L, -STAIR_RISE / L   # up-normal of the slope (y, z)
    for i in range(STAIR_STEPS):
        z = i * run
        nose = (i + 1) * rise
        box("Tread", (0, nose - 0.025, z + run / 2), (STAIR_W, 0.05, run + 0.04), "steel_light")
        box("TreadNose", (0, nose + 0.002, z + run - 0.03), (STAIR_W, 0.04, 0.05), "warning")
    for side in (-1.0, 1.0):
        x = side * (STAIR_W / 2 + 0.03)
        a = (x, -0.12 * ny, -0.12 * nz)
        b = (x, STAIR_RISE - 0.12 * ny, STAIR_RUN - 0.12 * nz)
        clip_floor(bar("StringerWeb", a, b, 0.02, "housing", 0.28))
        for off in (-0.13, 0.13):
            fa = (x - side * 0.035, a[1] + off * ny, a[2] + off * nz)
            fb = (x - side * 0.035, b[1] + off * ny, b[2] + off * nz)
            clip_floor(bar("StringerFlange", fa, fb, 0.07, "housing", 0.02))
        rail_h = 0.95
        posts = [0, 4, 8, 12, 16]
        for k in posts:
            pz, py = k * run, k * rise
            tube("Post", [(x, py, pz), (x, py + rail_h, pz)], 0.022, "warning", 8, caps=False)
        tube("HandRail", [(x, rail_h - 0.1, -0.25), (x, rail_h, 0.0), (x, STAIR_RISE + rail_h, STAIR_RUN),
                          (x, STAIR_RISE + rail_h, STAIR_RUN + 0.3)], 0.028, "warning", 8)
        tube("MidRail", [(x, 0.5, 0.0), (x, STAIR_RISE + 0.5, STAIR_RUN)], 0.018, "warning", 6)
    done("sm_env_depot_stair.glb")


def railing_segment():
    """1.2 m of deck railing along X (x -0.6 .. 0.6): a post at the -X end,
    round top rail at 1.1, mid rail, ink toe board. Tile every 1.2 m and
    close the run with sm_env_depot_railing_post. Base centre."""
    clear()
    tube("Post", [(-0.6, 0.0, 0), (-0.6, 1.1, 0)], 0.025, "warning", 8)
    box("PostFoot", (-0.6, 0.01, 0), (0.1, 0.02, 0.1), "sign_ink")
    tube("TopRail", [(-0.6, 1.1, 0), (0.6, 1.1, 0)], 0.028, "warning", 8, caps=False)
    tube("MidRail", [(-0.6, 0.55, 0), (0.6, 0.55, 0)], 0.018, "warning", 6, caps=False)
    box("ToeBoard", (0, 0.06, 0), (1.2, 0.12, 0.03), "sign_ink", 0.006)
    done("sm_env_depot_railing_segment.glb")


def railing_post():
    """The end post that closes a run of railing segments."""
    clear()
    tube("Post", [(0, 0.0, 0), (0, 1.1, 0)], 0.025, "warning", 8)
    ball("PostCap", (0, 1.1, 0), (0.035, 0.035, 0.035), "warning")
    box("PostFoot", (0, 0.01, 0), (0.1, 0.02, 0.1), "sign_ink")
    done("sm_env_depot_railing_post.glb")


def office_blind():
    """Venetian blind for the office window, 1.2 x 1.1, slats slightly
    open, front toward -Z. Origin at the bottom centre (sits on the sill)."""
    clear()
    w, h = 1.2, 1.1
    box("HeadRail", (0, h - 0.03, 0), (w + 0.02, 0.06, 0.07), "curtain", 0.01)
    box("BottomRail", (0, 0.015, 0), (w, 0.03, 0.05), "curtain", 0.008)
    n = 17
    for i in range(n):
        y = 0.07 + i * (h - 0.13) / (n - 1)
        box("Slat", (0, y, 0), (w - 0.02, 0.005, 0.05), "curtain", pitch=0.45)
    for x in (-0.4, 0.4):
        box("Ladder", (x, h / 2, -0.026), (0.008, h - 0.06, 0.003), "curtain_rib")
        box("Ladder", (x, h / 2, 0.026), (0.008, h - 0.06, 0.003), "curtain_rib")
    box("PullCord", (0.52, h * 0.55, -0.045), (0.006, h * 0.8, 0.006), "sign_ink")
    ball("CordKnob", (0.52, h * 0.15, -0.045), (0.018, 0.028, 0.018), "sign_ink")
    box("Wand", (-0.52, h * 0.62, -0.045), (0.012, h * 0.65, 0.012), "curtain")
    done("sm_env_depot_office_blind.glb")


def window_frame():
    """1.2 m of dark window frame (8 cm): sill, head and one mullion at the
    -X end; tile every 1.2 m and close with sm_env_depot_window_mullion.
    1.3 m tall, no glass (the game's glazing sits inside). Base centre."""
    clear()
    w, h, f = 1.2, 1.3, 0.08
    box("Sill", (0, f / 2, -0.02), (w, f, 0.14), "sign_ink", 0.012)
    box("Head", (0, h - f / 2, 0), (w, f, 0.1), "sign_ink", 0.012)
    box("Mullion", (-w / 2, h / 2, 0), (f, h, 0.1), "sign_ink", 0.012)
    done("sm_env_depot_window_frame.glb")


def window_mullion():
    """The end mullion that closes a run of window frames."""
    clear()
    box("Mullion", (0, 0.65, 0), (0.08, 1.3, 0.1), "sign_ink", 0.012)
    done("sm_env_depot_window_mullion.glb")


# =============================================================================
# Supplies cage: mesh panel and service window.
# =============================================================================

CAGE_H = 2.7


def _tube_frame(x0, x1, y0, y1, z, r=0.025, material="housing"):
    tube("Frame", [(x0, y0, z), (x0, y1, z), (x1, y1, z), (x1, y0, z), (x0, y0, z)], r, material, 8, caps=False)


def cage_panel():
    """1.2 x 2.7 panel of the supplies cage: 5 cm tube frame around a 25 cm
    diamond mesh (alpha texture), feet. Tiles every 1.2 m along X. Base centre."""
    clear()
    hx = 0.6
    _tube_frame(-hx + 0.025, hx - 0.025, 0.06, CAGE_H - 0.025, 0)
    tube("MidBar", [(-hx + 0.025, 1.1, 0), (hx - 0.025, 1.1, 0)], 0.02, "housing", 8, caps=False)
    mesh_quad("Mesh", -hx + 0.03, hx - 0.03, 0.065, CAGE_H - 0.03, 0.0)
    for x in (-hx + 0.03, hx - 0.03):
        box("Foot", (x, 0.02, 0), (0.08, 0.04, 0.3), "sign_ink", 0.01)
    done("sm_env_depot_cage_panel.glb")


def cage_window():
    """2.2 m service window of the supplies cage: mesh under a counter at
    1.05, the opening up to 2.05 with a half-open sliding grille, mesh above,
    a pass-through tray on the counter. Front (the hall) toward -Z. Base centre."""
    clear()
    hx = 1.1
    counter, lintel = 1.05, 2.05
    _tube_frame(-hx + 0.025, hx - 0.025, 0.06, CAGE_H - 0.025, 0)
    tube("Lintel", [(-hx + 0.025, lintel, 0), (hx - 0.025, lintel, 0)], 0.025, "housing", 8, caps=False)
    mesh_quad("MeshLow", -hx + 0.03, hx - 0.03, 0.065, counter - 0.03, 0.0)
    for x in (-hx + 0.03, hx - 0.03):
        box("Foot", (x, 0.02, 0), (0.08, 0.04, 0.3), "sign_ink", 0.01)
    mesh_quad("MeshHigh", -hx + 0.03, hx - 0.03, lintel + 0.03, CAGE_H - 0.03, 0.0)
    box("Counter", (0, counter, -0.05), (2 * hx + 0.1, 0.05, 0.55), "wood", 0.015)
    box("CounterEdge", (0, counter - 0.01, -0.325), (2 * hx + 0.1, 0.05, 0.02), "depot_orange")
    for x in (-0.8, 0.8):
        bar("CounterBracket", (x, counter - 0.03, -0.3), (x, counter - 0.3, -0.02), 0.04, "housing")
    # Sliding grille on a track, pulled half across from the left.
    box("GrilleTrack", (0, lintel - 0.05, 0.05), (2 * hx - 0.05, 0.04, 0.04), "sign_ink")
    gx0, gx1 = -hx + 0.05, -0.15
    _tube_frame(gx0, gx1, counter + 0.04, lintel - 0.08, 0.06, 0.015, "steel")
    mesh_quad("GrilleMesh", gx0 + 0.01, gx1 - 0.01, counter + 0.05, lintel - 0.09, 0.06)
    box("GrilleHandle", (gx1 - 0.04, 1.55, 0.09), (0.03, 0.18, 0.03), "ui_yellow", 0.008)
    # Pass-through tray, sunk into the counter's front.
    box("Tray", (0.35, counter + 0.035, -0.12), (0.5, 0.02, 0.34), "steel_light", 0.006)
    for side in (-1.0, 1.0):
        box("TrayLip", (0.35 + side * 0.25, counter + 0.05, -0.12), (0.02, 0.04, 0.34), "steel_light")
    box("TrayLipFront", (0.35, counter + 0.05, -0.29), (0.5, 0.04, 0.02), "steel_light")
    box("SignBoard", (0, CAGE_H + 0.12, -0.02), (1.2, 0.22, 0.03), "sign_ink", 0.01)
    box("SignBoardFace", (0, CAGE_H + 0.12, -0.037), (1.1, 0.14, 0.004), "ui_yellow")
    done("sm_env_depot_cage_window.glb")


# =============================================================================
# Safety and services on the walls; bins, water, wet-floor, pictogram sign.
# =============================================================================

def _extinguisher(x, y0, z):
    cyl("ExtBody", (x, y0 + 0.23, z), 0.075, 0.42, "danger_red", 12)
    ball("ExtDome", (x, y0 + 0.44, z), (0.075, 0.05, 0.075), "danger_red")
    cyl("ExtLabel", (x, y0 + 0.24, z), 0.077, 0.12, "paper", 12)
    cyl("ExtValve", (x, y0 + 0.51, z), 0.028, 0.08, "sign_ink", 8)
    box("ExtLever", (x + 0.05, y0 + 0.56, z), (0.12, 0.02, 0.03), "steel_light", pitch=0.0, roll=0.25)
    box("ExtGauge", (x - 0.03, y0 + 0.52, z - 0.03), (0.03, 0.03, 0.01), "paper")
    tube("ExtHose", [(x - 0.02, y0 + 0.52, z), (x - 0.1, y0 + 0.47, z), (x - 0.11, y0 + 0.3, z - 0.02), (x - 0.09, y0 + 0.2, z - 0.03)],
         0.014, "sign_ink", 6)


def extinguisher():
    """Floor-standing fire extinguisher, 0.6 m. Base centre."""
    clear()
    _extinguisher(0, 0.0, 0)
    cyl("Stand", (0, 0.015, 0), 0.1, 0.03, "sign_ink", 12)
    done("sm_env_depot_extinguisher.glb")


def extinguisher_cabinet():
    """Red open wall cabinet (bottom at 0.9) with its extinguisher and a
    number plate above (the game writes the number). Back on the wall,
    front toward -Z; origin on the floor at the wall."""
    clear()
    y0, w, h, d = 0.9, 0.36, 0.72, 0.24
    box("CabBack", (0, y0 + h / 2, -0.01), (w, h, 0.02), "danger_red", 0.005)
    for side in (-1.0, 1.0):
        box("CabSide", (side * (w / 2 - 0.015), y0 + h / 2, -d / 2), (0.03, h, d), "danger_red", 0.01)
    box("CabTop", (0, y0 + h - 0.015, -d / 2), (w, 0.03, d), "danger_red", 0.01)
    box("CabBottom", (0, y0 + 0.015, -d / 2), (w, 0.03, d), "danger_red", 0.01)
    box("CabLip", (0, y0 + 0.08, -d + 0.01), (w, 0.1, 0.02), "danger_red", 0.006)
    _extinguisher(0.02, y0 + 0.04, -0.11)
    box("NumberPlate", (0, y0 + h + 0.2, -0.015), (0.3, 0.3, 0.03), "danger_red", 0.01)
    box("NumberFace", (0, y0 + h + 0.2, -0.032), (0.24, 0.24, 0.004), "paper")
    done("sm_env_depot_extinguisher_cabinet.glb")


def electrical_panel():
    """Grey electrical cabinet (1.1 .. 2.0) with a warning sticker, an
    isolator with a red handle and three conduits up to 3.4 m. Wall piece,
    front toward -Z; origin on the floor at the wall."""
    clear()
    y0, w, h, d = 1.1, 0.72, 0.9, 0.22
    box("Cabinet", (0, y0 + h / 2, -d / 2), (w, h, d), "deck_grey", 0.02)
    box("DoorSeam", (0, y0 + h / 2, -d - 0.002), (0.012, h - 0.08, 0.004), "sign_ink")
    for x in (-0.05, 0.05):
        box("Handle", (x, y0 + h * 0.5, -d - 0.015), (0.025, 0.12, 0.03), "sign_ink", 0.006)
    panel("StickerRim", [(-0.14, y0 + 0.6), (0.0, y0 + 0.84), (0.14, y0 + 0.6)], -d - 0.006, -d - 0.002, "sign_ink")
    panel("Sticker", [(-0.11, y0 + 0.615), (0.0, y0 + 0.805), (0.11, y0 + 0.615)], -d - 0.009, -d - 0.005, "warning")
    panel("StickerBolt", [(0.01, y0 + 0.79), (-0.035, y0 + 0.69), (0.0, y0 + 0.69), (-0.015, y0 + 0.63),
                          (0.035, y0 + 0.72), (0.0, y0 + 0.72), (0.02, y0 + 0.79)], -d - 0.012, -d - 0.008, "sign_ink")
    for x in (-0.3, 0.3):
        box("NamePlate", (x * 0.8, y0 + 0.12, -d - 0.004), (0.16, 0.05, 0.006), "paper")
    # Isolator on the right.
    ix = w / 2 + 0.14
    box("Isolator", (ix, y0 + 0.55, -0.08), (0.18, 0.24, 0.16), "deck_grey", 0.015)
    box("IsolatorHandle", (ix, y0 + 0.55, -0.18), (0.04, 0.14, 0.05), "danger_red", 0.01, roll=0.5)
    tube("IsolatorConduit", [(ix, y0 + 0.67, -0.06), (ix, y0 + 1.1, -0.06)], 0.02, "steel", 6)
    for x in (-0.22, 0.0, 0.22):
        tube("Conduit", [(x, y0 + h - 0.01, -0.06), (x, 3.4, -0.06)], 0.025, "steel", 8)
        for y in (2.4, 3.1):
            box("Clamp", (x, y, -0.04), (0.07, 0.03, 0.06), "sign_ink")
    box("JunctionBox", (0, 2.75, -0.08), (0.62, 0.16, 0.1), "deck_grey", 0.01)
    done("sm_env_depot_electrical_panel.glb")


def first_aid():
    """First-aid cabinet (1.35 .. 1.7), green door with a white cross. Wall
    piece, front toward -Z; origin on the floor at the wall."""
    clear()
    y0 = 1.35
    box("Box", (0, y0 + 0.17, -0.07), (0.42, 0.34, 0.14), "curtain", 0.02)
    box("Door", (0, y0 + 0.17, -0.145), (0.38, 0.3, 0.02), "go_green", 0.008)
    box("CrossV", (0, y0 + 0.17, -0.157), (0.06, 0.2, 0.006), "paper")
    box("CrossH", (0, y0 + 0.17, -0.157), (0.2, 0.06, 0.006), "paper")
    box("Handle", (0.16, y0 + 0.17, -0.16), (0.02, 0.08, 0.02), "sign_ink")
    done("sm_env_depot_first_aid.glb")


def time_clock():
    """Punch clock (1.2 .. 1.55) with a card rack beside it. Wall piece,
    front toward -Z; origin on the floor at the wall (under the clock)."""
    clear()
    y0 = 1.2
    box("ClockBody", (0, y0 + 0.19, -0.09), (0.3, 0.38, 0.18), "curtain", 0.03)
    box("ClockBand", (0, y0 + 0.36, -0.09), (0.31, 0.05, 0.185), "depot_blue")
    cyl("ClockFace", (0, y0 + 0.22, -0.18), 0.1, 0.012, "paper", 16, ALONG_Z)
    for i in range(12):
        a = i * math.tau / 12
        box("Tick", (math.sin(a) * 0.08, y0 + 0.22 + math.cos(a) * 0.08, -0.188), (0.01, 0.018, 0.004), "sign_ink", roll=-a)
    box("HandH", (0.02, y0 + 0.24, -0.19), (0.012, 0.055, 0.003), "sign_ink", roll=-0.8)
    box("HandM", (0.0, y0 + 0.25, -0.192), (0.008, 0.075, 0.003), "sign_ink")
    box("Display", (0, y0 + 0.07, -0.181), (0.14, 0.04, 0.004), "screen")
    box("CardSlot", (0, y0 + 0.38, -0.1), (0.12, 0.012, 0.03), "sign_ink")
    # Card rack at +X... seen from the front (-Z) that is the viewer's left.
    rx = -0.42
    box("Rack", (rx, y0 + 0.2, -0.03), (0.34, 0.5, 0.06), "steel_light", 0.01)
    for r in range(3):
        for c in range(4):
            colour = ("paper", "logo_cardboard", "paper", "ui_mint")[(r + c) % 4]
            box("Card", (rx - 0.12 + c * 0.08, y0 + 0.07 + r * 0.16 + 0.05, -0.065), (0.06, 0.1, 0.006), colour)
        box("RackLip", (rx, y0 + 0.07 + r * 0.16, -0.07), (0.34, 0.03, 0.02), "steel", 0.004)
    done("sm_env_depot_time_clock.glb")


def recycle_station():
    """Three-bin recycling station, 1.35 wide, mouths on the lid shaped by
    type: slot (paper, blue), round (glass, green), square (plastic,
    yellow). Front toward -Z. Base centre."""
    clear()
    w, h, d = 0.43, 0.95, 0.5
    kinds = (("depot_blue", "slot"), ("go_green", "round"), ("ui_yellow", "square"))
    for i, (colour, mouth) in enumerate(kinds):
        x = (i - 1) * (w + 0.02)
        box("BinBody", (x, h / 2 - 0.02, 0), (w, h - 0.04, d), colour, 0.03)
        box("BinPlinth", (x, 0.025, 0), (w - 0.04, 0.05, d - 0.04), "sign_ink")
        box("BinLid", (x, h - 0.01, 0), (w + 0.01, 0.05, d + 0.01), "deck_grey", 0.02)
        box("BinLabel", (x, h * 0.62, -d / 2 - 0.004), (w * 0.6, w * 0.45, 0.006), "paper")
        box("BinLabelBand", (x, h * 0.62 + w * 0.17, -d / 2 - 0.006), (w * 0.6, 0.04, 0.005), colour)
        box("BinFrontLip", (x, h * 0.3, -d / 2 - 0.004), (w * 0.7, 0.03, 0.006), "sign_ink")
        yt, yb = h + 0.018, h + 0.012
        if mouth == "slot":
            floor_panel("Mouth", [(x - 0.14, -0.06), (x + 0.14, -0.06), (x + 0.14, -0.02), (x - 0.14, -0.02)], yb, yt + 0.003,
                        "sign_ink")
        elif mouth == "round":
            floor_panel("Mouth", [(x + math.cos(a) * 0.08, -0.04 + math.sin(a) * 0.08) for a in [k * math.tau / 14 for k in range(14)]],
                        yb, yt + 0.003, "sign_ink")
        else:
            floor_panel("Mouth", [(x - 0.09, -0.12), (x + 0.09, -0.12), (x + 0.09, 0.05), (x - 0.09, 0.05)], yb, yt + 0.003,
                        "sign_ink")
        box("Rim", (x, yt - 0.002, -0.04), (0.33, 0.004, 0.26), colour)
    done("sm_env_depot_recycle_station.glb")


def water_dispenser():
    """Water cooler with its bottle, taps toward -Z. Base centre."""
    clear()
    box("Body", (0, 0.5, 0), (0.32, 1.0, 0.32), "curtain", 0.03)
    box("Recess", (0, 0.72, -0.15), (0.24, 0.2, 0.03), "housing", 0.01)
    box("DripTray", (0, 0.63, -0.17), (0.22, 0.03, 0.08), "sign_ink", 0.008)
    for x, colour in ((-0.06, "depot_blue"), (0.06, "danger_red")):
        box("Tap", (x, 0.79, -0.17), (0.04, 0.05, 0.05), colour, 0.01)
    box("Base", (0, 0.04, 0), (0.33, 0.08, 0.33), "housing", 0.01)
    box("Collar", (0, 1.02, 0), (0.26, 0.04, 0.26), "housing", 0.01)
    cyl("Bottle", (0, 1.24, 0), 0.14, 0.34, "bubble", 14)
    cyl("BottleShoulder", (0, 1.07, 0), 0.06, 0.05, "bubble", 12, r2=0.14)
    cyl("BottleRing", (0, 1.3, 0), 0.142, 0.03, "bubble", 14)
    ball("BottleTop", (0, 1.41, 0), (0.14, 0.04, 0.14), "bubble")
    cyl("CupHolder", (0.2, 0.75, 0), 0.04, 0.2, "steel_light", 8)
    done("sm_env_depot_water_dispenser.glb")


def wet_floor_cone():
    """Yellow wet-floor cone, 0.62 m, with an ink band. Base centre."""
    clear()
    box("ConeBase", (0, 0.02, 0), (0.32, 0.04, 0.32), "ui_yellow", 0.015)
    cyl("Cone", (0, 0.32, 0), 0.14, 0.56, "ui_yellow", 12, r2=0.03)
    cyl("ConeBand", (0, 0.36, 0), 0.098, 0.1, "sign_ink", 12, r2=0.084)
    ball("ConeTip", (0, 0.6, 0), (0.035, 0.03, 0.035), "ui_yellow")
    done("sm_env_depot_wet_floor_cone.glb")


def wet_floor_sign():
    """Folding A-frame "wet floor" sign, 0.64 m, a warning triangle and a
    text band on each side (the game writes the words). Base centre."""
    from mathutils import Euler
    clear()
    lean = 0.2
    for side in (-1.0, 1.0):
        pitch = -side * lean          # top leans toward the middle
        centre = Vector(G(0, 0.318, side * math.sin(lean) * 0.31))
        rot = Euler((pitch, 0, 0))
        box("Board", (0, 0.318, side * math.sin(lean) * 0.31), (0.32, 0.64, 0.02), "ui_yellow", 0.015, pitch=pitch)
        for part, pts, dy in (("Triangle", [(-0.11, -0.08), (0.11, -0.08), (0.0, 0.11)], 0.1),
                              ("TextBand", [(-0.12, -0.03), (0.12, -0.03), (0.12, 0.03), (-0.12, 0.03)], -0.12)):
            o = panel(part, pts, -0.003, 0.003, "sign_ink")
            o.rotation_euler = rot
            o.location = centre + rot.to_matrix() @ Vector(G(0, dy, side * 0.013))
    tube("Hinge", [(-0.17, 0.63, 0), (0.17, 0.63, 0)], 0.015, "sign_ink", 6)
    done("sm_env_depot_wet_floor_sign.glb")


def pictogram_sign():
    """Generic pictogram sign, 0.42 square: dark frame, `SignPlate` (material
    sign_plate, the game tints it) and `Pictogram`, a quad mapped to cell 0
    of textures/depot/tx_depot_pictograms_512.png (4 x 4 cells; offset the
    UV by (col, row) * 0.25 for another pictogram, order in PICTOGRAMS).
    Back on the wall, faces -Z; origin at the back's bottom centre."""
    clear()
    s = 0.42
    box("Frame", (0, s / 2, -0.015), (s, s, 0.03), "sign_ink", 0.012)
    plate = box("SignPlate", (0, s / 2, -0.032), (s - 0.05, s - 0.05, 0.006), "sign_plate")
    plate.name = "SignPlate"
    p = (s - 0.1) / 2
    y = s / 2
    z = -0.0365
    pic = quad("Pictogram", [(p, y - p, z), (-p, y - p, z), (-p, y + p, z), (p, y + p, z)],
               [(0.0, 0.75), (0.25, 0.75), (0.25, 1.0), (0.0, 1.0)], "sign_pictogram")
    pic.name = "Pictogram"
    done("sm_env_depot_pictogram_sign.glb")


# =============================================================================
# Break room: fridge and kitchenette.
# =============================================================================

def fridge():
    """Two-door fridge 0.62 x 0.66 x 1.75, doors toward -Z. Base centre."""
    clear()
    w, d, h = 0.62, 0.66, 1.75
    box("Body", (0, h / 2 + 0.04, 0.02), (w, h - 0.08, d - 0.04), "curtain", 0.04)
    box("Kick", (0, 0.04, 0.02), (w - 0.04, 0.08, d - 0.08), "housing")
    box("FreezerDoor", (0, 1.5, -d / 2 + 0.02), (w - 0.02, 0.42, 0.05), "curtain", 0.025)
    box("FridgeDoor", (0, 0.71, -d / 2 + 0.02), (w - 0.02, 1.12, 0.05), "curtain", 0.025)
    for y0, y1 in ((1.36, 1.6), (1.0, 1.25)):
        tube("Handle", [(-0.25, y0, -d / 2 - 0.005), (-0.25, y0, -d / 2 - 0.035), (-0.25, y1, -d / 2 - 0.035),
                        (-0.25, y1, -d / 2 - 0.005)], 0.012, "steel_light", 6)
    box("Note", (0.1, 1.12, -d / 2 - 0.007), (0.12, 0.15, 0.003), "paper", roll=0.1)
    box("NoteB", (0.12, 0.85, -d / 2 - 0.007), (0.1, 0.1, 0.003), "ui_yellow", roll=-0.12)
    cyl("Magnet", (0.1, 1.18, -d / 2 - 0.01), 0.02, 0.01, "ui_red", 8, ALONG_Z)
    cyl("MagnetB", (0.14, 0.89, -d / 2 - 0.01), 0.018, 0.01, "ui_mint", 8, ALONG_Z)
    done("sm_env_depot_fridge.glb")


def kitchenette():
    """Break-room kitchenette: a 1.4 m base cabinet with a worktop (0.92),
    a microwave, a coffee maker with its pot, a kettle and two mugs. Front
    toward -Z. Base centre."""
    clear()
    w, d = 1.4, 0.6
    box("Cabinet", (0, 0.46, 0.02), (w - 0.04, 0.82, d - 0.06), "curtain", 0.02)
    box("Plinth", (0, 0.05, 0.03), (w - 0.08, 0.1, d - 0.1), "housing")
    box("Worktop", (0, 0.9, 0), (w, 0.04, d), "wood", 0.012)
    for i in range(3):
        x = -w / 2 + w / 6 + i * w / 3
        box("Door", (x, 0.48, -d / 2 + 0.03), (w / 3 - 0.03, 0.7, 0.02), "depot_blue", 0.012)
        box("Pull", (x + (0.15 if i < 2 else -0.15), 0.72, -d / 2 + 0.005), (0.02, 0.12, 0.02), "steel_light")
    top = 0.92
    # Microwave on the right.
    mx = 0.4
    box("Microwave", (mx, top + 0.15, 0.06), (0.5, 0.3, 0.38), "curtain", 0.025)
    box("MicroDoor", (mx - 0.06, top + 0.15, -0.135), (0.34, 0.24, 0.015), "housing", 0.01)
    box("MicroWindow", (mx - 0.07, top + 0.15, -0.144), (0.26, 0.16, 0.004), "door_glass")
    box("MicroPanel", (mx + 0.18, top + 0.15, -0.135), (0.1, 0.24, 0.012), "sign_ink", 0.006)
    for i in range(3):
        box("MicroButton", (mx + 0.18, top + 0.22 - i * 0.05, -0.143), (0.05, 0.025, 0.006), "steel_light")
    box("MicroDisplay", (mx + 0.18, top + 0.265, -0.143), (0.06, 0.02, 0.004), "ui_mint")
    # Coffee maker in the middle.
    cx = -0.1
    box("CoffeeBase", (cx, top + 0.02, 0.0), (0.22, 0.04, 0.26), "sign_ink", 0.01)
    box("CoffeeTower", (cx, top + 0.2, 0.08), (0.2, 0.36, 0.12), "sign_ink", 0.02)
    box("CoffeeHead", (cx, top + 0.34, -0.02), (0.2, 0.08, 0.2), "sign_ink", 0.02)
    cyl("CoffeePot", (cx, top + 0.1, -0.03), 0.07, 0.13, "door_glass", 10)
    cyl("CoffeeInPot", (cx, top + 0.08, -0.03), 0.066, 0.08, "wood", 10)
    box("PotHandle", (cx + 0.09, top + 0.11, -0.03), (0.02, 0.1, 0.03), "sign_ink")
    box("CoffeeLight", (cx - 0.06, top + 0.03, -0.131), (0.02, 0.012, 0.004), "signal_red")
    # Kettle on the left.
    kx = -0.5
    cyl("KettleBase", (kx, top + 0.015, 0.02), 0.08, 0.03, "sign_ink", 10)
    cyl("Kettle", (kx, top + 0.12, 0.02), 0.075, 0.18, "danger_red", 10, r2=0.06)
    box("KettleHandle", (kx + 0.08, top + 0.14, 0.02), (0.03, 0.14, 0.03), "sign_ink")
    cyl("KettleSpout", (kx - 0.08, top + 0.17, 0.02), 0.018, 0.08, "danger_red", 6, rot=(0, -0.7, 0))
    ball("KettleLid", (kx, top + 0.21, 0.02), (0.06, 0.02, 0.06), "sign_ink")
    for x, colour in ((-0.3, "ui_yellow"), (-0.24, "paper")):
        cyl("Mug", (x, top + 0.05, -0.18), 0.04, 0.1, colour, 10)
    done("sm_env_depot_kitchenette.glb")


# =============================================================================
# Workshop: scissor lift, compressor, workbench with vise.
# =============================================================================

def scissor_lift():
    """Low-rise vehicle scissor lift, raised to 0.55: two 4.2 m runways at
    x = +-0.85 along Z (vehicles drive on from -Z), scissor arms, ramps,
    a control post. Base centre."""
    clear()
    L, rw, top = 4.2, 0.6, 0.55
    for side in (-1.0, 1.0):
        x = side * 0.85
        box("BaseFrame", (x, 0.04, 0), (rw - 0.1, 0.08, L - 0.4), "sign_ink", 0.015)
        box("Runway", (x, top - 0.06, 0), (rw, 0.12, L), "danger_red", 0.03)
        for k in range(6):
            box("Tread", (x, top + 0.004, -L / 2 + 0.4 + k * 0.68), (rw - 0.08, 0.01, 0.06), "steel_light")
        box("RunwayStripe", (x + side * (rw / 2 + 0.002), top - 0.06, 0), (0.006, 0.05, L - 0.2), "warning")
        ramp = math.hypot(0.9, top)
        box("Ramp", (x, top / 2 + 0.01, -L / 2 - 0.45), (rw, 0.03, ramp), "steel_light", 0.01, pitch=-math.atan2(top, 0.9))
        for dx in (-0.2, 0.2):
            bar("ScissorA", (x + dx, 0.08, -1.3), (x + dx, top - 0.12, 1.3), 0.06, "housing", 0.12)
            bar("ScissorB", (x + dx, top - 0.12, -1.3), (x + dx, 0.08, 1.3), 0.06, "housing", 0.12)
        cyl("Pivot", (x, (top + 0.0) / 2 - 0.02, 0), 0.04, 0.5, "ui_yellow", 8, ALONG_X)
        rod("Ram", (x, 0.1, -0.9), (x, top - 0.2, 0.2), 0.045, "steel_light", 8)
        box("WheelStop", (x, top + 0.04, L / 2 - 0.1), (rw, 0.08, 0.06), "warning", 0.015)
    # Control post at the front left.
    px, pz = -1.55, -1.3
    box("ControlPost", (px, 0.55, pz), (0.28, 1.1, 0.22), "depot_blue", 0.03)
    box("ControlFace", (px, 0.85, pz - 0.112), (0.2, 0.26, 0.004), "sign_ink")
    for y, colour in ((0.92, "go_green"), (0.8, "danger_red")):
        cyl("Button", (px, y, pz - 0.12), 0.03, 0.02, colour, 8, ALONG_Z)
    tube("Hose", [(px + 0.14, 0.1, pz), (-1.0, 0.03, pz + 0.2), (-0.9, 0.03, -0.6)], 0.02, "sign_ink", 6)
    done("sm_env_depot_scissor_lift.glb")


def compressor():
    """Portable air compressor: red horizontal tank on wheels, motor and pump
    on top, belt guard, gauge; handle at +X, front toward -Z. Base centre."""
    clear()
    r, L = 0.19, 0.8
    y = r + 0.08
    cyl("Tank", (0, y, 0), r, L - 0.2, "danger_red", 14, ALONG_X)
    for side in (-1.0, 1.0):
        ball("TankEnd", (side * (L / 2 - 0.1), y, 0), (0.12, r, r), "danger_red")
    for z in (-0.15, 0.15):
        cyl("Wheel", (0.25, 0.1, z * 1.35), 0.1, 0.06, "rubber", 12, ALONG_Z)
        cyl("Hub", (0.25, 0.1, z * 1.35 + (0.032 if z > 0 else -0.032)), 0.045, 0.01, "ui_yellow", 8, ALONG_Z)
    box("FrontFoot", (-0.28, 0.05, 0), (0.06, 0.1, 0.3), "sign_ink", 0.01)
    box("Deck", (0, y + r + 0.01, 0), (0.6, 0.03, 0.3), "sign_ink", 0.008)
    cyl("Motor", (-0.12, y + r + 0.12, 0.02), 0.1, 0.24, "depot_blue", 12, ALONG_X)
    for i in range(3):
        cyl("MotorRib", (-0.2 + i * 0.08, y + r + 0.12, 0.02), 0.104, 0.02, "sign_ink", 12, ALONG_X)
    box("Pump", (0.15, y + r + 0.12, 0.02), (0.14, 0.2, 0.14), "housing", 0.02)
    for i in range(4):
        box("PumpFin", (0.15, y + r + 0.1 + i * 0.035, 0.02), (0.18, 0.012, 0.18), "sign_ink")
    box("BeltGuard", (0.02, y + r + 0.12, 0.11), (0.42, 0.18, 0.04), "ui_yellow", 0.02)
    cyl("Gauge", (0.0, y + r + 0.08, -0.14), 0.045, 0.02, "paper", 12, ALONG_Z)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.045, minor_radius=0.008, major_segments=12, minor_segments=3,
                                     location=G(0.0, y + r + 0.08, -0.152), rotation=ALONG_Z)
    _finish(bpy.context.object, "sign_ink").name = "GaugeRim"
    tube("Handle", [(0.35, y + r - 0.05, -0.14), (0.5, y + r + 0.15, -0.14), (0.5, y + r + 0.15, 0.14), (0.35, y + r - 0.05, 0.14)],
         0.018, "sign_ink", 6)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.12, minor_radius=0.018, major_segments=12, minor_segments=4,
                                     location=G(0.44, y + r - 0.02, 0.0), rotation=ALONG_X)
    _finish(bpy.context.object, "ui_yellow").name = "HoseCoil"
    done("sm_env_depot_compressor.glb")


def workbench_vise():
    """1.6 x 0.7 workbench (top 0.9) with a bench vise at the -X front
    corner, a drawer and a few tools. Front toward -Z. Base centre."""
    clear()
    box("Top", (0, 0.875, 0), (1.6, 0.05, 0.7), "wood", 0.015)
    for x in (-0.74, 0.74):
        for z in (-0.3, 0.3):
            box("Leg", (x, 0.43, z), (0.06, 0.85, 0.06), "depot_blue", 0.01)
        box("LegTie", (x, 0.15, 0), (0.05, 0.05, 0.6), "depot_blue")
    box("Shelf", (0, 0.17, 0), (1.44, 0.03, 0.6), "deck_grey", 0.006)
    box("Drawer", (0.35, 0.78, -0.33), (0.5, 0.12, 0.04), "depot_blue", 0.01)
    box("DrawerPull", (0.35, 0.78, -0.355), (0.16, 0.025, 0.02), "ui_yellow")
    # Vise.
    vx, vz = -0.55, -0.22
    t = 0.9
    box("ViseBase", (vx, t + 0.02, vz), (0.18, 0.04, 0.16), "steel", 0.01)
    box("ViseBody", (vx, t + 0.09, vz), (0.12, 0.1, 0.28), "depot_blue", 0.02)
    box("ViseFixedJaw", (vx, t + 0.16, vz + 0.09), (0.18, 0.08, 0.06), "depot_blue", 0.015)
    box("ViseMovingJaw", (vx, t + 0.16, vz - 0.06), (0.18, 0.08, 0.06), "depot_blue", 0.015)
    for z in (vz + 0.058, vz - 0.028):
        box("JawPlate", (vx, t + 0.17, z), (0.17, 0.05, 0.008), "steel_light")
    rod("ViseScrew", (vx, t + 0.1, vz - 0.09), (vx, t + 0.1, vz - 0.24), 0.014, "steel_light", 6)
    rod("ViseBar", (vx - 0.12, t + 0.1, vz - 0.24), (vx + 0.12, t + 0.1, vz - 0.24), 0.01, "steel_light", 6)
    for x in (vx - 0.12, vx + 0.12):
        ball("ViseBarEnd", (x, t + 0.1, vz - 0.24), (0.018, 0.018, 0.018), "sign_ink")
    # Tools.
    box("Hammer", (0.0, t + 0.012, -0.05), (0.3, 0.024, 0.03), "wood", yaw=0.3)
    box("HammerHead", (0.13, t + 0.025, 0.0), (0.04, 0.05, 0.11), "sign_ink", yaw=0.3)
    box("Wrench", (0.3, t + 0.006, 0.12), (0.26, 0.012, 0.03), "steel_light", yaw=-0.5)
    box("Toolbox", (0.55, t + 0.1, 0.15), (0.4, 0.2, 0.2), "danger_red", 0.02)
    box("ToolboxHandle", (0.55, t + 0.22, 0.15), (0.2, 0.03, 0.03), "sign_ink")
    done("sm_env_depot_workbench_vise.glb")


# =============================================================================
# N-319 iteration 3 (2026-10-01): workshop, office and break-room props.
#
# Same conventions as the N-319.2 kit. Wall boards (tool, paint swatch, cork)
# have their back on z = 0 and their origin on the floor under them, already
# at their mounting height. The hanging hard hat and vest have their origin at
# the wall peg they hang from. The locker door's origin is on its hinge axis
# at the floor; the fridge magnets share the fridge's origin.
# =============================================================================

PALETTE.update({
    "locker_teal": srgb("3f7f8c"),   # the lockers' colour in depot_furnishing.gd
})


def lathe(name, profile, material, segs=12, c=(0.0, 0.0, 0.0)):
    """Revolves a closed Godot (r, y) profile about the vertical axis through
    `c`. Points with r = 0 sit on the axis and close the shape with a fan."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    rings = []
    for r, y in profile:
        if r < 1e-6:
            v = bm.verts.new(G(c[0], c[1] + y, c[2]))
            rings.append([v] * segs)
        else:
            rings.append([bm.verts.new(G(c[0] + math.cos(k * math.tau / segs) * r, c[1] + y,
                                         c[2] + math.sin(k * math.tau / segs) * r)) for k in range(segs)])
    n = len(rings)
    for i in range(n):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for k in range(segs):
            m = (k + 1) % segs
            verts = []
            for v in (r0[k], r0[m], r1[m], r1[k]):
                if v not in verts:
                    verts.append(v)
            if len(verts) >= 3:
                bm.faces.new(verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return _finish(obj, material)


def flat_rect(name, cx, cy, w, h, z, material, ang=0.0):
    """A single quad (2 tris) in the XY plane at depth z, facing -Z, turned by
    `ang` about Z: paint on a board (tool silhouettes, peg holes)."""
    ca, sa = math.cos(ang), math.sin(ang)
    corners = []
    for lx, ly in ((w / 2, -h / 2), (-w / 2, -h / 2), (-w / 2, h / 2), (w / 2, h / 2)):
        corners.append((cx + lx * ca - ly * sa, cy + lx * sa + ly * ca, z))
    return quad(name, corners, [(0, 0), (1, 0), (1, 1), (0, 1)], material)


def place(o, at, pitch=0.0, yaw=0.0, roll=0.0):
    """Moves an object built around the origin to Godot `at`, turned like box()."""
    o.location = G(*at)
    o.rotation_mode = "XYZ"
    o.rotation_euler = (pitch, -roll, yaw)
    return o


def tire_stack():
    """Three worn tyres lying flat, 0.66 across, a little off-centre on each
    other; the top one still on its steel rim. Base centre."""
    clear()
    profile = [(0.2, -0.065), (0.235, -0.1), (0.305, -0.1), (0.33, -0.05), (0.33, 0.05), (0.305, 0.1),
               (0.235, 0.1), (0.2, 0.065)]
    for i, (dx, dz) in enumerate(((0.0, 0.0), (0.035, -0.02), (-0.025, 0.03))):
        lathe("Tire", profile, "fork_dark", 12, (dx, 0.1 + i * 0.2, dz))
    dx, dz = -0.025, 0.03
    lathe("Rim", [(0.0, 0.56), (0.12, 0.56), (0.205, 0.545), (0.205, 0.455), (0.0, 0.455)], "steel_light", 12,
          (dx, 0.0, dz))
    for k in range(5):
        a = k * math.tau / 5
        cyl("LugNut", (dx + math.cos(a) * 0.06, 0.567, dz + math.sin(a) * 0.06), 0.012, 0.016, "steel", 6)
    done("sm_env_depot_tire_stack.glb")


def tool_board():
    """1.2 x 0.8 m pegboard over the workbench (1.0 .. 1.8), each tool on its
    pegs in front of its painted silhouette; one silhouette is empty (someone
    has the wrench). Wall piece, front toward -Z; origin on the floor at the wall."""
    clear()
    y0, w, h = 1.0, 1.2, 0.8
    box("Board", (0, y0 + h / 2, -0.01), (w, h, 0.02), "logo_cardboard", 0.006)
    for x in (-w / 2 + 0.02, w / 2 - 0.02):
        box("BoardEdge", (x, y0 + h / 2, -0.012), (0.04, h, 0.026), "depot_blue")
    for y in (y0 + 0.02, y0 + h - 0.02):
        box("BoardEdge", (0, y, -0.012), (w, 0.04, 0.026), "depot_blue")
    zh, zs, zt = -0.0205, -0.021, -0.04
    # Peg holes: a sparse 10 cm grid, skipping where the tools hang.
    tools = []

    def tool(parts, pegs, present=True):
        tools.append(parts)
        for cx, cy, tw, th, colour, ang in parts:
            flat_rect("Silhouette", cx, cy, tw + 0.024, th + 0.024, zs, "sign_ink", ang)
            if present:
                box("Tool", (cx, cy, zt), (tw, th, 0.02), colour, roll=ang)
        if present:
            for px, py in pegs:
                bar("Peg", (px, py, -0.02), (px, py + 0.01, -0.06), 0.012, "steel")

    def covered(x, y):
        for parts in tools:
            for cx, cy, tw, th, _c, _a in parts:
                if abs(x - cx) < tw / 2 + 0.05 and abs(y - cy) < th / 2 + 0.05:
                    return True
        return False

    yc = y0 + h / 2
    # Hammer.
    tool([(-0.44, yc - 0.05, 0.035, 0.36, "wood", 0.0), (-0.44, yc + 0.15, 0.16, 0.05, "steel_light", 0.0)],
         [(-0.49, yc + 0.11), (-0.39, yc + 0.11)])
    # Two wrenches, and the empty place of a third.
    for x, length, present in ((-0.27, 0.3, True), (-0.2, 0.25, True), (-0.13, 0.2, False)):
        tool([(x, yc + 0.02, 0.03, length, "steel_light", 0.0), (x, yc + 0.02 + length / 2, 0.06, 0.05, "steel_light", 0.0)],
             [(x, yc + 0.02 + length / 2 - 0.05)], present)
    # Screwdrivers.
    for x, colour in ((0.0, "ui_yellow"), (0.07, "danger_red")):
        tool([(x, yc + 0.11, 0.035, 0.11, colour, 0.0), (x, yc - 0.02, 0.01, 0.16, "steel_light", 0.0)],
             [(x - 0.03, yc + 0.06), (x + 0.03, yc + 0.06)])
    # Pliers.
    tool([(0.21, yc + 0.03, 0.025, 0.26, "danger_red", 0.16), (0.25, yc + 0.03, 0.025, 0.26, "danger_red", -0.16),
          (0.23, yc + 0.17, 0.05, 0.06, "steel_light", 0.0)], [(0.23, yc + 0.11)])
    # Hand saw.
    tool([(0.44, yc - 0.06, 0.13, 0.28, "steel_light", 0.0), (0.44, yc + 0.14, 0.13, 0.1, "wood", 0.0)],
         [(0.44, yc + 0.2)])
    box("SawTeeth", (0.505, yc - 0.06, -0.051), (0.012, 0.27, 0.003), "sign_ink")
    box("SawGrip", (0.44, yc + 0.14, -0.051), (0.07, 0.04, 0.003), "sign_ink")
    # Tape measure low on the left.
    tool([(-0.3, y0 + 0.12, 0.08, 0.08, "ui_yellow", 0.0)], [(-0.3, y0 + 0.18)])
    for i in range(11):
        for j in range(7):
            x, y = -0.5 + i * 0.1, y0 + 0.1 + j * 0.1
            if (i + j) % 2 == 0 and not covered(x, y):
                flat_rect("PegHole", x, y, 0.014, 0.014, zh, "sign_ink")
    done("sm_env_depot_tool_board.glb")


def paint_swatch_board():
    """1.2 x 0.6 m framed board (1.2 .. 1.8) with six truck paint swatches:
    chip, a strip with the paint code and a tiny van; `Header` is a blank
    band the game may write on. Wall piece, front toward -Z; origin on the
    floor at the wall."""
    clear()
    y0, w, h = 1.2, 1.2, 0.6
    box("Backing", (0, y0 + h / 2, -0.01), (w, h, 0.02), "paper", 0.005)
    for x in (-w / 2 + 0.025, w / 2 - 0.025):
        box("Frame", (x, y0 + h / 2, -0.02), (0.05, h, 0.04), "housing", 0.01)
    for y in (y0 + 0.025, y0 + h - 0.025):
        box("Frame", (0, y, -0.02), (w, 0.05, 0.04), "housing", 0.01)
    box("Header", (0, y0 + h - 0.1, -0.022), (w - 0.16, 0.07, 0.004), "sign_ink").name = "Header"
    colours = ("depot_blue", "danger_red", "go_green", "ui_yellow", "depot_orange", "ui_mint")
    for i, colour in enumerate(colours):
        x = -0.45 + i * 0.18
        box("SwatchCard", (x, y0 + 0.25, -0.025), (0.15, 0.34, 0.01), "curtain")
        box("Swatch%d" % i, (x, y0 + 0.3, -0.032), (0.13, 0.2, 0.006), colour).name = "Swatch%d" % i
        box("SwatchCode", (x, y0 + 0.14, -0.031), (0.09, 0.018, 0.003), "sign_ink")
        box("VanBody", (x - 0.01, y0 + 0.31, -0.036), (0.07, 0.04, 0.003), "curtain")
        box("VanCab", (x + 0.035, y0 + 0.302, -0.036), (0.025, 0.025, 0.003), "curtain")
        cyl("Pin", (x, y0 + 0.405, -0.035), 0.009, 0.012, "steel", 6, ALONG_Z)
    done("sm_env_depot_paint_swatch_board.glb")


def desk_lamp():
    """Articulated desk lamp, 0.42 tall, head over the desk toward -Z.
    `LampGlow` (emissive `lamp_disc`) is the bulb disc under the shade, its
    own node so the game can switch it. Base centre."""
    from mathutils import Euler
    clear()
    cyl("Base", (0, 0.012, 0.05), 0.08, 0.024, "depot_blue", 12)
    cyl("Knuckle", (0, 0.04, 0.05), 0.02, 0.04, "sign_ink", 8, ALONG_X)
    rod("ArmLower", (0, 0.04, 0.05), (0, 0.3, 0.1), 0.01, "depot_blue", 6)
    cyl("Elbow", (0, 0.3, 0.1), 0.018, 0.04, "sign_ink", 8, ALONG_X)
    rod("ArmUpper", (0, 0.3, 0.1), (0, 0.35, -0.13), 0.009, "depot_blue", 6)
    rod("Spring", (0, 0.07, 0.07), (0, 0.27, 0.11), 0.004, "steel_light", 4)
    tilt = 0.55
    head_at = (0, 0.33, -0.17)
    head = cyl("Shade", (0, 0, 0), 0.07, 0.11, "depot_blue", 12, r2=0.032)
    place(head, head_at, pitch=tilt)
    cap = cyl("ShadeCap", (0, 0, 0), 0.034, 0.03, "sign_ink", 8)
    place(cap, head_at, pitch=tilt)
    cap.location = Vector(G(*head_at)) + Euler((tilt, 0, 0)).to_matrix() @ Vector(G(0, 0.06, 0))
    glow = cyl("LampGlow", (0, 0, 0), 0.06, 0.006, "lamp_disc", 12)
    place(glow, head_at, pitch=tilt)
    glow.location = Vector(G(*head_at)) + Euler((tilt, 0, 0)).to_matrix() @ Vector(G(0, -0.05, 0))
    glow.name = "LampGlow"
    done("sm_env_depot_desk_lamp.glb")


def cork_board():
    """0.9 x 0.6 m cork board (1.2 .. 1.8) in a wooden frame. `CorkSurface` is
    one quad mapped 0..1 over the whole cork (u to the right, v up as seen
    from the front) so the game can put a texture with the notes on it. Wall
    piece, front toward -Z; origin on the floor at the wall."""
    clear()
    y0, w, h, f = 1.2, 0.9, 0.6, 0.04
    box("Backing", (0, y0 + h / 2, -0.008), (w, h, 0.016), "housing")
    for x in (-w / 2 + f / 2, w / 2 - f / 2):
        box("Frame", (x, y0 + h / 2, -0.016), (f, h, 0.032), "wood", 0.008)
    for y in (y0 + f / 2, y0 + h - f / 2):
        box("Frame", (0, y, -0.016), (w, f, 0.032), "wood", 0.008)
    x0, x1, ya, yb, z = -w / 2 + f, w / 2 - f, y0 + f, y0 + h - f, -0.0165
    cork = quad("CorkSurface", [(x1, ya, z), (x0, ya, z), (x0, yb, z), (x1, yb, z)],
                [(0, 0), (1, 0), (1, 1), (0, 1)], "tape_brown")
    cork.name = "CorkSurface"
    done("sm_env_depot_cork_board.glb")


def mug():
    """Coffee mug, 9.5 cm, handle toward +X, `Coffee` inside. Base centre."""
    clear()
    lathe("Mug", [(0.0, 0.0), (0.038, 0.0), (0.042, 0.008), (0.042, 0.095), (0.036, 0.095), (0.035, 0.012),
                  (0.0, 0.012)], "danger_red", 12)
    cyl("Coffee", (0, 0.078, 0), 0.0352, 0.004, "wood", 12).name = "Coffee"
    tube("Handle", [(0.04, 0.078, 0), (0.07, 0.074, 0), (0.073, 0.03, 0), (0.04, 0.026, 0)], 0.008, "danger_red", 5)
    cyl("Stripe", (0, 0.064, 0), 0.0425, 0.012, "paper", 12)
    done("sm_env_depot_mug.glb")


def service_bell():
    """Counter service bell, 7 cm: dark base, chrome dome, plunger. Base centre."""
    clear()
    lathe("BellBase", [(0.0, 0.0), (0.055, 0.0), (0.058, 0.008), (0.055, 0.016), (0.0, 0.016)], "sign_ink", 12)
    lathe("Dome", [(0.0, 0.016), (0.048, 0.016), (0.046, 0.034), (0.034, 0.052), (0.016, 0.06), (0.0, 0.062)],
          "steel_light", 12)
    cyl("Plunger", (0, 0.068, 0), 0.005, 0.014, "steel", 6)
    ball("Button", (0, 0.076, 0), (0.011, 0.005, 0.011), "sign_ink")
    done("sm_env_depot_service_bell.glb")


def locker_door_open():
    """One loose locker door (the lockers in depot_furnishing.gd: 0.58 wide,
    1.95 tall, front at the body's face) to swing open about 25 degrees.
    Origin on the hinge axis at the floor; the door runs from the hinge
    toward +X (0 .. 0.54), outside toward -Z, 2 cm thick behind the origin's
    plane (z -0.02 .. 0). Mirror it in X for a right-hand hinge. The inside
    (+Z) has the folded rim, a coat hook and a photo."""
    clear()
    w, ya, yb, t = 0.54, 0.1, 1.9, 0.02
    hgt = yb - ya
    box("Door", (w / 2, ya + hgt / 2, -t / 2), (w, hgt, t), "locker_teal", 0.004)
    for vent in range(3):
        box("Vent", (w / 2, 1.7 - vent * 0.05, -t - 0.002), (0.3, 0.02, 0.004), "sign_ink")
    box("Handle", (0.45, 1.05, -t - 0.015), (0.03, 0.14, 0.03), "fan_blade", 0.006)
    box("NameCard", (w / 2, 1.45, -t - 0.002), (0.2, 0.07, 0.004), "paper")
    box("Lock", (0.45, 1.16, -t - 0.004), (0.025, 0.025, 0.008), "steel")
    # Inside: the folded rim (open toward +Z), a coat hook, a photo.
    for x in (0.012, w - 0.012):
        box("InnerRim", (x, ya + hgt / 2, 0.012), (0.024, hgt - 0.02, 0.024), "locker_teal")
    for y in (ya + 0.012, yb - 0.012):
        box("InnerRim", (w / 2, y, 0.012), (w - 0.05, 0.024, 0.024), "locker_teal")
    box("Stiffener", (w / 2, ya + hgt / 2, 0.008), (0.06, hgt - 0.06, 0.016), "locker_teal")
    tube("CoatHook", [(w / 2 + 0.12, 1.6, 0.0), (w / 2 + 0.12, 1.6, 0.05), (w / 2 + 0.12, 1.64, 0.06)], 0.006,
         "fan_blade", 5)
    box("Photo", (w / 2 - 0.12, 1.5, 0.0015), (0.1, 0.13, 0.003), "paper", roll=0.08)
    box("PhotoImage", (w / 2 - 0.12, 1.51, 0.0035), (0.08, 0.09, 0.002), "foam_blue", roll=0.08)
    for y in (0.4, 1.6):
        cyl("Hinge", (0.0, y, -t / 2), 0.008, 0.08, "steel", 6)
    done("sm_env_depot_locker_door_open.glb")


def _hat(at, pitch):
    """A hard hat around its own centre (rim plane), placed at `at`."""
    parts = [lathe("Hat", [(0.0, 0.15), (0.075, 0.143), (0.12, 0.11), (0.142, 0.05), (0.148, 0.0), (0.0, 0.0)],
                   "ui_yellow", 12),
             lathe("Brim", [(0.13, 0.012), (0.175, 0.0), (0.175, -0.012), (0.13, -0.006)], "ui_yellow", 12),
             box("Ridge", (0, 0.135, 0.0), (0.035, 0.04, 0.16), "ui_yellow", 0.01),
             box("Peak", (0, 0.0, -0.17), (0.2, 0.012, 0.07), "ui_yellow"),
             cyl("Harness", (0, -0.002, 0), 0.14, 0.004, "sign_ink", 12),
             box("HatSticker", (0.0, 0.07, -0.135), (0.05, 0.035, 0.012), "depot_blue", pitch=-0.4)]
    from mathutils import Euler, Matrix
    m = Matrix.Translation(G(*at)) @ Euler((pitch, 0, 0)).to_matrix().to_4x4()
    bpy.context.view_layer.update()
    for o in parts:
        o.rotation_mode = "XYZ"
        o.matrix_world = m @ o.matrix_world
    return parts


def hard_hat():
    """Yellow hard hat hanging on a wall peg, tipped forward a little.
    Origin at the peg on the wall (the hat hangs from it). Back on z = 0."""
    clear()
    cyl("PegPlate", (0, 0, -0.005), 0.025, 0.01, "steel", 8, ALONG_Z)
    rod("Peg", (0, 0, -0.01), (0, 0.03, -0.17), 0.01, "steel", 6)
    _hat((0, -0.06, -0.16), -0.25)
    done("sm_env_depot_hard_hat.glb")


def safety_vest():
    """Orange hi-vis vest on a hanger from a wall peg, two reflective bands
    and shoulder strips. Origin at the peg on the wall; back on z = 0."""
    clear()
    cyl("PegPlate", (0, 0, -0.005), 0.025, 0.01, "steel", 8, ALONG_Z)
    rod("Peg", (0, 0, -0.01), (0, 0.02, -0.09), 0.01, "steel", 6)
    zf, zb = -0.1, -0.06
    tube("HangerHook", [(0, -0.07, -0.08), (0, 0.025, -0.08), (0, 0.04, -0.06), (0, 0.025, -0.045)], 0.004,
         "steel_light", 4)
    tube("Hanger", [(-0.2, -0.14, -0.08), (0, -0.07, -0.08), (0.2, -0.14, -0.08)], 0.007, "wood", 5)
    outline = [(-0.07, -0.08), (-0.15, -0.1), (-0.2, -0.17), (-0.24, -0.3), (-0.24, -0.72), (0.24, -0.72),
               (0.24, -0.3), (0.2, -0.17), (0.15, -0.1), (0.07, -0.08), (0.0, -0.3)]
    panel("Vest", outline, zf, zb, "depot_orange")
    for y in (-0.48, -0.62):
        box("ReflectiveBand", (0, y, (zf + zb) / 2), (0.49, 0.05, 0.046), "curtain")
    for x in (-0.11, 0.11):
        box("ReflectiveStrap", (x, -0.27, zf - 0.002), (0.045, 0.3, 0.004), "curtain", roll=-0.12 if x < 0 else 0.12)
    box("Zip", (0, -0.51, zf - 0.003), (0.008, 0.42, 0.004), "sign_ink")
    done("sm_env_depot_safety_vest.glb")


def fridge_magnets():
    """Five fridge magnets for sm_env_depot_fridge.glb, in the fridge's own
    space (put this at the fridge's transform): a star, a heart, a round one
    holding a photo, a parcel and a little van, clear of the handles and the
    fridge's own notes."""
    clear()
    z0, z1 = -0.335, -0.345
    star = []
    for k in range(10):
        a = math.pi / 2 + k * math.pi / 5
        r = 0.032 if k % 2 == 0 else 0.014
        star.append((-0.1 + math.cos(a) * r, 1.56 + math.sin(a) * r))
    panel("MagnetStar", star, z0, z1, "ui_yellow")
    heart = [(0.0, -0.03), (0.03, 0.0), (0.032, 0.016), (0.022, 0.026), (0.01, 0.024), (0.0, 0.014),
             (-0.01, 0.024), (-0.022, 0.026), (-0.032, 0.016), (-0.03, 0.0)]
    panel("MagnetHeart", [(0.05 + x, 1.05 + y) for x, y in heart], z0, z1, "danger_red")
    box("Photo", (0.17, 1.41, -0.3365), (0.09, 0.11, 0.003), "paper", roll=-0.07)
    box("PhotoImage", (0.17, 1.415, -0.3385), (0.075, 0.08, 0.002), "foam_blue", roll=-0.07)
    cyl("MagnetRound", (0.17, 1.46, -0.341), 0.016, 0.012, "go_green", 8, ALONG_Z)
    box("MagnetParcel", (-0.05, 0.62, -0.341), (0.05, 0.04, 0.012), "logo_cardboard")
    box("MagnetParcelTape", (-0.05, 0.62, -0.348), (0.012, 0.04, 0.003), "tape_brown")
    box("MagnetVan", (0.12, 0.5, -0.341), (0.06, 0.03, 0.012), "depot_blue")
    box("MagnetVanCab", (0.158, 0.495, -0.341), (0.02, 0.022, 0.012), "depot_blue")
    for x in (0.1, 0.145):
        cyl("MagnetVanWheel", (x, 0.483, -0.348), 0.007, 0.004, "sign_ink", 6, ALONG_Z)
    done("sm_env_depot_fridge_magnets.glb")


_special_materials()


BUILDERS = {
    "door": [door_slat, door_slat_window, door_bottom_bar, door_frame],
    "rack": [rack_frame, rack_beam_level, shelf_frame, shelf_deck],
    "forklift": [forklift_body, forklift_carriage],
    "conveyor": [conveyor],
    "lamps": [high_bay_lamp, tube_fixture],
    "fan": [ceiling_fan],
    "clock": [wall_clock, clock_hand_hour, clock_hand_minute],
    "supplies": [supply_padding, supply_insurance],
    "shop": [shop_tape_roll, shop_foam_blue, shop_foam_orange],
    "staging": [packing_table, pallet_jack],
    # N-319.2 kit.
    "ceiling": [bay_lamp_bell, tube_linear, duct_straight, duct_elbow, cable_tray],
    "dispatch": [dispatch_desk],
    "bay": [bollard, column_guard, wheel_chock, wheel_stop, door_light],
    "logistics": [roll_cage, roll_cage_loaded, flat_cardboard_stack, pallet_wrapped, sorting_table, rolling_ladder],
    "office": [stair, railing_segment, railing_post, office_blind, window_frame, window_mullion],
    "cage": [cage_panel, cage_window],
    "safety": [extinguisher, extinguisher_cabinet, electrical_panel, first_aid, time_clock, recycle_station,
               water_dispenser, wet_floor_cone, wet_floor_sign, pictogram_sign],
    "breakroom": [fridge, kitchenette],
    "workshop": [scissor_lift, compressor, workbench_vise],
    # N-319 iteration 3.
    "iter3": [tire_stack, tool_board, paint_swatch_board, desk_lamp, cork_board, mug, service_bell,
              locker_door_open, hard_hat, safety_vest, fridge_magnets],
}
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for group, builders in BUILDERS.items():
    if not ONLY or group in ONLY:
        for builder in builders:
            builder()

print("DEPOT_REPORT")
for name, tris in REPORT:
    print("  %-42s %6d tris" % (name, tris))
