"""Vertex colour for the game export: soft ambient occlusion and a blush.

GL Compatibility has no SSAO, and a round character lit by one sun reads
flat: nothing darkens under the chin, where the tummy hangs over the shorts
or between the legs. Each vertex casts rays over its hemisphere against the
whole character (rest pose) and darkens by the share that hits something
close. Skin also gets a warm blush on the cheeks, nose and ears.

Godot's glTF importer multiplies the material colour by COLOR_0, so the
crew-coloured T-shirt keeps its tint and gains the shading. The export
writes the active colour attribute (export_vertex_color='ACTIVE').
"""
import math, random
import bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

RAYS = 48
DISTANCE = .45      # BU (0.22 m in game): only near geometry occludes
STRENGTH = .55
FLOOR = .58         # darkest a vertex may get
NUDGE = .004

# (centre, radius, strength), BU at rest: cheeks, nose tip, ears.
BLUSH = [((.45, -.42, 2.69), .19, 1.), ((-.45, -.42, 2.69), .19, 1.),
         ((0, -.60, 2.84), .08, .8),
         ((.62, .03, 2.83), .12, .45), ((-.62, .03, 2.83), .12, .45)]
BLUSH_TINT = (1.0, .70, .66)   # multiplies the skin at full blush (linear)

def _hemisphere(n, count, rng):
    """Cosine-weighted directions around the normal n."""
    t = n.orthogonal().normalized(); b = n.cross(t)
    out = []
    for _ in range(count):
        u, v = rng.random(), rng.random()
        r, a = math.sqrt(u), 2*math.pi*v
        out.append((t*(r*math.cos(a)) + b*(r*math.sin(a)) + n*math.sqrt(1-u)).normalized())
    return out

def apply(body, skin_material='Skin'):
    """Writes a point colour attribute 'Col' on body (object mode, rest pose)."""
    rng = random.Random(7)
    mw = body.matrix_world
    bm = bmesh.new(); bm.from_mesh(body.data); bm.transform(mw)
    bm.normal_update()
    tree = BVHTree.FromBMesh(bm)
    skin_slot = next((i for i, s in enumerate(body.material_slots) if s.material and s.material.name == skin_material), -1)
    skin = [False]*len(bm.verts)
    for f in bm.faces:
        if f.material_index == skin_slot:
            for v in f.verts: skin[v.index] = True
    colours = []
    for v in bm.verts:
        n = v.normal
        origin = v.co + n*NUDGE
        hits = 0
        for d in _hemisphere(n, RAYS, rng):
            loc, normal, index, dist = tree.ray_cast(origin, d, DISTANCE)
            # A ray starting inside another part hits its back face: ignore it.
            if loc is not None and normal.dot(d) < 0:
                hits += 1 - dist/DISTANCE
        ao = max(FLOOR, 1 - STRENGTH*hits/RAYS*1.6)
        c = [ao, ao, ao]
        if skin[v.index]:
            w = 0.
            for centre, radius, k in BLUSH:
                w = max(w, k*math.exp(-((v.co-Vector(centre)).length/radius)**2*2))
            c = [c[i]*(1-w+w*BLUSH_TINT[i]) for i in range(3)]
        colours.append(c)
    bm.free()
    attr = body.data.color_attributes.get('Col') or body.data.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    for i, c in enumerate(colours):
        attr.data[i].color = (*c, 1.)
    body.data.color_attributes.active_color = attr
    body.data.color_attributes.render_color_index = body.data.color_attributes.find('Col')
    return len(colours)
