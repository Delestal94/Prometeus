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
import math
import bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

RAYS = 96
# Neighbour-averaging passes over the finished occlusion.
SMOOTHING = 4
DISTANCE = .45      # BU (0.22 m in game): only near geometry occludes
STRENGTH = .55
FLOOR = .58         # darkest a vertex may get
NUDGE = .004

# (centre, radius, strength), BU at rest: cheeks, nose tip, ears.
# The cheeks sit on the cheekbones, beside and under the eyes.
BLUSH = [((.42, -.40, 2.76), .18, 1.), ((-.42, -.40, 2.76), .18, 1.),
         ((0, -.60, 2.84), .08, .8),
         ((.62, .03, 2.83), .12, .45), ((-.62, .03, 2.83), .12, .45)]
BLUSH_TINT = (1.0, .70, .66)   # multiplies the skin at full blush (linear)

def _hemisphere(n, count):
    """Cosine-weighted directions around the normal n: the same even
    (Fibonacci) pattern at every vertex. Random rays gave each vertex its own
    noise, which the long triangles of a limb stretched into vertical
    stripes down the calves."""
    t = n.orthogonal().normalized(); b = n.cross(t)
    out = []
    for i in range(count):
        u, v = (i+.5)/count, (i*0.6180339887) % 1.
        r, a = math.sqrt(u), 2*math.pi*v
        out.append((t*(r*math.cos(a)) + b*(r*math.sin(a)) + n*math.sqrt(1-u)).normalized())
    return out

def apply(body, skin_material='Skin'):
    """Writes a point colour attribute 'Col' on body (object mode, rest pose)."""
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
        for d in _hemisphere(n, RAYS):
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
    # Soften what is left over the mesh edges (the blush is smooth already).
    neighbours = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    for _ in range(SMOOTHING):
        colours = [[.5*c[k] + .5*sum(colours[j][k] for j in nb)/len(nb) for k in range(3)] if nb else c
                   for c, nb in zip(colours, neighbours)]
    bm.free()
    attr = body.data.color_attributes.get('Col') or body.data.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    for i, c in enumerate(colours):
        attr.data[i].color = (*c, 1.)
    body.data.color_attributes.active_color = attr
    body.data.color_attributes.render_color_index = body.data.color_attributes.find('Col')
    return len(colours)
