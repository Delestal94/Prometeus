"""Level crossing and train for Take My Package (N-129 / N-130, 2026-09-27).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python do-not-drop/assets/tools/build_rail_crossing.py

Replaces the cubes `rail_crossing_segment.gd` used to build out of code. The
segment keeps its own collision (post, barrier arm, one box per train car);
these are only what you see. Pieces, in `models/environment/rail/`:

  sm_env_rail_track.glb            84 m of track across the road (x -42..42),
                                   berm of ballast off the road and a timber
                                   plank deck on it. Origin on the track axis.
  sm_env_rail_crossing_signal.glb  post, crossbuck, bell and the twin lamp
                                   board facing Godot +Z, plus the barrier
                                   drive cabinet behind. Lenses are the nodes
                                   `LampLeft` / `LampRight` (the script swaps
                                   their material to flash them).
  sm_env_rail_barrier_arm.glb      the arm, authored along +X from its hinge
                                   at the origin (10.6 m), counterweight on -X.
  sm_env_rail_locomotive.glb       cartoon steam loco, nose toward +X (the
                                   direction the train runs).
  sm_env_rail_wagon_boxcar.glb     boxcar with the delivery-box logo.
  sm_env_rail_wagon_tanker.glb     tank car.

Train cars fit the gameplay box (7.5 x 3 x 2.6 m, bottom at 0.35 m) give or
take the chimney, the cowcatcher and the couplers; wheels sit on the rails
(rail top 0.12 m). Origin at the centre of the base, metres, Blender Z-up
(the exporter turns it into Godot's Y-up; Blender -Y is Godot +Z).

Pass names after "--" to rebuild only some of them:
    blender --background --factory-startup --python build_rail_crossing.py -- loco track
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from lowpoly_kit import (PALETTE, ROOT, blob, clear, cone, cube, cylinder,  # noqa: E402
                         export, flat_poly, jitter, mat, triangle_count)


def srgb(hex_code):
    """Palette hex (as in docs/direccion-visual.md) to the linear RGBA the kit uses."""
    out = []
    for i in (0, 2, 4):
        c = int(hex_code[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


PALETTE.update({
    # Toy-train primaries: the UI's YELLOW and RED/SKY family, a notch deeper
    # so they hold up under the sun instead of glowing.
    "loco_blue": srgb("2f6fb5"), "loco_red": srgb("e0412f"),
    "loco_yellow": srgb("ffc93c"), "charcoal": srgb("2b2f36"),
    "boxcar_orange": srgb("ee7f2d"), "boxcar_rib": srgb("c25e1f"),
    "boxcar_door": srgb("fff0d6"), "logo_cardboard": srgb("e0a867"),
    "tank_mint": srgb("2dc49a"), "roof_grey": srgb("6c7478"),
    "rail_steel": srgb("7d8488"), "ballast": srgb("8a8279"),
    "danger_red": srgb("d8322b"), "brass": srgb("e8b43c"),
    "crossing_lens": srgb("5a1210"),
})

OUT = os.path.join(ROOT, "models", "environment", "rail")
REPORT = []
GAUGE = 1.435
RAIL_Y = GAUGE / 2.0
ALONG_X = (0.0, math.pi / 2.0, 0.0)     # a cylinder/cone lying along +X
ALONG_Y = (math.pi / 2.0, 0.0, 0.0)     # a cylinder/cone lying along -Y (facing the front)


def done(filename):
    path = os.path.join(OUT, filename)
    REPORT.append((filename, triangle_count()))
    export(path)


def extrude_x(name, profile, x0, x1, steps, material, y=0.0):
    """A convex (y, z) profile swept along X from x0 to x1, with `steps` rings:
    the extra rings let the terrain conform bend long pieces (rails, berm)."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    rings = []
    for i in range(steps + 1):
        x = x0 + (x1 - x0) * i / steps
        rings.append([bm.verts.new((x, y + py, pz)) for py, pz in profile])
    count = len(profile)
    for i in range(steps):
        a, b = rings[i], rings[i + 1]
        for j in range(count):
            k = (j + 1) % count
            bm.faces.new([a[j], a[k], b[k], b[j]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat(material))
    return obj


def taper_bar(name, x0, x1, h0, h1, d0, d1, material, y=0.0, z=0.0):
    """A box along X whose height/depth shrink from (h0, d0) at x0 to (h1, d1) at x1."""
    profile0 = [(-d0 / 2, -h0 / 2), (d0 / 2, -h0 / 2), (d0 / 2, h0 / 2), (-d0 / 2, h0 / 2)]
    obj = extrude_x(name, profile0, x0, x1, 1, material, y)
    for v in obj.data.vertices:
        if abs(v.co.x - x1) < 1e-5:
            v.co.y = y + (v.co.y - y) * d1 / d0
            v.co.z = v.co.z * h1 / h0
        v.co.z += z
    obj.data.update()
    return obj


def wheel(name, x, y, z, radius, material, hub_material, width=0.15, verts=12):
    side = 1.0 if y > 0 else -1.0
    cylinder(name, (x, y, z), radius, width, material, verts, rot=ALONG_Y)
    cylinder(name + "Hub", (x, y + side * (width / 2 + 0.03), z), radius * 0.36, 0.06, hub_material, 8, rot=ALONG_Y)


def bogie(prefix, x):
    cube(prefix + "Frame", (x, 0, 0.56), (2.1, 1.9, 0.22), "charcoal", 0.04)
    for dx in (-0.62, 0.62):
        for y in (-RAIL_Y - 0.02, RAIL_Y + 0.02):
            wheel(prefix + "Wheel", x + dx, y, 0.5, 0.38, "charcoal", "loco_yellow", 0.14)
    for y in (-1.0, 1.0):
        cube(prefix + "Spring", (x, y, 0.62), (0.5, 0.1, 0.22), "loco_red", 0.02)


def couplers(length):
    for side in (-1.0, 1.0):
        cube("Coupler", (side * (length / 2 + 0.12), 0, 0.82), (0.3, 0.3, 0.22), "charcoal", 0.03)


# =============================================================================
# Track: rails over the road and 36 m each way, sleepers and ballast berm off
# the road, a timber plank deck on it (the classic rural crossing).
# =============================================================================

def track():
    clear()
    span, road_half = 42.0, 6.2
    rail = [(-0.07, 0.0), (0.07, 0.0), (0.04, 0.12), (-0.04, 0.12)]
    for y in (-RAIL_Y, RAIL_Y):
        extrude_x("Rail", rail, -span, span, 28, "rail_steel", y)
    berm = [(-1.8, -0.3), (1.8, -0.3), (1.3, 0.03), (-1.3, 0.03)]
    for side in (-1.0, 1.0):
        x0, x1 = side * road_half, side * span
        extrude_x("Ballast", berm, min(x0, x1), max(x0, x1), 12, "ballast")
        x = road_half + 0.5
        while x < span - 0.3:
            cube("Sleeper", (side * x, 0, 0.035), (0.26, 2.3, 0.09), "wood")
            x += 1.45
    # Planks on the road: two inside the gauge, one outside each rail, a
    # flangeway gap by every rail. Top at 0.07, under the rail head.
    for y, width in ((-0.3, 0.54), (0.3, 0.54), (-1.14, 0.7), (1.14, 0.7)):
        cube("CrossingPlank", (0, y, 0.035), (road_half * 2.0, width, 0.07), "wood")
    done("sm_env_rail_track.glb")


# =============================================================================
# Crossing signal: front (lamps, crossbuck) toward Blender -Y = Godot +Z.
# =============================================================================

def crossing_signal():
    clear()
    cube("PostBase", (0, 0, 0.12), (0.5, 0.5, 0.24), "concrete", 0.04)
    cylinder("Post", (0, 0, 1.8), 0.085, 3.36, "sign_white", 10)
    for z in (0.55, 1.65):
        cylinder("PostBand", (0, 0, z), 0.092, 0.22, "sign_ink", 10)
    # The bell: a fat brass dome on top, rung by the CrossingBell sound.
    cylinder("BellStem", (0, 0, 3.56), 0.04, 0.16, "metal", 6)
    cone("Bell", (0, 0, 3.72), 0.2, 0.09, 0.2, "brass", 10)
    blob("BellKnob", (0, 0, 3.84), (0.06, 0.06, 0.05), "brass")
    # Crossbuck: red-edged white boards, the second a hair in front.
    for index, tilt in enumerate((0.6, -0.6)):
        y = -0.1 - index * 0.05
        cube("CrossbuckEdge", (0, y, 3.15), (1.62, 0.035, 0.3), "danger_red", 0.01, rot=(0, tilt, 0))
        cube("Crossbuck", (0, y - 0.022, 3.15), (1.5, 0.012, 0.19), "sign_white", 0.0, rot=(0, tilt, 0))
    cylinder("CrossbuckBolt", (0, -0.2, 3.15), 0.05, 0.05, "metal", 8, rot=ALONG_Y)
    LAMP_Z = 2.35
    # Lamp board: white rim, black face, two round lamps with hoods.
    cube("LampBracket", (0, -0.07, LAMP_Z), (0.2, 0.1, 0.1), "metal")
    cube("LampBoardRim", (0, -0.13, LAMP_Z), (1.02, 0.03, 0.44), "sign_white", 0.012)
    cube("LampBoard", (0, -0.15, LAMP_Z), (0.94, 0.03, 0.36), "sign_ink", 0.012)
    for x, lens in ((-0.28, "LampLeft"), (0.28, "LampRight")):
        cylinder("LampHousing", (x, -0.21, LAMP_Z), 0.155, 0.1, "sign_ink", 12, rot=ALONG_Y)
        cylinder(lens, (x, -0.27, LAMP_Z), 0.12, 0.03, "crossing_lens", 12, rot=ALONG_Y)
        cube("LampHood", (x, -0.3, LAMP_Z + 0.17), (0.34, 0.2, 0.025), "sign_ink", rot=(-0.25, 0, 0))
    # Barrier drive cabinet behind the post; the arm (its own model) hinges
    # on the shaft at 1.05 m in the plane 0.28 m behind the post.
    cube("BarrierCabinet", (0, 0.58, 0.55), (0.46, 0.34, 1.1), "warning", 0.05)
    for z in (0.3, 0.75):
        cube("CabinetStripe", (0, 0.58, z), (0.47, 0.35, 0.09), "sign_ink")
    cylinder("BarrierShaft", (0, 0.4, 1.05), 0.055, 0.1, "metal", 8, rot=ALONG_Y)
    done("sm_env_rail_crossing_signal.glb")


# =============================================================================
# Barrier arm: hinge at the origin, arm along +X, 0.28 m toward Godot +Z
# (Blender -Y); the script turns it round for the other side of the road.
# =============================================================================

def barrier_arm():
    clear()
    y = -0.28
    cylinder("ArmHub", (0, y, 0), 0.17, 0.2, "sign_ink", 12, rot=ALONG_Y)
    cylinder("ArmHubCap", (0, y - 0.11, 0), 0.08, 0.03, "warning", 8, rot=ALONG_Y)
    cube("Counterweight", (-0.55, y, 0), (0.7, 0.24, 0.34), "sign_ink", 0.04)
    cube("CounterweightStripe", (-0.55, y, 0), (0.12, 0.25, 0.35), "warning")
    length, start, parts = 10.6, 0.12, 9
    step = (length - start) / parts
    for i in range(parts):
        x0, x1 = start + i * step, start + (i + 1) * step
        t0, t1 = x0 / length, x1 / length
        taper_bar("ArmStripe", x0, x1, 0.17 - 0.07 * t0, 0.17 - 0.07 * t1, 0.12 - 0.04 * t0,
                  0.12 - 0.04 * t1, "danger_red" if i % 2 == 0 else "sign_white", y)
    blob("ArmTip", (length, y, 0), (0.06, 0.05, 0.06), "danger_red")
    for x in (4.6, 9.4):
        cube("ArmLampBase", (x, y, 0.08), (0.12, 0.08, 0.04), "sign_ink")
        blob("ArmLamp", (x, y, 0.13), (0.06, 0.05, 0.05), "danger_red")
    done("sm_env_rail_barrier_arm.glb")


# =============================================================================
# Locomotive: a toy steam engine with a big round nose -- blue boiler with
# brass bands, a huge funnel, headlight on the smokebox, red cab, yellow
# cowcatcher like a moustache. Runs toward +X.
# =============================================================================

def locomotive():
    clear()
    cube("Frame", (0.2, 0, 0.74), (7.3, 2.1, 0.28), "charcoal", 0.04)
    cube("RunningBoard", (0.95, 0, 0.93), (5.2, 2.55, 0.1), "charcoal", 0.03)
    cube("Valance", (0.95, 0, 0.84), (5.22, 2.57, 0.08), "loco_yellow")
    # Boiler and smokebox.
    cylinder("Boiler", (0.8, 0, 1.95), 0.95, 4.0, "loco_blue", 16, rot=ALONG_X)
    for x in (-0.55, 0.6, 1.8, 2.72):
        cylinder("BoilerBand", (x, 0, 1.95), 0.975, 0.09, "brass", 16, rot=ALONG_X)
    cylinder("Smokebox", (3.1, 0, 1.95), 1.02, 0.8, "charcoal", 16, rot=ALONG_X)
    cone("SmokeboxDoor", (3.59, 0, 1.95), 0.92, 0.56, 0.18, "metal", 16, rot=ALONG_X)
    blob("DoorKnob", (3.72, 0, 1.95), (0.11, 0.13, 0.13), "brass")
    cube("NumberPlate", (3.69, 0, 1.55), (0.04, 0.5, 0.2), "loco_red", 0.01)
    # The funnel: oversized on purpose.
    cone("Chimney", (2.72, 0, 3.15), 0.26, 0.5, 1.0, "charcoal", 12)
    cylinder("ChimneyLip", (2.72, 0, 3.69), 0.54, 0.12, "charcoal", 12)
    cylinder("ChimneyBand", (2.72, 0, 3.55), 0.46, 0.1, "loco_red", 12)
    # Headlight on top of the smokebox, lens is "lamp" so it glows at night.
    cube("HeadlightBracket", (3.42, 0, 2.95), (0.3, 0.2, 0.12), "charcoal")
    cylinder("Headlight", (3.45, 0, 3.18), 0.28, 0.42, "loco_yellow", 12, rot=ALONG_X)
    cylinder("HeadlightLens", (3.67, 0, 3.18), 0.22, 0.04, "lamp", 12, rot=ALONG_X)
    # Domes and whistle.
    blob("SteamDome", (1.25, 0, 2.86), (0.42, 0.42, 0.4), "brass")
    blob("SandDome", (0.05, 0, 2.84), (0.33, 0.33, 0.3), "loco_red")
    cylinder("Whistle", (-0.75, 0, 3.0), 0.07, 0.3, "brass", 8)
    # Cab.
    cube("Cab", (-2.35, 0, 2.05), (2.4, 2.45, 2.3), "loco_red", 0.07)
    cube("CabStripe", (-2.35, 0, 1.45), (2.43, 2.48, 0.12), "loco_yellow")
    cube("CabRoof", (-2.35, 0, 3.28), (2.95, 2.8, 0.18), "charcoal", 0.06)
    cube("CabRoofTop", (-2.35, 0, 3.42), (2.4, 2.0, 0.14), "charcoal", 0.05)
    for y in (-1.0, 1.0):
        cube("CabWindowFrame", (-2.05, y * 1.22, 2.55), (1.12, 0.04, 0.86), "loco_yellow", 0.01)
        cube("CabWindow", (-2.05, y * 1.235, 2.55), (0.96, 0.04, 0.7), "window")
        cylinder("CabPorthole", (-1.14, y * 0.78, 2.62), 0.2, 0.05, "window", 10, rot=ALONG_X)
        cylinder("CabPortholeRim", (-1.16, y * 0.78, 2.62), 0.25, 0.04, "loco_yellow", 10, rot=ALONG_X)
    # Wheels: three big red drivers, a trailing wheel under the cab, a rod.
    for y in (-RAIL_Y - 0.05, RAIL_Y + 0.05):
        side = 1.0 if y > 0 else -1.0
        for x in (-0.35, 0.85, 2.05):
            wheel("Driver", x, y, 0.67, 0.55, "loco_red", "loco_yellow", 0.16, 14)
        wheel("TrailingWheel", -2.55, y, 0.5, 0.38, "loco_red", "loco_yellow", 0.14)
        cube("SideRod", (0.85, y + side * 0.16, 0.6), (2.6, 0.05, 0.1), "metal", 0.02)
        cylinder("Cylinder", (3.05, side * 1.0, 0.95), 0.3, 0.85, "charcoal", 10, rot=ALONG_X)
        cylinder("CylinderCap", (3.5, side * 1.0, 0.95), 0.31, 0.06, "brass", 10, rot=ALONG_X)
    # Buffer beam and cowcatcher.
    cube("BufferBeam", (3.58, 0, 0.98), (0.2, 2.4, 0.34), "loco_red", 0.03)
    for y in (-0.85, 0.85):
        cylinder("Buffer", (3.76, y, 0.98), 0.14, 0.18, "charcoal", 8, rot=ALONG_X)
    flat_poly("Cowcatcher", [(3.5, 0.2), (4.2, 0.2), (3.72, 0.84), (3.5, 0.84)], -1.0, 2.0, "loco_yellow", plane="xz")
    for y in (-0.6, 0.0, 0.6):
        flat_poly("CowcatcherSlat", [(3.72, 0.22), (4.23, 0.22), (3.75, 0.86), (3.72, 0.86)], y - 0.05, 0.1, "charcoal", plane="xz")
    cube("Coupler", (-3.87, 0, 0.82), (0.3, 0.3, 0.22), "charcoal", 0.03)
    done("sm_env_rail_locomotive.glb")


# =============================================================================
# Wagons.
# =============================================================================

def boxcar():
    clear()
    length = 7.3
    cube("Frame", (0, 0, 0.84), (7.4, 2.25, 0.22), "charcoal", 0.03)
    cube("Body", (0, 0, 2.06), (length, 2.5, 2.2), "boxcar_orange", 0.06)
    for x in (-3.15, -2.35, -1.55, 1.55, 2.35, 3.15):
        cube("Rib", (x, 0, 2.06), (0.09, 2.56, 2.12), "boxcar_rib")
    cube("Roof", (0, 0, 3.21), (length + 0.12, 2.64, 0.16), "roof_grey", 0.05)
    cube("RoofRidge", (0, 0, 3.33), (length - 0.1, 1.9, 0.12), "roof_grey", 0.04)
    cube("RoofWalk", (0, 0, 3.42), (length - 0.3, 0.5, 0.05), "charcoal")
    # Sliding door with the delivery-box logo on both sides.
    cube("Door", (0, 0, 2.02), (2.1, 2.58, 1.96), "boxcar_door", 0.03)
    for z in (1.0, 3.04):
        cube("DoorRail", (0, 0, z), (4.6, 2.62, 0.08), "charcoal")
    for y, t in ((-1.31, 0.025), (1.285, 0.025)):
        flat_poly("LogoBox", [(-0.45, 1.62), (0.45, 1.62), (0.45, 2.42), (-0.45, 2.42)], y, t, "logo_cardboard")
        flat_poly("LogoLid", [(-0.5, 2.42), (0.5, 2.42), (0.38, 2.62), (-0.38, 2.62)], y, t, "logo_cardboard")
        flat_poly("LogoTape", [(-0.09, 1.62), (0.09, 1.62), (0.09, 2.62), (-0.09, 2.62)], y - 0.01 if y < 0 else y + 0.01, t, "loco_yellow")
        cube("DoorHandle", (0.82, y + (0.02 if y < 0 else 0.0), 2.0), (0.06, 0.04, 0.5), "charcoal")
    for x in (-2.65, 2.65):
        bogie("Bogie", x)
    couplers(length + 0.1)
    done("sm_env_rail_wagon_boxcar.glb")


def tanker():
    clear()
    cube("Frame", (0, 0, 0.84), (7.4, 2.25, 0.22), "charcoal", 0.03)
    cube("Walkway", (0, 0, 0.99), (7.2, 2.6, 0.06), "charcoal", 0.02)
    for x in (-2.3, 2.3):
        cube("Saddle", (x, 0, 1.12), (0.45, 1.9, 0.3), "charcoal", 0.03)
    cylinder("Tank", (0, 0, 2.15), 1.12, 6.0, "tank_mint", 16, rot=ALONG_X)
    for side in (-1.0, 1.0):
        cone("TankEnd", (side * 3.2, 0, 2.15), 1.12, 0.62, 0.4, "tank_mint", 16, rot=(0, side * math.pi / 2.0, 0))
        blob("TankEndCap", (side * 3.4, 0, 2.15), (0.16, 0.63, 0.63), "tank_mint", 1)
        cylinder("TankEndRing", (side * 3.02, 0, 2.15), 1.14, 0.1, "charcoal", 16, rot=ALONG_X)
    for x in (-2.3, 2.3):
        cylinder("TankBand", (x, 0, 2.15), 1.14, 0.14, "charcoal", 16, rot=ALONG_X)
    for x in (-1.45, 1.45):
        cylinder("TankStripe", (x, 0, 2.15), 1.14, 0.16, "loco_yellow", 16, rot=ALONG_X)
    cylinder("Dome", (0, 0, 3.3), 0.45, 0.35, "tank_mint", 12)
    cylinder("DomeLid", (0, 0, 3.5), 0.5, 0.08, "charcoal", 12)
    blob("DomeValve", (0, 0, 3.58), (0.1, 0.1, 0.08), "brass")
    for y in (-1.0, 1.0):
        cylinder("Badge", (0, y * 1.1, 2.15), 0.52, 0.14, "sign_white", 16, rot=ALONG_Y)
        blob("BadgeDrop", (0, y * 1.18, 2.08), (0.17, 0.05, 0.2), "tank_mint")
        cone("BadgeDropTip", (0, y * 1.18, 2.3), 0.13, 0.0, 0.2, "tank_mint", 8)
    for x in (-2.65, 2.65):
        bogie("Bogie", x)
    couplers(7.4)
    done("sm_env_rail_wagon_tanker.glb")


# =============================================================================
# Tunnel portal: the train comes out of one and goes into the other, instead
# of popping into existence 42 m down the line (playtest 2026-09-28). One
# model for both ends: the facade stands in the plane x = 0 facing -X (the
# road), the bore runs 12 m into +X (the hill route_terrain.gd raises behind
# it). Origin on the track axis at rail-base level, like the track model,
# whose rails end exactly where these begin.
#
# Masonry: a warm stone facade with pilasters, a cornice and a parapet, a ring
# of lighter voussoirs with a keystone, quoins up the jambs, wing walls that
# hold back the cutting's slopes, and a plinth along the foot. Inside, the
# bore darkens to black (vertex colours, which LowpolyMaterials multiplies in)
# so the train fades into it rather than vanishing.
# =============================================================================

PORTAL_OPENING = 2.35      # half-width of the arch (RailCrossingSegment.BORE_HALF_WIDTH)
PORTAL_SPRING = 3.7        # where the arch springs from the jambs
PORTAL_CROWN = PORTAL_SPRING + PORTAL_OPENING   # 6.05, RailCrossingSegment.BORE_CROWN
PORTAL_HALF = 5.6          # half-width of the facade (RailCrossingSegment.PORTAL_HALF_WIDTH)
PORTAL_HEIGHT = 8.4        # top of the facade, under the cornice (PORTAL_HEIGHT)
PORTAL_THICK = 1.0         # facade depth along the track
BORE_LENGTH = 12.0         # RailCrossingSegment.BORE_LENGTH
WING_LENGTH = 7.0
WING_ANGLE = math.radians(25.0)


def _mesh_object(name, bm, material):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat(material))
    return obj


def prism(name, profile, origin, udir, vdir, thickness, material):
    """A convex (u, z) outline laid out along `udir` from `origin`, extruded
    `thickness` along `vdir` (both horizontal unit vectors)."""
    bm = bmesh.new()

    def at(u, z, w):
        return (origin[0] + udir[0] * u + vdir[0] * w, origin[1] + udir[1] * u + vdir[1] * w, origin[2] + z)

    a = [bm.verts.new(at(u, z, 0.0)) for u, z in profile]
    b = [bm.verts.new(at(u, z, thickness)) for u, z in profile]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(len(profile)):
        j = (i + 1) % len(profile)
        bm.faces.new([a[i], a[j], b[j], b[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _mesh_object(name, bm, material)


def _arch_ring(radius, steps=16):
    """The bore's cross-section (y, z), jamb foot to jamb foot over the arch."""
    ring = [(radius, 0.0), (radius, PORTAL_SPRING * 0.5), (radius, PORTAL_SPRING)]
    for i in range(1, steps):
        a = math.pi * i / steps
        ring.append((radius * math.cos(a), PORTAL_SPRING + radius * math.sin(a)))
    ring += [(-radius, PORTAL_SPRING), (-radius, PORTAL_SPRING * 0.5), (-radius, 0.0)]
    return ring


def _sweep(name, ring, stations, material, inward):
    """`ring` swept along +X through `stations`: an open tube (no floor),
    faces turned toward the axis (`inward`) or away from it."""
    bm = bmesh.new()
    rows = [[bm.verts.new((x, y, z)) for y, z in ring] for x in stations]
    for a, b in zip(rows, rows[1:]):
        for j in range(len(ring) - 1):
            bm.faces.new([a[j], a[j + 1], b[j + 1], b[j]])
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    probe = bm.faces[len(ring) // 2]   # a face up in the arch
    centre = probe.calc_center_median()
    towards_axis = Vector((centre.x, 0.0, PORTAL_SPRING * 0.5)) - centre
    if (probe.normal.dot(towards_axis) > 0.0) != inward:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    return _mesh_object(name, bm, material)


def _facade():
    """The wall with the arch cut out of it: quads fanned between the arch
    and the wall's outline (corners included), plus the two piers, extruded
    back PORTAL_THICK."""
    bm = bmesh.new()
    rise = PORTAL_HEIGHT - PORTAL_SPRING
    corner = math.atan2(rise, PORTAL_HALF)
    angles = sorted(set([math.pi * i / 16 for i in range(17)] + [corner, math.pi - corner]))
    inner, outer = [], []
    for a in angles:
        c, s = math.cos(a), math.sin(a)
        inner.append(bm.verts.new((0.0, PORTAL_OPENING * c, PORTAL_SPRING + PORTAL_OPENING * s)))
        t = min(PORTAL_HALF / abs(c) if abs(c) > 1e-6 else 1e9, rise / s if s > 1e-6 else 1e9)
        outer.append(bm.verts.new((0.0, c * t, PORTAL_SPRING + s * t)))
    faces = []
    for i in range(len(angles) - 1):
        faces.append(bm.faces.new([inner[i], outer[i], outer[i + 1], inner[i + 1]]))
    for side, top_in, top_out in ((1.0, inner[0], outer[0]), (-1.0, inner[-1], outer[-1])):
        foot_in = bm.verts.new((0.0, side * PORTAL_OPENING, 0.0))
        foot_out = bm.verts.new((0.0, side * PORTAL_HALF, 0.0))
        # Same winding as the arch quads on both sides.
        pier = [foot_in, foot_out, top_out, top_in] if side > 0.0 else [foot_out, foot_in, top_in, top_out]
        faces.append(bm.faces.new(pier))
    extruded = bmesh.ops.extrude_face_region(bm, geom=faces)
    moved = [e for e in extruded["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(PORTAL_THICK, 0.0, 0.0), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _mesh_object("PortalFacade", bm, "portal_stone")


def _shade_bore():
    """Vertex colours: full light on the outside, dimming through the depth of
    the facade and down the bore to black a few metres short of its end."""
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            continue
        mesh = obj.data
        colours = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        mesh.color_attributes.active_color = colours
        for loop in mesh.loops:
            p = obj.matrix_world @ mesh.vertices[loop.vertex_index].co
            light = 1.0
            if abs(p.y) < PORTAL_OPENING + 0.08 and p.z < PORTAL_CROWN + 0.08 and p.x > 0.02:
                depth = min(max(p.x / PORTAL_THICK, 0.0), 1.0)
                far = min(max((p.x - PORTAL_THICK) / (BORE_LENGTH * 0.72 - PORTAL_THICK), 0.0), 1.0)
                light = (1.0 - 0.4 * depth * depth * (3 - 2 * depth)) * (1.0 - far * far * (3 - 2 * far))
            colours.data[loop.index].color = (light, light, light, 1.0)


def tunnel_portal():
    clear()
    PALETTE.update({
        "portal_stone": srgb("9a8f7e"), "portal_trim": srgb("cdbfa4"),
        "tunnel_soot": srgb("4d4843"), "tunnel_black": srgb("050505"),
    })
    _facade()
    # Voussoirs round the arch, the keystone deeper and prouder than the rest.
    count = 15
    gap = 0.025
    for i in range(count):
        a0 = math.pi * i / count + gap
        a1 = math.pi * (i + 1) / count - gap
        key = i == count // 2
        r0, r1 = PORTAL_OPENING - 0.05, PORTAL_OPENING + (1.05 if key else 0.72)
        outline = [(r0 * math.cos(a0), PORTAL_SPRING + r0 * math.sin(a0)),
                   (r1 * math.cos(a0), PORTAL_SPRING + r1 * math.sin(a0)),
                   (r1 * math.cos(a1), PORTAL_SPRING + r1 * math.sin(a1)),
                   (r0 * math.cos(a1), PORTAL_SPRING + r0 * math.sin(a1))]
        prism("Keystone" if key else "Voussoir", outline, (-0.22 if key else -0.13, 0.0, 0.0),
              (0.0, 1.0, 0.0), (1.0, 0.0, 0.0), 0.6, "portal_trim")
    for side in (-1.0, 1.0):
        # Impost where the arch springs, quoins up the jamb (long and short
        # in turn), the plinth along the foot.
        cube("Impost", (0.1, side * (PORTAL_OPENING + 0.42), PORTAL_SPRING - 0.14), (0.7, 0.95, 0.28), "portal_trim", 0.03)
        z = 0.0
        for k, height in enumerate((0.8, 0.72, 0.8, 0.7)):
            width = 0.85 if k % 2 == 0 else 0.55
            cube("Quoin", (0.08, side * (PORTAL_OPENING + width / 2 - 0.04), z + height / 2),
                 (0.56, width, height - 0.05), "portal_trim", 0.03)
            z += height
        cube("Plinth", (-0.35, side * (PORTAL_OPENING + 0.1 + (PORTAL_HALF - PORTAL_OPENING) / 2), -0.1),
             (1.3, PORTAL_HALF - PORTAL_OPENING + 0.2, 0.6), "portal_trim", 0.04)
        # Pilasters at the facade's edges, battered (thicker at the foot).
        prism("Pilaster", [(-0.75, -0.3), (0.3, -0.3), (0.3, PORTAL_HEIGHT), (-0.32, PORTAL_HEIGHT)],
              (0.0, side * PORTAL_HALF - (0.95 if side > 0 else 0.0), 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0),
              0.95, "portal_stone")
        # Wing walls flaring out toward the road, stepping down with the slope
        # of the cutting they hold back, a coping on top and a pier at the end.
        along = (-math.cos(WING_ANGLE), side * math.sin(WING_ANGLE), 0.0)
        out = (math.sin(WING_ANGLE), side * math.cos(WING_ANGLE), 0.0)
        root = (-0.3, side * (PORTAL_HALF - 0.55), 0.0)
        top0, top1 = PORTAL_HEIGHT - 0.6, 1.3
        prism("WingWall", [(0.0, -0.3), (WING_LENGTH, -0.3), (WING_LENGTH, top1), (0.0, top0)],
              root, along, out, 0.8, "portal_stone")
        coping_root = (root[0] - out[0] * 0.12, root[1] - out[1] * 0.12, 0.0)
        prism("WingCoping", [(0.0, top0), (WING_LENGTH, top1), (WING_LENGTH, top1 + 0.24), (0.0, top0 + 0.24)],
              coping_root, along, out, 1.04, "portal_trim")
        end = (root[0] + along[0] * WING_LENGTH + out[0] * 0.4, root[1] + along[1] * WING_LENGTH + out[1] * 0.4)
        yaw = math.atan2(along[1], along[0])
        cube("WingPier", (end[0], end[1], 0.6), (1.1, 1.1, 1.9), "portal_stone", 0.04, rot=(0, 0, yaw))
        cube("WingPierCap", (end[0], end[1], 1.62), (1.3, 1.3, 0.2), "portal_trim", 0.03, rot=(0, 0, yaw))
    # Cornice, parapet and its coping along the top.
    cube("Cornice", (0.3, 0, PORTAL_HEIGHT + 0.16), (PORTAL_THICK + 0.75, PORTAL_HALF * 2 + 0.5, 0.32), "portal_trim", 0.04)
    cube("Parapet", (0.45, 0, PORTAL_HEIGHT + 0.62), (0.7, PORTAL_HALF * 2 - 0.2, 0.6), "portal_stone", 0.03)
    cube("ParapetCoping", (0.45, 0, PORTAL_HEIGHT + 1.0), (0.9, PORTAL_HALF * 2, 0.16), "portal_trim", 0.03)
    # A blank date stone over the keystone.
    cube("Tablet", (-0.1, 0, PORTAL_CROWN + 1.55), (0.2, 1.7, 0.62), "portal_trim", 0.04)
    # Moss where rain sits: on the cornice and the wing piers' caps.
    for y, size in ((-3.9, 0.7), (-1.2, 0.45), (2.6, 0.8), (4.6, 0.5)):
        moss = blob("Moss", (0.0, y, PORTAL_HEIGHT + 0.34), (0.35, size, 0.1), "moss")
        jitter(moss, 0.04, int(abs(y) * 10))
    # The bore: soot-dark masonry inside, its outer shell (only ever seen
    # from above, through the hill) and a black end, a ballast floor with the
    # track running on into the dark.
    stations = [PORTAL_THICK - 0.02, 2.0, 3.5, 5.5, 8.0, BORE_LENGTH]
    _sweep("BoreLining", _arch_ring(PORTAL_OPENING), stations, "tunnel_soot", True)
    _sweep("BoreShell", _arch_ring(PORTAL_OPENING + 0.45), [PORTAL_THICK - 0.02, BORE_LENGTH], "portal_stone", False)
    bm = bmesh.new()
    cap = [bm.verts.new((BORE_LENGTH, y, z)) for y, z in _arch_ring(PORTAL_OPENING + 0.02)]
    face = bm.faces.new(cap)
    face.normal_update()
    if face.normal.x > 0.0:
        bmesh.ops.reverse_faces(bm, faces=[face])
    _mesh_object("BoreEnd", bm, "tunnel_black")
    # Ballast a few centimetres proud of the ground (like the track's berm),
    # so the level ground the terrain keeps under the mouth never shows
    # through, and a gravel apron across the foot of the facade covering
    # where the terrain opens up for the bore.
    extrude_x("BoreBallast", [(-PORTAL_OPENING, -0.3), (PORTAL_OPENING, -0.3), (PORTAL_OPENING, 0.04),
                              (-PORTAL_OPENING, 0.04)], -0.2, BORE_LENGTH, 8, "ballast")
    cube("Apron", (-1.2, 0, -0.13), (2.2, PORTAL_HALF * 2 - 0.4, 0.34), "ballast")
    # Masonry backing behind the facade: the hill can't come right up against
    # the wall on the terrain's 2 m grid, so this wedge fills the gap (and the
    # terrain's hole over the bore), from under the parapet's coping down into
    # the hill rising behind it.
    prism("Backfill", [(0.85, PORTAL_CROWN + 0.45), (5.4, PORTAL_CROWN + 0.45), (5.4, PORTAL_CROWN + 0.9),
                       (0.85, PORTAL_HEIGHT + 0.88)],
          (0.0, -PORTAL_HALF - 0.15, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), PORTAL_HALF * 2 + 0.3, "portal_stone")
    rail = [(-0.07, 0.0), (0.07, 0.0), (0.04, 0.12), (-0.04, 0.12)]
    for y in (-RAIL_Y, RAIL_Y):
        extrude_x("Rail", rail, 0.0, BORE_LENGTH, 6, "rail_steel", y)
    x = 0.55
    while x < BORE_LENGTH - 0.3:
        cube("Sleeper", (x, 0, 0.035), (0.26, 2.3, 0.09), "wood")
        x += 1.45
    _shade_bore()
    REPORT.append(("sm_env_rail_tunnel_portal.glb", triangle_count()))
    path = os.path.join(OUT, "sm_env_rail_tunnel_portal.glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_materials="EXPORT", export_apply=True, export_vertex_color="ACTIVE")
    print("EXPORTED", os.path.relpath(path, ROOT))


BUILDERS = {"track": track, "signal": crossing_signal, "arm": barrier_arm,
            "loco": locomotive, "boxcar": boxcar, "tanker": tanker, "portal": tunnel_portal}
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for builder_name, builder in BUILDERS.items():
    if not ONLY or builder_name in ONLY:
        builder()

print("RAIL_REPORT")
for name, tris in REPORT:
    print("  %-40s %6d tris" % (name, tris))
