extends Node3D
class_name DeliveryHouse
## One delivery stop along the route: a small house with a doorbell. A
## player carrying a package rings it and whoever answers reacts to the
## package's state -- eats the box if it survived, something worse if it
## didn't (docs/tareas-nacho.md, house delivery system). This script only
## owns the physical/presentation reaction; it doesn't invent scoring or
## life-loss rules -- that's game-rules territory (see `resolved` signal
## and the EventBus follow-up noted in docs/tareas-nacho.md).
##
## Not tied to a specific package id on purpose -- a player can only carry
## one package at a time, so whatever they're holding when they ring *is*
## the delivery attempt. Matching against a specific assigned package only
## matters once picking a package back out of the van to walk it here is
## possible at all (currently isn't -- see the note in tareas-nacho.md).

const WALL := Color("9c8a6f")
const ROOF := Color("6b4f3a")
const DOOR := Color("46342a")
const PORCH := Color("7a8a7f")
const HOUSE_VISUALS: Array[String] = [
	"res://assets/models/architecture/sm_arch_delivery_house_cottage.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_cabin.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_bungalow.glb",
]

signal resolved(outcome: StringName, package_id: StringName)  # see OUTCOMES below

## Every way a stop can end. A dented box is its own outcome rather than
## being rounded up to "fine": it's the case the delivery photo exists for
## (the resident may complain about it afterwards), so collapsing it into
## delivered_ok would quietly disable half the mechanic.
const OUTCOME_OK: StringName = &"delivered_ok"
const OUTCOME_AT_RISK: StringName = &"delivered_at_risk"
const OUTCOME_RUINED: StringName = &"delivered_ruined"
const OUTCOME_MISSED: StringName = &"missed"

var delivered: bool = false
## Which stop this is along the route (route.gd sets it). The phone camera
## files a photo against this number, so it has to match the index route.gd
## reports through house_resolved.
var house_index: int = 0
## What actually happened here, once it did -- kept so the photo the player
## takes afterwards can be filed against this specific delivery (the photo
## is what refutes a complaint at the results screen).
var outcome: StringName = &""
var delivered_package_id: StringName = &""
var visual_variant: int = 0
var doorbell: DoorbellPoint
var _resident: MeshInstance3D
var _bell_player: AudioStreamPlayer3D
var _reaction_player: AudioStreamPlayer3D


func _ready() -> void:
	# Findable without walking route.gd's house list: the phone camera looks
	# for the nearest door it can document, and it has no business knowing
	# how the route is built.
	add_to_group(&"delivery_house")
	_build_house()
	_bell_player = AudioStreamPlayer3D.new()
	_bell_player.stream = SynthAudio.glass_chime()
	_bell_player.unit_size = 8.0
	_bell_player.max_distance = 25.0
	add_child(_bell_player)
	_reaction_player = AudioStreamPlayer3D.new()
	_reaction_player.unit_size = 8.0
	_reaction_player.max_distance = 25.0
	add_child(_reaction_player)


## Called by whoever manages the final goal for any house nobody ever rang --
## driving past a house without delivering is a real ending, not a dead end
## (see route.gd's goal zone).
func force_resolve_if_missed() -> void:
	if not delivered:
		_resolve(OUTCOME_MISSED, null)


func _on_doorbell_rung(carried_package: Node) -> void:
	if delivered:
		return
	_bell_player.play()
	if carried_package == null:
		_resolve(OUTCOME_MISSED, null)
		return
	var state: int = int(carried_package.get(&"trap_state"))
	match state:
		ITrapBehavior.TrapState.RUINED:
			_resolve(OUTCOME_RUINED, carried_package)
		ITrapBehavior.TrapState.AT_RISK:
			_resolve(OUTCOME_AT_RISK, carried_package)
		_:
			_resolve(OUTCOME_OK, carried_package)


func _resolve(result: StringName, package: Node) -> void:
	delivered = true
	outcome = result
	if package != null:
		var id: Variant = package.get(&"package_id")
		delivered_package_id = StringName(id) if id != null else &""
		# The resident takes the box, one way or another -- consumed either
		# way, matching "se come la caja" for the good outcome; the ruined
		# case still hands it off, just with a worse reaction. Deferred so
		# this never frees a node mid-signal, while whoever is listening
		# (level_base.gd -> RunManager) still sees a valid package.
		package.call_deferred(&"queue_free")
	# The resident's reaction follows what they were actually handed: a groan
	# for a wreck, the same groan quieter for something dented, a cheer for
	# a box that made it.
	_reaction_player.stream = SynthAudio.creature_groan() if result in [OUTCOME_RUINED, OUTCOME_AT_RISK] else SynthAudio.honk_horn()
	_reaction_player.volume_db = -6.0 if result == OUTCOME_AT_RISK else 0.0
	_reaction_player.play()
	resolved.emit(result, delivered_package_id)


func _build_house() -> void:
	var body := StaticBody3D.new()
	body.name = "HouseBody"
	body.collision_layer = 1
	body.collision_mask = 6
	add_child(body)
	var collider := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(6.0, 3.2, 5.0)
	collider.position = Vector3(0.0, 1.6, 0.0)
	collider.shape = box_shape
	body.add_child(collider)
	var visual := load(HOUSE_VISUALS[posmod(visual_variant, HOUSE_VISUALS.size())]) as PackedScene
	if visual != null:
		var visual_instance := visual.instantiate()
		visual_instance.name = "HouseVisual"
		add_child(visual_instance)

	# The resident (placeholder, no art pipeline yet) stays hidden until
	# someone actually rings -- popping out is the whole point of the joke.
	_resident = MeshInstance3D.new()
	_resident.name = "Resident"
	var resident_mesh := CapsuleMesh.new()
	resident_mesh.radius = 0.35
	resident_mesh.height = 1.3
	_resident.mesh = resident_mesh
	# The imported house fronts face local -Z (the same direction set by
	# Route._build_houses()), so keep the resident and interaction point on
	# the actual porch instead of behind the building.
	_resident.position = Vector3(0.0, 0.85, -2.7)
	_resident.material_override = _material(Color("d9b48f"))
	_resident.visible = false
	add_child(_resident)
	resolved.connect(func(_outcome: StringName, _package_id: StringName) -> void: _resident.visible = true)

	doorbell = DoorbellPoint.new()
	doorbell.name = "Doorbell"
	doorbell.position = Vector3(-0.7, 1.1, -2.6)
	var bell_shape := SphereShape3D.new()
	bell_shape.radius = 1.6
	var bell_collider := CollisionShape3D.new()
	bell_collider.shape = bell_shape
	doorbell.add_child(bell_collider)
	add_child(doorbell)
	doorbell.rung.connect(_on_doorbell_rung)


## Where a photo of this delivery should be aimed: the porch, where the
## resident pops out and the box changes hands -- not the roof ridge that
## the node origin sits under.
func porch_position() -> Vector3:
	return _resident.global_position if is_instance_valid(_resident) else global_position


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
