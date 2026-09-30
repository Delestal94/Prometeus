"""Loose clutter riding in the cargo bay for Take My Package (N-139, 2026-09-30).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_cargo_clutter.py

Replaces the primitives `scripts/presentation/cargo_clutter.gd` used to build
the toolbox and the thermos that slide about the cargo bay, in the cartoon
line of the depot and street props (build_depot_props.py,
build_street_props.py): chunky, bevelled, flat palette colours. They are seen
up close (the player stands in the bay with the boxes), so they carry more
small parts than a roadside prop, still well under the close-prop budget.

The rigid bodies keep their colliders (BoxShape 0.36 x 0.20 x 0.20 and
CylinderShape r 0.045 x 0.26): the models are sized to sit inside them, only
the handle and the cup-lid stick out on top, as the old primitives did.

  Blender coordinates (Z up; the glTF exporter turns them into Godot's Y up,
  Blender -Y becomes Godot +Z). Origin at the centre of the BASE, metres; the
  game shifts the mesh down by half the collider height to centre it on the
  body. Each GLB is ONE mesh node, several material surfaces.

  models/props/cargo/sm_prop_cargo_toolbox.glb   node/mesh "Toolbox"
      Body 0.36 (X) x 0.20 (Y) x 0.20 (Z) exactly -- tray, seam, bevelled lid,
      back hinge (+Y), two latches and a name plate on the front (-Y, Godot
      +Z). Arched handle with its brackets on top, up to z ~0.26.
  models/props/cargo/sm_prop_cargo_thermos.glb   node/mesh "Thermos"
      Body r 0.045, 0.26 tall to the lid's rim; two light bands; the dark
      cup-lid ends at z 0.29 (0.03 over the collider, as before). Side handle
      toward +X, out to x ~0.06 (1.5 cm past the collider).

Materials (new palette entries, none of them in LowpolyMaterials.DETAIL, so
they stay flat colour): "toolbox_red" #d2412f, "tool_steel" #3b3f42 (handle,
hinge, seam), "latch_steel" #a7b0b2, "warning" (kit), "thermos_blue" #2c7fb8
(metallic 0.4, roughness 0.35), "thermos_band" #bfe3f0, "thermos_cap"
#1f2326.

No baked AO: bake_vertex_ao.py looks 1.2 m around each corner, meant for
houses and vehicles; on a 20 cm prop every face would come out uniformly
dark, and test_baked_ao.gd does not list close props.

Pass names after "--" to rebuild only some of them:
    blender --background --factory-startup --python build_cargo_clutter.py -- toolbox
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from lowpoly_kit import PALETTE, ROOT, clear, cube, cylinder, export, mat, triangle_count  # noqa: E402


def srgb(hex_code):
    """Palette hex (as in docs/direccion-visual.md) to the linear RGBA the kit uses."""
    out = []
    for i in (0, 2, 4):
        c = int(hex_code[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


PALETTE.update({
    "toolbox_red": srgb("d2412f"), "tool_steel": srgb("3b3f42"),
    "latch_steel": srgb("a7b0b2"),
    "thermos_blue": srgb("2c7fb8"), "thermos_band": srgb("bfe3f0"),
    "thermos_cap": srgb("1f2326"),
})
# Surface finish per material (the kit makes everything matte 0.88).
FINISH = {
    "toolbox_red": (0.25, 0.55), "tool_steel": (0.5, 0.5), "latch_steel": (0.7, 0.35),
    "thermos_blue": (0.4, 0.35), "thermos_band": (0.0, 0.6), "thermos_cap": (0.0, 0.7),
}

CARGO = os.path.join(ROOT, "models", "props", "cargo")
REPORT = []


def finish(name):
    m = mat(name)
    if name in FINISH:
        metallic, roughness = FINISH[name]
        principled = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        principled.inputs["Metallic"].default_value = metallic
        principled.inputs["Roughness"].default_value = roughness
        m.metallic = metallic
        m.roughness = roughness
    return m


def done(name, relative):
    """Joins everything into one mesh `name`, checks it and exports it."""
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    o.data.name = name
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    for m in o.data.materials:
        finish(m.name)
    corners = [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = [min(c[i] for c in corners) for i in range(3)]
    hi = [max(c[i] for c in corners) for i in range(3)]
    REPORT.append((relative, triangle_count(), lo, hi))
    export(os.path.join(CARGO, relative))


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


def box(name, lo, hi, material, bevel=0.0, segments=1):
    """A box between corners `lo` and `hi`, edges rounded by `bevel`."""
    size = tuple(h - l for l, h in zip(lo, hi))
    centre = tuple((l + h) / 2.0 for l, h in zip(lo, hi))
    o = cube(name, centre, size, material)
    if bevel:
        round_edges(o, bevel, segments)
    return o


def lathe(name, profile, sides, material, start=0.0, centre=(0.0, 0.0)):
    """Revolves (radius, z) points about the vertical axis through `centre`;
    a radius of 0 is a single tip vertex (a flat cap's centre)."""
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
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            if len(a) == 1:
                bm.faces.new([a[0], b[k], b[j]])
            elif len(b) == 1:
                bm.faces.new([a[k], a[j], b[0]])
            else:
                bm.faces.new([a[k], a[j], b[j], b[k]])
    if len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def sweep(name, points, radius, material, sides=6, plane="xz", y=0.0):
    """A round bar of `radius` bent along a polyline of (a, z) points drawn in
    the XZ plane at depth `y` (plane="xz") or the XZ plane turned to YZ
    (plane="yz", `a` along Y at x = `y`). Capped at both ends."""
    def at(a, z):
        return Vector((a, y, z)) if plane == "xz" else Vector((y, a, z))

    side_axis = Vector((0.0, 1.0, 0.0)) if plane == "xz" else Vector((1.0, 0.0, 0.0))
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    pts = [at(a, z) for a, z in points]
    rings = []
    for i, p in enumerate(pts):
        prev_p = pts[max(i - 1, 0)]
        next_p = pts[min(i + 1, len(pts) - 1)]
        tangent = (next_p - prev_p).normalized()
        normal = side_axis.cross(tangent).normalized()
        rings.append([bm.verts.new(p + (normal * math.cos(k * math.tau / sides) + side_axis * math.sin(k * math.tau / sides)) * radius)
                      for k in range(sides)])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new([a[k], a[j], b[j], b[k]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


# --- Toolbox ---------------------------------------------------------------

W, D, H = 0.36, 0.20, 0.20     # collider: width X, depth Y, height Z
SEAM = 0.132                   # where the lid meets the tray


def toolbox():
    """Front (-Y, Godot +Z): latches and plate. Back (+Y): hinge."""
    clear()
    hw, hd = W / 2.0, D / 2.0
    # Tray: 4 mm inside the collider on every side, so the latches and the
    # hinge reach the collider's faces without passing them.
    box("Tray", (-hw + 0.004, -hd + 0.006, 0.0), (hw - 0.004, hd - 0.006, SEAM - 0.004), "toolbox_red", 0.01, 1)
    # A rolled rim round the tray's mouth, and the dark gap under the lid.
    box("TrayRim", (-hw + 0.002, -hd + 0.004, SEAM - 0.016), (hw - 0.002, hd - 0.004, SEAM - 0.004), "toolbox_red", 0.004, 1)
    box("Seam", (-hw + 0.012, -hd + 0.014, SEAM - 0.005), (hw - 0.012, hd - 0.014, SEAM + 0.005), "tool_steel")
    # Lid: overhangs the tray a little, a soft domed top.
    box("Lid", (-hw, -hd + 0.002, SEAM + 0.004), (hw, hd - 0.002, H - 0.012), "toolbox_red", 0.006, 1)
    box("LidTop", (-hw + 0.012, -hd + 0.014, H - 0.02), (hw - 0.012, hd - 0.014, H - 0.003), "toolbox_red", 0.008, 1)
    # Stamped rib along the lid, where the handle sits.
    box("LidRib", (-0.13, -0.035, H - 0.004), (0.13, 0.035, H + 0.0), "toolbox_red")
    # Piano hinge along the back, knuckles on the seam.
    cylinder("Hinge", (0.0, hd - 0.007, SEAM), 0.007, W - 0.06, "tool_steel", 6, rot=(0.0, math.pi / 2.0, 0.0))
    for x in (-0.12, 0.0, 0.12):
        box("HingeLeaf", (x - 0.025, hd - 0.004, SEAM - 0.014), (x + 0.025, hd - 0.001, SEAM + 0.014), "latch_steel")
    # Two latches on the front: a catch on the lid, a lever over the seam.
    for x in (-0.115, 0.115):
        box("LatchCatch", (x - 0.016, -hd, SEAM + 0.012), (x + 0.016, -hd + 0.004, SEAM + 0.03), "latch_steel", 0.002)
        box("LatchLever", (x - 0.02, -hd, SEAM - 0.04), (x + 0.02, -hd + 0.006, SEAM + 0.014), "latch_steel", 0.003)
        box("LatchLip", (x - 0.012, -hd, SEAM + 0.006), (x + 0.012, -hd + 0.002, SEAM + 0.02), "tool_steel")
    # Name plate on the tray front, yellow like the depot's warning trim.
    box("Plate", (-0.055, -hd + 0.002, 0.04), (0.055, -hd + 0.006, 0.08), "warning", 0.002)
    for x in (-0.045, 0.045):
        box("PlateRivet", (x - 0.004, -hd, 0.056), (x + 0.004, -hd + 0.002, 0.064), "tool_steel")
    # Skids: a dark runner under each end of the base.
    for sx in (-1.0, 1.0):
        box("Skid", (min(sx * 0.155, sx * 0.172), -hd + 0.02, 0.0), (max(sx * 0.155, sx * 0.172), hd - 0.02, 0.01), "tool_steel")
    # Handle: brackets on the lid, an arched steel bar, a rubber grip.
    for sx in (-1.0, 1.0):
        box("HandleBracket", (sx * 0.1 - 0.014, -0.018, H - 0.002), (sx * 0.1 + 0.014, 0.018, H + 0.016), "tool_steel", 0.004)
    arch = [(-0.1, H + 0.008), (-0.097, H + 0.03), (-0.086, H + 0.045), (-0.066, H + 0.051),
            (0.066, H + 0.051), (0.086, H + 0.045), (0.097, H + 0.03), (0.1, H + 0.008)]
    sweep("Handle", arch, 0.007, "tool_steel", 6)
    cylinder("HandleGrip", (0.0, 0.0, H + 0.051), 0.012, 0.11, "tool_steel", 8, rot=(0.0, math.pi / 2.0, 0.0))
    done("Toolbox", "sm_prop_cargo_toolbox.glb")


# --- Thermos ---------------------------------------------------------------

R, TH = 0.045, 0.26            # collider radius and height
SIDES = 12


def thermos():
    """Camping flask; the handle is toward +X (Godot +X)."""
    clear()
    lathe("Body", [(0.0, 0.0), (R - 0.004, 0.0), (R, 0.006), (R, 0.2), (R - 0.004, 0.214),
                   (0.034, 0.222), (0.034, 0.232), (0.0, 0.232)], SIDES, "thermos_blue")
    # Rubber foot ring and two light bands.
    lathe("Foot", [(0.0, 0.0), (R - 0.002, 0.0), (R - 0.001, 0.016), (0.0, 0.016)], SIDES, "thermos_cap")
    for z0, z1 in ((0.03, 0.046), (0.176, 0.19)):
        lathe("Band", [(0.0, z0), (R + 0.0015, z0), (R + 0.0015, z1), (0.0, z1)], SIDES, "thermos_band")
    # Cup-lid: a tapered cup screwed over the neck, a ridged rim, a flat top.
    lathe("Cup", [(0.0, 0.214), (R + 0.002, 0.214), (R + 0.002, 0.224), (R, 0.228), (R - 0.001, 0.27),
                  (R - 0.004, 0.284), (R - 0.009, 0.29), (0.0, 0.29)], SIDES, "thermos_cap")
    lathe("CupRim", [(0.0, 0.254), (R + 0.0015, 0.254), (R + 0.0015, 0.262), (0.0, 0.262)], SIDES, "thermos_band")
    # Side handle: a flat strap bent out to +X, lugs at both ends.
    strap = [(R - 0.004, 0.06), (R + 0.005, 0.066), (R + 0.009, 0.085), (R + 0.009, 0.125),
             (R + 0.009, 0.145), (R + 0.005, 0.162), (R - 0.004, 0.168)]
    sweep("Handle", strap, 0.0055, "thermos_cap", 6, plane="xz", y=0.0)
    for z in (0.062, 0.166):
        cylinder("HandleLug", (R - 0.001, 0.0, z), 0.009, 0.012, "thermos_cap", 6, rot=(0.0, math.pi / 2.0, 0.0))
    done("Thermos", "sm_prop_cargo_thermos.glb")


BUILDERS = {"toolbox": toolbox, "thermos": thermos}
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for key, builder in BUILDERS.items():
    if not ONLY or key in ONLY:
        builder()

print("CARGO_CLUTTER_REPORT (Blender axes: X, Y, Z-up)")
for name, tris, lo, hi in REPORT:
    print("  %-28s %5d tris  min (%.3f, %.3f, %.3f)  max (%.3f, %.3f, %.3f)" % (name, tris, *lo, *hi))
