"""Roadside service station for Take My Package (N-110.1, 2026-10-01).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_service_station.py

Replaces the DepotKit boxes (and the three borrowed depot props) that
`scripts/gameplay/route/service_stop.gd` built the station from, in the same
chunky low-poly line as the depot kit (`build_depot_props.py`): flat palette
colours, soft bevels, no realistic textures. The script keeps every collider,
the counter Area3D, the glowing strips (canopy light, pump screens, totem
bands) and the Label3D texts; these GLBs are only what you see, folded into
the station's batches with `DepotKit.model()`.

Authored in GODOT coordinates (x right, y up, z toward the viewer) with G()/GS()
swapping to Blender's Z-up; the glTF exporter turns it back. Metres. Each piece
is in the local space of the ServiceStop part that places it (the road runs
toward -Z, the lay-by is toward -X), origin at the centre of its base on the
ground. Pieces, in `models/environment/service/`:

  sm_env_service_canopy.glb   Forecourt (part origin): concrete island slab
                              5.6 x 10.4, two pump islands with curbs and
                              bollards, four columns and the flat canopy
                              (underside at y 3.86, top 4.4), extinguisher on
                              a column. The light panel under it stays in code.
  sm_env_service_pump.glb     One fuel pump, 0.6 x 1.65 x 0.85, its face (and
                              the display the code lights) toward -X, hose
                              and nozzle on the +Z side.
  sm_env_service_kiosk.glb    Kiosk 4.6 x 8.6: walls from y -0.6 (so a slope
                              never opens a gap) to 3.0, flat roof with a sign
                              fascia over the -X front (the Label3D goes on
                              it), serving window with the striped awning and
                              the wooden counter (top at y 1.08) at z -1.2,
                              door at z 3.0, water tank on the roof, gas
                              bottles and AC unit at the back (+X).
  sm_env_service_totem.glb    Price pole: plinth, 7.6 m post, lit board frame
                              2.7 x 1.8 (centre y 6.5, face toward +Z, the
                              titles are Label3D) and a price panel under it.
  sm_env_service_crates.glb   Pallet with wooden crates and oil cans, 1.2 x 1.2,
                              behind the kiosk (where N-311's cosmetic hides).
  sm_env_service_drum.glb     Oil drum, 0.6 wide, 0.9 tall.

Pass names after "--" to rebuild only some of them:
    blender --background --factory-startup --python build_service_station.py -- pump kiosk
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
    # The colours service_stop.gd already used, so the station keeps its look
    # (teal and warning yellow brand, red pumps, cream kiosk), plus a few
    # shared with the depot kit (same names, same batches in Godot).
    "svc_teal": srgb("2f6f6a"), "svc_teal_dark": srgb("234f4c"),
    "svc_red": srgb("c8553d"), "svc_cream": srgb("ece7d8"),
    "svc_wall": srgb("e0d3b0"), "svc_plinth": srgb("b7a988"),
    "svc_concrete": srgb("a9b0aa"), "svc_curb": srgb("8c9791"),
    "svc_steel": srgb("c9d1cc"), "svc_dark": srgb("3b4a4f"),
    "svc_board": srgb("263b3e"), "svc_counter": srgb("9a6b3f"),
    "svc_counter_top": srgb("c49a66"), "svc_crate": srgb("b58a55"),
    "svc_hose": srgb("2b3033"), "svc_tank": srgb("5d7f8a"),
    "svc_gas": srgb("e8772e"), "svc_drum": srgb("2f5d8a"),
    "warning": srgb("e7be51"), "door_glass": srgb("2a4550"),
    "danger_red": srgb("d8322b"), "sign_ink": srgb("1e2235"),
    "paper": srgb("fff6e6"), "wood": srgb("b08a5a"),
})

OUT = os.path.join(ROOT, "models", "environment", "service")
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


def box(name, c, s, material, bevel=0.0, yaw=0.0, roll=0.0):
    """Box centred at Godot `c`, size `s`; yaw about Y, roll about Z (Godot)."""
    bpy.ops.mesh.primitive_cube_add(location=G(*c))
    o = bpy.context.object
    o.name = name
    o.scale = tuple(v / 2.0 for v in GS(*s))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new("Round", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "NONE"
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.rotation_euler = (0.0, -roll, yaw)
    return _finish(o, material)


def cyl(name, c, r1, depth, material, verts=10, rot=(0, 0, 0), r2=None):
    """Cylinder (cone if r2 given) centred at Godot `c`; vertical unless rot says otherwise."""
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r1 if r2 is None else r2,
                                    depth=depth, location=G(*c))
    o = bpy.context.object
    o.name = name
    o.rotation_euler = rot
    return _finish(o, material)


def ball(name, c, size, material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=1, location=G(*c))
    o = bpy.context.object
    o.name = name
    o.scale = GS(*size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(o, material)


def tube(name, pts, radius, material, sides=6):
    """A round tube through Godot points (hoses, pipes), open-ended."""
    P = [Vector(G(*p)) for p in pts]
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    rings = []
    n = len(P)
    for i in range(n):
        t = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized()
        a = t.cross(Vector((0, 0, 1)))
        if a.length < 1e-3:
            a = t.cross(Vector((1, 0, 0)))
        a.normalize()
        b = t.cross(a)
        rings.append([bm.verts.new(P[i] + (a * math.cos(k * math.tau / sides) + b * math.sin(k * math.tau / sides))
                                   * radius) for k in range(sides)])
    for i in range(n - 1):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new([rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return _finish(obj, material)


def side_panel(name, points, z0, z1, material):
    """A flat outline in Godot's XY plane (points are (x, y)), from Godot z0 to z1."""
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


def bollard(x, z, height=0.9):
    cyl("Bollard", (x, height * 0.5, z), 0.1, height, "warning", 8)
    cyl("BollardBand", (x, height - 0.18, z), 0.105, 0.12, "sign_ink", 8)
    cyl("BollardCap", (x, height + 0.03, z), 0.1, 0.06, "warning", 8, r2=0.06)


# =============================================================================
# Forecourt: slab, islands, columns, canopy.
# =============================================================================

def canopy():
    clear()
    # The slab sets the forecourt off from the yard (0.06 above the ground,
    # its skirt 0.64 down for slopes), with a curb lip around it.
    box("Slab", (0, -0.29, 0), (5.6, 0.7, 10.4), "svc_concrete", 0.04)
    for z in (-5.15, 5.15):
        box("SlabCurb", (0, 0.05, z), (5.6, 0.12, 0.14), "svc_curb", 0.02)
    # Painted lane arrows on the slab, toward -Z (the way the road runs).
    for x in (-1.6,):
        pts = [(-0.18, 0.0), (0.18, 0.0), (0.18, -0.8), (0.42, -0.8), (0.0, -1.35), (-0.42, -0.8), (-0.18, -0.8)]
        mesh = bpy.data.meshes.new("LaneArrow")
        obj = bpy.data.objects.new("LaneArrow", mesh)
        bpy.context.collection.objects.link(obj)
        bm = bmesh.new()
        bm.faces.new([bm.verts.new(G(x + px, 0.065, pz + 0.7)) for px, pz in pts])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        for f in bm.faces:
            if f.normal.z < 0:
                f.normal_flip()
        bm.to_mesh(mesh)
        bm.free()
        _finish(obj, "svc_cream")
    # Two pump islands under the canopy line, the pumps stand on them.
    for z in (-2.8, 2.8):
        box("Island", (-1.6, 0.13, z), (1.1, 0.16, 2.0), "svc_curb", 0.05)
        box("IslandTop", (-1.6, 0.215, z), (1.0, 0.02, 1.9), "svc_concrete")
        for zz in (z - 0.85, z + 0.85):
            bollard(-1.6, zz, 0.75)
    # Columns, each on a small base, with a yellow guard band at bumper height.
    for x in (-2.3, 2.3):
        for z in (-4.4, 4.4):
            box("ColumnBase", (x, 0.15, z), (0.5, 0.3, 0.5), "svc_curb", 0.04)
            box("Column", (x, 2.1, z), (0.3, 3.8, 0.3), "svc_steel", 0.03)
            box("ColumnGuard", (x, 0.65, z), (0.34, 0.6, 0.34), "warning", 0.02)
            box("ColumnGuardBand", (x, 0.65, z), (0.35, 0.14, 0.35), "sign_ink")
    # The canopy: a deep teal fascia with a yellow stripe, light grey soffit.
    box("CanopySoffit", (0, 3.92, 0), (5.3, 0.12, 10.1), "svc_steel")
    box("CanopyFascia", (0, 4.24, 0), (5.6, 0.52, 10.4), "svc_teal", 0.05)
    box("CanopyStripe", (0, 4.05, 0), (5.66, 0.14, 10.46), "warning", 0.02)
    box("CanopyCap", (0, 4.53, 0), (5.5, 0.06, 10.3), "svc_teal_dark")
    # Brand chips at the canopy ends, facing the road ends (+Z / -Z).
    for z in (-5.24, 5.24):
        box("CanopyBadge", (-1.6, 4.27, z), (1.4, 0.34, 0.04), "svc_cream", 0.01)
        box("CanopyBadgeDot", (-2.15, 4.27, z * 1.004), (0.22, 0.22, 0.04), "svc_red")
    # Extinguisher on its bracket, on the column nearest the counter.
    x, z = -2.3, -4.4
    box("ExtBracket", (x, 1.05, z + 0.17), (0.18, 0.06, 0.04), "sign_ink")
    cyl("Extinguisher", (x, 0.86, z + 0.29), 0.09, 0.5, "danger_red", 10)
    cyl("ExtTop", (x, 1.15, z + 0.29), 0.09, 0.08, "danger_red", 10, r2=0.04)
    box("ExtHandle", (x, 1.21, z + 0.29), (0.04, 0.04, 0.14), "sign_ink")
    tube("ExtHose", [(x + 0.02, 1.17, z + 0.36), (x + 0.1, 1.0, z + 0.4), (x + 0.07, 0.75, z + 0.38)], 0.015, "sign_ink", 5)
    done("sm_env_service_canopy.glb")


def pump():
    clear()
    # Face toward -X: the display (lit in code at x -0.33) and the price strip.
    box("Plinth", (0, 0.06, 0), (0.7, 0.12, 0.95), "svc_curb", 0.03)
    box("Body", (0, 0.8, 0), (0.6, 1.36, 0.85), "svc_red", 0.05)
    box("BodyBand", (0, 0.45, 0), (0.62, 0.12, 0.87), "svc_cream", 0.02)
    box("Head", (0, 1.58, 0), (0.68, 0.18, 0.93), "svc_cream", 0.04)
    box("HeadBrand", (-0.345, 1.58, 0), (0.02, 0.1, 0.5), "svc_teal")
    # Display bezel and the keypad under it; the glowing screen is the code's.
    box("DisplayBezel", (-0.31, 1.1, 0), (0.02, 0.42, 0.6), "svc_dark", 0.01)
    box("Keypad", (-0.31, 0.78, 0.0), (0.02, 0.16, 0.3), "svc_steel")
    for i in range(3):
        box("Key", (-0.325, 0.78, -0.09 + i * 0.09), (0.02, 0.07, 0.06), "sign_ink")
    # Nozzle holster on the +Z side and its hose drooping to the island.
    box("Holster", (-0.05, 1.05, 0.46), (0.18, 0.24, 0.08), "svc_dark", 0.02)
    box("Nozzle", (-0.05, 1.1, 0.53), (0.08, 0.22, 0.07), "sign_ink", 0.02, roll=0.2)
    tube("Hose", [(-0.05, 0.98, 0.54), (-0.12, 0.7, 0.62), (-0.18, 0.4, 0.6), (-0.1, 0.2, 0.5),
                  (0.08, 0.3, 0.46), (0.2, 0.9, 0.44)], 0.025, "svc_hose", 6)
    done("sm_env_service_pump.glb")


# =============================================================================
# Kiosk.
# =============================================================================

def kiosk():
    clear()
    W, D, H = 4.6, 8.6, 3.0
    fx = -W / 2.0  # the front, facing the lay-by
    box("Walls", (0, (H - 0.6) / 2.0, 0), (W, H + 0.6, D), "svc_wall", 0.03)
    box("Plinth", (0, 0.2, 0), (W + 0.06, 0.4, D + 0.06), "svc_plinth")
    # Corner trims break the cream block into a building.
    for x in (-W / 2, W / 2):
        for z in (-D / 2, D / 2):
            box("CornerTrim", (x, H / 2, z), (0.16, H, 0.16), "svc_teal", 0.02)
    # Flat roof with overhang, a parapet lip, and the fascia that carries the sign.
    box("Roof", (0, H + 0.12, 0), (W + 0.6, 0.24, D + 0.6), "svc_teal", 0.04)
    box("RoofDeck", (0.05, H + 0.25, 0), (W + 0.3, 0.04, D + 0.3), "svc_curb")
    box("SignFascia", (fx - 0.2, H + 0.55, 0), (0.2, 0.7, 6.2), "svc_board", 0.03)
    box("SignFasciaTop", (fx - 0.2, H + 0.93, 0), (0.24, 0.08, 6.3), "warning", 0.01)
    box("SignFasciaFoot", (fx - 0.2, H + 0.18, 0), (0.24, 0.06, 6.3), "warning", 0.01)
    for z in (-2.6, 2.6):
        box("SignStay", (fx + 0.1, H + 0.55, z), (0.5, 0.06, 0.06), "svc_steel")
    # Water tank on legs over the back half: the rural silhouette from the road.
    tx, tz = 0.9, 2.2
    for dx in (-0.45, 0.45):
        for dz in (-0.45, 0.45):
            box("TankLeg", (tx + dx, H + 0.6, tz + dz), (0.08, 0.7, 0.08), "svc_steel")
    box("TankDeck", (tx, H + 0.97, tz), (1.1, 0.06, 1.1), "svc_steel")
    cyl("Tank", (tx, H + 1.5, tz), 0.55, 1.0, "svc_tank", 12)
    cyl("TankLid", (tx, H + 2.06, tz), 0.55, 0.14, "svc_tank", 12, r2=0.2)
    # Serving window: dark frame, glass, a mullion; shelves of goods inside.
    wz, wy = -1.2, 1.75
    box("WindowFrame", (fx - 0.03, wy, wz), (0.08, 1.36, 3.16), "svc_dark", 0.02)
    box("WindowGlass", (fx - 0.06, wy, wz), (0.04, 1.2, 3.0), "door_glass")
    for z in (wz - 0.5, wz + 0.5):
        box("WindowMullion", (fx - 0.09, wy, z), (0.04, 1.2, 0.06), "svc_dark")
    for y in (1.45, 1.95):
        box("ShelfLine", (fx - 0.085, y, wz), (0.02, 0.04, 2.9), "svc_steel")
        for i in range(7):
            colour = ("warning", "svc_red", "svc_cream", "svc_teal")[i % 4]
            box("ShelfGood", (fx - 0.09, y + 0.12, wz - 1.2 + i * 0.4), (0.02, 0.18 + 0.04 * (i % 2), 0.22), colour)
    # Striped awning: alternating slats sloping out from the wall, a scalloped valance.
    rise, reach = 0.4, 1.2
    angle = math.atan2(rise, reach)
    length = math.hypot(rise, reach)
    stripes = 8
    span = 3.6
    for i in range(stripes):
        z = wz - span / 2 + span / stripes * (i + 0.5)
        colour = "svc_red" if i % 2 == 0 else "svc_cream"
        box("Awning", (fx - reach / 2, 2.62 - rise / 2, z), (length, 0.05, span / stripes), colour, roll=angle)
        side_panel("AwningFlap", [(fx - reach - 0.02, 2.42), (fx - reach - 0.02, 2.2),
                                  (fx - reach + 0.02, 2.2), (fx - reach + 0.02, 2.42)],
                   z - span / stripes / 2, z + span / stripes / 2, colour)
    for z in (wz - span / 2, wz + span / 2):
        side_panel("AwningCheek", [(fx, 2.62), (fx - reach, 2.22), (fx - reach, 2.2), (fx, 2.2)],
                   z - 0.02, z + 0.02, "svc_red")
    # The counter under the window: wooden front, a lighter top, goods and the bell.
    cx = fx - 0.45
    box("CounterBody", (cx, 0.5, wz), (0.9, 1.0, 3.4), "svc_counter", 0.03)
    for i in range(4):
        box("CounterPlank", (cx - 0.455, 0.5, wz - 1.275 + i * 0.85), (0.02, 0.9, 0.06), "svc_crate")
    box("CounterTop", (cx - 0.05, 1.04, wz), (1.05, 0.08, 3.5), "svc_counter_top", 0.02)
    for i, z in enumerate((-2.4, -2.1, -1.8)):
        cyl("Jar", (cx + 0.1, 1.17, z), 0.08, 0.18, ("warning", "svc_red", "svc_teal")[i], 8)
        cyl("JarLid", (cx + 0.1, 1.28, z), 0.085, 0.04, "svc_steel", 8)
    for i in range(3):
        box("Pack", (cx + 0.1, 1.16 + i * 0.12, -0.6), (0.3, 0.12, 0.22), ("warning", "svc_cream", "warning")[i], 0.01)
    cyl("BellBase", (cx - 0.1, 1.1, 0.2), 0.08, 0.03, "sign_ink", 10)
    ball("Bell", (cx - 0.1, 1.13, 0.2), (0.065, 0.06, 0.065), "svc_steel")
    # Door at the front end, with a small window and a handle; a mat in front.
    dz = 3.0
    box("DoorFrame", (fx - 0.03, 1.1, dz), (0.08, 2.2, 1.14), "svc_dark", 0.02)
    box("Door", (fx - 0.06, 1.05, dz), (0.04, 2.08, 1.0), "svc_teal")
    box("DoorPane", (fx - 0.085, 1.5, dz), (0.02, 0.7, 0.6), "door_glass")
    box("DoorHandle", (fx - 0.11, 1.05, dz - 0.36), (0.05, 0.05, 0.16), "svc_steel")
    box("DoorMat", (fx - 0.45, 0.02, dz), (0.6, 0.04, 1.0), "svc_dark")
    # Wall lamp over the door (the glow is the canopy's; this is the fitting).
    box("WallLamp", (fx - 0.12, 2.45, dz), (0.2, 0.12, 0.3), "svc_dark", 0.02)
    # Back (+X): AC unit, a cage with gas bottles, a downpipe.
    bx = W / 2
    box("ACUnit", (bx + 0.25, 2.1, -2.0), (0.4, 0.55, 0.8), "svc_steel", 0.03)
    box("ACGrille", (bx + 0.46, 2.1, -2.0), (0.02, 0.4, 0.5), "svc_dark")
    box("GasCageFloor", (bx + 0.45, 0.05, 1.0), (0.8, 0.1, 1.5), "svc_curb")
    for z in (0.65, 1.0, 1.35):
        cyl("GasBottle", (bx + 0.45, 0.45, z), 0.15, 0.7, "svc_gas", 10)
        cyl("GasValve", (bx + 0.45, 0.86, z), 0.05, 0.12, "svc_steel", 6)
    for z in (0.25, 1.75):
        box("GasCagePost", (bx + 0.82, 0.6, z), (0.05, 1.2, 0.05), "svc_steel")
    box("GasCageRail", (bx + 0.82, 1.15, 1.0), (0.04, 0.04, 1.5), "svc_steel")
    box("GasCageRail", (bx + 0.82, 0.6, 1.0), (0.04, 0.04, 1.5), "svc_steel")
    box("Downpipe", (bx + 0.08, 1.5, -D / 2 + 0.25), (0.1, 3.0, 0.1), "svc_steel")
    # A back door and a high window, so the long back wall is not a blank block.
    box("BackDoorFrame", (bx + 0.03, 1.1, 3.0), (0.08, 2.2, 1.1), "svc_dark", 0.02)
    box("BackDoor", (bx + 0.06, 1.05, 3.0), (0.04, 2.08, 0.96), "svc_steel")
    box("BackDoorStep", (bx + 0.3, 0.06, 3.0), (0.5, 0.12, 1.2), "svc_curb")
    box("BackWindowFrame", (bx + 0.03, 2.1, -0.6), (0.06, 0.6, 1.4), "svc_dark")
    box("BackWindow", (bx + 0.05, 2.1, -0.6), (0.04, 0.48, 1.28), "door_glass")
    box("BackWindowSill", (bx + 0.08, 1.78, -0.6), (0.14, 0.05, 1.5), "svc_teal")
    # Side window on the road end (-Z), a lit menu board on the +Z end.
    box("SideWindow", (0, 1.7, -D / 2 - 0.03), (1.6, 0.9, 0.06), "door_glass")
    box("SideWindowFrame", (0, 1.7, -D / 2 - 0.02), (1.72, 1.02, 0.04), "svc_dark")
    box("SideWindowSill", (0, 1.22, -D / 2 - 0.07), (1.8, 0.06, 0.14), "svc_teal")
    box("MenuBoard", (-0.6, 1.6, D / 2 + 0.04), (1.6, 1.0, 0.06), "svc_board", 0.02)
    for i in range(4):
        box("MenuLine", (-0.6, 1.88 - i * 0.2, D / 2 + 0.075), (1.2 - 0.15 * (i % 2), 0.06, 0.02), "svc_cream")
    done("sm_env_service_kiosk.glb")


# =============================================================================
# Price pole (totem).
# =============================================================================

def totem():
    clear()
    box("Plinth", (0, 0.2, 0), (0.9, 0.5, 0.9), "svc_curb", 0.05)
    box("Pole", (0, 3.4, 0), (0.32, 6.4, 0.32), "svc_steel", 0.03)
    # The board (titles are Label3D at z 0.13): a frame round a dark face.
    box("BoardFace", (0, 6.5, 0), (2.6, 1.7, 0.22), "svc_board")
    box("BoardFrameL", (-1.33, 6.5, 0), (0.08, 1.86, 0.26), "svc_teal", 0.02)
    box("BoardFrameR", (1.33, 6.5, 0), (0.08, 1.86, 0.26), "svc_teal", 0.02)
    box("BoardRoof", (0, 7.52, 0), (2.9, 0.1, 0.36), "svc_teal_dark", 0.02)
    # Price panel under the board: two rows of white digit plates with colour chips.
    box("PricePanel", (0, 5.05, 0), (2.2, 0.85, 0.2), "svc_teal", 0.03)
    for row, y in enumerate((5.25, 4.85)):
        box("PriceChip", (-0.8, y, 0.11), (0.36, 0.26, 0.02), ("svc_red", "warning")[row])
        for i in range(3):
            box("PriceDigit", (-0.3 + i * 0.4, y, 0.11), (0.3, 0.3, 0.02), "svc_cream")
            box("PriceDigit", (-0.3 + i * 0.4, y, -0.11), (0.3, 0.3, 0.02), "svc_cream")
    done("sm_env_service_totem.glb")


# =============================================================================
# Back-yard clutter.
# =============================================================================

def crates():
    clear()
    # Pallet: three runners and five deck boards.
    for x in (-0.5, 0.0, 0.5):
        box("PalletRunner", (x, 0.05, 0), (0.12, 0.1, 1.2), "wood")
    for i in range(5):
        box("PalletBoard", (0, 0.125, -0.5 + i * 0.25), (1.2, 0.03, 0.16), "wood")
    # Two wooden crates side by side and one on top, turned a little.
    for x, y, yaw in ((-0.3, 0.42, 0.0), (0.3, 0.42, 0.05), (0.0, 0.98, -0.15)):
        box("Crate", (x, y, 0.0), (0.56, 0.56, 0.9), "svc_crate", 0.02, yaw=yaw)
        for zz in (-0.3, 0.3):
            dx, dz = math.sin(yaw) * zz, math.cos(yaw) * zz
            box("CrateSlat", (x + dx, y, dz), (0.58, 0.58, 0.06), "svc_counter", 0.01, yaw=yaw)
    # Oil cans on the right crate.
    for i, z in enumerate((-0.35, -0.12, 0.11)):
        box("OilCan", (0.45, 0.83, z), (0.12, 0.26, 0.2), ("warning", "svc_red", "warning")[i], 0.01)
    done("sm_env_service_crates.glb")


def drum():
    clear()
    cyl("Drum", (0, 0.45, 0), 0.3, 0.9, "svc_drum", 12)
    for y in (0.3, 0.6):
        cyl("DrumRib", (0, y, 0), 0.31, 0.04, "svc_drum", 12)
    cyl("DrumLid", (0, 0.905, 0), 0.28, 0.02, "svc_steel", 12)
    cyl("DrumBung", (0.12, 0.925, 0.05), 0.04, 0.03, "sign_ink", 6)
    done("sm_env_service_drum.glb")


BUILDERS = {
    "canopy": [canopy], "pump": [pump], "kiosk": [kiosk], "totem": [totem],
    "crates": [crates], "drum": [drum],
}
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for group, builders in BUILDERS.items():
    if not ONLY or group in ONLY:
        for builder in builders:
            builder()

print("SERVICE_REPORT")
for name, tris in REPORT:
    print("  %-34s %6d tris" % (name, tris))
