class_name ReferenceTruck
extends Node3D
## Presentation adapter for the authored low-poly box truck. Gameplay stays in
## vehicle.tscn (collision, seats, mounts, door controls, wheels), laid out to
## match this model; this node only dresses it: hangs the model, makes the
## glass see-through, puts the authored wheels on the physics wheels, turns
## the steering wheel, animates the doors and ramp, and builds the cargo rack
## art from the very collision shapes the packages rest on.

const TRUCK_PATH := "res://assets/models/truck_reference_lowpoly.glb"
const MODEL_SCALE := 0.8
## Blender's +X front becomes Godot's -Z front; the offset lines the model's
## floor, axles and cab up with the collision in vehicle.tscn.
const MODEL_OFFSET := Vector3(0.0, -0.674, 0.604)
const GLASS_MATERIAL := "DT_Glass"
const DOOR_SECONDS := 0.55
const RAMP_SECONDS := 0.4
## Hinge node, opening direction and angle (radians) of every door leaf.
## Blender's vertical Z axis is Godot's Y inside the model, so each hinge
## swings on its own rotation.y; the sign sends the leaf outward.
const DOORS := {
	&"rear": [["RearDoor_Left_HINGE_Z", -1.92], ["RearDoor_Right_HINGE_Z", 1.92]],
	&"cab_left": [["CabDoor_Left_HINGE_Z", -1.1]],
	&"cab_right": [["CabDoor_Right_HINGE_Z", 1.1]],
}
const WHEELS := {
	"Wheel_Front_Left_AXLE_Y": "FrontLeftWheel",
	"Wheel_Front_Right_AXLE_Y": "FrontRightWheel",
	"Wheel_Rear_Left_AXLE_Y": "RearLeftWheel",
	"Wheel_Rear_Right_AXLE_Y": "RearRightWheel",
}
const RACK_ACCENT := Color("f0a236")

var vehicle: VehicleBody3D
var model: Node3D
var steering_wheel: Node3D
var ramp_visual: Node3D
## Panel seams (ReferenceTruckPanelLines), hung on the panels they mark.
var panel_lines: Array[MeshInstance3D] = []
var _hinges: Dictionary = {}
var _door_state: Dictionary = {}
var _door_tweens: Dictionary = {}
var _door_audio: Dictionary = {}
var _ramp_deployed: bool = true
var _ramp_tween: Tween
var _steel: Material
var _dark: Material
var _accent: StandardMaterial3D
var _cab: ReferenceTruckCab
var _cargo: ReferenceTruckCargo


func _ready() -> void:
	vehicle = get_parent() as VehicleBody3D
	if vehicle == null or vehicle.get_node_or_null(^"BodyVisuals/ReferenceTruckModel") != null:
		return
	model = _load_model()
	if model == null:
		push_error("No se pudo cargar el modelo de camión: " + TRUCK_PATH)
		return
	model.name = "ReferenceTruckModel"
	model.position = MODEL_OFFSET
	model.rotation.y = PI * 0.5
	model.scale = Vector3.ONE * MODEL_SCALE
	vehicle.get_node(^"BodyVisuals").add_child(model)
	_steel = ReferenceTruckProps.material_named(model, "DT_Steel")
	_dark = ReferenceTruckProps.material_named(model, "DT_Dark")
	_accent = StandardMaterial3D.new()
	_accent.albedo_color = RACK_ACCENT
	_accent.roughness = 0.6
	_cab = ReferenceTruckCab.new(model, _steel, _dark, _accent)
	_cargo = ReferenceTruckCargo.new(vehicle, model, _steel, _dark, _accent)
	_remove_authored_shelving()
	_make_glass_transparent()
	_cab.reshape_side_windows()
	_attach_wheel_visuals()
	steering_wheel = _cab.build_steering_pivot()
	_cab.dress_cab()
	_collect_doors()
	_cargo.build_cargo_fittings()
	_cargo.build_jump_seats()
	_build_ramp()
	_build_bulkhead_collision()
	panel_lines = ReferenceTruckPanelLines.new(vehicle, model).build()
	_build_windshield_rain()
	_bind_presentation()


func _load_model() -> Node3D:
	# The imported scene is what an exported build ships; the raw .glb is not
	# packed. GLTFDocument covers a fresh checkout whose import cache doesn't
	# exist yet (command-line tests before the editor has ever opened it).
	if ResourceLoader.exists(TRUCK_PATH, "PackedScene"):
		var packed := load(TRUCK_PATH) as PackedScene
		if packed != null:
			return packed.instantiate() as Node3D
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	if document.append_from_file(TRUCK_PATH, state) != OK:
		return null
	return document.generate_scene(state) as Node3D


## The wall between cab and cargo bay was drawn but not solid: a loose box
## (or anything else) braking hard slid straight through it into the cab.
## One box per authored panel, on the truck's own body, in vehicle space;
## the communication window between them stays open.
func _build_bulkhead_collision() -> void:
	var to_vehicle: Transform3D = vehicle.global_transform.affine_inverse()
	for mesh: Node in model.find_children("Bulkhead*", "MeshInstance3D", true, false):
		var box: AABB = (to_vehicle * (mesh as Node3D).global_transform) * (mesh as MeshInstance3D).get_aabb()
		var shape := CollisionShape3D.new()
		shape.name = "%sCollision" % mesh.name
		var box_shape := BoxShape3D.new()
		# Panels are thin art; give the solid a little depth so fast objects
		# can't slip through between two physics steps.
		box_shape.size = Vector3(box.size.x, box.size.y, maxf(box.size.z, 0.12))
		shape.shape = box_shape
		shape.position = box.get_center()
		vehicle.add_child(shape)


## The model's three-tier side shelves are 0.39 m deep with 0.54 m between
## tiers: no package in this game fits on them. The deep rack on the left
## wall (vehicle.tscn + ReferenceTruckCargo) replaces them.
func _remove_authored_shelving() -> void:
	for node: Node in model.find_children("Shelf*", "", true, false):
		node.get_parent().remove_child(node)
		node.queue_free()


## Glass is chosen by material, not by node name: the windshield is called
## "FrontWindshield" (no "window"/"glass" in it), while frame pieces such as
## "CabDoorWindowHeader" are opaque paint that must stay solid.
func _make_glass_transparent() -> void:
	var glass := StandardMaterial3D.new()
	glass.resource_name = "TruckGlass"
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.62, 0.82, 0.9, 0.16)
	glass.metallic_specular = 0.9
	glass.roughness = 0.06
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Shadow maps drew stair-stepped pillar shadows across every pane.
	glass.disable_receive_shadows = true
	# Writes depth like a solid: overlapping panes (the sliding communication
	# window, glass seen through glass) otherwise swap draw order as the
	# camera moves and flicker.
	glass.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	for mesh: MeshInstance3D in ReferenceTruckProps.meshes(model):
		if ReferenceTruckProps.uses_material(mesh, GLASS_MATERIAL):
			mesh.material_override = glass
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Each authored wheel (tire, rim, hub, bolts) is centred on its AXLE node.
## It hangs on the physics VehicleWheel3D with no offset at all, so the
## native spin, steer and suspension move it around its own hub; the physics
## wheel sits on the same axle with the tire's real radius (vehicle.tscn).
func _attach_wheel_visuals() -> void:
	var axle_basis := Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * MODEL_SCALE)
	for art_name: String in WHEELS:
		var art := model.find_child(art_name, true, false) as Node3D
		var wheel := vehicle.get_node_or_null(NodePath(WHEELS[art_name])) as VehicleWheel3D
		if art == null or wheel == null:
			continue
		art.reparent(wheel, false)
		art.transform = Transform3D(axle_basis, Vector3.ZERO)



func _collect_doors() -> void:
	for door: StringName in DOORS:
		var leaves: Array = []
		for entry: Array in DOORS[door]:
			var hinge := model.find_child(entry[0], true, false) as Node3D
			if hinge != null:
				leaves.append([hinge, float(entry[1])])
				_add_leaf_collision(hinge)
		_hinges[door] = leaves
		var open := bool(vehicle.call(&"is_door_open", door))
		_door_state[door] = open
		_pose_door(1.0 if open else 0.0, door)
		var audio := AudioStreamPlayer3D.new()
		audio.name = "DoorAudio_" + String(door)
		audio.stream = preload("res://modules/synth_audio/synth_audio.gd").impact_thud()
		audio.unit_size = 6.0
		audio.max_distance = 30.0
		if not leaves.is_empty():
			audio.position = vehicle.to_local((leaves[0][0] as Node3D).global_position)
		# Under this node (vehicle space, identity transform), not the vehicle
		# itself, so the van's own direct children stay just its gameplay parts.
		add_child(audio)
		_door_audio[door] = audio


## A solid slab the size of the door leaf, hanging from its hinge so it
## swings with the animation: an open door stops players and the box in
## their hands instead of being walked (or carried) straight through. On
## the cargo shell's layer with no mask of its own, like the ramp: it never
## touches the road or pushes the truck.
func _add_leaf_collision(hinge: Node3D) -> void:
	var bounds := AABB()
	var first: bool = true
	var to_hinge: Transform3D = hinge.global_transform.affine_inverse()
	for node: Node in hinge.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = to_hinge * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		return
	var body := StaticBody3D.new()
	body.name = "LeafCollision"
	body.collision_layer = 64  # vehicle.gd SHELL_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = bounds.size
	shape.shape = slab
	shape.position = bounds.get_center()
	body.add_child(shape)
	hinge.add_child(body)


func _pose_door(amount: float, door: StringName) -> void:
	for leaf: Array in _hinges.get(door, []):
		(leaf[0] as Node3D).rotation.y = float(leaf[1]) * amount


## Called by vehicle.gd whenever the replicated door state changes, on every
## peer. Swings open with a little overshoot, closes with a latch thud.
func set_door_open(door: StringName, open: bool) -> void:
	if not _hinges.has(door) or bool(_door_state.get(door, false)) == open:
		return
	_door_state[door] = open
	var leaves: Array = _hinges[door]
	if leaves.is_empty():
		return
	var previous: Tween = _door_tweens.get(door)
	if previous != null and previous.is_valid():
		previous.kill()
	var start: float = (leaves[0][0] as Node3D).rotation.y / float(leaves[0][1])
	var tween := create_tween()
	tween.tween_method(_pose_door.bind(door), start, 1.0 if open else 0.0, DOOR_SECONDS) \
		.set_trans(Tween.TRANS_BACK if open else Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	_door_tweens[door] = tween
	var audio: AudioStreamPlayer3D = _door_audio.get(door)
	if audio == null:
		return
	if open:
		_play_door_sound(audio, 1.9, -24.0)
	else:
		tween.tween_callback(_play_door_sound.bind(audio, 1.25, -12.0))


func _play_door_sound(audio: AudioStreamPlayer3D, pitch: float, volume_db: float) -> void:
	if not audio.is_inside_tree():
		return
	audio.pitch_scale = pitch
	audio.volume_db = volume_db
	audio.play()


## Each frame: the pedals dip with what the truck does, the jump seats drop
## for whoever sits in them.
func _process(delta: float) -> void:
	if _cab != null:
		_cab.animate_pedals(vehicle, delta)
	if _cargo != null:
		_cargo.animate_jump_seats(get_tree(), delta)


## Ramp art matches RearRamp/Shape (ReferenceTruckCargo.build_ramp); this keeps
## whether it is out, and the stowing slide.
func _build_ramp() -> void:
	ramp_visual = _cargo.build_ramp()
	if ramp_visual == null:
		return
	_ramp_deployed = bool(vehicle.get(&"rear_ramp_deployed"))
	_cargo.pose_ramp(1.0 if _ramp_deployed else 0.0)





## Body colour and trim colour (vehicle.gd: paint and variant). The model's
## "DT_White" panels and "DT_Blue" trim get their own copies once, so the
## shared imported materials are never changed.
var _paint_materials: Dictionary = {}


func set_paint(body: Color, trim: Color) -> void:
	if model == null:
		return
	for pair: Array in [["DT_White", body], ["DT_Blue", trim]]:
		var name_: String = pair[0]
		if not _paint_materials.has(name_):
			var source := ReferenceTruckProps.material_named(model, name_) as BaseMaterial3D
			if source == null:
				continue
			var copy := source.duplicate() as BaseMaterial3D
			_paint_materials[name_] = copy
			for mesh: MeshInstance3D in ReferenceTruckProps.meshes(model):
				for surface: int in range(mesh.mesh.get_surface_count()):
					if mesh.mesh.surface_get_material(surface) == source:
						mesh.set_surface_override_material(surface, copy)
		(_paint_materials[name_] as BaseMaterial3D).albedo_color = pair[1]


## The old van's retro dressing (N-114): a chrome strip along the top of the
## front bumper and a chrome ring round each headlight. Pure presentation, in
## the truck's own space (the lamps and the bumper are at those spots in the
## authored model); removed again when the variant isn't retro.
const RETRO_NAME := "RetroChrome"
const CHROME := Color("d9dde2")


func set_retro(enabled: bool) -> void:
	if vehicle == null or model == null:
		return
	var existing: Node = vehicle.get_node_or_null(NodePath("BodyVisuals/" + RETRO_NAME))
	if existing != null:
		if enabled:
			return
		existing.free()
		return
	if not enabled:
		return
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = CHROME
	chrome.metallic = 0.85
	chrome.roughness = 0.22
	var holder := Node3D.new()
	holder.name = RETRO_NAME
	vehicle.get_node(^"BodyVisuals").add_child(holder)
	# The bumper's top front edge: x +-1.05, top at y 0.63, front face at z -2.796.
	ReferenceTruckProps.add_box(holder, Vector3(2.1, 0.06, 0.09), Vector3(0.0, 0.63, -2.83), chrome)
	for side: float in [-1.0, 1.0]:
		# Headlight lens centres at x +-0.752, y 0.526, on the nose's front.
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.135
		torus.outer_radius = 0.17
		torus.rings = 16
		torus.ring_segments = 6
		ring.mesh = torus
		ring.material_override = chrome
		ring.rotation.x = PI * 0.5
		ring.scale = Vector3(1.0, 1.0, 0.45)
		ring.position = Vector3(0.752 * side, 0.526, -2.835)
		holder.add_child(ring)


func set_ramp_deployed(deployed: bool) -> void:
	if ramp_visual == null or deployed == _ramp_deployed:
		return
	_ramp_deployed = deployed
	if _ramp_tween != null and _ramp_tween.is_valid():
		_ramp_tween.kill()
	_ramp_tween = create_tween()
	_ramp_tween.tween_method(_cargo.pose_ramp, 0.0 if deployed else 1.0, 1.0 if deployed else 0.0, RAMP_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Drops and wipers on the windshield (N-303, windshield_rain.gd).
func _build_windshield_rain() -> void:
	var windshield := model.find_child("FrontWindshield", true, false) as MeshInstance3D
	if windshield == null or windshield.mesh == null:
		return
	var rain := WindshieldRain.new()
	rain.name = "WindshieldRain"
	vehicle.get_node(^"BodyVisuals").add_child(rain)
	rain.setup(vehicle, windshield)
	# The model's own two blades are static and sat under the animated ones
	# (two X's on the glass): the animated pair replaces them.
	for blade: Node in model.find_children("Wiper*", "MeshInstance3D", true, false):
		if ReferenceTruck.is_model_wiper(blade.name):
			(blade as MeshInstance3D).visible = false


## The model's own blades ("Wiper", "Wiper.001" / "Wiper_001"), not the
## animated "WiperArm"s of WindshieldRain.
static func is_model_wiper(node_name: String) -> bool:
	return node_name == "Wiper" or node_name.begins_with("Wiper.") or node_name.begins_with("Wiper_")


func _bind_presentation() -> void:
	var presentation := vehicle.get_node_or_null(^"VehiclePresentation")
	if presentation == null or not presentation.has_method(&"bind_model"):
		return
	presentation.call(&"bind_model", steering_wheel,
		model.find_children("HeadlightLens*", "MeshInstance3D", true, false),
		model.find_children("TailLight*", "MeshInstance3D", true, false))
