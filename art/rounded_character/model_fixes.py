"""Weight fixes applied on top of personaje_redondeado.blend at export time.

The modeling file is never saved by the export, so these run every time
(build_game_export.py and any preview script that needs the same skin).
"""
import bpy
from mathutils.kdtree import KDTree

def smoothstep(a, b, x):
    t = max(0., min(1., (x-a)/(b-a)))
    return t*t*(3-2*t)

def smooth_weights(o, inside, iterations):
    """Laplacian smoothing of every vertex group over the mesh edges, for the
    vertices whose world position satisfies inside(); sums stay normalised."""
    n = len(o.data.vertices)
    region = [inside(o.matrix_world @ v.co) for v in o.data.vertices]
    neighbours = [[] for _ in range(n)]
    for e in o.data.edges:
        a, b = e.vertices
        neighbours[a].append(b); neighbours[b].append(a)
    names = [g.name for g in o.vertex_groups]
    w = [dict() for _ in range(n)]
    for v in o.data.vertices:
        for g in v.groups:
            w[v.index][g.group] = g.weight
    for _ in range(iterations):
        new = [dict(x) for x in w]
        for i in range(n):
            if not region[i] or not neighbours[i]:
                continue
            acc = {}
            for j in neighbours[i]:
                for g, x in w[j].items():
                    acc[g] = acc.get(g, 0.) + x/len(neighbours[i])
            mix = {g: .5*w[i].get(g, 0.) + .5*acc.get(g, 0.) for g in set(acc) | set(w[i])}
            total = sum(mix.values()) or 1.
            new[i] = {g: x/total for g, x in mix.items() if x/total > .002}
        w = new
    for i in range(n):
        if not region[i]:
            continue
        for gi in range(len(names)):
            o.vertex_groups[gi].remove([i])
        for g, x in w[i].items():
            o.vertex_groups[g].add([i], x, 'REPLACE')

def apply(rig):
    """Every fix, in order: skin weights, then trimming hidden geometry."""
    reweight(rig)
    trim_hidden(rig)

def reweight(rig):
    meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == rig]
    for o in meshes:
        side = o.name.rsplit('.', 1)[-1]
        # Knee blend centred on the joint (z 0.555) and about a leg radius
        # wide, so deep squats bend the knee instead of denting its front;
        # the hidden rim under the shorts hem (above ~0.62) still follows
        # the thigh, or bent knees pull skin through the front of the shorts.
        if o.name.startswith('Pierna.'):
            for v in o.data.vertices:
                t = smoothstep(.46, .63, v.co.z)
                o.vertex_groups['thigh.'+side].add([v.index], t, 'REPLACE')
                o.vertex_groups['shin.'+side].add([v.index], 1-t, 'REPLACE')
        # Shoes were rigid (all foot): the toe box now bends at the ball, so
        # the toes stay flat on the ground while the heel lifts at push-off.
        if o.name.startswith(('Zapato.', 'Suela.')):
            toe = o.vertex_groups.get('toe.'+side) or o.vertex_groups.new(name='toe.'+side)
            foot = o.vertex_groups['foot.'+side]
            for v in o.data.vertices:
                y = (o.matrix_world @ v.co).y
                t = smoothstep(-.19, -.31, y) if y < -.19 else 0.
                toe.add([v.index], t, 'REPLACE')
                foot.add([v.index], 1-t, 'REPLACE')
    # The shirt's pelvis weight fell from 0.17 to 0 in one ring (z ~1.40),
    # creasing the tummy whenever the spine bends against the pelvis
    # (squats, landings). Relax the lower shirt's weights along its edges.
    shirt = next((o for o in meshes if o.name.startswith('Camiseta · cuerpo')), None)
    if shirt is not None:
        smooth_weights(shirt, lambda p: p.z < 1.7 and abs(p.x) < 1.0, 12)
    # Trim pieces (hems, seams) were skinned on their own and drift from the
    # garment under them when the torso bends: a jagged line shows through.
    # Each vertex takes the weights of the nearest garment vertex.
    # (The shorts cuffs keep their own skin: they must follow the thigh, and
    # the nearest shorts vertex on their inner side belongs to the crotch.)
    for trim, garment in (('Camiseta · dobladillo', 'Camiseta · cuerpo'),
                          ('Cuello · costura', 'Cuello')):
        source = next((o for o in meshes if o.name.startswith(garment) and not o.name.startswith(trim)), None)
        if source is None:
            continue
        tree = KDTree(len(source.data.vertices))
        for v in source.data.vertices:
            tree.insert(source.matrix_world @ v.co, v.index)
        tree.balance()
        for o in (m for m in meshes if m.name.startswith(trim)):
            for g in list(o.vertex_groups):
                o.vertex_groups.remove(g)
            for v in o.data.vertices:
                _, index, _ = tree.find(o.matrix_world @ v.co)
                for g in source.data.vertices[index].groups:
                    name = source.vertex_groups[g.group].name
                    group = o.vertex_groups.get(name) or o.vertex_groups.new(name=name)
                    group.add([v.index], g.weight, 'REPLACE')


# Hidden in the rest pose, but once the thighs swing forward (Sit, Jump) the
# leg tops poke out of the shorts and the shorts' waist out of the shirt:
# each is weighted differently from the garment over it. Cut them where the
# garment still covers the cut (shorts hem 0.577-0.673, shirt hem ~1.11).
TRIM_ABOVE = {'Pierna': .64, 'Short · pieza': 1.3}

def trim_hidden(rig):
    import bmesh
    for o in [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == rig]:
        limit = next((z for k, z in TRIM_ABOVE.items() if o.name.startswith(k)), None)
        if limit is None:
            continue
        bm = bmesh.new(); bm.from_mesh(o.data)
        doomed = [v for v in bm.verts if (o.matrix_world @ v.co).z > limit]
        bmesh.ops.delete(bm, geom=doomed, context='VERTS')
        bm.to_mesh(o.data); bm.free()
