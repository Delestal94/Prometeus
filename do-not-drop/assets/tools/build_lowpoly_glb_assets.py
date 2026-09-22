"""Build the authored low-poly GLB library for Do Not Drop.

Run with Blender in background mode from this folder's project root.  Materials
are embedded in each GLB so Godot can import every model without an external
texture dependency; this matches the project's flat-colour art direction.
"""
import bpy
import math
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ARCH = os.path.join(ROOT, "models", "architecture")
FOREST = os.path.join(ROOT, "models", "environment", "forest")
PROPS = os.path.join(ROOT, "models", "environment", "props")
CARGO = os.path.join(ROOT, "models", "cargo")
VEHICLES = os.path.join(ROOT, "models", "vehicles")
for directory in (ARCH, FOREST, PROPS, CARGO, VEHICLES):
    os.makedirs(directory, exist_ok=True)
os.makedirs(FOREST, exist_ok=True)

PALETTE = {
    "wall": (0.66, 0.46, 0.30, 1), "plaster": (0.78, 0.66, 0.48, 1),
    "roof": (0.36, 0.12, 0.08, 1), "roof_blue": (0.10, 0.22, 0.28, 1),
    "wood": (0.28, 0.13, 0.055, 1), "window": (0.20, 0.48, 0.58, 1),
    "trim": (0.91, 0.79, 0.52, 1), "chimney": (0.30, 0.24, 0.22, 1),
    "trunk": (0.22, 0.10, 0.035, 1), "birch": (0.72, 0.70, 0.57, 1),
    "leaf_dark": (0.06, 0.26, 0.10, 1), "leaf": (0.12, 0.40, 0.15, 1),
    "leaf_light": (0.28, 0.54, 0.14, 1), "fern": (0.08, 0.34, 0.13, 1),
    "grass": (0.25, 0.47, 0.16, 1), "flower": (0.93, 0.55, 0.24, 1),
    "mushroom": (0.76, 0.16, 0.10, 1), "stone": (0.30, 0.36, 0.32, 1),
    "metal": (0.22, 0.31, 0.34, 1),
    "cardboard": (0.54, 0.31, 0.13, 1), "tape": (0.87, 0.67, 0.18, 1),
    "danger": (0.83, 0.16, 0.08, 1), "orange": (0.95, 0.31, 0.05, 1),
    "rubber": (0.035, 0.045, 0.04, 1), "car_blue": (0.07, 0.28, 0.52, 1),
    "car_red": (0.62, 0.07, 0.05, 1), "lamp": (1.0, 0.75, 0.24, 1),
}
MATS = {}

def mat(name):
    if name not in MATS:
        m = bpy.data.materials.new(name)
        m.diffuse_color = PALETTE[name]
        # glTF reads the Principled BSDF base colour, not Blender's viewport
        # `diffuse_color`. Resolve it by node type rather than a UI label so the
        # exporter remains valid across Blender 5.x localisations/builds.
        m.use_nodes = True
        principled = next((node for node in m.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
        if principled is None:
            raise RuntimeError("Principled BSDF missing for material %s" % name)
        principled.inputs["Base Color"].default_value = PALETTE[name]
        principled.inputs["Roughness"].default_value = 0.88
        m.roughness = 0.88
        MATS[name] = m
    return MATS[name]

def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

def cube(name, loc, scale, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object; o.name = name; o.scale = (scale[0]/2, scale[1]/2, scale[2]/2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new("SoftEdges", "BEVEL"); mod.width = bevel; mod.segments = 1
        bpy.context.view_layer.objects.active = o; bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mat(material)); return o

def cone(name, loc, radius1, radius2, depth, material, verts=8):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius1, radius2=radius2, depth=depth, location=loc)
    o = bpy.context.object; o.name = name; o.data.materials.append(mat(material)); return o

def uv_sphere(name, loc, scale, material):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat(material)); return o

def export(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_materials="EXPORT", export_apply=True)

def roof(name, z, width, depth, material):
    # Two pitched halves, clear low-poly roof silhouette.
    for x, angle in [(-width*0.25, -0.48), (width*0.25, 0.48)]:
        o = cube(name, (x, 0, z), (width*0.58, depth*1.1, 0.20), material, 0.04)
        o.rotation_euler[1] = angle

def house(variant):
    clear()
    if variant == "cottage":
        wall, roofmat, width, depth = "plaster", "roof", 5.5, 4.5
    elif variant == "cabin":
        wall, roofmat, width, depth = "wall", "roof_blue", 5.0, 4.1
    else:
        wall, roofmat, width, depth = "plaster", "roof_blue", 6.2, 4.8
    cube("HouseWalls", (0, 0, 1.55), (width, depth, 3.1), wall, 0.08)
    roof("PitchedRoof", 3.35, width, depth, roofmat)
    cube("FrontDoor", (0, depth/2 + .035, 1.05), (1.12, .10, 2.1), "wood", 0.03)
    cube("DoorTrim", (0, depth/2 + .065, 2.18), (1.36, .11, .15), "trim")
    for x in (-width*.30, width*.30):
        cube("Window", (x, depth/2 + .04, 1.95), (.95, .09, .85), "window", .02)
        cube("WindowTrim", (x, depth/2 + .075, 2.43), (1.12, .12, .08), "trim")
    cube("Porch", (0, depth/2+.65, .15), (2.8, 1.35, .30), "wood", .04)
    for x in (-1.1, 1.1): cube("PorchPost", (x, depth/2+.95, 1.25), (.13, .13, 2.2), "wood")
    cube("Chimney", (width*.27, -depth*.18, 4.15), (.55, .55, 1.85), "chimney")
    if variant == "cabin":
        for z in (.65, 1.3, 1.95, 2.6): cube("LogTrim", (0, depth/2+.06, z), (width*.96, .12, .07), "trim")
    if variant == "bungalow":
        cube("SideBay", (-width*.42, depth*.12, 1.35), (1.45, 1.55, 2.7), wall, .05)
    export(os.path.join(ARCH, "sm_arch_delivery_house_%s.glb" % variant))

def tree_oak():
    clear(); cone("Trunk", (0,0,2.25), .38, .26, 4.5, "trunk", 7)
    for p,s,c in [((-1,0,4.4),(1.9,1.7,1.55),"leaf_dark"), ((.95,.1,4.7),(1.75,1.55,1.65),"leaf"), ((0,-.25,6.0),(1.7,1.55,1.5),"leaf_light")]: uv_sphere("OakCrown", p, s, c)
def tree_birch():
    clear(); cone("BirchTrunk", (0,0,3.2), .22, .14, 6.4, "birch", 7)
    for z,x in [(3.7,-.38),(4.8,.35),(5.8,-.2),(6.6,.2)]: uv_sphere("BirchLeaves", (x,0,z), (1.05,.9,1.1), "leaf")
def tree_pine():
    clear(); cone("PineTrunk",(0,0,3),.25,.14,6,"trunk",7)
    for z,r in [(3.0,1.65),(4.35,1.3),(5.55,.9),(6.55,.52)]: cone("PineTier",(0,0,z),r,.06,2.2,"leaf_dark" if z<4 else "leaf",8)
def tree_maple():
    clear(); cone("MapleTrunk",(0,0,2.5),.33,.19,5,"trunk",7)
    for p in [(-.9,0,4.8),(.85,0,4.7),(0,.1,5.8),(0,0,4.0)]: uv_sphere("MapleCrown",p,(1.55,1.35,1.35),"leaf_light")
def tree_dead():
    clear(); cone("DeadTrunk",(0,0,2.7),.32,.12,5.4,"trunk",6)
    for angle,z in [(.72,4.2),(-.85,3.8),(1.7,4.65)]:
        b=cone("BareBranch",(0,0,z),.10,.035,2.2,"trunk",6); b.rotation_euler[1]=angle
def tree_sapling():
    clear(); cone("SaplingTrunk",(0,0,1.5),.11,.055,3,"trunk",6)
    for z,r in [(1.9,.7),(2.55,.5),(3.05,.27)]: cone("SaplingFoliage",(0,0,z),r,.03,.9,"leaf_light",7)

def bush():
    clear()
    for p,s in [((0,0,.45),(1.05,.85,.7)), ((.65,.1,.52),(.75,.7,.7)), ((-.65,0,.48),(.7,.65,.65))]: uv_sphere("Bush",p,s,"leaf")
def fern():
    clear()
    for i in range(9):
        a=i*math.tau/9; leaf=cube("FernFrond",(math.cos(a)*.42,math.sin(a)*.42,.23),(.18,.72,.06),"fern"); leaf.rotation_euler=(0.38,0,a)
def grass():
    clear()
    for i in range(12):
        a=i*math.tau/12; blade=cone("GrassBlade",(math.cos(a)*.22,math.sin(a)*.22,.28),.07,.012,.7,"grass",4); blade.rotation_euler[1]=.25
def flowers():
    clear(); cone("FlowerStem",(0,0,.35),.035,.02,.7,"grass",5)
    for a in range(5): uv_sphere("Petal",(math.cos(a*math.tau/5)*.16,math.sin(a*math.tau/5)*.16,.74),(.16,.08,.06),"flower")
    uv_sphere("FlowerCenter",(0,0,.74),(.08,.08,.08),"trim")
def mushroom():
    clear(); cone("MushroomStem",(0,0,.20),.11,.09,.4,"plaster",8); cone("MushroomCap",(0,0,.46),.38,.08,.25,"mushroom",10)
def log():
    clear(); o=cone("FallenLog",(0,0,.32),.28,.24,2.8,"trunk",8); o.rotation_euler[1]=math.pi/2
    for x in (-.7,.45): cone("LogBranch",(x,.18,.55),.09,.035,.9,"trunk",6).rotation_euler[1]=.8
def rock():
    clear(); uv_sphere("ForestRock",(0,0,.35),(.75,.55,.45),"stone")

def cargo_box(kind):
    clear()
    dims = {"fragile": (1.15, .85, .9), "vented": (1.2, .9, .95), "balance": (.72, .72, 1.55), "heavy": (1.35, 1.05, .72)}[kind]
    cube("CargoBox", (0, 0, dims[2]/2), dims, "cardboard", .045)
    cube("PackingTape", (0, 0, dims[2]+.01), (dims[0]*.25, dims[1]*1.02, .035), "tape")
    cube("ShippingLabel", (0, dims[1]/2+.012, dims[2]*.60), (dims[0]*.38, .025, dims[2]*.22), "plaster")
    if kind == "fragile":
        for x in (-.28, .28): cone("FragileMarker", (x, dims[1]/2+.03, dims[2]*.6), .11, .11, .035, "danger", 3).rotation_euler[0] = math.pi/2
    elif kind == "vented":
        for x in (-.35, 0, .35): cube("Vent", (x, dims[1]/2+.03, dims[2]*.62), (.12,.03,.25), "rubber")
    elif kind == "balance":
        cube("BalanceBand", (0,0,dims[2]*.55), (dims[0]*1.03,dims[1]*1.03,.12), "tape")
    else:
        for x in (-.4,.4): cube("HeavyStrap", (x,0,dims[2]*.5), (.11,dims[1]*1.04,dims[2]*1.04), "rubber")
    export(os.path.join(CARGO, "sm_cargo_package_%s.glb" % kind))

def parked_car(kind):
    clear(); color = "car_blue" if kind == "hatchback" else "car_red"
    cube("CarBody", (0,0,.65), (3.8,1.65,.75), color, .16)
    cube("Cabin", (-.25,0,1.23), (2.05,1.48,.72), "window", .12)
    for x in (-1.25,1.25):
        for y in (-.88,.88):
            wheel=cone("Wheel",(x,y,.38),.42,.42,.22,"rubber",10); wheel.rotation_euler[0]=math.pi/2
    for x in (-1.85,1.85):
        cube("Light",(x,-.01,.73),(.10,1.25,.19),"lamp" if x<0 else "danger",.03)
    if kind == "pickup": cube("CargoBed", (1.15,0,1.0), (1.25,1.55,.42), "car_red", .07)
    export(os.path.join(VEHICLES, "sm_vehicle_parked_%s.glb" % kind))

def roadside_prop(kind):
    clear()
    if kind == "traffic_cone":
        cone("Cone",(0,0,.42),.27,.055,.8,"orange",8); cone("ReflectiveBand",(0,0,.56),.16,.15,.12,"plaster",8); cube("Base",(0,0,.05),(.52,.52,.1),"rubber",.02)
    elif kind == "road_barrier":
        cube("BarrierBoard",(0,0,.75),(2.2,.18,.72),"danger",.04)
        for x in (-.82,.82): cone("BarrierFoot",(x,0,.32),.17,.17,.64,"orange",8)
        for x in (-.42,.42): cube("WarningStripe",(x,-.105,.75),(.18,.025,.72),"plaster")
    elif kind == "mailbox":
        cube("Post",(0,0,.62),(.12,.12,1.24),"wood")
        cube("Mailbox",(0,0,1.35),(1.05,.62,.52),"car_blue",.10); cube("Flag",(.45,-.35,1.56),(.06,.06,.42),"danger")
    elif kind == "street_lamp":
        cone("LampPost",(0,0,2.7),.12,.08,5.4,"metal",10); cube("LampArm",(.48,0,5.15),(1.0,.12,.12),"metal"); cube("LampHead",(.95,0,4.95),(.4,.32,.24),"lamp",.04)
    elif kind == "bench":
        for z in (.52,.95): cube("BenchSlat",(0,0,z),(2.2,.42,.12),"wood",.02)
        for x in (-.75,.75): cube("BenchLeg",(x,0,.3),(.12,.42,.6),"metal")
    export(os.path.join(PROPS, "sm_env_prop_%s.glb" % kind))

for name in ("cottage", "cabin", "bungalow"): house(name)
for name, fn in {
    "oak": tree_oak, "birch": tree_birch, "pine_tall": tree_pine,
    "maple": tree_maple, "dead": tree_dead, "pine_sapling": tree_sapling,
    "bush_round": bush, "fern": fern, "grass_clump": grass,
    "wildflower": flowers, "mushroom": mushroom, "fallen_log": log, "rock": rock,
}.items():
    fn(); export(os.path.join(FOREST, "sm_env_forest_%s.glb" % name))
for name in ("fragile", "vented", "balance", "heavy"): cargo_box(name)
for name in ("hatchback", "pickup"): parked_car(name)
for name in ("traffic_cone", "road_barrier", "mailbox", "street_lamp", "bench"): roadside_prop(name)
