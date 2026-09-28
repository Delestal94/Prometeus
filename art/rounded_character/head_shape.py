"""The head's shape, shared by build_character.py (which sculpts it) and
render_review.py (which lays the face on it). character_face.gd in the game
repeats FACE_* and the jowl formula: keep the three in step.

Blender units, front -Y, up +Z. The game export scales by 0.5 and turns the
rig to face -Z, so the head centre 2.89 becomes 1.445 m.
"""
import math
from mathutils import Vector

HEAD_CENTRE = Vector((0, 0, 2.89))
HEAD_RADII = (.60, .55, .57)          # x, depth (y), height (z)
HEAD_JOWL = .07                       # extra width at the bottom of the head
FACE_OFFSET = .006                    # the face floats this far off the skin

def smoothstep(a, b, x):
    t = max(0., min(1., (x-a)/(b-a)))
    return t*t*(3-2*t)

def direction(lon, lat):
    """Unit direction for a longitude/latitude on the head (front is -Y)."""
    return Vector((math.sin(lon)*math.cos(lat), -math.cos(lon)*math.cos(lat), math.sin(lat)))

def jowl(dz):
    """Soft jowls: the lower half of the head widens (x and depth)."""
    return 1+HEAD_JOWL*smoothstep(.2, -.8, dz)

# (direction, height, width) bumps pushed out along the surface; the face
# ignores them. The cheeks that were here (2026-09-27) stuck out of the head
# and were taken off; the blush in vertex_shading.py stays.
BUMPS = []

def point(d, bumps=True):
    """Surface point of the head for the unit direction d."""
    p = Vector((HEAD_RADII[0]*d.x*jowl(d.z), HEAD_RADII[1]*d.y*jowl(d.z), HEAD_RADII[2]*d.z))
    if bumps:
        p += p.normalized()*sum(h*math.exp(-(d-c).length_squared/(2*w*w)) for c, h, w in BUMPS)
    return HEAD_CENTRE + p

def face_point(u, v):
    """Where the face texture's (u, v) sits: character_face.gd _patch_point()."""
    d = direction((u-.5)*1.9, (.5-v)*1.5)
    p = point(d, False)-HEAD_CENTRE
    return HEAD_CENTRE + p*(1+FACE_OFFSET/p.length)

def hairline(d):
    """Height (unit direction z) where the short hair starts: high on the
    forehead, just over the ears at the sides, down to the nape at the back."""
    return .12 + .50*max(0., -d.y)**1.3 - .40*max(0., d.y)**1.5
