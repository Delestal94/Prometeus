extends RefCounted
## The delivery houses of the route and everything around them: dealing each one a spot beside the
## road (square to its stop, backed off until it clears the asphalt), its yard, worn path, number
## sign and the lines of sight kept clear of trees. route.gd builds the road and calls this for
## each stop; the arrays it fills (`houses`, the anchors, the clear and sight zones) belong to
## route.gd, which hands over the very same ones.

## House/road proportions carried over unchanged from the old handcrafted
## route -- only WHERE the road goes changed, not how wide it or a house
## approach is.
const HOUSE_LATERAL_OFFSET: float = 10.5
const HOUSE_PATH_LATERAL_OFFSET: float = 7.9
## Closest a house's front (porch step, roof eaves) may come to the road
## centreline. Houses are dealt in different sizes -- the farmhouse's porch
## reaches 4.3 m out of its origin -- so a fixed HOUSE_LATERAL_OFFSET put
## some decks right over the edge line; each house steps back as needed.
const HOUSE_FRONT_CLEARANCE: float = 7.6
## Clear ground left between any part of a house and the asphalt's edge,
## checked against the WHOLE finished road: a bend right before or after a
## stop (or a later leg doubling back) can swing the road toward the house.
## 3.0, was 1.4: the front yard needs room for the waiting house's sign and
## mailbox (house_waiting_marker.gd) between the porch and the asphalt.
const HOUSE_ROAD_MARGIN: float = 3.0
const HOUSE_PUSH_STEP: float = 0.5
const HOUSE_MAX_PUSH: float = 12.0
## How far above the house's own roof its "CASA N" label floats. 1.0 let the
## roof's peak cut the second line (the ordered box) from the road.
const HOUSE_LABEL_CLEARANCE: float = 1.8
## Kept clear of trees and roadside props: the lines of sight from the road,
## every SIGHT_LINE_STEP metres over the last SIGHT_LINE_LENGTH before a
## house, to the house itself -- the truck must see it coming (N-501). They
## follow the real road, so a bend just before the house is covered too.
const SIGHT_LINE_LENGTH: float = 120.0
const SIGHT_LINE_STEP: float = 30.0
const SIGHT_LINE_RADIUS: float = 3.5
## Trees keep this far from a house centre: enough room for the yard (fence
## line sits ~7-8 m out) without the forest growing through the porch.
const HOUSE_CLEAR_RADIUS: float = 9.0
## Every house model's porch deck is 0.30 m tall (both Blender batches).
const PORCH_DECK_HEIGHT: float = 0.3
## The colour of the "CASA N" signs and the start sign.
const TEAL := Color("65b5a1")

const YARD_DIR: String = "res://assets/models/environment/yard/"
const YARD_DOORMAT: String = YARD_DIR + "sm_env_yard_doormat.glb"
const YARD_FLOWER_POT: String = YARD_DIR + "sm_env_yard_flower_pot.glb"
const YARD_FENCE: String = YARD_DIR + "sm_env_yard_picket_fence.glb"
const YARD_GNOME: String = YARD_DIR + "sm_env_yard_garden_gnome.glb"
const YARD_DOG_HOUSE: String = YARD_DIR + "sm_env_yard_dog_house.glb"
const BARN: String = "res://assets/models/architecture/sm_arch_barn.glb"

var _route: Node3D
var _terrain: TerrainField
## The route's own arrays (see route.gd): the houses built so far, the road cursor and side each
## was dealt, the house models' dealing order, the road's dense path, and the circles / lines of
## sight where no tree or roadside prop may stand.
var _houses: Array[DeliveryHouse]
var _anchors: Array[Dictionary]
var _deck: Array[int]
var _path_points: Array[Vector3]
var _clear_zones: Array[Vector3]
var _sight_zones: Array[Vector3]


func _init(
	route: Node3D,
	terrain: TerrainField,
	houses: Array[DeliveryHouse],
	anchors: Array[Dictionary],
	deck: Array[int],
	path_points: Array[Vector3],
	clear_zones: Array[Vector3],
	sight_zones: Array[Vector3],
) -> void:
	_route = route
	_terrain = terrain
	_houses = houses
	_anchors = anchors
	_deck = deck
	_path_points = path_points
	_clear_zones = clear_zones
	_sight_zones = sight_zones


## The road, shoulder and terrain sit at three distinct elevations. Imported
## props have their local origin at their base, so every dressed object needs
## to be placed on the surface below it instead of blindly at world y = 0.
## Pure function of lateral distance -- doesn't care whether the segment
## it's dressing is straight or curved, so it needed no changes at all.
static func ground_height_at(x: float) -> float:
	var lateral: float = absf(x)
	if lateral <= 6.0:
		return 0.0
	if lateral <= 14.0:
		return -0.1
	return -0.3


## A model's visible extent in `root_node`'s space, so yard pieces line up with
## whichever house shape was dealt instead of assuming one footprint.
static func local_bounds(root_node: Node3D, node: Node) -> AABB:
	var result := AABB()
	var first: bool = true
	for child: Node in node.find_children("*", "VisualInstance3D", true, false):
		var xform: Transform3D = root_node.global_transform.affine_inverse() * (child as Node3D).global_transform
		var box: AABB = xform * (child as VisualInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


static func instantiate_dressing(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	LowpolyMaterials.apply(node)
	return node


## One house per package (docs/tareas-nacho.md house delivery system), one
## per leg, positioned and oriented relative to the cursor's OWN heading at
## this point in the road -- a fixed world-space side offset (the old
## approach) would plant the house in the middle of the asphalt the moment
## the road had turned away from the +X/-Z axes. The house is a detour off
## the road, not part of the chain: the caller keeps its own cursor.
func build_house(cursor: Transform3D, index: int) -> DeliveryHouse:
	var side: float = -1.0 if index % 2 == 0 else 1.0
	var house := DeliveryHouse.new()
	house.name = "House%d" % index
	house.visual_variant = _deck[index % _deck.size()]
	house.house_index = index
	# The house model's entrance is on local -Z. Rotate that face toward the
	# asphalt rather than along the road, so stops address the route.
	house.transform = _house_transform(cursor, side, HOUSE_LATERAL_OFFSET)
	_route.add_child(house)
	_houses.append(house)
	# Step back far enough that this model's porch clears the road.
	var visual: Node3D = house.get_node_or_null(^"HouseVisual")
	if visual != null:
		var reach: float = -local_bounds(house, visual).position.z
		house.transform = _house_transform(cursor, side, maxf(HOUSE_LATERAL_OFFSET, HOUSE_FRONT_CLEARANCE + reach))
	_anchors.append({"cursor": cursor, "side": side})
	return house


func _house_transform(cursor: Transform3D, side: float, lateral: float) -> Transform3D:
	var offset := Vector3(side * lateral, ground_height_at(lateral), 0.0)
	return cursor * Transform3D(Basis(Vector3.UP, side * PI * 0.5), offset)


## Runs once the whole road exists: backs any house away (along its own
## back, keeping it square to its stop) until every corner of it -- porch,
## eaves, side bay -- stands HOUSE_ROAD_MARGIN clear of the asphalt, then
## lays out its yard, path and number around where it finally stands.
func keep_houses_off_road() -> void:
	for index: int in range(_houses.size()):
		var house: DeliveryHouse = _houses[index]
		var visual: Node3D = house.get_node_or_null(^"HouseVisual")
		if visual != null:
			var bounds: AABB = local_bounds(house, visual)
			var pushed: float = 0.0
			while house_road_gap(house, bounds) < HOUSE_ROAD_MARGIN and pushed < HOUSE_MAX_PUSH:
				house.position += house.basis.z.normalized() * HOUSE_PUSH_STEP
				pushed += HOUSE_PUSH_STEP
		_build_yard(house, index)
		var anchor: Dictionary = _anchors[index]
		_build_house_path(anchor.cursor, anchor.side, house)
		var top: float = local_bounds(house, visual).end.y if visual != null else 4.0
		var label_at: Vector3 = house.position + Vector3.UP * (top + HOUSE_LABEL_CLEARANCE)
		var caption: String = tr("WORLD_HOUSE_NUMBER") % (index + 1)
		RouteProps.label(_route, "HouseNumber%d" % index, caption, label_at, 0.01, TEAL, true)
		_route.get_node(NodePath("HouseNumber%d" % index)).set_meta(&"height_above_house", top + HOUSE_LABEL_CLEARANCE)


## Smallest distance from the house's footprint outline (corners and edge
## midpoints of its model's bounds) to the edge of any asphalt on the route.
func house_road_gap(house: Node3D, bounds: AABB) -> float:
	var gap: float = INF
	var x0: float = bounds.position.x
	var x1: float = bounds.end.x
	var z0: float = bounds.position.z
	var z1: float = bounds.end.z
	var mid_x: float = (x0 + x1) * 0.5
	var mid_z: float = (z0 + z1) * 0.5
	var outline: Array[Vector2] = [Vector2(x0, z0), Vector2(x1, z0), Vector2(x0, z1), Vector2(x1, z1),
			Vector2(mid_x, z0), Vector2(mid_x, z1), Vector2(x0, mid_z), Vector2(x1, mid_z)]
	for local: Vector2 in outline:
		var p: Vector3 = house.transform * Vector3(local.x, 0.0, local.y)
		var road: Vector3 = _terrain.nearest(Vector2(p.x, p.z))
		gap = minf(gap, road.x - road.z)
	return gap


## A narrow worn path makes each stop feel connected to the road. It stops
## at the shoulder rather than widening the driving lane or blocking traffic.
func _build_house_path(cursor: Transform3D, side: float, house: Node3D) -> void:
	var a: Vector3 = cursor * Vector3(side * 5.8, 0.0, 0.0)
	var b: Vector3 = house.position
	_terrain.paths.append({"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z)})


## Yard dressing so a delivery stop reads as someone's home, not a box
## dropped by the road. Houses stand only ~10 m from the centreline and their
## porch reaches to ~7 m, so there's no front garden to speak of: the doormat
## and pots ride on the porch deck (part of the house, never moved), and the
## lot -- fence down both sides, gnome, dog house, the farm's barn -- runs
## along the sides and back. Lot pieces are only proposals: RouteDresser
## validates each one like any other prop and drops what doesn't fit (which
## is how a fence once ended up on the asphalt, before it did).
## Choices come from the house index, not the RNG, so adding dressing never
## reshuffles the road itself.
func _build_yard(house: DeliveryHouse, index: int) -> void:
	var yard := Node3D.new()
	yard.name = "Yard"
	house.add_child(yard)
	var visual: Node3D = house.get_node_or_null(^"HouseVisual")
	var bounds := AABB(Vector3(-3.0, 0.0, -3.0), Vector3(6.0, 3.0, 6.0))
	if visual != null:
		bounds = local_bounds(house, visual)
	var front: float = bounds.position.z
	var flip: float = 1.0 if index % 2 == 0 else -1.0
	# `front` includes the porch step (0.23 m); these sit back on the deck,
	# between the door frame and the porch posts.
	_yard_piece(yard, YARD_DOORMAT, Vector3(0.0, PORCH_DECK_HEIGHT, front + 0.75), 0.0, 0.5, true)
	for x: float in [-0.95, 0.95]:
		_yard_piece(yard, YARD_FLOWER_POT, Vector3(x, PORCH_DECK_HEIGHT, front + 0.6), 0.0, 0.3, true)
	# Side fences: 2 m panels turned to run front-to-back beside the house.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (bounds.size.x * 0.5 + 1.6)
		var z: float = front + 1.0
		while z < bounds.end.z + 2.0:
			# 0.95, not 1.0: 2 m panels end to end would "touch" and fail the overlap check.
			_yard_piece(yard, YARD_FENCE, Vector3(x, 0.0, z), PI * 0.5, 0.95, false)
			z += 2.0
	var gnome_at := Vector3((bounds.size.x * 0.5 + 0.7) * flip, 0.0, front + 1.6)
	_yard_piece(yard, YARD_GNOME, gnome_at, deg_to_rad(20.0 * flip), 0.3, false)
	if index % 2 == 1:
		var dog_house_at := Vector3(-flip * (bounds.size.x * 0.5 + 0.8), 0.0, bounds.end.z - 0.4)
		_yard_piece(yard, YARD_DOG_HOUSE, dog_house_at, PI, 0.7, false)
	_clear_zones.append(Vector3(house.position.x, house.position.z, HOUSE_CLEAR_RADIUS))
	_clear_sight_lines(house, (_anchors[index].cursor as Transform3D).origin)
	# The farmhouse gets its barn beside it -- a farm, not a lone house.
	var model: String = DeliveryHouse.HOUSE_VISUALS[posmod(house.visual_variant, DeliveryHouse.HOUSE_VISUALS.size())]
	if model.ends_with("farmhouse.glb"):
		# Turned a quarter, the barn's 12.7 m length runs sideways: 11 m out
		# leaves a proper farmyard gap instead of a lean-to.
		var barn: Node3D = _yard_piece(yard, BARN, Vector3(bounds.position.x - 11.0, 0.0, 4.0), PI * 0.5, 6.4, false)
		if barn != null:
			var barn_at: Vector3 = _route.to_local(barn.global_position)
			_clear_zones.append(Vector3(barn_at.x, barn_at.z, 9.0))


## Nothing between the arriving truck and the house: walks the road back
## from the house's stop and clears a line from each sample to the house.
func _clear_sight_lines(house: Node3D, stop: Vector3) -> void:
	var nearest: int = 0
	for index: int in range(_path_points.size()):
		if _path_points[index].distance_squared_to(stop) < _path_points[nearest].distance_squared_to(stop):
			nearest = index
	var travelled: float = 0.0
	var next_sample: float = SIGHT_LINE_STEP
	var index: int = nearest
	while index > 0 and travelled < SIGHT_LINE_LENGTH:
		travelled += _path_points[index].distance_to(_path_points[index - 1])
		index -= 1
		if travelled < next_sample:
			continue
		next_sample += SIGHT_LINE_STEP
		var from: Vector3 = _path_points[index]
		var length: float = Vector2(house.position.x - from.x, house.position.z - from.z).length()
		var along: float = 0.0
		while along <= length:
			var at: Vector3 = from.lerp(house.position, along / maxf(length, 0.01))
			_sight_zones.append(Vector3(at.x, at.z, SIGHT_LINE_RADIUS))
			along += SIGHT_LINE_RADIUS * 2.0


func _yard_piece(
	yard: Node3D, path: String, local_position: Vector3, yaw: float, footprint: float, on_porch: bool
) -> Node3D:
	var piece := instantiate_dressing(path)
	if piece == null:
		return null
	piece.transform = Transform3D(Basis(Vector3.UP, yaw), local_position)
	piece.set_meta(&"footprint", footprint)
	piece.set_meta(&"on_porch", on_porch)
	yard.add_child(piece)
	return piece
