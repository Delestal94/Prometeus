"""Route set pieces for Take My Package (N-131 .. N-134, 2026-09-27).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_route_pieces.py

Replaces the cubes the tunnel, narrow bridge and chicane segments and the
power line (route_dresser.gd) drew out of code, in the cartoon line of the
train (build_rail_crossing.py) and the street props (build_street_props.py).
The scripts keep every collision box they always had (hidden); these models
are only what you see. Pieces, in `models/environment/route/`:

  sm_env_route_tunnel_module.glb   4 m of bore (Blender y -2..2): walls with a
                                   dark dado, cream tiles and a teal band, an
                                   elliptic vault (springs at 2.6 m, crown at
                                   4.8 m = the collision roof), a rib, a
                                   yellow/black kerb, cable tray, reflectors,
                                   stone outside and a grass hump on top. The
                                   segment lays 11 of them: short pieces, so
                                   conform_geometry() can bend them onto the
                                   terrain like the boxes it replaced.
  sm_env_route_tunnel_portal.glb   stone headwall with voussoirs, keystone,
                                   quoins, buttresses, coping, a height-limit
                                   roundel, grass and bushes on top. Front face
                                   toward Godot +Z (the way into the tunnel);
                                   the exit portal is turned half round.
  sm_env_route_tunnel_lamp.glb     ceiling lamp, origin at its top (the mount);
                                   the lens is the mesh `Lens` (the segment
                                   gives it its emissive material).
  sm_env_route_bridge_deck.glb     4 m of deck (6 m asphalt, edge lines,
                                   concrete slab, teal steel girders).
  sm_env_route_bridge_post.glb     the post every 4 m (collision 0.3 x 1.08).
  sm_env_route_bridge_water.glb    36 m of river under the deck: water, banks,
                                   abutments, two piers, ripples and foam.
                                   Origin at the middle of the span.
  sm_env_route_chicane_barrier.glb 4.4 x 1.0 x 0.8 m: two jersey sections with
                                   diagonal warning bands leaning toward +X
                                   (the gap to steer through) and a striped
                                   bollard with an amber lamp on that end.
  sm_env_route_power_pole.glb      wooden pole (base 0.3 m underground),
                                   braced cross-arm along X, three insulators
                                   (x -0.75 / +0.75 on the arm, one on top) and
                                   a warning plate: mesh `PowerPole`. The pole
                                   transformer is the separate mesh
                                   `Transformer`. Under 400 tris together.

Origin at the centre of the base (the road surface for the road pieces),
metres, Blender Z-up (the exporter turns it into Godot's Y-up; Blender +Y is
Godot -Z, i.e. further down the road).

Pass names after "--" to rebuild only some of them:
    blender --background --factory-startup --python build_route_pieces.py -- tunnel pole
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from lowpoly_kit import (MATS, PALETTE, ROOT, blob, clear, cone, cube,  # noqa: E402
                         cylinder, export, flat_poly, jitter, triangle_count)


def srgb(hex_code):
    """Palette hex (as in docs/direccion-visual.md) to the linear RGBA the kit uses."""
    out = []
    for i in (0, 2, 4):
        c = int(hex_code[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


# Names before the dot pick LowpolyMaterials' detail map in Godot ("stone",
# "concrete", "grass"); the part after it is just another colour of it.
PALETTE.update({
    "stone.sand": srgb("c8a67a"), "stone.light": srgb("a9aea2"),
    "stone.key": srgb("e2c98f"), "stone.dark": srgb("6f7571"),
    "concrete.light": srgb("b9c0b8"), "concrete.jersey": srgb("c9cec4"),
    "tunnel_tile": srgb("ece3c8"), "tunnel_dado": srgb("3f5d61"),
    "teal": srgb("65b5a1"), "charcoal": srgb("2b2f36"),
    "road": srgb("394a50"), "marking": srgb("d4d9c2"),
    "girder": srgb("2f8479"), "water": srgb("4a93a3"),
    "water_light": srgb("8fd0da"), "foam": srgb("e6f6f4"),
    "bank": srgb("8a7456"), "danger_red": srgb("d8322b"),
    "pole_wood": srgb("6b5238"), "insulator": srgb("7ecbd6"),
    "transformer": srgb("8e9c9a"), "ink": srgb("1e2235"),
})


def mat(name):
    """lowpoly_kit.mat() with dotted names allowed (kit colours otherwise)."""
    if name not in MATS:
        m = bpy.data.materials.new(name)
        m.diffuse_color = PALETTE[name]
        m.use_nodes = True
        principled = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if principled is None:
            raise RuntimeError("Principled BSDF missing for material %s" % name)
        principled.inputs["Base Color"].default_value = PALETTE[name]
        principled.inputs["Roughness"].default_value = 0.88
        MATS[name] = m
    return MATS[name]


# The kit's primitives call its own mat(); route the dotted names through ours.
import lowpoly_kit  # noqa: E402
lowpoly_kit.mat = mat

OUT = os.path.join(ROOT, "models", "environment", "route")
REPORT = []
ALONG_X = (0.0, math.pi / 2.0, 0.0)
ALONG_Y = (math.pi / 2.0, 0.0, 0.0)


def done(filename):
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            # No n-gons in the files: triangulate the concave outlines here.
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
            bm.to_mesh(o.data)
            bm.free()
    REPORT.append((filename, triangle_count()))
    export(os.path.join(OUT, filename))


def prism_y(name, outline, y0, y1, material, rings=1):
    """An (x, z) outline (any simple polygon) swept along Y from y0 to y1."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    loops = []
    for i in range(rings + 1):
        y = y0 + (y1 - y0) * i / rings
        loops.append([bm.verts.new((x, y, z)) for x, z in outline])
    n = len(outline)
    for i in range(rings):
        a, b = loops[i], loops[i + 1]
        for j in range(n):
            k = (j + 1) % n
            bm.faces.new([a[j], a[k], b[k], b[j]])
    bm.faces.new(loops[0])
    bm.faces.new(list(reversed(loops[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def prism_x(name, outline, x0, x1, material, shear=0.0, shear_from=0.0):
    """A (y, z) outline swept along X; `shear` leans it (x += (z - shear_from) * shear)."""
    obj = prism_y(name, [(y, z) for y, z in outline], x0, x1, material)
    for v in obj.data.vertices:
        # prism_y built it as (a, y, z) with a = outline y; swap to (x, y, z).
        a, x, z = v.co.x, v.co.y, v.co.z
        v.co.x, v.co.y = x + (z - shear_from) * shear, a
    obj.data.update()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


# =============================================================================
# Tunnel (N-131). The collision is a 9.4 m wide, 4.8 m tall box bore (walls
# 4.7..5.3, roof 4.8..5.3); the vault only rounds its top corners, above
# where the truck can reach.
# =============================================================================

HALF = 4.7
SPRING = 2.6
RISE = 2.2
MODULE = 4.0


def bore_arch(steps=10, inset=0.0):
    """The vault's inner edge, right to left (theta 0..pi), `inset` further in."""
    points = []
    for i in range(steps + 1):
        t = math.pi * i / steps
        points.append(((HALF - inset) * math.cos(t), SPRING + (RISE - inset) * math.sin(t)))
    return points


def bore_outline(inset=0.0, floor=0.0):
    """The opening: walls from `floor` up, then the vault."""
    return [(HALF - inset, floor)] + bore_arch(10, inset) + [(-(HALF - inset), floor)]


def tunnel_module():
    clear()
    y0, y1 = -MODULE / 2, MODULE / 2
    # The shell: inverted U round the bore, flat roof on top.
    shell = bore_outline(0.0, -0.35) + [(-5.3, -0.35), (-5.3, 5.3), (5.3, 5.3), (5.3, -0.35)]
    prism_y("TunnelShell", shell, y0, y1, "concrete.light")
    for side in (-1.0, 1.0):
        # Inside, from the floor up: dark dado, teal band, cream tiles.
        cube("Dado", (side * (HALF - 0.03), 0, 0.6), (0.06, MODULE, 1.2), "tunnel_dado")
        cube("Band", (side * (HALF - 0.05), 0, 1.3), (0.1, MODULE, 0.2), "teal")
        cube("Tiles", (side * (HALF - 0.025), 0, 1.98), (0.05, MODULE, 1.16), "tunnel_tile")
        cube("CableTray", (side * (HALF - 0.1), 0, 2.4), (0.12, MODULE, 0.09), "charcoal")
        # Kerb in yellow and black metres: reads speed in the half-dark.
        for i in range(4):
            cube("Kerb", (side * (HALF - 0.17), y0 + 0.5 + i, 0.09), (0.35, 1.0, 0.18),
                 "warning" if i % 2 == 0 else "charcoal")
        cube("Reflector", (side * (HALF - 0.07), 0.9, 0.85), (0.04, 0.22, 0.12), "reflector")
        # Outside: stone cladding.
        cube("OuterStone", (side * 5.33, 0, 2.47), (0.06, MODULE, 5.64), "stone")
    # A rib round the bore every module.
    outer = bore_outline(0.0, 0.18)
    inner = bore_outline(0.12, 0.18)
    rib = outer + list(reversed(inner))
    # Off-centre so it never meets the ceiling lamps (tunnel_segment.gd).
    prism_y("Rib", rib, 0.32, 0.68, "concrete.light")
    # Earth hump over the roof, grass on top.
    hump = [(5.36, 5.2), (6.0, 5.05), (4.6, 6.1), (2.4, 6.75), (0.0, 6.95),
            (-2.4, 6.75), (-4.6, 6.1), (-6.0, 5.05), (-5.36, 5.2)]
    prism_y("Hump", hump, y0, y1, "grass", rings=2)
    done("sm_env_route_tunnel_module.glb")


def tunnel_lamp():
    clear()
    cube("Housing", (0, 0, -0.08), (1.0, 0.36, 0.16), "charcoal", 0.03)
    lens = cube("Lens", (0, 0, -0.17), (0.86, 0.24, 0.04), "lamp")
    lens.name = "Lens"
    for x in (-0.35, 0.35):
        cube("Clip", (x, 0, -0.17), (0.05, 0.3, 0.06), "charcoal")
    done("sm_env_route_tunnel_lamp.glb")


def voussoir(name, t0, t1, depth, y0, y1, material):
    """One arch stone between angles t0..t1 of the vault, `depth` thick."""
    def at(t, extra):
        # Outward normal of the ellipse, so the stones radiate.
        nx, nz = math.cos(t) / HALF, math.sin(t) / RISE
        ln = math.hypot(nx, nz)
        return (HALF * math.cos(t) + nx / ln * extra, SPRING + RISE * math.sin(t) + nz / ln * extra)
    outline = [at(t0, -0.02), at(t1, -0.02), at(t1, depth), at(t0, depth)]
    return prism_y(name, outline, y0, y1, material)


def tunnel_portal():
    clear()
    rng = random.Random(131)
    front, back = -0.4, 0.4
    top = 7.0
    # Headwall: a U round the opening.
    wall = bore_outline(0.0, -0.4) + [(-6.6, -0.4), (-6.6, top), (6.6, top), (6.6, -0.4)]
    prism_y("Headwall", wall, front, back, "stone.sand")
    # A few proud blocks so the sandstone reads as coursed stone.
    for i in range(16):
        x = rng.choice((-1, 1)) * rng.uniform(5.2, 6.2) if i < 8 else rng.uniform(-3.6, 3.6)
        z = rng.uniform(0.5, 4.6) if i < 8 else rng.uniform(5.6, 6.6)
        if abs(x) < 3.2 and z < 6.0:
            continue
        cube("Block", (x, front - 0.04, z), (rng.choice((0.7, 0.9, 1.1)), 0.1, 0.42), rng.choice(("stone.sand", "stone.light")), 0.03)
    # Voussoirs round the vault, keystone at the crown.
    count = 13
    for i in range(count):
        t0 = math.pi * i / count + 0.012
        t1 = math.pi * (i + 1) / count - 0.012
        key = i == count // 2
        voussoir("Keystone" if key else "Voussoir", t0 - (0.03 if key else 0), t1 + (0.03 if key else 0),
                 1.05 if key else 0.75, front - (0.26 if key else 0.16), back - 0.2,
                 "stone.key" if key else ("stone.light" if i % 2 else "stone.dark"))
    # Quoins down the jambs, long and short in turn.
    for side in (-1.0, 1.0):
        for i in range(4):
            w = 0.95 if i % 2 == 0 else 0.6
            cube("Quoin", (side * (HALF + w / 2), front - 0.08, 0.33 + i * 0.64), (w, 0.2, 0.58),
                 "stone.light" if i % 2 == 0 else "stone.dark", 0.03)
        # Buttresses at the ends, stepped back at the top.
        cube("Buttress", (side * 6.35, front - 0.22, 2.8), (0.8, 0.5, 6.4), "stone.dark", 0.04)
        flat_poly("ButtressCap", [(front - 0.47, 6.0), (front + 0.03, 6.0), (front + 0.03, 6.5)],
                  side * 6.35 - 0.4, 0.8, "stone.dark", plane="yz")
        # Rocks at the foot, grass and bushes on top, ivy spilling over.
        jitter(blob("Rock", (side * 7.1, front - 0.2, 0.0), (0.7, 0.55, 0.5), "stone", 1), 0.08, 7 + int(side))
        jitter(blob("Rock", (side * 7.3, front + 0.8, 0.0), (0.5, 0.45, 0.35), "stone.dark", 1), 0.06, 9 + int(side))
        jitter(blob("Bush", (side * 5.2, back + 0.6, 7.55), (1.1, 0.9, 0.75), "leaf", 1), 0.1, 11 + int(side))
        jitter(blob("Bush", (side * 3.6, back + 1.2, 7.35), (0.8, 0.7, 0.55), "leaf_light", 1), 0.08, 13 + int(side))
        for k, (dx, dz, s) in enumerate(((0.0, 6.35, 0.55), (0.45, 5.75, 0.4), (-0.1, 5.25, 0.3))):
            jitter(blob("Ivy", (side * (5.6 + dx), front - 0.12, dz), (s, 0.14, s * 1.3), "leaf_dark", 1), 0.04, 20 + k + int(side) * 5)
    cube("Coping", (0, (front + back) / 2 - 0.05, top + 0.15), (13.8, 1.1, 0.3), "stone.dark", 0.05)
    # Grass cushion over the coping, running back into the tunnel's hump.
    hump = [(6.0, 7.2), (4.6, 7.55), (2.4, 7.75), (0.0, 7.8), (-2.4, 7.75), (-4.6, 7.55), (-6.0, 7.2),
            (-6.0, 5.05), (6.0, 5.05)]
    prism_y("Grass", hump, front + 0.1, back + 2.4, "grass")
    # Height-limit roundel over the keystone: red ring, white face, arrows.
    cylinder("SignRing", (0, front - 0.22, 6.2), 0.52, 0.06, "danger_red", 16, rot=ALONG_Y)
    cylinder("SignFace", (0, front - 0.26, 6.2), 0.4, 0.04, "sign_white", 16, rot=ALONG_Y)
    for dz, flip in ((0.18, -1), (-0.18, 1)):
        flat_poly("SignArrow", [(-0.13, 6.2 + dz), (0.13, 6.2 + dz), (0.0, 6.2 + dz + flip * 0.14)],
                  front - 0.3, 0.02, "ink", plane="xz")
    cube("SignBar", (0, front - 0.29, 6.2), (0.5, 0.02, 0.035), "ink")
    done("sm_env_route_tunnel_portal.glb")


# =============================================================================
# Narrow bridge (N-132). Deck collision 6 x 0.4 m (top at 0), posts 0.3 x
# 1.08 m at x = +-3.05; the railing is its own model.
# =============================================================================

def bridge_deck():
    clear()
    cube("Slab", (0, 0, -0.25), (6.6, MODULE, 0.4), "concrete", 0.03)
    cube("Asphalt", (0, 0, -0.03), (5.9, MODULE, 0.06), "road")
    for x in (-2.62, 2.62):
        cube("EdgeLine", (x, 0, 0.004), (0.12, MODULE, 0.012), "marking")
    for side in (-1.0, 1.0):
        cube("Fascia", (side * 3.25, 0, -0.72), (0.12, MODULE, 0.56), "girder")
        cube("FasciaLip", (side * 3.3, 0, -0.44), (0.16, MODULE, 0.06), "girder")
        # Inner girder: web and bottom flange.
        cube("Web", (side * 1.7, 0, -0.75), (0.1, MODULE, 0.6), "girder")
        cube("Flange", (side * 1.7, 0, -1.07), (0.42, MODULE, 0.06), "girder")
        cube("FasciaFlange", (side * 3.2, 0, -1.02), (0.3, MODULE, 0.06), "girder")
    cube("CrossBeam", (0, 0, -0.75), (6.3, 0.12, 0.5), "girder")
    done("sm_env_route_bridge_deck.glb")


def bridge_post():
    clear()
    cube("Post", (0, 0, 0.5), (0.34, 0.34, 1.1), "concrete.light", 0.03)
    cone("Cap", (0, 0, 1.13), 0.3, 0.05, 0.16, "concrete", 4, rot=(0, 0, math.pi / 4))
    cube("Band", (0, 0, 0.82), (0.36, 0.36, 0.14), "warning")
    for y in (-0.185, 0.185):
        cube("Reflector", (0, y, 0.82), (0.12, 0.012, 0.08), "reflector")
    done("sm_env_route_bridge_post.glb")


def bridge_water():
    clear()
    rng = random.Random(132)
    level = -1.6
    half_len = 18.0
    cube("Water", (0, 0, level - 0.03), (30.0, 2 * half_len - 3.0, 0.06), "water")
    for end in (-1.0, 1.0):
        # Banks: earth sloping from the neighbours' ground (-0.3) into the river.
        bank = [(end * half_len, -0.3), (end * half_len, level - 0.25), (end * (half_len - 3.2), level - 0.25)]
        prism_x("Bank", bank, -15.0, 15.0, "bank")
        prism_x("BankGrass", [(end * half_len, -0.28), (end * (half_len - 0.5), -0.42), (end * half_len, -0.42)],
                -15.0, 15.0, "grass")
        # Abutment under the deck end.
        cube("Abutment", (0, end * (half_len - 1.1), (level - 0.3 - 0.45) / 2), (7.2, 1.8, -0.45 - (level - 0.3)), "stone.light", 0.04)
        for i in range(7):
            x = rng.uniform(-13.0, 13.0)
            if abs(x) < 4.2:
                continue
            jitter(blob("Rock", (x, end * (half_len - 3.0 + rng.uniform(-0.3, 0.4)), level + 0.05),
                        (rng.uniform(0.35, 0.7), rng.uniform(0.3, 0.5), rng.uniform(0.2, 0.35)), "stone", 1), 0.05, i + int(end * 10))
    # Piers at a third and two thirds, cutwaters facing the current (along X).
    for y in (-6.0, 6.0):
        prism_x("Pier", [(y - 0.45, level - 0.4), (y + 0.45, level - 0.4), (y + 0.45, -1.1), (y - 0.45, -1.1)], -2.6, 2.6, "stone.light")
        for side in (-1.0, 1.0):
            flat_poly("Cutwater", [(side * 2.6, y - 0.45), (side * 3.3, y), (side * 2.6, y + 0.45)],
                      level - 0.4, -1.1 - (level - 0.4), "stone.light", plane="xy")
        cube("PierCap", (0, y, -1.12), (5.6, 1.1, 0.12), "stone.dark", 0.03)
        # Foam round the pier on the water.
        flat_poly("Foam", [(-3.7, y), (-2.6, y - 0.75), (2.6, y - 0.75), (3.7, y), (2.6, y + 0.75), (-2.6, y + 0.75)],
                  level, 0.012, "foam", plane="xy")
    # Ripple streaks along the current.
    for i in range(16):
        x = rng.uniform(-13.5, 13.5)
        y = rng.uniform(-13.5, 13.5)
        if abs(x) < 3.6 and (abs(abs(y) - 6.0) < 1.2):
            continue
        w = rng.uniform(1.2, 2.6)
        flat_poly("Ripple", [(x - w / 2, y), (x, y - 0.07), (x + w / 2, y), (x, y + 0.07)],
                  level + 0.005, 0.01, "water_light", plane="xy")
    done("sm_env_route_bridge_water.glb")


# =============================================================================
# Chicane (N-133): 4.4 m across the road, 1.0 m deep, 0.8 m tall (the solid
# box goes to 1.6 m). +X is the end next to the gap to steer through.
# =============================================================================

JERSEY = [(-0.5, 0.0), (0.5, 0.0), (0.5, 0.08), (0.3, 0.28), (0.18, 0.8), (-0.18, 0.8), (-0.3, 0.28), (-0.5, 0.08)]
JERSEY_TOP = [(-0.31, 0.3), (0.31, 0.3), (0.19, 0.81), (-0.19, 0.81)]


def chicane_barrier():
    clear()
    sections = ((-2.2, -0.05), (0.05, 1.8))
    for x0, x1 in sections:
        prism_x("Jersey", JERSEY, x0, x1, "concrete.jersey")
        # Warning bands leaning toward +X, round the top of the barrier.
        x = x0 + 0.12
        band = 0.26
        while x + band + 0.3 < x1:
            prism_x("Band", JERSEY_TOP, x, x + band, "warning", shear=0.55, shear_from=0.3)
            x += band * 2.0
        # Slots at the foot, a hook on top.
        for sx in (x0 + 0.5, x1 - 0.5):
            cube("Slot", (sx, 0, 0.07), (0.4, 1.02, 0.12), "charcoal")
        cube("Hook", ((x0 + x1) / 2, 0, 0.84), (0.2, 0.08, 0.08), "charcoal")
    # The bollard at the gap end: black and yellow rings, amber lamp.
    cx = 1.99
    for i in range(5):
        cylinder("Bollard", (cx, 0, 0.1 + i * 0.2), 0.2, 0.2, "warning" if i % 2 else "charcoal", 10)
    cylinder("BollardCap", (cx, 0, 1.03), 0.22, 0.06, "charcoal", 10)
    blob("Lamp", (cx, 0, 1.14), (0.12, 0.12, 0.1), "lamp", 1)
    for y in (-0.21, 0.21):
        cube("Reflector", (cx, y, 0.7), (0.18, 0.02, 0.1), "reflector")
    done("sm_env_route_chicane_barrier.glb")


# =============================================================================
# Power pole (N-134). One MultiMesh instance per pole: keep it under 400 tris.
# Wires hang at (x -0.75 | 0 | +0.75, 7.02 | 7.26 | 7.02) (route_dresser.gd).
# =============================================================================

def power_pole():
    clear()
    parts = []
    parts.append(cone("Pole", (0, 0, 3.4), 0.16, 0.11, 7.4, "pole_wood", 6))
    parts.append(cube("Arm", (0, 0, 6.8), (1.9, 0.12, 0.12), "pole_wood"))
    for side in (-1.0, 1.0):
        # Brace from the pole to the arm.
        brace = cube("Brace", (side * 0.3, -0.08, 6.52), (0.66, 0.04, 0.05), "pole_wood")
        brace.rotation_euler = (0, -side * 0.72, 0)
        parts.append(brace)
    for x, z in ((-0.75, 6.86), (0.75, 6.86), (0.0, 7.1)):
        parts.append(cylinder("Pin", (x, 0, z + 0.05), 0.025, 0.1, "charcoal", 4))
        parts.append(cone("Insulator", (x, 0, z + 0.12), 0.07, 0.045, 0.1, "insulator", 6))
        parts.append(cone("InsulatorSkirt", (x, 0, z + 0.075), 0.09, 0.05, 0.03, "insulator", 6))
    parts.append(cone("PoleCap", (0, 0, 7.12), 0.12, 0.0, 0.1, "charcoal", 6))
    parts.append(cube("Plate", (0, -0.13, 2.4), (0.2, 0.02, 0.28), "warning"))
    parts.append(cube("PlateMark", (0, -0.142, 2.43), (0.05, 0.01, 0.14), "ink"))
    parts.append(cube("Tag", (0, -0.125, 1.7), (0.1, 0.01, 0.06), "sign_white"))
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.ops.object.join()
    pole = bpy.context.object
    pole.name = "PowerPole"
    pole.data.name = "PowerPole"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # The transformer can hanging on the far side, apart so the line can have
    # one every few poles.
    t = [cylinder("Can", (0, 0.36, 5.3), 0.2, 0.6, "transformer", 8),
         cone("Lid", (0, 0.36, 5.66), 0.22, 0.12, 0.12, "transformer", 8),
         cube("Bracket", (0, 0.18, 5.45), (0.08, 0.2, 0.4), "charcoal"),
         cylinder("Bushing", (0.08, 0.36, 5.78), 0.03, 0.12, "insulator", 4),
         cylinder("Bushing", (-0.08, 0.36, 5.78), 0.03, 0.12, "insulator", 4),
         cube("Stripe", (0, 0.36 - 0.2, 5.22), (0.2, 0.03, 0.08), "warning")]
    bpy.ops.object.select_all(action="DESELECT")
    for o in t:
        o.select_set(True)
    bpy.context.view_layer.objects.active = t[0]
    bpy.ops.object.join()
    can = bpy.context.object
    can.name = "Transformer"
    can.data.name = "Transformer"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    done("sm_env_route_power_pole.glb")


BUILDERS = {
    "tunnel": (tunnel_module, tunnel_portal, tunnel_lamp),
    "bridge": (bridge_deck, bridge_post, bridge_water),
    "chicane": (chicane_barrier,),
    "pole": (power_pole,),
}
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for group, builders in BUILDERS.items():
    if not ONLY or group in ONLY:
        for builder in builders:
            builder()

print("ROUTE_REPORT")
for name, tris in REPORT:
    print("  %-40s %6d tris" % (name, tris))
