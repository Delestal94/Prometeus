class_name RoutePlacement
extends RefCounted
## The single gate every roadside object goes through (see route_dresser.gd
## for the six checks): the occupancy grid, clear and sight zones, slope and
## same-kind spacing, then settling the model on the ground -- sunk a little,
## leaned with the slope, with a soft contact shadow under it. RouteDresser
## and its feature builders (RouteSignage, RouteWildlife, RoutePowerLines)
## share one of these per route, so they all see each other's claims.

const GRID_CELL: float = 8.0
const MAX_FOOTPRINT: float = 8.0
## Terrain.nearest() returns 4x its HALO when a point has no road tile
## nearby at all -- i.e. there's no ground there to stand on.
const NO_TERRAIN_DISTANCE: float = 250.0
## Above this much carved-away depth (route_terrain.gd river_depth_at()) a
## spot counts as "in the riverbed" and nothing gets planted there -- low
## enough that a power pole still fits on a bridge's shallow outer bank
## (its own line is allowed to cross the river), but high enough to keep
## everything out of the actual water and the bare bed beside it.
const RIVER_MISFIT_DEPTH: float = 0.5
## Fake contact shadows (presentation/contact_shadow.gd): how far the soft
## band reaches in and out of a parked car's footprint.
const ContactShadow = preload("res://scripts/presentation/contact_shadow.gd")
const CONTACT_SHADOW_MARGIN: float = 0.6
## What lights up after dark (N-304, LowpolyMaterials.light_up()), by model.
const NIGHT_LIGHTS: Dictionary = {
	RouteDresser.PROPS + "sm_env_prop_street_lamp_refined.glb": ["lamp_glass"],
	"res://assets/models/vehicles/sm_vehicle_parked_hatchback.glb": ["lamp"],
	"res://assets/models/vehicles/sm_vehicle_parked_pickup.glb": ["lamp"],
}
const WINDMILL_TURN_SECONDS: float = 14.0
## Ground contact (see _settle()). A model's "feet" are every vertex within
## CONTACT_BAND of its lowest point; of those, the outermost one per angular
## sector around the origin (plus the very lowest) is kept, so a tree's root
## tips, a log's two ends and a bench's four legs are all checked against the
## terrain right under them instead of under the object's centre. Kept thin:
## a parked car's sills sit ~0.3 m above its tyres, and counting them as feet
## sank the wheels into the ground.
const CONTACT_BAND: float = 0.08
const CONTACT_SECTORS: int = 8
## Once nothing floats, everything sinks a touch more so no hairline of sky
## shows under a foot where the terrain bends between samples: proportional
## to how far the feet spread, within these bounds (metres).
const SINK_RATIO: float = 0.05
const SINK_RANGE: Vector2 = Vector2(0.02, 0.1)
## Ground plants that lie on the ground rather than grow out of it, and so
## lean with the slope (a stump or a fern stays upright like a tree).
const LEAN_MODELS: Array[String] = [
	"sm_env_forest_fallen_log.glb", "sm_env_forest_deadfall_branch.glb",
	"sm_env_forest_rock.glb", "sm_env_forest_mossy_rock_cluster.glb",
]
static var _contact_cache: Dictionary = {}


var _route: Node3D
var _terrain: Node
## Where houses and their yards are: nothing but the yard itself goes there.
var clear_zones: Array[Vector3] = []
## Like clear_zones, but only for what would hide a house from the road
## (route.gd's sight lines, N-501): trees and props stay out, while a road
## sign (thin, and there to be seen) may stand in one.
var sight_zones: Array[Vector3] = []
var _grid: Dictionary = {}
var _same_kind: Dictionary = {}
var _packed: Dictionary = {}
## How many things each rule/feature actually placed, and why the rest were
## turned down ({id: {reason: count}}), for tests and tuning.
var placed_counts: Dictionary = {}
var rejected_counts: Dictionary = {}


func _init(route: Node3D, terrain: Node) -> void:
	_route = route
	_terrain = terrain


## The single gate every object goes through. `xform` is in the segment's
## space. Returns the spawned node, or null when the spot fails a check.
func try_place(segment: RouteSegment, group_name: String, path: String, xform: Transform3D,
		fields: Dictionary) -> Node3D:
	var p: Vector3 = segment.transform * xform.origin
	var radius: float = float(fields.get("radius", 0.5))
	var solid: bool = bool(fields.get("solid", true))
	var id: StringName = StringName(fields.get("id", &""))
	var min_same: float = float(fields.get("min_same", 0.0))
	var footprint: float = float(fields.get("footprint", radius))
	if misfit(p, radius, float(fields.get("clearance", 7.0)), float(fields.get("max_slope", 0.35)), true, id, min_same,
			footprint) != &"":
		return null
	if not bool(fields.get("see_through", false)) and in_zones(sight_zones, p, footprint):
		reject(id, &"sight_line")
		return null
	var node := instantiate(path)
	if node == null:
		return null
	if fields.has("behaviour"):
		# Before entering the tree, so the behaviour's _ready() runs.
		node.set_script(fields.behaviour)
	node.transform = xform
	group(segment, group_name).add_child(node)
	settle(node, p, bool(fields.get("tilt", false)) or path.get_file() in LEAN_MODELS)
	if fields.has("contact_shadow"):
		_lay_contact_shadow(segment, node, float(fields.contact_shadow))
	node.set_meta(&"rule", id)
	node.set_meta(&"reach", radius)
	node.set_meta(&"footprint", footprint)
	node.set_meta(&"solid", solid)
	if fields.has("zone"):
		node.set_meta(&"zone", RouteDresser.ZONE_NAMES[fields.zone])
	if solid:
		occupy(p, footprint)
	if min_same > 0.0:
		remember_kind(id, p)
	var rotor: Node3D = node.find_child("WindmillRotor", true, false) as Node3D
	if rotor != null:
		# Blender's rotor axis (+Y) arrives as Godot's local Z.
		rotor.create_tween().set_loops().tween_property(rotor, "rotation:z", TAU, WINDMILL_TURN_SECONDS).from(0.0)
	count(id)
	return node


## The six checks from the class comment, in cheapest-first order. Returns
## why a spot was turned down, or &"" when it fits (and records the reason).
## `in_world` = false is for a house's own yard, which sits inside that
## house's cleared zone by definition (it still can't overlap itself).
func misfit(p: Vector3, radius: float, clearance: float, max_slope: float, in_world: bool, id: StringName,
		min_same: float, footprint: float = -1.0) -> StringName:
	# `radius` is how close the object itself comes to the road; `footprint`
	# is the ground it claims from others (a guardrail is thin across the
	# road but 4 m along it).
	var claim: float = footprint if footprint >= 0.0 else radius
	var reason: StringName = &""
	var road: float = _terrain.nearest(Vector2(p.x, p.z)).x
	if road >= NO_TERRAIN_DISTANCE:
		reason = &"no_terrain"
	elif road - radius < clearance:
		reason = &"road"
	elif _terrain.river_depth_at(Vector2(p.x, p.z)) > RIVER_MISFIT_DEPTH:
		reason = &"river"
	elif in_world and in_clear_zone(p, claim):
		reason = &"clear_zone"
	elif overlaps(p, claim):
		reason = &"occupied"
	elif min_same > 0.0 and _near_same(p, id, min_same):
		reason = &"same_kind"
	elif _slope(p, maxf(radius, 0.5)) > max_slope:
		reason = &"slope"
	if reason != &"":
		if not rejected_counts.has(id):
			rejected_counts[id] = {}
		rejected_counts[id][reason] = int(rejected_counts[id].get(reason, 0)) + 1
	return reason


func in_clear_zone(p: Vector3, radius: float) -> bool:
	return in_zones(clear_zones, p, radius)


func in_zones(zones: Array[Vector3], p: Vector3, radius: float) -> bool:
	for zone: Vector3 in zones:
		if Vector2(p.x - zone.x, p.z - zone.y).length() < zone.z + radius:
			return true
	return false


func reject(id: StringName, reason: StringName) -> void:
	if not rejected_counts.has(id):
		rejected_counts[id] = {}
	rejected_counts[id][reason] = int(rejected_counts[id].get(reason, 0)) + 1


## Remembers `p` as a spot `id` stands on, for its min_same spacing.
func remember_kind(id: StringName, p: Vector3) -> void:
	if not _same_kind.has(id):
		_same_kind[id] = []
	_same_kind[id].append(Vector2(p.x, p.z))



func _near_same(p: Vector3, id: StringName, distance: float) -> bool:
	for other: Vector2 in _same_kind.get(id, []):
		if other.distance_to(Vector2(p.x, p.z)) < distance:
			return true
	return false


func _slope(p: Vector3, reach: float) -> float:
	var dx: float = absf(_terrain.height_at(p + Vector3(reach, 0.0, 0.0)) - _terrain.height_at(p - Vector3(reach, 0.0,
			0.0)))
	var dz: float = absf(_terrain.height_at(p + Vector3(0.0, 0.0, reach)) - _terrain.height_at(p - Vector3(0.0, 0.0,
			reach)))
	return maxf(dx, dz) / (2.0 * reach)


func occupy(p: Vector3, radius: float) -> void:
	var key := Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))
	if not _grid.has(key):
		_grid[key] = []
	_grid[key].append(Vector3(p.x, p.z, radius))


func overlaps(p: Vector3, radius: float) -> bool:
	var reach: int = ceili((radius + MAX_FOOTPRINT) / GRID_CELL)
	var center := Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))
	for dx: int in range(-reach, reach + 1):
		for dz: int in range(-reach, reach + 1):
			for other: Vector3 in _grid.get(center + Vector2i(dx, dz), []):
				if Vector2(other.x - p.x, other.y - p.z).length() < other.z + radius:
					return true
	return false


## Puts `node` (already posed and parented) down at route-space `p`: leans it
## with the slope if asked, then lowers it until every contact point is at or
## under the terrain right below it, plus a small sink. Placing by the centre
## alone is what left a tree's downhill roots or a log's far end in the air.
func settle(node: Node3D, p: Vector3, lean: bool = false) -> void:
	node.global_position = _route.to_global(p)
	var contacts: PackedVector3Array = contact_points(node)
	if lean:
		_lean_with_ground(node, p, contacts)
	var basis: Basis = _route.global_basis.inverse() * node.global_basis
	var y: float = INF
	var spread: float = 0.0
	for contact: Vector3 in contacts:
		var offset: Vector3 = basis * contact
		y = minf(y, _terrain.height_at(p + Vector3(offset.x, 0.0, offset.z)) - offset.y)
		spread = maxf(spread, Vector2(offset.x, offset.z).length())
	if y == INF:
		y = _terrain.height_at(p)
	p.y = y - clampf(spread * SINK_RATIO, SINK_RANGE.x, SINK_RANGE.y)
	node.global_position = _route.to_global(p)


## Tilts `node` to the ground plane across its own length and width: a 4 m
## log reads the slope between its two ends, not over the metre at its middle.
func _lean_with_ground(node: Node3D, p: Vector3, contacts: PackedVector3Array) -> void:
	var scale: Vector3 = node.basis.get_scale()
	var reach := Vector2(0.5, 0.5)
	for contact: Vector3 in contacts:
		reach = reach.max(Vector2(absf(contact.x) * scale.x, absf(contact.z) * scale.z))
	var right: Vector3 = node.global_basis.x.normalized()
	var forward: Vector3 = node.global_basis.z.normalized()
	var rise_x: float = _terrain.height_at(p + right * reach.x) - _terrain.height_at(p - right * reach.x)
	var rise_z: float = _terrain.height_at(p + forward * reach.y) - _terrain.height_at(p - forward * reach.y)
	node.rotate_object_local(Vector3.FORWARD, -atan(rise_x / (2.0 * reach.x)))
	node.rotate_object_local(Vector3.RIGHT, -atan(rise_z / (2.0 * reach.y)))


## A soft dark band where `node` meets the ground (N-308.2), draped over the
## terrain vertex by vertex: the piece itself sinks a few cm into the ground
## when settled (SINK_RANGE), so a patch hung from it would be buried. Laid
## after settling (it isn't part of what stands on the ground) and in a group
## of its own, not under the car: DressingBatcher.bake() shares one mesh per
## model, and each car's ground is its own. (merge_segment_geometry() still
## folds the bands into the segment's merged mesh, vertices where they were
## laid; the meta then points at a freed node.) Knockable pieces get none --
## the patch would fly off with them.
func _lay_contact_shadow(segment: Node3D, node: Node3D, opacity: float) -> void:
	var bounds: AABB = mesh_bounds(node)
	var in_route: Transform3D = _route.global_transform.affine_inverse() * node.global_transform
	var scale: Vector3 = in_route.basis.get_scale()
	var frame := Transform3D(in_route.basis.orthonormalized(),
			in_route * Vector3(bounds.get_center().x, 0.0, bounds.get_center().z))
	var footprint := Vector2(bounds.size.x * scale.x, bounds.size.z * scale.z)
	var band: ArrayMesh = ContactShadow.mesh(frame, footprint, CONTACT_SHADOW_MARGIN,
			func(point: Vector3) -> float: return _terrain.height_at(point))
	var patch: MeshInstance3D = ContactShadow.instance(band, opacity)
	group(segment, "ContactShadows").add_child(patch, true)
	patch.global_transform = _route.global_transform
	node.set_meta(&"contact_shadow", patch)


func group(segment: Node3D, group_name: String) -> Node3D:
	var group: Node3D = segment.get_node_or_null(NodePath(group_name)) as Node3D
	if group == null:
		group = Node3D.new()
		group.name = group_name
		segment.add_child(group)
	return group


func instantiate(path: String) -> Node3D:
	if not _packed.has(path):
		_packed[path] = load(path) as PackedScene
	var packed: PackedScene = _packed[path]
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	LowpolyMaterials.apply(node)
	# After dark the street lamps and parked cars' lamps glow (N-304).
	if NIGHT_LIGHTS.has(path):
		LowpolyMaterials.light_up(node, NIGHT_LIGHTS[path])
	return node


func count(id: StringName) -> void:
	placed_counts[id] = int(placed_counts.get(id, 0)) + 1


## How far a model's visible base sits above (or below) its own origin, in
## the node's unscaled local space. Most props are exported with the base at
## y=0, but some (ferns, fallen logs, round bushes) are not, and would float
## or sink if placed by their origin.
static func base_offset(node: Node3D) -> float:
	var lowest: float = _lowest_mesh_y(node, node)
	return lowest if lowest != INF else 0.0


## How far the highest of `node`'s feet sits above the terrain right under it
## (negative = every foot is in the ground). For tests: after _settle() this
## is -sink, never above zero.
static func ground_gap(node: Node3D, route: Node3D, terrain: Node) -> float:
	var basis: Basis = route.global_basis.inverse() * node.global_basis
	var origin: Vector3 = route.to_local(node.global_position)
	var gap: float = -INF
	for contact: Vector3 in contact_points(node):
		var foot: Vector3 = origin + basis * contact
		gap = maxf(gap, foot.y - float(terrain.call(&"height_at", foot)))
	return gap


## The model's feet in its own (unscaled) space: see CONTACT_BAND. Cached per
## scene file, since every oak has the same roots.
static func contact_points(node: Node3D) -> PackedVector3Array:
	var key: String = node.scene_file_path
	if key != "" and _contact_cache.has(key):
		return _contact_cache[key]
	var vertices := PackedVector3Array()
	_collect_vertices(node, node, vertices)
	var contacts := PackedVector3Array()
	if vertices.is_empty():
		contacts.append(Vector3.ZERO)
	else:
		var lowest: Vector3 = vertices[0]
		for v: Vector3 in vertices:
			if v.y < lowest.y:
				lowest = v
		contacts.append(lowest)
		var outermost: Array = []
		outermost.resize(CONTACT_SECTORS)
		for v: Vector3 in vertices:
			if v.y > lowest.y + CONTACT_BAND:
				continue
			var sector: int = posmod(floori(atan2(v.z, v.x) / TAU * CONTACT_SECTORS), CONTACT_SECTORS)
			var best: Variant = outermost[sector]
			if best == null or Vector2(v.x, v.z).length_squared() > Vector2(best.x, best.z).length_squared():
				outermost[sector] = v
		for v: Variant in outermost:
			if v != null:
				contacts.append(v)
	if key != "":
		_contact_cache[key] = contacts
	return contacts


static func _collect_vertices(root_node: Node3D, node: Node, into: PackedVector3Array) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var mesh: Mesh = (child as MeshInstance3D).mesh
			var xform: Transform3D = root_node.global_transform.affine_inverse() * (child as Node3D).global_transform
			for surface: int in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					into.append(xform * v)
		if child is Node3D:
			_collect_vertices(root_node, child, into)


static func _lowest_mesh_y(root_node: Node3D, node: Node) -> float:
	var lowest: float = INF
	for child: Node in node.get_children():
		if child is VisualInstance3D:
			var xform: Transform3D = root_node.global_transform.affine_inverse() * (child as Node3D).global_transform
			lowest = minf(lowest, (xform * (child as VisualInstance3D).get_aabb()).position.y)
		if child is Node3D:
			lowest = minf(lowest, _lowest_mesh_y(root_node, child))
	return lowest


static func mesh_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first: bool = true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var xform: Transform3D = Transform3D.IDENTITY
		var walker: Node = mesh
		while walker != root and walker != null:
			xform = (walker as Node3D).transform * xform
			walker = walker.get_parent()
		var box: AABB = xform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
