class_name DepotDressing
extends RefCounted
## What makes the depot feel lived in: the facade lettering and safety
## posters, the wall clock, the ceiling fans, the staff at their posts (and
## the forklift), and the radio in the break area. The moving parts are
## handed to DepotAmbience, which animates them.

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")
const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const RADIO_PROGRAM: AudioStream = preload("res://assets/audio/music/mus_depot_radio_loop.ogg")

var clock_hour: Node3D
var clock_minute: Node3D
var fans: Array[Node3D] = []

var _root: Node3D


func _init(root: Node3D) -> void:
	_root = root


func build_signs() -> void:
	# Facade: the company's name over the door, readable from the road.
	var facade := DepotLabels.text(_root, "TAKE MY PACKAGE", Vector3(0.0, 6.6, -Layout.WALL - 0.05), PI, 110,
			Color("ffc93c"), Layout.DISPLAY_FONT, 0.009, 20)
	facade.name = "FacadeTitle"
	DepotLabels.text(_root, tr("WORLD_DEPOT_FACADE_SUB"), Vector3(0.0, 5.65, -Layout.WALL - 0.05), PI, 44, Layout.PAPER,
			Layout.DISPLAY_FONT, 0.008, 10)
	DepotLabels.text(_root, tr("WORLD_DEPOT_STAFF"), Vector3(9.5, 2.35, -Layout.WALL - 0.09), PI, 36, Layout.PAPER,
			Layout.DISPLAY_FONT, 0.006, 6)
	# Inside, on the board across the roller door's drum (sm_env_depot_door_frame):
	# in front of the drum, so it reads from right under the door too.
	# The board leans 0.3 rad toward the room; the text sits 4 cm off its face.
	var exit_sign := DepotLabels.text(_root, tr("WORLD_DEPOT_DOOR_INSIDE"),
			Vector3(0.0, Layout.FLOOR_TOP + Layout.DOOR_HEIGHT + 0.45 - 0.04 * sin(0.3),
					0.02 + 0.855 + 0.04 * cos(0.3)),
			0.0, 64, Color("ffc93c"), Layout.DISPLAY_FONT, 0.008, 14)
	exit_sign.rotation.x = 0.3
	exit_sign.name = "ExitSign"
	# Safety posters on the walls.
	# On the front wall, left of the door: on the left wall it hung behind
	# the stock racking, where nobody could read it.
	_poster(Vector3(-7.5, 2.2, 0.06), 0.0, tr("WORLD_DEPOT_POSTER_VEST_TITLE"),
			tr("WORLD_DEPOT_POSTER_VEST_BODY"), Color("ff9f1c"))
	_poster(Vector3(-Layout.HALF_WIDTH + 0.07, 2.2, 31.2), PI * 0.5, tr("WORLD_DEPOT_POSTER_LIFT_TITLE"),
			tr("WORLD_DEPOT_POSTER_LIFT_BODY"), Color("4cc9f0"))
	# Between the column at z 24.8 and the supplies shelf (from z 26.65),
	# which used to hide half of it.
	# On the wardrobe's partition, facing the hall: under the mezzanine it would
	# hang in the dark.
	_poster(Vector3(DepotZones.WALL_X - 0.08, 2.0, 14.3), -PI * 0.5, tr("WORLD_DEPOT_POSTER_FRAGILE_TITLE"),
			tr("WORLD_DEPOT_POSTER_FRAGILE_BODY"), Color("ff5e5b"))
	_poster(Vector3(-8.0, 2.4, Layout.DEPTH - 0.07), PI, tr("WORLD_DEPOT_POSTER_ONEBOX_TITLE"),
			tr("WORLD_DEPOT_POSTER_ONEBOX_BODY"), Color("2dd4a3"))
	_build_clock()


func _poster(at: Vector3, yaw: float, title: String, body: String, accent: Color) -> void:
	var kit := DepotKit.new(_root, "PosterColliders")
	var basis := Basis(Vector3.UP, yaw)
	kit.box_xf(Vector3(1.1, 1.5, 0.02), Transform3D(basis, at), DepotKit.flat(Layout.PAPER, 0.9))
	# The header band stands 1 cm proud of the paper (it was 2.5 mm, and the
	# two faces shimmered into each other from across the hall).
	var band_at: Vector3 = at + basis * Vector3(0.0, 0.0, 0.01) + Vector3(0.0, 0.58, 0.0)
	kit.box_xf(Vector3(1.1, 0.34, 0.02), Transform3D(basis, band_at), DepotKit.flat(accent, 0.8))
	kit.commit("Poster")
	var face: Vector3 = basis * Vector3(0.0, 0.0, 0.03)
	var heading := DepotLabels.text(_root, title, at + face + Vector3(0.0, 0.58, 0.0), yaw, 34, Layout.PAPER,
			Layout.DISPLAY_FONT, 0.0045, 6)
	DepotLabels.fit_label(heading, 0.98)
	var text := DepotLabels.text(_root, body, at + face + Vector3(0.0, -0.05, 0.0), yaw, 30, Layout.INK,
			Layout.BODY_FONT, 0.004, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.width = 240


func _build_clock() -> void:
	var clock := Node3D.new()
	clock.name = "WallClock"
	clock.position = Vector3(3.0, 4.8, Layout.DEPTH - 0.08)
	clock.rotation.y = PI
	_root.add_child(clock)
	# Body, face and ticks: one model, face toward the clock's +Z.
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = DepotKit.merged_mesh(DepotKit.depot_model("sm_env_depot_wall_clock"))
	clock.add_child(body)
	clock_hour = _clock_hand(clock, "sm_env_depot_clock_hand_hour")
	clock_minute = _clock_hand(clock, "sm_env_depot_clock_hand_minute")


## A hand on its spindle: the model points +Y from its origin, the pivot
## turns about Z (see DepotAmbience).
func _clock_hand(clock: Node3D, model_name: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.position.z = 0.05
	clock.add_child(pivot)
	var hand := MeshInstance3D.new()
	hand.mesh = DepotKit.merged_mesh(DepotKit.depot_model(model_name))
	pivot.add_child(hand)
	return pivot


func build_fans() -> void:
	# Two big ceiling fans turning slowly.
	for at: Vector3 in [Vector3(-3.0, 6.3, 20.8), Vector3(6.5, 6.3, 16.0)]:
		var fan := Node3D.new()
		fan.name = "CeilingFan"
		fan.position = at
		_root.add_child(fan)
		var kit := DepotKit.new(fan, "FanColliders")
		kit.model(DepotKit.depot_model("sm_env_depot_ceiling_fan"), Transform3D.IDENTITY)
		kit.commit("Fan")
		var rod := MeshInstance3D.new()
		var rod_mesh := CylinderMesh.new()
		rod_mesh.top_radius = 0.03
		rod_mesh.bottom_radius = 0.03
		rod_mesh.height = Layout.CEILING - at.y
		rod.mesh = rod_mesh
		rod.material_override = DepotKit.flat(Color("263238"), 0.5, 0.4)
		rod.position = at + Vector3(0.0, (Layout.CEILING - at.y) * 0.5, 0.0)
		_root.add_child(rod)
		fans.append(fan)


func build_life() -> void:
	# The clerk behind the cage's window, facing the truck bay (+X).
	var clerk := _worker(Vector3(-11.0, Layout.FLOOR_TOP, 5.4), -PI * 0.5, Color("2dd4a3"), [
		tr("WORLD_DEPOT_CLERK_1"), tr("WORLD_DEPOT_CLERK_2"), tr("WORLD_DEPOT_CLERK_3")])
	clerk.name = "Clerk"
	# At the desk in the office on the mezzanine.
	var dispatcher := _worker(Vector3(11.4, Layout.FLOOR_TOP + Layout.MEZZANINE_HEIGHT, 29.95), PI, Color("4cc9f0"), [
		tr("WORLD_DEPOT_DISPATCHER_1"), tr("WORLD_DEPOT_DISPATCHER_2")])
	dispatcher.name = "Dispatcher"
	var packer := _worker(Vector3(2.2, Layout.FLOOR_TOP, 28.2), 0.0, Color("ff9f1c"), [
		tr("WORLD_DEPOT_PACKER_1"), tr("WORLD_DEPOT_PACKER_2"), tr("WORLD_DEPOT_PACKER_3")])
	packer.name = "Packer"
	var mechanic := _worker(Vector3(13.5, Layout.FLOOR_TOP, 5.2), -PI * 0.5, Color("c0392b"), [
		tr("WORLD_DEPOT_MECHANIC_1"), tr("WORLD_DEPOT_MECHANIC_2")])
	mechanic.name = "Mechanic"
	var walker := _worker(Vector3(-8.5, Layout.FLOOR_TOP, 25.2), 0.0, Color("ffc93c"), [
		tr("WORLD_DEPOT_WALKER_1"), tr("WORLD_DEPOT_WALKER_2"), tr("WORLD_DEPOT_WALKER_3")])
	walker.name = "StockWalker"
	walker.waypoints = [Vector3(-8.5, Layout.FLOOR_TOP, 14.4), Vector3(-8.5, Layout.FLOOR_TOP, 25.2),
			Vector3(-2.6, Layout.FLOOR_TOP, 25.0),
		Vector3(0.6, Layout.FLOOR_TOP, 29.0), Vector3(-2.6, Layout.FLOOR_TOP, 25.0), Vector3(-8.5, Layout.FLOOR_TOP,
				25.2)]
	var forklift := DepotForklift.new()
	forklift.name = "Forklift"
	forklift.place(Vector3(Layout.FORKLIFT_LANE_X, Layout.FLOOR_TOP, Layout.FORKLIFT_LANE_Z.x + 1.6),
			Vector3(Layout.FORKLIFT_LANE_X, Layout.FLOOR_TOP, 26.2))
	_root.add_child(forklift)


func _worker(at: Vector3, yaw: float, uniform: Color, lines: Array) -> DepotWorker:
	var worker := DepotWorker.new()
	worker.uniform = uniform
	worker.position = at
	worker.rotation.y = yaw
	worker.lines = PackedStringArray(lines)
	_root.add_child(worker)
	return worker


func build_audio() -> void:
	# No room tone: the hum over the loading zone grated, even brought down to
	# its measured level (playtest 2026-09-25) -- the user asked for it gone.
	var radio := AudioStreamPlayer3D.new()
	radio.name = "Radio"
	# The break area's radio (N-403): a lo-fi program composed for it.
	var program := RADIO_PROGRAM.duplicate() as AudioStreamOggVorbis
	program.loop = true
	radio.stream = program
	radio.bus = &"Music"
	radio.volume_db = WorldMix.DEPOT_RADIO_DB
	radio.unit_size = 3.0
	radio.max_distance = 22.0
	radio.position = Vector3(12.8, 1.1, 21.0)
	radio.autoplay = true
	_root.add_child(radio)
