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
const SLAT_DEPTH: float = 0.07
const CURTAIN := Color("d9dcd6")
const RIB := Color("b9beb8")
const HOUSING := Color("3b4c53")
const RAIL := Color("59656a")
const RUBBER := Color("1e2528")
const BEACON := Color("ff9f1c")

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
	_bottom_bar.position = Vector3(0.0, bottom + 0.04, 0.0)
	_bottom_bar.visible = bottom < height - 0.1
	var closed_part: float = height - bottom
	_shape.disabled = closed_part < 0.6
	if not _shape.disabled:
		(_shape.shape as BoxShape3D).size = Vector3(width, closed_part, 0.3)
		_shape.position = Vector3(0.0, bottom + closed_part * 0.5, 0.0)


func _build() -> void:
	var slat_mesh := BoxMesh.new()
	slat_mesh.size = Vector3(width, SLAT_HEIGHT - 0.02, SLAT_DEPTH)
	var rib_mesh := BoxMesh.new()
	rib_mesh.size = Vector3(width, 0.035, SLAT_DEPTH + 0.03)
	var slat_material := DepotKit.flat(CURTAIN, 0.5, 0.25)
	var rib_material := DepotKit.flat(RIB, 0.5, 0.3)
	var count: int = ceili(height / SLAT_HEIGHT)
	for index: int in range(count):
		var slat := MeshInstance3D.new()
		slat.name = "Slat%d" % index
		slat.mesh = slat_mesh
		slat.material_override = slat_material
		var rib := MeshInstance3D.new()
		rib.mesh = rib_mesh
		rib.material_override = rib_material
		rib.position = Vector3(0.0, SLAT_HEIGHT * 0.5 - 0.01, 0.0)
		slat.add_child(rib)
		add_child(slat)
		_slats.append(slat)
	_bottom_bar = MeshInstance3D.new()
	_bottom_bar.name = "BottomBar"
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(width, 0.08, 0.12)
	_bottom_bar.mesh = bar_mesh
	_bottom_bar.material_override = DepotKit.flat(RUBBER, 0.9)
	add_child(_bottom_bar)
	# Fixed frame: guide rails, drum housing, hazard-striped jambs.
	var kit := DepotKit.new(self, "FrameColliders")
	var rail := DepotKit.flat(RAIL, 0.5, 0.4)
	var stripes := DepotKit.detailed(Color.WHITE, "res://assets/textures/environment/tx_env_warning_256.png", 0.9, 0.7)
	for side: float in [-1.0, 1.0]:
		var x: float = side * (width * 0.5 + 0.06)
		kit.box(Vector3(0.12, height + 0.3, 0.2), Vector3(x, (height + 0.3) * 0.5, 0.0), rail)
		kit.box(Vector3(0.36, height, 0.08), Vector3(side * (width * 0.5 + 0.3), height * 0.5, -0.4), stripes)
		# Bollards protect the jambs from the truck's mirrors.
		kit.cylinder(0.14, 1.1, Transform3D(Basis.IDENTITY, Vector3(side * (width * 0.5 + 0.35), 0.55, -0.7)), DepotKit.flat(Color("e7be51"), 0.6), 14, true)
		kit.cylinder(0.145, 0.12, Transform3D(Basis.IDENTITY, Vector3(side * (width * 0.5 + 0.35), 0.78, -0.7)), DepotKit.flat(Color("1e2528")), 14)
	kit.box(Vector3(width + 0.8, 0.9, 0.9), Vector3(0.0, height + 0.45, 0.35), DepotKit.ribbed(HOUSING, 0.6))
	kit.box(Vector3(0.5, 0.36, 0.3), Vector3(width * 0.5 + 0.2, height + 0.2, 0.95), DepotKit.flat(Color("2a3439"), 0.6, 0.4))
	# Threshold: a steel plate with a hazard band either side.
	kit.box(Vector3(width, 0.03, 0.5), Vector3(0.0, 0.015, 0.0), DepotKit.flat(Color("6c767a"), 0.4, 0.6))
	kit.box(Vector3(width, 0.02, 0.35), Vector3(0.0, 0.012, -0.45), stripes)
	kit.box(Vector3(width, 0.02, 0.35), Vector3(0.0, 0.012, 0.45), stripes)
	kit.commit("DoorFrame")
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
