class_name RouteGoalLot
extends Node3D
## The end of the route (tareas de Nacho N-116): the company's base in the
## town, a levelled lot at the end of the road where the truck is left. It
## replaces the old concrete arch. The run ends when the truck is stopped
## INSIDE the free bay (level_base.gd counts the stop the same way it counted
## it in the arch: route.is_vehicle_in_delivery + near-zero speed), not when it
## crosses a line.
##
## What is there: an asphalt slab (about 40 x 30 m) with a kerb and a fence,
## a gate with a guard booth whose barrier lifts when the truck comes near, a
## building along the back with the company's big sign, street lamps that
## light up at night, and a row of six painted bays. Five hold parked company
## trucks (solid: hitting one is a normal crash); one is free, marked with its
## number painted big, a floor arrow, cones and a sign over it. To one side
## another truck is being unloaded by a couple of workers; on the other side
## there is a hose. Nothing moves through the free bay.
##
## Lot space: origin on the road's last point at ground level, -Z forward
## (the way the truck arrives), X to the driver's right. Everything that is
## drawn or placed comes from the session seed (configure()), so every peer
## has the same lot; the host alone decides that the run is over.
##
## Cost: about 40 draw calls (boxes merged into one mesh, trucks and lamps as
## MultiMesh); the only per-frame work is the bay check, and only while a
## truck is within reach of the lot.

## The truck is parked (or has left) the free bay. Route turns it into
## delivery_entered/exited, which level_base.gd's stop timer reads.
signal bay_occupied_changed(occupied: bool, body: Node3D)

const HALF_WIDTH: float = 20.0
const FRONT_Z: float = -1.0
const BACK_Z: float = -31.0
const GATE_HALF: float = 4.5
const SLAB_TOP: float = 0.05
const FENCE_HEIGHT: float = 2.2
const BUILDING_DEPTH: float = 6.0
const BUILDING_HEIGHT: float = 5.2
## Ground the platform levels and keeps clear, around the slab and building.
## (Four metres of margin all round: the terrain is a 2 m grid.)
const PLATFORM_HALF: Vector2 = Vector2(25.0, 23.5)
const PLATFORM_CENTRE_Z: float = -19.5

const BAY_COUNT: int = 6
const BAY_WIDTH: float = 4.2
const BAY_LENGTH: float = 8.8
const BAY_BACK_Z: float = -30.4
const BAY_FRONT_Z: float = BAY_BACK_Z + BAY_LENGTH

## The driven truck (vehicle.tscn): two points on its centreline, nose and
## tail, in its own space. Both inside the bay = parked in it.
const VEHICLE_NOSE_Z: float = -2.6
const VEHICLE_TAIL_Z: float = 4.2
const BAY_MARGIN: float = 0.25
const TAIL_OVERHANG: float = 0.8
## Tidy parking: less than this many degrees off the bay's axis.
const TIDY_DEGREES: float = 10.0

const TRUCK_PATH: String = "res://assets/models/truck_reference_lowpoly.glb"
const LAMP_PATH: String = "res://assets/models/environment/props/sm_env_prop_street_lamp_refined.glb"
const CONE_PATH: String = "res://assets/models/environment/props/sm_env_prop_traffic_cone.glb"
const BOX_PATH: String = "res://assets/models/cargo/sm_cargo_box_cube.glb"
const TRUCK_SCALE: float = 0.8
## From the model's origin (its centre in Blender) to nose and tail, after scale.
const TRUCK_NOSE: float = 3.43
const TRUCK_TAIL: float = 4.16
const TRUCK_WIDTH: float = 2.5
const TRUCK_HEIGHT: float = 3.0
## Where a lamp's glass hangs, in the model's space.
const LAMP_GLASS: Vector3 = Vector3(0.92, 3.85, 0.0)

const ASPHALT := Color("41494e")
const KERB := Color("9aa39d")
const LINE := Color("d4d9c2")
const YELLOW := Color("e7be51")
const TEAL := Color("65b5a1")
const TEAL_DARK := Color("2f7f78")
const WALL := Color("b7beb6")
const ROOF := Color("6f7a78")
const POST := Color("707a78")
const BOARD := Color("263b3e")
const RED := Color("c8352b")
const WHITE := Color("f1efe2")
const DARK := Color("1b2a2d")
const HOSE_GREEN := Color("2f9e57")
const CART := Color("5c6a70")

const GATE_OPEN_ANGLE: float = -1.45
const GATE_SECONDS: float = 0.9
const ARM_SEGMENTS: int = 12
const ARM_LENGTH: float = 9.0

## Sight of the lot: gate and workers wake when a truck is this near.
const WAKE_HALF: Vector3 = Vector3(26.0, 5.0, 33.0)
const WAKE_CENTRE: Vector3 = Vector3(0.0, 4.0, -3.0)

## Set by configure().
var spine_seed: int = 0
var town_name: String = ""
var darkness: float = 0.0
## The free bay: which of the row (0 = leftmost) and the number painted on it.
var free_index: int = 0
var bay_number: int = 1
var first_number: int = 1
## -1 = the truck being unloaded stands on the left, 1 = on the right.
var unload_side: float = -1.0
## Per bay: x offset, yaw, z offset of the parked truck.
var truck_jitter: Array[Vector3] = []
## How far off the bay's axis the truck in it stands (degrees), while it is in.
var parked_deviation: float = 0.0
var workers: Array[Node3D] = []
var gate_open: bool = false
var cones: Array[RigidBody3D] = []
var lamp_spots: Array[Vector3] = []
## Where each parked truck is drawn (lot space), in bay order: kept because a
## MultiMesh does not hand its instances back in a headless run.
var truck_transforms: Array[Transform3D] = []

var _occupant: Node3D
var _lamp_bases: Array[Vector3] = []
var _vehicles: Array[Node3D] = []
var _arm: Node3D
var _gate_tween: Tween


## Everything the lot decides from the session, before it is built.
func configure(seed_value: int, town: String, darkness_level: float) -> void:
	spine_seed = seed_value
	town_name = town
	darkness = darkness_level
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, &"goal_lot"])
	first_number = rng.randi_range(1, 4)
	free_index = rng.randi_range(0, BAY_COUNT - 1)
	unload_side = -1.0 if rng.randf() < 0.5 else 1.0
	truck_jitter.clear()
	for bay: int in range(BAY_COUNT):
		truck_jitter.append(Vector3(
				rng.randf_range(-0.25, 0.25), rng.randf_range(-0.05, 0.05), rng.randf_range(0.0, 0.4)))
	bay_number = first_number + free_index


static func bay_x(index: int) -> float:
	return (float(index) - float(BAY_COUNT - 1) * 0.5) * BAY_WIDTH


## The lot's platform for route_terrain.gd, in the route's space (this node
## sits in it): flat at the lot's own height, turned with the road.
func terrain_platform() -> Dictionary:
	var forward: Vector3 = transform.basis * Vector3(0.0, 0.0, -1.0)
	return {
		"centre": Vector2(transform.origin.x, transform.origin.z) + Vector2(forward.x, forward.z) * -PLATFORM_CENTRE_Z,
		"along": Vector2(forward.x, forward.z).normalized(),
		"half": PLATFORM_HALF,
		"height": transform.origin.y,
	}


## Circles (x, z, radius) in the route's space where nothing is planted.
func clear_zones() -> Array[Vector3]:
	var zones: Array[Vector3] = []
	var z: float = 0.0
	while z > BACK_Z - BUILDING_DEPTH - 6.0:
		var x: float = -HALF_WIDTH - 4.0
		while x <= HALF_WIDTH + 4.0:
			var point: Vector3 = transform * Vector3(x, 0.0, z)
			zones.append(Vector3(point.x, point.z, 9.0))
			x += 12.0
		z -= 12.0
	return zones


## The way from the road into the free bay, in the route's space, a point
## every few metres (the route's dense path: GPS distance, off-road check).
func path_points() -> Array[Vector3]:
	var bay: Vector3 = Vector3(bay_x(free_index), 0.0, (BAY_BACK_Z + BAY_FRONT_Z) * 0.5)
	var corners: Array[Vector3] = [Vector3(0.0, 0.0, -14.0), Vector3(bay.x, 0.0, BAY_FRONT_Z + 3.0), bay]
	var points: Array[Vector3] = [transform * Vector3.ZERO]
	var from: Vector3 = Vector3.ZERO
	for corner: Vector3 in corners:
		var steps: int = maxi(1, ceili(from.distance_to(corner) / 8.0))
		for step: int in range(1, steps + 1):
			points.append(transform * from.lerp(corner, float(step) / steps))
		from = corner
	return points


## Where the truck's origin should stand to be well parked in the free bay (world).
func parking_pose() -> Transform3D:
	var local := Transform3D(Basis.IDENTITY, Vector3(bay_x(free_index), 0.9, BAY_BACK_Z - VEHICLE_NOSE_Z + 0.8))
	return global_transform * local


## Centre of the free bay on the ground (world).
func bay_centre() -> Vector3:
	return to_global(Vector3(bay_x(free_index), SLAB_TOP, (BAY_BACK_Z + BAY_FRONT_Z) * 0.5))


func bay_transform() -> Transform3D:
	return Transform3D(global_basis, bay_centre())


func is_bay_occupied() -> bool:
	return _occupant != null


## Where the results camera should sit, seen from the truck (world, unit):
## out into the lot, away from the back wall.
func results_direction() -> Vector3:
	var out: Vector3 = global_basis * Vector3(0.0, 0.0, 1.0)
	return Vector3(out.x, 0.0, out.z).normalized()


## The tidy-parking line for the results screen (RunManager.world_stories()).
func result_stories() -> Array[String]:
	var stories: Array[String] = []
	if _occupant != null and parked_deviation < TIDY_DEGREES:
		stories.append(tr("WORLD_LOT_TIDY_PARKING"))
	return stories


func _ready() -> void:
	add_to_group(&"goal_lot")
	add_to_group(&"run_stories")
	set_physics_process(false)
	_build_static()
	_build_signs()
	_build_trucks()
	_build_props()
	_build_lamps()
	_build_gate()
	_build_workers()
	_build_colliders()
	_build_area()
	if darkness > 0.0:
		_build_lights()
	set_meta(&"halo_points", PackedVector3Array(lamp_spots))


# --- Sensing ---------------------------------------------------------------

func _build_area() -> void:
	var area := Area3D.new()
	area.name = "LotArea"
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	area.position = WAKE_CENTRE
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = WAKE_HALF * 2.0
	shape.shape = box
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body not in _vehicles:
		_vehicles.append(body)
	set_physics_process(true)
	open_gate()
	_wake_workers(true)


func _on_body_exited(body: Node3D) -> void:
	_vehicles.erase(body)
	if body == _occupant:
		_set_occupant(null)
	if _vehicles.is_empty():
		set_physics_process(false)
		_wake_workers(false)


func _physics_process(_delta: float) -> void:
	var found: Node3D = null
	for body: Node3D in _vehicles:
		if is_instance_valid(body) and is_in_bay(body):
			found = body
			break
	if found != null:
		parked_deviation = deviation_of(found)
	_set_occupant(found)


func _set_occupant(body: Node3D) -> void:
	if body == _occupant:
		return
	var previous: Node3D = _occupant
	_occupant = body
	if body == null:
		bay_occupied_changed.emit(false, previous)
	else:
		bay_occupied_changed.emit(true, body)


## Both ends of the truck's centreline inside the free bay's lines.
func is_in_bay(body: Node3D) -> bool:
	var local: Transform3D = bay_transform().affine_inverse() * body.global_transform
	var nose: Vector3 = local * Vector3(0.0, 0.0, VEHICLE_NOSE_Z)
	var tail: Vector3 = local * Vector3(0.0, 0.0, VEHICLE_TAIL_Z)
	var half: float = BAY_WIDTH * 0.5 - BAY_MARGIN
	var back: float = -BAY_LENGTH * 0.5 - 0.1
	var front: float = BAY_LENGTH * 0.5 + TAIL_OVERHANG
	return absf(nose.x) <= half and absf(tail.x) <= half \
			and nose.z >= back and tail.z <= front and nose.z <= front and tail.z >= back


## Degrees between the truck's axis and the bay's (either way round).
func deviation_of(body: Node3D) -> float:
	var forward: Vector3 = bay_transform().affine_inverse().basis * body.global_basis * Vector3(0.0, 0.0, -1.0)
	var angle: float = absf(rad_to_deg(atan2(forward.x, -forward.z)))
	return minf(angle, 180.0 - angle)


## The barrier lifts (a truck came near the gate).
func open_gate() -> void:
	if gate_open or _arm == null:
		return
	gate_open = true
	if _gate_tween != null:
		_gate_tween.kill()
	_gate_tween = create_tween()
	_gate_tween.tween_property(_arm, "rotation:z", GATE_OPEN_ANGLE, GATE_SECONDS) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _wake_workers(awake: bool) -> void:
	for worker: Node3D in workers:
		worker.process_mode = Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED


# --- Ground, fence, building ----------------------------------------------

func _build_static() -> void:
	var solid := GoalLotKit.Boxes.new()
	var glass := GoalLotKit.Boxes.new()
	var depth: float = FRONT_Z - BACK_Z
	var mid_z: float = (FRONT_Z + BACK_Z) * 0.5
	var slab_at := Vector3(0.0, SLAB_TOP - 0.25, mid_z)
	solid.add(Vector3(HALF_WIDTH * 2.0, 0.5, depth), Transform3D(Basis.IDENTITY, slab_at), ASPHALT)
	# Kerb along both sides and the front, open at the gate.
	for side: float in [-1.0, 1.0]:
		solid.add_standing(Vector3(0.4, 0.15, depth), Vector3(side * (HALF_WIDTH - 0.2), SLAB_TOP, mid_z), KERB)
		var run: float = HALF_WIDTH - GATE_HALF - 0.5
		var front_at := Vector3(side * (GATE_HALF + 0.5 + run * 0.5), SLAB_TOP, FRONT_Z - 0.2)
		solid.add_standing(Vector3(run, 0.15, 0.4), front_at, KERB)
	_build_fence(solid, glass)
	_build_paint(solid)
	_build_building(solid)
	_build_booth(solid)
	_build_cart_and_hose(solid, glass)
	var body := solid.build()
	body.name = "LotStatic"
	add_child(body)
	var panes := glass.build(_translucent_material())
	panes.name = "LotTranslucent"
	panes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panes)


static var _translucent: StandardMaterial3D


static func _translucent_material() -> StandardMaterial3D:
	if _translucent == null:
		_translucent = GoalLotKit.coloured_material().duplicate() as StandardMaterial3D
		_translucent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_translucent.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _translucent


func _build_fence(solid: GoalLotKit.Boxes, panes: GoalLotKit.Boxes) -> void:
	var depth: float = FRONT_Z - BACK_Z
	var mid_z: float = (FRONT_Z + BACK_Z) * 0.5
	var mesh_colour := Color(0.72, 0.8, 0.82, 0.22)
	var runs: Array[Array] = []
	for side: float in [-1.0, 1.0]:
		runs.append([Vector3(side * (HALF_WIDTH - 0.05), 0.0, mid_z), depth, true])
		var run: float = HALF_WIDTH - GATE_HALF - 0.5
		runs.append([Vector3(side * (GATE_HALF + 0.5 + run * 0.5), 0.0, FRONT_Z - 0.05), run, false])
	for entry: Array in runs:
		var centre: Vector3 = entry[0]
		var length: float = entry[1]
		var along_z: bool = entry[2]
		var size := Vector3(0.08, 0.08, length) if along_z else Vector3(length, 0.08, 0.08)
		for height: float in [FENCE_HEIGHT - 0.05, 1.1]:
			solid.add(size, Transform3D(Basis.IDENTITY, centre + Vector3(0.0, SLAB_TOP + height, 0.0)), POST)
		var pane := Vector3(0.02, FENCE_HEIGHT - 0.3, length) if along_z else Vector3(length, FENCE_HEIGHT - 0.3, 0.02)
		var pane_at: Vector3 = centre + Vector3(0.0, SLAB_TOP + FENCE_HEIGHT * 0.5, 0.0)
		panes.add(pane, Transform3D(Basis.IDENTITY, pane_at), mesh_colour)
		var posts: int = ceili(length / 3.8) + 1
		for index: int in range(posts):
			var offset: float = -length * 0.5 + length * float(index) / float(posts - 1)
			var at: Vector3 = centre + (Vector3(0.0, 0.0, offset) if along_z else Vector3(offset, 0.0, 0.0))
			solid.add_standing(Vector3(0.14, FENCE_HEIGHT, 0.14), at + Vector3(0.0, SLAB_TOP, 0.0), POST)
	# Gate pillars.
	for side: float in [-1.0, 1.0]:
		var pillar := Vector3(side * (GATE_HALF + 0.25), SLAB_TOP, FRONT_Z - 0.3)
		solid.add_standing(Vector3(0.5, 3.0, 0.5), pillar, KERB)
		solid.add_standing(Vector3(0.62, 0.2, 0.62), pillar + Vector3(0.0, 3.0, 0.0), TEAL)


func _build_paint(solid: GoalLotKit.Boxes) -> void:
	var y: float = SLAB_TOP
	var span: float = BAY_LENGTH - 0.2
	var mid_z: float = (BAY_BACK_Z + BAY_FRONT_Z) * 0.5
	var free_x: float = bay_x(free_index)
	# The free bay's floor, under the lines.
	solid.add_standing(Vector3(BAY_WIDTH - 0.14, 0.008, span), Vector3(free_x, y, mid_z), TEAL_DARK)
	for index: int in range(BAY_COUNT + 1):
		var x: float = (float(index) - float(BAY_COUNT) * 0.5) * BAY_WIDTH
		solid.add_standing(Vector3(0.14, 0.012, span), Vector3(x, y, mid_z), LINE)
	solid.add_standing(Vector3(BAY_WIDTH * BAY_COUNT, 0.012, 0.14), Vector3(0.0, y, BAY_BACK_Z + 0.07), LINE)
	# Yellow round the free one, dashes across its mouth.
	for side: float in [-1.0, 1.0]:
		solid.add_standing(Vector3(0.2, 0.016, span), Vector3(free_x + side * BAY_WIDTH * 0.5, y, mid_z), YELLOW)
	solid.add_standing(Vector3(BAY_WIDTH, 0.016, 0.2), Vector3(free_x, y, BAY_BACK_Z + 0.1), YELLOW)
	for dash: int in range(5):
		var x: float = free_x + (float(dash) - 2.0) * 0.8
		solid.add_standing(Vector3(0.5, 0.016, 0.2), Vector3(x, y, BAY_FRONT_Z - 0.1), YELLOW)
	# The floor arrow leading in, tip toward the bay.
	var tip: Vector3 = Vector3(free_x, y, BAY_FRONT_Z + 4.4)
	solid.add_standing(Vector3(0.45, 0.014, 3.0), tip + Vector3(0.0, 0.0, 2.3), LINE)
	for side: float in [-1.0, 1.0]:
		var bar_yaw: float = side * deg_to_rad(38.0)
		var toward_back: Vector3 = Vector3(sin(bar_yaw), 0.0, cos(bar_yaw))
		var bar_at: Vector3 = tip + toward_back + Vector3(0.0, 0.007, 0.0)
		solid.add(Vector3(0.45, 0.014, 2.0), Transform3D(Basis(Vector3.UP, bar_yaw), bar_at), LINE)
	# Rails of chevrons down the middle of the lane from the gate: a hint of the way.
	for step: int in range(3):
		var at: Vector3 = Vector3(0.0, y, -6.0 - float(step) * 3.0)
		for side: float in [-1.0, 1.0]:
			var bar_yaw: float = side * deg_to_rad(40.0)
			var chevron_at: Vector3 = at + Vector3(side * 0.45, 0.006, 0.55)
			solid.add(Vector3(0.3, 0.012, 1.4), Transform3D(Basis(Vector3.UP, bar_yaw), chevron_at), LINE)


func _build_building(solid: GoalLotKit.Boxes) -> void:
	var centre_z: float = BACK_Z - BUILDING_DEPTH * 0.5
	var width: float = HALF_WIDTH * 2.0 + 1.0
	solid.add_standing(Vector3(width, BUILDING_HEIGHT, BUILDING_DEPTH), Vector3(0.0, 0.0, centre_z), WALL)
	solid.add_standing(Vector3(width + 0.4, 0.3, BUILDING_DEPTH + 0.4), Vector3(0.0, BUILDING_HEIGHT, centre_z), ROOF)
	solid.add_standing(Vector3(width + 0.02, 0.35, 0.1), Vector3(0.0, BUILDING_HEIGHT - 0.35, BACK_Z + 0.05), TEAL)
	# A roller door and a dark strip of windows behind each bay.
	for index: int in range(BAY_COUNT):
		var x: float = bay_x(index)
		solid.add_standing(Vector3(3.2, 3.1, 0.08), Vector3(x, 0.0, BACK_Z + 0.04), Color("59636a"))
		for slat: int in range(5):
			var groove_at := Vector3(x, 0.5 + float(slat) * 0.55, BACK_Z + 0.05)
			solid.add_standing(Vector3(3.2, 0.05, 0.1), groove_at, Color("48525a"))
	# The base sign on the roof: two posts and the board's frame.
	for side: float in [-1.0, 1.0]:
		solid.add_standing(Vector3(0.35, 0.8, 0.35), Vector3(side * 6.0, BUILDING_HEIGHT + 0.3, BACK_Z - 1.6), POST)
	var board := Transform3D(Basis.IDENTITY, Vector3(0.0, BUILDING_HEIGHT + 2.4, BACK_Z - 1.6))
	solid.add(Vector3(15.0, 3.0, 0.3), board, BOARD)
	solid.add(Vector3(15.0, 0.2, 0.32), Transform3D(Basis.IDENTITY, board.origin + Vector3(0.0, 1.4, 0.0)), TEAL)
	solid.add(Vector3(15.0, 0.2, 0.32), Transform3D(Basis.IDENTITY, board.origin + Vector3(0.0, -1.4, 0.0)), TEAL)
	# The plaques over the bays: a small dark one over each parked truck, a
	# big teal one over the free bay.
	for index: int in range(BAY_COUNT):
		var x: float = bay_x(index)
		if index == free_index:
			solid.add(Vector3(3.8, 1.6, 0.12), Transform3D(Basis.IDENTITY, Vector3(x, 3.9, BACK_Z + 0.08)), TEAL_DARK)
			solid.add(Vector3(3.9, 0.12, 0.14), Transform3D(Basis.IDENTITY, Vector3(x, 4.7, BACK_Z + 0.08)), YELLOW)
			solid.add(Vector3(3.9, 0.12, 0.14), Transform3D(Basis.IDENTITY, Vector3(x, 3.1, BACK_Z + 0.08)), YELLOW)
		else:
			solid.add(Vector3(1.5, 0.9, 0.1), Transform3D(Basis.IDENTITY, Vector3(x, 3.9, BACK_Z + 0.07)), BOARD)


func _build_booth(solid: GoalLotKit.Boxes) -> void:
	var at: Vector3 = Vector3(GATE_HALF + 2.4, SLAB_TOP, FRONT_Z - 2.6)
	solid.add_standing(Vector3(2.6, 2.4, 2.4), at, Color("d8ddd2"))
	solid.add_standing(Vector3(3.2, 0.2, 3.0), at + Vector3(0.0, 2.4, 0.0), RED)
	# Windows on the road side and the approach side.
	solid.add_standing(Vector3(0.06, 0.9, 1.7), at + Vector3(-1.3, 1.1, 0.0), DARK)
	solid.add_standing(Vector3(1.9, 0.9, 0.06), at + Vector3(0.0, 1.1, 1.2), DARK)
	# The barrier's post, on the right-hand pillar.
	solid.add_standing(Vector3(0.3, 1.0, 0.3), Vector3(GATE_HALF - 0.05, SLAB_TOP, FRONT_Z - 0.3), RED)


## An empty cart, some boxes' worth of pallets and the wash hose.
func _build_cart_and_hose(solid: GoalLotKit.Boxes, glass: GoalLotKit.Boxes) -> void:
	var cart: Vector3 = Vector3(unload_side * 15.4, SLAB_TOP, -6.4)
	solid.add_standing(Vector3(1.4, 0.08, 0.9), cart + Vector3(0.0, 0.3, 0.0), CART)
	for wheel_x: float in [-0.55, 0.55]:
		for wheel_z: float in [-0.35, 0.35]:
			solid.add_standing(Vector3(0.1, 0.24, 0.24), cart + Vector3(wheel_x, 0.0, wheel_z), DARK)
	solid.add_standing(Vector3(0.05, 0.75, 0.9), cart + Vector3(unload_side * -0.7, 0.3, 0.0), CART)
	var hose_side: float = -unload_side
	var tap: Vector3 = Vector3(hose_side * (HALF_WIDTH - 0.4), SLAB_TOP, -14.0)
	solid.add_standing(Vector3(0.3, 0.7, 0.3), tap, POST)
	solid.add_standing(Vector3(0.4, 0.12, 0.12), tap + Vector3(-hose_side * 0.3, 0.55, 0.0), YELLOW)
	var end: Vector3 = Vector3(hose_side * 13.8, SLAB_TOP, -17.4)
	var previous: Vector3 = tap + Vector3(-hose_side * 0.45, 0.06, 0.0)
	var pieces: int = 14
	for step: int in range(1, pieces + 1):
		var t: float = float(step) / float(pieces)
		var point: Vector3 = tap.lerp(end, t) + Vector3(0.0, 0.06, sin(t * TAU) * 1.1)
		var length: float = previous.distance_to(point)
		if length > 0.01:
			var facing := Basis.looking_at((point - previous).normalized(), Vector3.UP)
			solid.add(Vector3(0.1, 0.1, length + 0.04), Transform3D(facing, (previous + point) * 0.5), HOSE_GREEN)
		previous = point
	solid.add(Vector3(0.14, 0.14, 0.4), Transform3D(Basis.IDENTITY, end + Vector3(0.0, 0.1, 0.0)), YELLOW)
	var puddle_at: Vector3 = end + Vector3(hose_side * -1.4, 0.02, 0.0)
	glass.add(Vector3(3.0, 0.01, 2.0), Transform3D(Basis.IDENTITY, puddle_at), Color(0.25, 0.4, 0.5, 0.5))


# --- Signs ----------------------------------------------------------------

func _build_signs() -> void:
	var board_z: float = BACK_Z - 1.6 + 0.2
	var y: float = BUILDING_HEIGHT + 2.4
	_text("SignTitle", tr("WORLD_LOT_SIGN_TITLE"), Vector3(0.0, y + 0.45, board_z), 150, 0.0085, WHITE)
	_text("SignTown", "— %s —" % town_name, Vector3(0.0, y - 0.6, board_z), 96, 0.0085, TEAL)
	var free_x: float = bay_x(free_index)
	_text("FreeBayWord", tr("WORLD_LOT_FREE_BAY"), Vector3(free_x, 4.28, BACK_Z + 0.16), 110, 0.0065, WHITE)
	_text("FreeBayNumberWall", str(bay_number), Vector3(free_x, 3.5, BACK_Z + 0.16), 110, 0.0065, YELLOW)
	for index: int in range(BAY_COUNT):
		if index != free_index:
			_text("BayPlaque%d" % (first_number + index), str(first_number + index),
					Vector3(bay_x(index), 3.9, BACK_Z + 0.14), 100, 0.0075, WHITE)
	# The number painted on the ground in front of the free bay.
	var painted: Label3D = _text("FreeBayNumberFloor", str(bay_number),
			Vector3(free_x, SLAB_TOP + 0.03, BAY_FRONT_Z + 2.0), 230, 0.012, WHITE)
	painted.rotation_degrees.x = -90.0


func _text(node_name: String, text: String, at: Vector3, font_size: int, pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font = RouteProps.SIGN_FONT
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 10
	label.outline_modulate = Color("16252a")
	label.shaded = false
	label.position = at
	add_child(label)
	return label


# --- Trucks, cones, boxes, lamps ------------------------------------------

func _truck_transform(x: float, yaw: float, nose_z: float) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw + PI * 0.5).scaled(Vector3.ONE * TRUCK_SCALE)
	return Transform3D(basis, Vector3(x, SLAB_TOP, nose_z + TRUCK_NOSE))


## Model prep for the parked trucks: no authored shelving (like the driven
## truck), see-through panes, and the rear doors open on the unloading one.
static func _prepare_truck(root: Node3D, rear_open: bool) -> void:
	for node: Node in root.find_children("Shelf*", "", true, false):
		node.get_parent().remove_child(node)
		node.free()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		for surface: int in range(part.mesh.get_surface_count()):
			var material: Material = part.mesh.surface_get_material(surface)
			if material != null and material.resource_name == ReferenceTruck.GLASS_MATERIAL:
				part.material_override = GoalLotKit.glass_material()
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if rear_open:
		for leaf: Array in ReferenceTruck.DOORS[&"rear"]:
			var hinge := root.find_child(leaf[0], true, false) as Node3D
			if hinge != null:
				hinge.rotation.y = float(leaf[1])


func _build_trucks() -> void:
	var xforms: Array[Transform3D] = []
	for index: int in range(BAY_COUNT):
		if index == free_index:
			continue
		var jitter: Vector3 = truck_jitter[index]
		xforms.append(_truck_transform(bay_x(index) + jitter.x, jitter.y, BAY_BACK_Z + 0.7 + jitter.z))
	truck_transforms = xforms
	var closed: Mesh = GoalLotKit.merged_model(TRUCK_PATH, "closed",
			func(root: Node3D) -> void: _prepare_truck(root, false), false)
	if closed != null:
		var parked := GoalLotKit.multimesh_instance(closed, xforms)
		parked.name = "ParkedTrucks"
		add_child(parked)
	var open: Mesh = GoalLotKit.merged_model(TRUCK_PATH, "open",
			func(root: Node3D) -> void: _prepare_truck(root, true), false)
	if open != null:
		var unloading := MeshInstance3D.new()
		unloading.name = "UnloadingTruck"
		unloading.mesh = open
		unloading.transform = _truck_transform(unload_side * 15.4, 0.0, -16.4)
		add_child(unloading)


func _build_props() -> void:
	# Cones at the mouth of the free bay: knocked over if hit, like the road's.
	var cone_mesh: Mesh = GoalLotKit.merged_model(CONE_PATH)
	var free_x: float = bay_x(free_index)
	for side: float in [-1.0, 1.0]:
		for offset: float in [0.45, 1.6]:
			var cone := RigidBody3D.new()
			cone.name = "Cone%d" % cones.size()
			cone.collision_layer = 1
			cone.collision_mask = 1 | 2
			cone.mass = 3.0
			cone.can_sleep = true
			cone.position = Vector3(free_x + side * (BAY_WIDTH * 0.5 + 0.1 * offset), SLAB_TOP + 0.005,
					BAY_FRONT_Z + offset)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.36, 0.7, 0.36)
			shape.shape = box
			shape.position = Vector3(0.0, 0.37, 0.0)
			cone.add_child(shape)
			if cone_mesh != null:
				var visual := MeshInstance3D.new()
				visual.mesh = cone_mesh
				cone.add_child(visual)
			add_child(cone)
			cone.sleeping = true
			cones.append(cone)
	# Cargo boxes: on the cart and stacked by the unloading truck's tail.
	var box_mesh: Mesh = GoalLotKit.merged_model(BOX_PATH, "", Callable(), false)
	if box_mesh == null:
		return
	var cart_x: float = unload_side * 15.4
	var at: Array[Vector3] = [
		Vector3(cart_x - 0.32, 0.38, -6.4), Vector3(cart_x + 0.32, 0.38, -6.4),
		Vector3(cart_x, 0.38, -6.4 - 0.05), Vector3(cart_x - 0.16, 1.03, -6.4),
		Vector3(cart_x + unload_side * -2.0, 0.0, -8.2), Vector3(cart_x + unload_side * -2.7, 0.0, -8.0),
		Vector3(cart_x + unload_side * -2.3, 0.65, -8.1),
	]
	var xforms: Array[Transform3D] = []
	for index: int in range(at.size()):
		var point: Vector3 = at[index] + Vector3(0.0, SLAB_TOP, 0.0)
		xforms.append(Transform3D(Basis(Vector3.UP, float(index) * 0.7), point))
	var crates := GoalLotKit.multimesh_instance(box_mesh, xforms)
	crates.name = "CargoBoxes"
	add_child(crates)


func _build_lamps() -> void:
	var mesh: Mesh = GoalLotKit.merged_model(LAMP_PATH, "lit", func(root: Node3D) -> void:
		LowpolyMaterials.light_up(root, ["lamp_glass"]))
	var xforms: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		for z: float in [-5.5, -19.0]:
			var lamp_yaw: float = 0.0 if side < 0.0 else PI
			var lamp := Transform3D(Basis(Vector3.UP, lamp_yaw), Vector3(side * (HALF_WIDTH - 1.6), SLAB_TOP, z))
			xforms.append(lamp)
			lamp_spots.append(lamp * LAMP_GLASS)
			_lamp_bases.append(lamp.origin)
	if mesh != null:
		var lamps := GoalLotKit.multimesh_instance(mesh, xforms)
		lamps.name = "Lamps"
		add_child(lamps)


## After dark the lamps light the slab and the free bay has a light of its
## own. Off on the lowest quality (world_quality.gd), where the glow and the
## halos alone remain.
func _build_lights() -> void:
	if WorldQuality.level == WorldQuality.Level.LOW:
		return
	var lights: Array[Dictionary] = []
	for spot: Vector3 in lamp_spots:
		lights.append({"at": spot + Vector3(0.0, -0.3, 0.0), "colour": Color(1.0, 0.8, 0.55),
				"energy": 1.3, "range": 15.0})
	lights.append({"at": Vector3(bay_x(free_index), 4.6, BAY_FRONT_Z - 1.0), "colour": Color(0.6, 1.0, 0.9),
			"energy": 1.1, "range": 12.0})
	for entry: Dictionary in lights:
		var light := OmniLight3D.new()
		light.name = "LotLight"
		light.position = entry.at
		light.light_color = entry.colour
		light.light_energy = float(entry.energy) * darkness
		light.omni_range = float(entry.range)
		light.shadow_enabled = false
		add_child(light)


# --- Gate ------------------------------------------------------------------

func _build_gate() -> void:
	_arm = Node3D.new()
	_arm.name = "BarrierArm"
	_arm.position = Vector3(GATE_HALF, SLAB_TOP + 1.05, FRONT_Z - 0.3)
	add_child(_arm)
	var stripes := GoalLotKit.Boxes.new()
	var piece: float = ARM_LENGTH / float(ARM_SEGMENTS)
	for index: int in range(ARM_SEGMENTS):
		var stripe_at := Vector3(-(float(index) + 0.5) * piece, 0.0, 0.0)
		stripes.add(Vector3(piece, 0.14, 0.14), Transform3D(Basis.IDENTITY, stripe_at),
				RED if index % 2 == 0 else WHITE)
	var mesh := stripes.build()
	mesh.name = "ArmStripes"
	_arm.add_child(mesh)


# --- People ----------------------------------------------------------------

func _build_workers() -> void:
	var truck_x: float = unload_side * 15.4
	var lines_a: PackedStringArray = [tr("WORLD_LOT_WORKER_1"), tr("WORLD_LOT_WORKER_2")]
	var lines_b: PackedStringArray = [tr("WORLD_LOT_WORKER_3"), tr("WORLD_LOT_WORKER_2")]
	# One carries boxes between the truck's tail and the cart.
	workers.append(_worker("WorkerCarrier", Vector3(truck_x + 0.9, SLAB_TOP, -8.2),
			[Vector3(truck_x + 0.9, 0.0, -8.4), Vector3(truck_x + 1.0, 0.0, -6.9)], lines_a))
	# The other stands by the cart checking the load.
	var checker: Node3D = _worker("WorkerChecker", Vector3(truck_x - unload_side * 1.6, SLAB_TOP, -6.9), [], lines_b)
	checker.rotation.y = PI * 0.5 * -unload_side
	workers.append(checker)
	_wake_workers(false)


func _worker(node_name: String, at: Vector3, waypoints: Array[Vector3], lines: PackedStringArray) -> Node3D:
	var worker := DepotWorker.new()
	worker.name = node_name
	worker.position = at
	worker.waypoints = waypoints
	worker.lines = lines
	worker.walk_speed = 1.0
	add_child(worker)
	return worker


# --- Collisions ------------------------------------------------------------

func _build_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "LotColliders"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	# The slab: a prism, its mouth ramped down to the road so the wheels do not hit a step.
	var slab := CollisionShape3D.new()
	slab.name = "Slab"
	var prism := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for side: float in [-1.0, 1.0]:
		var x: float = side * HALF_WIDTH
		points.append_array([Vector3(x, -0.5, FRONT_Z), Vector3(x, -0.5, BACK_Z), Vector3(x, 0.0, FRONT_Z),
				Vector3(x, SLAB_TOP, FRONT_Z - 1.5), Vector3(x, SLAB_TOP, BACK_Z)])
	prism.points = points
	slab.shape = prism
	body.add_child(slab)
	var depth: float = FRONT_Z - BACK_Z
	var run: float = HALF_WIDTH - GATE_HALF - 0.5
	for side: float in [-1.0, 1.0]:
		var fence_y: float = SLAB_TOP + FENCE_HEIGHT * 0.5
		_box(body, "SideFence", Vector3(0.3, FENCE_HEIGHT, depth),
				Vector3(side * HALF_WIDTH, fence_y, (FRONT_Z + BACK_Z) * 0.5))
		_box(body, "FrontFence", Vector3(run, FENCE_HEIGHT, 0.3),
				Vector3(side * (GATE_HALF + 0.5 + run * 0.5), fence_y, FRONT_Z - 0.05))
		_box(body, "GatePillar", Vector3(0.5, 3.0, 0.5),
				Vector3(side * (GATE_HALF + 0.25), SLAB_TOP + 1.5, FRONT_Z - 0.3))
	_box(body, "Building", Vector3(HALF_WIDTH * 2.0 + 1.0, BUILDING_HEIGHT, BUILDING_DEPTH),
			Vector3(0.0, BUILDING_HEIGHT * 0.5, BACK_Z - BUILDING_DEPTH * 0.5))
	_box(body, "Booth", Vector3(2.6, 2.4, 2.4), Vector3(GATE_HALF + 2.4, SLAB_TOP + 1.2, FRONT_Z - 2.6))
	for base: Vector3 in _lamp_bases:
		_box(body, "LampPost", Vector3(0.3, 4.5, 0.3), base + Vector3(0.0, 2.25, 0.0))
	for index: int in range(BAY_COUNT):
		if index == free_index:
			continue
		var jitter: Vector3 = truck_jitter[index]
		var nose_z: float = BAY_BACK_Z + 0.7 + jitter.z
		_truck_box(body, bay_x(index) + jitter.x, jitter.y, nose_z)
	_truck_box(body, unload_side * 15.4, 0.0, -16.4)


func _truck_box(body: StaticBody3D, x: float, yaw: float, nose_z: float) -> void:
	var length: float = TRUCK_NOSE + TRUCK_TAIL
	var centre_z: float = nose_z + length * 0.5
	var shape := _box(body, "ParkedTruck", Vector3(TRUCK_WIDTH, TRUCK_HEIGHT, length),
			Vector3(x, SLAB_TOP + 0.25 + TRUCK_HEIGHT * 0.5, centre_z))
	# Turned about the truck's own middle, like the drawn one.
	var pivot: Vector3 = Vector3(x, 0.0, nose_z + TRUCK_NOSE)
	var turn := Basis(Vector3.UP, yaw)
	shape.transform = Transform3D(turn, pivot + turn * (shape.position - pivot))


func _box(body: StaticBody3D, node_name: String, size: Vector3, at: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.name = node_name
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)
	return shape
