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

signal resolved(outcome: StringName)  # &"delivered_ok", &"delivered_ruined", or &"missed"

var delivered: bool = false
var doorbell: DoorbellPoint
var _resident: MeshInstance3D
var _bell_player: AudioStreamPlayer3D
var _reaction_player: AudioStreamPlayer3D


func _ready() -> void:
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
		_resolve(&"missed", null)


func _on_doorbell_rung(carried_package: Node) -> void:
	if delivered:
		return
	_bell_player.play()
	if carried_package == null:
		_resolve(&"missed", null)
		return
	var state: int = int(carried_package.get(&"trap_state"))
	if state == ITrapBehavior.TrapState.RUINED:
		_resolve(&"delivered_ruined", carried_package)
	else:
		_resolve(&"delivered_ok", carried_package)


func _resolve(outcome: StringName, package: Node) -> void:
	delivered = true
	if package != null:
		# The resident takes the box, one way or another -- consumed either
		# way, matching "se come la caja" for the good outcome; the ruined
		# case still hands it off, just with a worse reaction.
		package.queue_free()
	_reaction_player.stream = SynthAudio.creature_groan() if outcome == &"delivered_ruined" else SynthAudio.honk_horn()
	_reaction_player.play()
	resolved.emit(outcome)


func _build_house() -> void:
	var body := StaticBody3D.new()
	body.name = "HouseBody"
	body.collision_layer = 1
	body.collision_mask = 6
	add_child(body)
	var wall_mesh := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(6.0, 3.2, 5.0)
	wall_mesh.mesh = wall_box
	wall_mesh.position = Vector3(0.0, 1.6, 0.0)
	wall_mesh.material_override = _material(WALL)
	body.add_child(wall_mesh)
	var collider := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = wall_box.size
	collider.position = wall_mesh.position
	collider.shape = box_shape
	body.add_child(collider)

	var roof_mesh := MeshInstance3D.new()
	var roof_box := BoxMesh.new()
	roof_box.size = Vector3(6.8, 0.6, 5.6)
	roof_mesh.mesh = roof_box
	roof_mesh.position = Vector3(0.0, 3.5, 0.0)
	roof_mesh.material_override = _material(ROOF)
	add_child(roof_mesh)

	var door_mesh := MeshInstance3D.new()
	var door_box := BoxMesh.new()
	door_box.size = Vector3(1.1, 2.1, 0.08)
	door_mesh.mesh = door_box
	door_mesh.position = Vector3(0.0, 1.05, 2.54)
	door_mesh.material_override = _material(DOOR)
	add_child(door_mesh)

	var porch_mesh := MeshInstance3D.new()
	var porch_box := BoxMesh.new()
	porch_box.size = Vector3(3.0, 0.1, 2.0)
	porch_mesh.mesh = porch_box
	porch_mesh.position = Vector3(0.0, 0.05, 3.5)
	porch_mesh.material_override = _material(PORCH)
	add_child(porch_mesh)

	# The resident (placeholder, no art pipeline yet) stays hidden until
	# someone actually rings -- popping out is the whole point of the joke.
	_resident = MeshInstance3D.new()
	_resident.name = "Resident"
	var resident_mesh := CapsuleMesh.new()
	resident_mesh.radius = 0.35
	resident_mesh.height = 1.3
	_resident.mesh = resident_mesh
	_resident.position = Vector3(0.0, 0.85, 2.7)
	_resident.material_override = _material(Color("d9b48f"))
	_resident.visible = false
	add_child(_resident)
	resolved.connect(func(_outcome: StringName) -> void: _resident.visible = true)

	doorbell = DoorbellPoint.new()
	doorbell.name = "Doorbell"
	doorbell.position = Vector3(0.7, 1.1, 2.6)
	var bell_shape := SphereShape3D.new()
	bell_shape.radius = 1.6
	var bell_collider := CollisionShape3D.new()
	bell_collider.shape = bell_shape
	doorbell.add_child(bell_collider)
	add_child(doorbell)
	doorbell.rung.connect(_on_doorbell_rung)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
