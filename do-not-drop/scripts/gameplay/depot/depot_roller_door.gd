class_name DepotRollerDoor
extends Node3D
## The depot's big sectional roller door. Rolls its slats up into the drum
## housing above the opening and back down, with a warning beacon and a motor
## rumble while it moves. Collision follows the curtain: a closed door is a
## wall, an open one is nothing at all.
##
## Pure mechanism and presentation. Whether it SHOULD close is the depot's
## call (depot.gd decides on the host and tells every peer), so this never
## runs on its own.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")

signal finished_moving(open: bool)

@export var width: float = 6.6
@export var height: float = 4.8
## Seconds for a full run between open and closed.
@export var travel_seconds: float = 4.2

const SLAT_HEIGHT: float = 0.3
const BEACON := Color("ff9f1c")
## The models (assets/tools/build_depot_props.py) are authored for this
## opening width; another width stretches them along X.
const MODEL_WIDTH: float = 6.6
## The slat with the row of vision panes, counted from the bottom (~1.6 m up
## when the door is down: eye height from the cab).
const WINDOW_SLAT: int = 5

## 0 closed, 1 fully open. Presentation reads it every frame.
var openness: float = 1.0
var is_open: bool = true
var _target: float = 1.0
var _slats: Array[MeshInstance3D] = []
var _bottom_bar: MeshInstance3D
var _body: StaticBody3D
var _shape: CollisionShape3D
var _beacon_light: OmniLight3D
var _beacon_lens: MeshInstance3D
var _motor: AudioStreamPlayer3D
var _beacon_time: float = 0.0
## The door's signal lights (the kit's, one on each side of the wall): the red X shows
## while the door is shut or moving, the green arrow only once it is fully open.
var _signal_red: Array[Node3D] = []
var _signal_green: Array[Node3D] = []


func _ready() -> void:
	_build()
	_apply_openness()


## Snaps (animate = false) or rolls toward the given state.
func set_open(open: bool, animate: bool = true) -> void:
	is_open = open
	_target = 1.0 if open else 0.0
	if not animate:
		openness = _target
		_apply_openness()
		return
	if not _motor.playing:
		_motor.play()


func is_moving() -> bool:
	return not is_equal_approx(openness, _target)


func _process(delta: float) -> void:
	var moving: bool = is_moving()
	if moving:
		openness = move_toward(openness, _target, delta / travel_seconds)
		_apply_openness()
		if not is_moving():
			_motor.stop()
			finished_moving.emit(is_open)
	# The beacon only turns while the door is moving -- it's a warning, not
	# decoration: stay clear of the threshold.
	_beacon_light.visible = moving
	if moving:
		_beacon_time += delta
		_beacon_light.light_energy = 1.4 + sin(_beacon_time * 12.0) * 1.2
	(_beacon_lens.material_override as StandardMaterial3D).emission_energy_multiplier = 2.5 if moving and sin(_beacon_time * 12.0) > 0.0 else 0.25


func _apply_openness() -> void:
	# The curtain's bottom edge rises with openness; slats above the lintel
	# are wound up on the drum and disappear into its housing.
	var bottom: float = openness * (height - 0.05)
	for index: int in range(_slats.size()):
		var y: float = bottom + (float(index) + 0.5) * SLAT_HEIGHT
		var slat: MeshInstance3D = _slats[index]
		slat.visible = y < height
		slat.position = Vector3(0.0, y, 0.0)
	var green: bool = openness >= 0.99
	for light: Node3D in _signal_green:
		light.visible = green
	for light: Node3D in _signal_red:
		light.visible = not green
	_bottom_bar.position = Vector3(0.0, bottom + 0.04, 0.0)
	_bottom_bar.visible = bottom < height - 0.1
	var closed_part: float = height - bottom
	_shape.disabled = closed_part < 0.6
	if not _shape.disabled:
		(_shape.shape as BoxShape3D).size = Vector3(width, closed_part, 0.3)
		_shape.position = Vector3(0.0, bottom + closed_part * 0.5, 0.0)


func _build() -> void:
	var stretch := Vector3(width / MODEL_WIDTH, 1.0, 1.0)
	var slat_mesh: Mesh = DepotKit.merged_mesh(DepotKit.depot_model("sm_env_depot_door_slat"))
	var window_mesh: Mesh = DepotKit.merged_mesh(DepotKit.depot_model("sm_env_depot_door_slat_window"))
	var count: int = ceili(height / SLAT_HEIGHT)
	for index: int in range(count):
		var slat := MeshInstance3D.new()
		slat.name = "Slat%d" % index
		slat.mesh = window_mesh if index == WINDOW_SLAT else slat_mesh
		slat.scale = stretch
		add_child(slat)
		_slats.append(slat)
	_bottom_bar = MeshInstance3D.new()
	_bottom_bar.name = "BottomBar"
	_bottom_bar.mesh = DepotKit.merged_mesh(DepotKit.depot_model("sm_env_depot_door_bottom_bar"))
	_bottom_bar.scale = stretch
	add_child(_bottom_bar)
	# Fixed frame: guide rails, drum housing, striped jambs, bollards, the
	# threshold -- one model folded into the batch. The bollards stay solid.
	var kit := DepotKit.new(self, "FrameColliders")
	kit.model(DepotKit.depot_model("sm_env_depot_door_frame"), Transform3D(Basis.from_scale(stretch), Vector3.ZERO))
	for side: float in [-1.0, 1.0]:
		kit.collider(Vector3(0.28, 1.1, 0.28), Transform3D(Basis.IDENTITY, Vector3(side * (width * 0.5 + 0.35), 0.55, -0.7)))
	kit.commit("DoorFrame")
	_build_signal_lights()
	_beacon_lens = MeshInstance3D.new()
	_beacon_lens.name = "BeaconLens"
	var lens := SphereMesh.new()
	lens.radius = 0.12
	lens.height = 0.2
	_beacon_lens.mesh = lens
	var lens_material := DepotKit.glow(BEACON, 0.25).duplicate() as StandardMaterial3D
	_beacon_lens.material_override = lens_material
	# Outside, on the wall above the jamb: it warns whoever is out front.
	_beacon_lens.position = Vector3(width * 0.5 + 0.3, height + 0.45, -0.5)
	add_child(_beacon_lens)
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color = BEACON
	_beacon_light.omni_range = 7.0
	_beacon_light.position = _beacon_lens.position + Vector3(0.0, 0.0, -0.3)
	_beacon_light.visible = false
	add_child(_beacon_light)
	_body = StaticBody3D.new()
	_body.name = "CurtainBody"
	_body.collision_layer = 1
	_body.collision_mask = 6
	_shape = CollisionShape3D.new()
	_shape.shape = BoxShape3D.new()
	_body.add_child(_shape)
	add_child(_body)
	_motor = AudioStreamPlayer3D.new()
	_motor.name = "Motor"
	_motor.stream = SynthAudio.roller_door()
	_motor.bus = &"SFX"
	_motor.unit_size = 10.0
	_motor.max_distance = 45.0
	_motor.volume_db = WorldMix.ROLLER_DOOR_DB
	_motor.position = Vector3(0.0, height + 0.4, 0.0)
	add_child(_motor)


## The kit's signal light, inside (facing +Z) and outside (facing -Z) at the right jamb's
## wall, at head height: a red X for closed or moving, a green arrow for open.
func _build_signal_lights() -> void:
	var packed := load(DepotKit.depot_model("sm_env_depot_door_light")) as PackedScene
	if packed == null:
		return
	for spec: Array in [[Vector3(width * 0.5 + 0.75, 1.9, 0.02), PI], [Vector3(width * 0.5 + 0.75, 1.9, -0.32), 0.0]]:
		var light := packed.instantiate() as Node3D
		LowpolyMaterials.apply(light)
		light.name = "SignalLight%d" % maxi(_signal_red.size(), 0)
		light.position = spec[0]
		light.rotation.y = float(spec[1])
		add_child(light)
		var red := light.find_child("DoorLightRed", true, false) as Node3D
		var green := light.find_child("DoorLightGreen", true, false) as Node3D
		if red != null:
			_signal_red.append(red)
		if green != null:
			_signal_green.append(green)
