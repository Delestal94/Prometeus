extends Node3D
class_name ServiceStop
## The station itself (tareas de Nacho N-110): its own low-poly models
## (N-110.1, assets/tools/build_service_station.py) folded into batches with
## the depot's kit (DepotKit) -- a canopy over two
## pumps, a kiosk with the counter, a lit price pole that shows from far off,
## and a pile of crates at the back where a hidden cosmetic will go (N-311,
## see hidden_cosmetic_spot). The lay-by in front of it and the signs that
## announce it are the segment's (ServiceStopSegment); what the counter sells
## is ServiceStopShop.
##
## Local space is the segment's: the station's origin is its middle along the
## road, +X is the driver's right, the road runs toward -Z. Every visible piece
## is a rigid part with the "rigid" meta, so on the delivery route the terrain
## (RouteTerrain.conform_geometry) lifts each one to the ground under it, and
## the counter is an Area3D, which it lifts too. Nothing here reads a random
## number: the station is the same everywhere.
##
## Costs: ~40 draw calls (a batch per palette material per part), all of them hidden
## beyond VIEW_RANGE metres and scaled down by WorldQuality; nothing runs per
## frame. It frees with its segment.

const COUNTER: Script = preload("res://scripts/gameplay/route/service_counter.gd")
const SHOP: Script = preload("res://scripts/gameplay/route/service_stop_shop.gd")
const SIGN_FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
## How far the station is still drawn (WorldQuality scales it on low).
const VIEW_RANGE: float = 240.0
## The lay-by, in this node's space: where a truck counts as pulled in.
const BAY_X: Vector2 = Vector2(5.8, 12.8)
const BAY_Z: Vector2 = Vector2(-20.0, 18.0)
## The station's own models (assets/tools/build_service_station.py, N-110.1);
## DepotKit caches each once loaded.
const MODELS: Array[String] = ["sm_env_service_canopy", "sm_env_service_pump", "sm_env_service_kiosk",
		"sm_env_service_totem", "sm_env_service_crates", "sm_env_service_drum"]
const MODEL_DIR: String = "res://assets/models/environment/service/%s.glb"
## Top of the pump islands on the forecourt slab, where the pumps stand.
const ISLAND_TOP: float = 0.22
## The pallet of crates behind the kiosk, in the kiosk's space: next to (not
## over) the hidden cosmetic's spot.
const CRATES_AT := Vector3(4.0, 0.0, 5.5)
## Where the hidden cosmetic will be found (N-311): behind the kiosk, a few
## metres off the beaten path.
const COSMETIC_AT := Vector3(23.0, 0.1, 6.5)

## The ground the station stands on, in the parent segment's space (the
## segment sets it before the node enters the tree).
var ground_y: float = -0.3
## Anchor for N-311: a Marker3D, also in the group &"hidden_cosmetic_spot".
var hidden_cosmetic_spot: Marker3D
var counter: Node
var shop: Node


func _ready() -> void:
	add_to_group(&"service_stop")
	_build_forecourt()
	_build_kiosk()
	_build_totem()
	shop = SHOP.new()
	shop.name = "Shop"
	add_child(shop)
	counter = COUNTER.new()
	counter.name = "Counter"
	counter.set(&"shop", shop)
	counter.position = Vector3(16.2, ground_y + 1.15, -1.2)
	add_child(counter)
	hidden_cosmetic_spot = Marker3D.new()
	hidden_cosmetic_spot.name = "HiddenCosmeticSpot"
	hidden_cosmetic_spot.position = COSMETIC_AT + Vector3(0.0, ground_y, 0.0)
	hidden_cosmetic_spot.set_meta(&"rigid", true)
	hidden_cosmetic_spot.add_to_group(&"hidden_cosmetic_spot")
	add_child(hidden_cosmetic_spot)


## Loads the borrowed props now, for a level that lays stations while it runs
## (Endless): the first station then doesn't read them in the tick that builds it.
static func warm_models() -> void:
	for model_name: String in MODELS:
		DepotKit.merged_mesh(model_path(model_name))


## Path of one of the station's models, by file name without extension.
static func model_path(model_name: String) -> String:
	return MODEL_DIR % model_name


## Whether a world point is on the lay-by (a truck pulled in to shop). The
## levels use it to not count a crew that parked here as stuck.
func in_bay(world_point: Vector3) -> bool:
	var local: Vector3 = to_local(world_point)
	return local.x >= BAY_X.x and local.x <= BAY_X.y and local.z >= BAY_Z.x and local.z <= BAY_Z.y \
			and absf(local.y - ground_y) < 6.0


# --- Building ------------------------------------------------------------------


## Canopy over two pumps, on a slab that sets the forecourt off from the yard.
## What shows is the station's own model (assets/tools/build_service_station.py);
## the colliders and the glowing strips (canopy light, pump screens) stay here.
func _build_forecourt() -> void:
	var part := _part("Forecourt", Vector3(14.6, ground_y, 0.0))
	var kit := DepotKit.new(part, "Colliders")
	kit.model(model_path(MODELS[0]), Transform3D.IDENTITY)
	for x: float in [-2.3, 2.3]:
		for z: float in [-4.4, 4.4]:
			kit.collider(Vector3(0.3, 4.6, 0.3), Transform3D(Basis.IDENTITY, Vector3(x, 1.8, z)))
	kit.box(Vector3(4.6, 0.05, 9.4), Vector3(0.0, 3.84, 0.0), DepotKit.glow(Color("ffe2a0"), 1.3))
	for z: float in [-2.8, 2.8]:
		kit.model(model_path(MODELS[1]), Transform3D(Basis.IDENTITY, Vector3(-1.6, ISLAND_TOP, z)))
		kit.collider(Vector3(0.6, 1.5, 0.85), Transform3D(Basis.IDENTITY, Vector3(-1.6, 0.75, z)))
		kit.box(Vector3(0.02, 0.32, 0.5), Vector3(-1.935, ISLAND_TOP + 1.1, z), DepotKit.glow(Color("9fe3c8"), 1.2))
	_finish(kit)


## Kiosk with its counter on the side facing the lay-by, an awning over it,
## a door, a window, the sign over the front, and the crates at the back.
func _build_kiosk() -> void:
	var part := _part("Kiosk", Vector3(19.9, ground_y, 0.0))
	var kit := DepotKit.new(part, "Colliders")
	# The model's walls go 0.6 m below the ground so a slope never opens a gap under them.
	kit.model(model_path(MODELS[2]), Transform3D.IDENTITY)
	kit.collider(Vector3(4.6, 3.8, 8.6), Transform3D(Basis.IDENTITY, Vector3(0.0, 1.3, 0.0)))
	kit.collider(Vector3(0.9, 1.05, 3.4), Transform3D(Basis.IDENTITY, Vector3(-2.75, 0.525, -1.2)))
	# Gas bottles in their cage at the back.
	kit.collider(Vector3(0.8, 1.2, 1.5), Transform3D(Basis.IDENTITY, Vector3(2.75, 0.6, 1.0)))
	# A pallet of crates and a drum at the back, beside N-311's hidden spot.
	var crates := Transform3D(Basis(Vector3.UP, 0.25), CRATES_AT)
	kit.model(model_path(MODELS[4]), crates)
	kit.collider(Vector3(1.2, 1.3, 1.2), crates * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.65, 0.0)))
	kit.model(model_path(MODELS[5]), Transform3D(Basis.IDENTITY, Vector3(3.2, 0.0, 4.4)))
	kit.collider(Vector3(0.6, 0.9, 0.6), Transform3D(Basis.IDENTITY, Vector3(3.2, 0.45, 4.4)))
	_finish(kit)
	_label(part, tr("WORLD_SERVICE_KIOSK_SIGN"), Vector3(-2.62, 3.55, 0.0), -PI * 0.5, 72, Color("ece7d8"), 0.006,
			5.6)


## A tall pole with a lit board, ahead of the lay-by: what a driver reads from
## far off, before the signs say anything.
func _build_totem() -> void:
	var part := _part("Totem", Vector3(13.4, ground_y, 27.0))
	var kit := DepotKit.new(part, "Colliders")
	kit.model(model_path(MODELS[3]), Transform3D.IDENTITY)
	kit.collider(Vector3(0.32, 7.6, 0.32), Transform3D(Basis.IDENTITY, Vector3(0.0, 3.4, 0.0)))
	kit.box(Vector3(2.7, 0.14, 0.26), Vector3(0.0, 7.36, 0.0), DepotKit.glow(Color("e7be51"), 1.3))
	kit.box(Vector3(2.7, 0.14, 0.26), Vector3(0.0, 5.64, 0.0), DepotKit.glow(Color("65b5a1"), 1.0))
	_finish(kit)
	var title: Label3D = _label(part, tr("WORLD_SERVICE_TOTEM_TITLE"), Vector3(0.0, 6.75, 0.13), 0.0, 110,
			Color("f3e9c9"), 0.008)
	_label(part, tr("WORLD_SERVICE_TOTEM_TEXT"), Vector3(0.0, 6.05, 0.13), 0.0, 54, Color("9fe3c8"), 0.006)
	title.double_sided = true


func _part(part_name: String, at: Vector3) -> Node3D:
	var part := Node3D.new()
	part.name = part_name
	part.position = at
	part.set_meta(&"rigid", true)
	add_child(part)
	return part


## Batches the kit's boxes and applies the quality range to every batch.
func _finish(kit: DepotKit) -> void:
	for instance: MeshInstance3D in kit.commit("Batch"):
		instance.visibility_range_end = VIEW_RANGE * WorldQuality.setting("range_scale")
		instance.set_meta(WorldQuality.BASE_RANGE_META, VIEW_RANGE)


## A caption on a part, shrunk to fit if another language runs long.
func _label(parent: Node3D, text: String, at: Vector3, yaw: float, font_size: int, colour: Color,
		pixel: float, max_width: float = 2.5) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = SIGN_FONT
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = colour
	label.outline_size = 0
	label.position = at
	label.rotation.y = yaw
	label.double_sided = false
	var wide: float = SIGN_FONT.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * pixel
	if wide > max_width:
		label.font_size = maxi(int(floor(font_size * max_width / wide)), 8)
	parent.add_child(label)
	return label
