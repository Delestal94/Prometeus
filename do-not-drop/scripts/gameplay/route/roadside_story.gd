extends Node3D
class_name RoadsideStory
## Little stories by the road (tareas de Nacho N-602): rare, static scenes a
## driver catches out of the corner of an eye, telling the game's premise
## without a word of tutorial. RouteDresser puts up at most one every
## MIN_GAP metres (_dress_roadside_stories()); `kind` picks which:
##
##   VAN_SPILL  the competition's van nosed into the ditch, back door hanging
##              open, its parcels strewn across the grass;
##   HEN        a hen pecking about next to the box she broke out of;
##   BILLBOARD  "TAKE MY PACKAGE -- entregamos (casi) todo" on a billboard.
##
## Built in _ready() from the existing models, the same for every peer (all
## the scatter comes from `story_seed`). Only what the truck could really
## hit is solid: the van's body and the billboard's legs.

enum Kind { VAN_SPILL, HEN, BILLBOARD }

## How much ground each kind claims around its origin (RouteDresser keeps
## other things out of it).
const FOOTPRINT: Dictionary = {Kind.VAN_SPILL: 5.5, Kind.HEN: 1.6, Kind.BILLBOARD: 4.8}
## How close each gets to the road, from its origin (for the dresser's road check).
const REACH: Dictionary = {Kind.VAN_SPILL: 3.2, Kind.HEN: 1.0, Kind.BILLBOARD: 4.8}
const VAN: String = "res://assets/models/vehicles/sm_vehicle_competitor_van.glb"
const BOXES: Array[String] = [
	"res://assets/models/cargo/sm_cargo_box_cube.glb", "res://assets/models/cargo/sm_cargo_box_flat.glb",
	"res://assets/models/cargo/sm_cargo_box_tall.glb",
]
const HEN_MODEL: String = "res://assets/models/cargo/contents/sm_cargo_content_hen.glb"
const FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const BILLBOARD_SIZE := Vector2(8.4, 3.4)
const BILLBOARD_HEIGHT: float = 2.6
## Text keeps this far in from the panel's edges; a line that wouldn't fit
## (a longer translation of the slogan too) is set smaller until it does.
const BILLBOARD_TEXT_MARGIN: float = 0.45
const BILLBOARD_PIXEL_SIZE: float = 0.01
const BRAND_TEAL := Color("1f8a86")
const BRAND_CREAM := Color("f3ecd8")
const BRAND_ORANGE := Color("e8862b")
const HEN_PECK_SECONDS: float = 1.6
## How far the spilled van's nose is tipped down into the ditch (before
## fit_to_ground() knows the real ground).
const VAN_NOSE_DOWN_DEG: float = 13.0
## Once it does: the front bumper this far into the ground, the back wheels
## this far off it -- nose-down on any slope, not just on the flat.
const VAN_NOSE_BURIED: float = 0.45
const VAN_TAIL_LIFT: float = 0.4
## The van model's nose and tail along its length (its -Z is the nose).
const VAN_NOSE_Z: float = -2.6
const VAN_TAIL_Z: float = 2.3

@export var kind: Kind = Kind.BILLBOARD
@export var story_seed: int = 0

var _hen: Node3D
var _van: Node3D
var _van_collision: Node3D
var _time: float = 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = story_seed
	match kind:
		Kind.VAN_SPILL:
			_build_van_spill(rng)
		Kind.HEN:
			_build_hen(rng)
		Kind.BILLBOARD:
			_build_billboard()
	set_process(kind == Kind.HEN)


## The hen pecks: head down, up again, now and then.
func _process(delta: float) -> void:
	if _hen == null:
		return
	_time += delta
	var phase: float = fmod(_time, HEN_PECK_SECONDS) / HEN_PECK_SECONDS
	_hen.rotation.x = -0.45 * maxf(0.0, sin(phase * TAU * 2.0)) if phase < 0.5 else 0.0


func _build_van_spill(rng: RandomNumberGenerator) -> void:
	# Nose down into the ditch, turned away from the road, one side sagging.
	# The model's nose is its -Z, so a negative pitch tips it down: the
	# front bumper digs in about half a metre, the back wheels come off the
	# grass.
	var van := _model(VAN)
	van.name = "CompetitorVan"
	van.rotation = Vector3(deg_to_rad(-VAN_NOSE_DOWN_DEG), deg_to_rad(28.0 + rng.randf_range(-8.0, 8.0)), deg_to_rad(-7.0))
	van.position = Vector3(0.0, -0.08, 0.0)
	add_child(van)
	# The back door, swung wide open on its hinge (the model's door is part
	# of the body): a slab in the body's own colour.
	var body_material: Material = _first_material(van.find_child("CargoBody", true, false))
	var door := MeshInstance3D.new()
	door.name = "BackDoorOpen"
	var slab := BoxMesh.new()
	slab.size = Vector3(1.05, 1.8, 0.06)
	door.mesh = slab
	door.material_override = body_material
	var hinge := Node3D.new()
	hinge.name = "BackDoorHinge"
	hinge.position = Vector3(1.08, 1.45, 2.12)
	hinge.rotation.y = deg_to_rad(105.0)
	hinge.add_child(door)
	door.position = Vector3(-0.53, 0.0, 0.0)
	van.add_child(hinge)
	var solid := _solid_box("VanCollision", Vector3(2.3, 2.4, 5.3), Vector3(0.0, 1.2, 0.0))
	solid.transform = van.transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.0))
	_van = van
	_van_collision = solid
	# Parcels strewn out of the back and down the grass.
	var behind: Vector3 = van.transform * Vector3(0.0, 0.0, 3.2)
	for index: int in range(6):
		var box := _model(BOXES[index % BOXES.size()])
		box.name = "SpilledBox%d" % index
		var spread := Vector3(rng.randf_range(-2.6, 2.6), 0.0, rng.randf_range(0.0, 3.2))
		box.position = behind + van.basis * spread
		box.position.y = 0.0
		box.rotation = Vector3(deg_to_rad(rng.randf_range(-12.0, 12.0)), rng.randf() * TAU, deg_to_rad(rng.randf_range(-90.0, 90.0) if index % 3 == 0 else rng.randf_range(-10.0, 10.0)))
		add_child(box)


func _build_hen(rng: RandomNumberGenerator) -> void:
	var box := _model(BOXES[0])
	box.name = "BrokenBox"
	# On its side, flaps burst open, a little crushed.
	box.rotation = Vector3(0.0, rng.randf() * TAU, deg_to_rad(84.0))
	box.scale = Vector3(1.0, 0.85, 1.0)
	box.position = Vector3(0.0, 0.32, 0.0)
	for flap_name: String in ["FlapFront", "FlapBack", "FlapLeft", "FlapRight"]:
		var flap := box.find_child(flap_name, true, false) as Node3D
		if flap != null:
			flap.rotation.x += deg_to_rad(rng.randf_range(60.0, 120.0)) * (1.0 if flap_name in ["FlapFront", "FlapRight"] else -1.0)
	add_child(box)
	_hen = _model(HEN_MODEL)
	_hen.name = "Hen"
	# Only the live hen: the model also carries her "ruined" pieces for the
	# box's contents view.
	for child: Node in _hen.get_children():
		if child is Node3D and child.name != "Intact":
			(child as Node3D).visible = false
	_hen.position = Vector3(rng.randf_range(0.9, 1.3), 0.0, rng.randf_range(-0.6, 0.6))
	_hen.rotation.y = rng.randf() * TAU
	_hen.scale = Vector3.ONE * 1.4
	add_child(_hen)


func _build_billboard() -> void:
	var top: float = BILLBOARD_HEIGHT + BILLBOARD_SIZE.y
	var legs := StaticBody3D.new()
	legs.name = "BillboardCollision"
	legs.collision_layer = 1
	legs.collision_mask = 0
	add_child(legs)
	for x: float in [-BILLBOARD_SIZE.x * 0.35, BILLBOARD_SIZE.x * 0.35]:
		_box("Leg", Vector3(0.22, top, 0.22), Vector3(x, top * 0.5, -0.2), Color("5b4a3a"))
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(0.26, top, 0.26)
		shape.shape = box_shape
		shape.position = Vector3(x, top * 0.5, -0.2)
		legs.add_child(shape)
	var center_y: float = BILLBOARD_HEIGHT + BILLBOARD_SIZE.y * 0.5
	_box("Board", Vector3(BILLBOARD_SIZE.x, BILLBOARD_SIZE.y, 0.12), Vector3(0.0, center_y, 0.0), BRAND_TEAL)
	_box("Panel", Vector3(BILLBOARD_SIZE.x - 0.3, BILLBOARD_SIZE.y - 0.3, 0.13), Vector3(0.0, center_y, 0.0), BRAND_CREAM)
	_box("Stripe", Vector3(BILLBOARD_SIZE.x - 0.3, 0.42, 0.14), Vector3(0.0, BILLBOARD_HEIGHT + 0.36, 0.0), BRAND_ORANGE)
	var text_width: float = BILLBOARD_SIZE.x - 0.3 - BILLBOARD_TEXT_MARGIN * 2.0
	_text("Brand", "TAKE MY PACKAGE", Vector3(0.0, center_y + 0.55, 0.08), fit_font_size("TAKE MY PACKAGE", 130, text_width), BRAND_TEAL)
	var slogan: String = tr("WORLD_BILLBOARD_SLOGAN")
	_text("Slogan", slogan, Vector3(0.0, center_y - 0.45, 0.08), fit_font_size(slogan, 80, text_width), Color("3a2f25"))
	# A parcel sitting on the top edge (the box's origin is its base), off
	# the lettering, one corner hanging out over the front.
	var parcel := _model(BOXES[0])
	parcel.name = "BillboardParcel"
	parcel.scale = Vector3.ONE * 1.6
	parcel.position = Vector3(BILLBOARD_SIZE.x * 0.5 - 0.8, top, 0.2)
	parcel.rotation = Vector3(0.0, deg_to_rad(-18.0), 0.0)
	add_child(parcel)


## The largest size up to `font_size` at which `text` spans no more than
## `max_width` metres on the billboard.
static func fit_font_size(text: String, font_size: int, max_width: float) -> int:
	var size: int = font_size
	while size > 8 and FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * BILLBOARD_PIXEL_SIZE > max_width:
		size -= 2
	return size


## Rests every loose piece on the ground under it: the story is placed as a
## whole (RouteDresser._settle()), but beside a road the ground slopes, and
## pieces at the story's own height floated over a dip or sank into a rise.
## `height_at` takes a point in this node's space and returns the ground's
## height there, in the same space. The van is pitched so its nose digs in
## and its tail lifts whatever the slope does.
func fit_to_ground(height_at: Callable) -> void:
	for child: Node in get_children():
		if not child is Node3D or child == _van or child == _van_collision or child is StaticBody3D:
			continue
		var piece := child as Node3D
		if piece.name.begins_with("Spilled") or piece.name in ["BrokenBox", "Hen"]:
			var base_offset: float = piece.position.y if piece.name == "BrokenBox" else 0.0
			piece.position.y = float(height_at.call(piece.position)) + base_offset
	if _van == null:
		return
	var yaw := Basis(Vector3.UP, _van.rotation.y)
	var nose_at: Vector3 = _van.position + yaw * Vector3(0.0, 0.0, VAN_NOSE_Z)
	var tail_at: Vector3 = _van.position + yaw * Vector3(0.0, 0.0, VAN_TAIL_Z)
	var nose_y: float = float(height_at.call(nose_at)) - VAN_NOSE_BURIED
	var tail_y: float = float(height_at.call(tail_at)) + VAN_TAIL_LIFT
	# Rising toward the tail (+Z) is a negative pitch about X: nose down.
	var pitch: float = -atan2(tail_y - nose_y, VAN_TAIL_Z - VAN_NOSE_Z)
	_van.rotation.x = pitch
	# The pivot sits between the two, where the line through them passes.
	var along: float = -VAN_NOSE_Z / (VAN_TAIL_Z - VAN_NOSE_Z)
	_van.position.y = lerpf(nose_y, tail_y, along)
	_van_collision.transform = _van.transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.0))


func _model(path: String) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	LowpolyMaterials.apply(node)
	return node


func _first_material(node: Node) -> Material:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_node := node as MeshInstance3D
		var material: Material = mesh_node.get_surface_override_material(0) if mesh_node.get_surface_override_material_count() > 0 else null
		return material if material != null else mesh_node.mesh.surface_get_material(0)
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color("d9d4c8")
	return fallback


func _solid_box(node_name: String, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child(body)
	return body


func _box(node_name: String, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = at
	add_child(node, true)


func _text(node_name: String, text: String, at: Vector3, font_size: int, color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font = FONT
	label.font_size = font_size
	label.pixel_size = BILLBOARD_PIXEL_SIZE
	label.modulate = color
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = at
	add_child(label)
