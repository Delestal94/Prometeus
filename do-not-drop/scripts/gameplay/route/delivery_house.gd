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

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const ContactShadow = preload("res://scripts/presentation/contact_shadow.gd")
const WALL := Color("9c8a6f")
const ROOF := Color("6b4f3a")
const DOOR := Color("46342a")
const PORCH := Color("7a8a7f")
const HOUSE_VISUALS: Array[String] = [
	"res://assets/models/architecture/sm_arch_delivery_house_cottage.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_cabin.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_bungalow.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_two_story.glb",
	"res://assets/models/architecture/sm_arch_delivery_house_farmhouse.glb",
]
const RESIDENT_SCENE: PackedScene = preload("res://assets/models/characters/sm_char_player_lowpoly.glb")
## The doorbell panel (N-302, assets/tools/build_doorbell.py): origin at the
## back of the plate, front toward -Z.
const DOORBELL_PANEL: String = "res://assets/models/environment/props/sm_env_prop_doorbell_panel.glb"
## Where the panel hangs: on the knob's side of the door, in the strip of
## plain wall between the frame (to x 0.64) and the nearest shutter (the
## cottage's, from x 0.79), at doorbell height over the porch floor (y 0.31);
## and each visual's front wall there, measured on the models (the cabin's
## logs stand proud of the others' plaster).
const DOORBELL_PANEL_X: float = 0.715
const DOORBELL_HEIGHT: float = 1.55
const DOORBELL_WALL_Z: Array[float] = [-2.25, -2.20, -2.40, -2.50, -2.30]
## The door's raised panels stand this far out from the wall line above
## (measured on the models: the upper panel's face), and the "nobody home"
## note (N-604) goes on the upper one, at this height over the ground.
const DOOR_PANEL_PROUD: float = 0.125
const NOTE_HEIGHT: float = 1.82
## The point you ring from stands this far out from the wall, in front of it.
const DOORBELL_REACH: float = 0.3
## The number window and the bell push, lit from inside while the house waits.
const DOORBELL_WINDOW := Color("fff1d6")
const DOORBELL_BUTTON := Color("e7be51")
const DOORBELL_INK := Color("1e2235")
const DOORBELL_FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
## Solid volumes per visual, [size, centre] pairs matching the walls only --
## never the porch, so the doorbell stays reachable. The first three share
## the original 6x5 box; the farmhouse is wider and has a wing out back
## (Blender -Y becomes Godot +Z on import).
const HOUSE_COLLIDERS: Array = [
	[[Vector3(6.0, 3.2, 5.0), Vector3(0.0, 1.6, 0.0)]],
	[[Vector3(6.0, 3.2, 5.0), Vector3(0.0, 1.6, 0.0)]],
	[[Vector3(6.0, 3.2, 5.0), Vector3(0.0, 1.6, 0.0)]],
	[[Vector3(6.0, 5.6, 5.0), Vector3(0.0, 2.8, 0.0)]],
	[[Vector3(7.0, 3.2, 4.6), Vector3(0.0, 1.6, 0.0)], [Vector3(2.6, 2.8, 3.4), Vector3(2.24, 1.4, 3.22)]],
]

## The contact shadow around each house's walls: a band this wide either
## side of the wall line.
const HOUSE_SHADOW_MARGIN: float = 0.9
const HOUSE_SHADOW_OPACITY: float = 0.7

signal resolved(outcome: StringName, package_id: StringName)  # see OUTCOMES below

## What the neighbour says at the door (N-604, DoorReaction): five lines per
## outcome, one picked per house from the session seed so every peer reads
## the same one. "wrong" is a box that isn't theirs (handed back, the house
## keeps waiting); "missed" is the note left on the door when nobody rang.
const REACTION_LINES: Dictionary = {
	&"delivered_ok": [
		"WORLD_REACTION_OK_1", "WORLD_REACTION_OK_2", "WORLD_REACTION_OK_3",
		"WORLD_REACTION_OK_4", "WORLD_REACTION_OK_5",
	],
	&"delivered_at_risk": [
		"WORLD_REACTION_AT_RISK_1", "WORLD_REACTION_AT_RISK_2", "WORLD_REACTION_AT_RISK_3",
		"WORLD_REACTION_AT_RISK_4", "WORLD_REACTION_AT_RISK_5",
	],
	&"delivered_ruined": [
		"WORLD_REACTION_RUINED_1", "WORLD_REACTION_RUINED_2", "WORLD_REACTION_RUINED_3",
		"WORLD_REACTION_RUINED_4", "WORLD_REACTION_RUINED_5",
	],
	&"wrong": [
		"WORLD_REACTION_WRONG_1", "WORLD_REACTION_WRONG_2",
		"WORLD_REACTION_WRONG_3", "WORLD_REACTION_WRONG_4", "WORLD_REACTION_WRONG_5",
	],
	&"missed": [
		"WORLD_REACTION_MISSED_1", "WORLD_REACTION_MISSED_2",
		"WORLD_REACTION_MISSED_3", "WORLD_REACTION_MISSED_4",
		"WORLD_REACTION_MISSED_5",
	],
}

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
## The box this house ordered (route.assign_packages()), or empty for "any".
## Ringing with somebody else's box gets it handed straight back.
var assigned_package_id: StringName = &""
var assigned_label: String = ""
signal wrong_package_offered(expected_label: String)
var doorbell: DoorbellPoint
## Porch light, mailbox and order sign: tells the crew from the road that this
## house is still waiting, and for which box (N-501).
var waiting_marker: HouseWaitingMarker
## The doorbell panel on the wall, and whether it's lit (the house waits).
var doorbell_panel: Node3D
var doorbell_number: Label3D
var doorbell_lit: bool = true
var _doorbell_materials: Array[StandardMaterial3D] = []
var _resident: Node3D
## The neighbour's scene at the door (N-604).
var reaction: DoorReaction
var _bell_player: AudioStreamPlayer3D
var _reaction_player: AudioStreamPlayer3D


func _ready() -> void:
	# Findable without walking route.gd's house list: the phone camera looks
	# for the nearest door it can document, and it has no business knowing
	# how the route is built.
	add_to_group(&"delivery_house")
	_build_house()
	_bell_player = AudioStreamPlayer3D.new()
	_bell_player.bus = &"SFX"
	_bell_player.stream = SynthAudio.glass_chime()
	_bell_player.unit_size = 8.0
	_bell_player.volume_db = WorldMix.DOORBELL_DB
	_bell_player.max_distance = 25.0
	add_child(_bell_player)
	_reaction_player = AudioStreamPlayer3D.new()
	_reaction_player.bus = &"Voice"
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
	if assigned_package_id != &"" and StringName(carried_package.get(&"package_id")) != assigned_package_id:
		# Not theirs: the resident shakes their head and the box stays with
		# whoever brought it -- the delivery isn't spent on a mix-up.
		_reaction_player.stream = SynthAudio.creature_groan()
		_reaction_player.volume_db = WorldMix.RESIDENT_GROAN_DB + WorldMix.RESIDENT_WRONG_BOX_OFFSET_DB
		_reaction_player.play()
		wrong_package_offered.emit(assigned_label)
		return
	var state: int = int(carried_package.get(&"trap_state"))
	match state:
		ITrapBehavior.TrapState.RUINED:
			_resolve(OUTCOME_RUINED, carried_package)
		ITrapBehavior.TrapState.AT_RISK:
			_resolve(OUTCOME_AT_RISK, carried_package)
		_:
			# Whatever's inside may be perfect, but a box handed over open
			# has obviously been gone through: it counts as delivered with
			# reservations, same as a dented one.
			var opened: bool = carried_package.get(&"is_open") == true
			_resolve(OUTCOME_AT_RISK if opened else OUTCOME_OK, carried_package)


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
		# (level_base.gd -> RunManager) still sees a valid package. consume()
		# also empties the carrier's hands, which a bare free never did.
		if package.has_method(&"consume"):
			package.call(&"consume", _resident.global_position)
		else:
			package.call_deferred(&"queue_free")
	# The resident's reaction follows what they were actually handed: a groan
	# for a wreck, the same groan quieter for something dented, a cheer for
	# a box that made it.
	_reaction_player.stream = SynthAudio.creature_groan() if result in [OUTCOME_RUINED, OUTCOME_AT_RISK] else SynthAudio.honk_horn()
	var groan: bool = result in [OUTCOME_RUINED, OUTCOME_AT_RISK]
	_reaction_player.volume_db = (WorldMix.RESIDENT_GROAN_DB if groan else WorldMix.RESIDENT_CHEER_DB) + (WorldMix.RESIDENT_AT_RISK_OFFSET_DB if result == OUTCOME_AT_RISK else 0.0)
	_reaction_player.play()
	resolved.emit(result, delivered_package_id)


func _build_house() -> void:
	var body := StaticBody3D.new()
	body.name = "HouseBody"
	body.collision_layer = 1
	body.collision_mask = 6
	add_child(body)
	var variant: int = posmod(visual_variant, HOUSE_VISUALS.size())
	for volume: Array in HOUSE_COLLIDERS[variant]:
		# Where the walls meet the ground, a soft dark band (N-308.2).
		ContactShadow.add(self, Vector3((volume[1] as Vector3).x, 0.0, (volume[1] as Vector3).z),
			Vector2((volume[0] as Vector3).x, (volume[0] as Vector3).z), HOUSE_SHADOW_MARGIN, HOUSE_SHADOW_OPACITY)
		var collider := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = volume[0]
		collider.position = volume[1]
		collider.shape = box_shape
		body.add_child(collider)
	var visual := load(HOUSE_VISUALS[variant]) as PackedScene
	if visual != null:
		var visual_instance := visual.instantiate()
		visual_instance.name = "HouseVisual"
		LowpolyMaterials.apply(visual_instance)
		# Somebody's home: the windows glow after dark (N-304).
		LowpolyMaterials.light_up(visual_instance, ["window"])
		add_child(visual_instance)
		# A few hundred authored parts, none of which ever move: one draw
		# call per material instead of one per part.
		DressingBatcher.merge_into_one(visual_instance)

	# The resident shares the game's rigged low-poly character rather than a
	# capsule. A warm unique uniform makes them read as a local, not player 2.
	_resident = RESIDENT_SCENE.instantiate() as Node3D
	_resident.name = "Resident"
	# The imported house fronts face local -Z (the same direction set by
	# Route._build_houses()), so keep the resident and interaction point on
	# the actual porch instead of behind the building.
	_resident.position = Vector3(0.0, 0.0, -2.7)
	# The character model faces -Z (as the depot staff do), out of the door
	# toward the road; no turn needed.
	_resident.rotation.y = 0.0
	_resident.scale = Vector3.ONE * 0.92
	_tint_first_mesh(_resident, Color("b56f4d"))
	_resident.visible = false
	add_child(_resident)
	# The neighbour's reaction (N-604): from the record the host relays to
	# everyone, so clients see it too -- `resolved` only fires on the host.
	reaction = DoorReaction.new()
	reaction.name = "DoorReaction"
	add_child(reaction)
	reaction.setup(_resident, house_index, Vector3(0.0, NOTE_HEIGHT, DOORBELL_WALL_Z[variant] - DOOR_PANEL_PROUD))
	var events: Node = get_node_or_null(^"/root/EventBus")
	if events != null:
		events.connect(&"house_delivery_recorded", _on_delivery_reaction)
		events.connect(&"house_refused_package", _on_refused_reaction)

	doorbell = DoorbellPoint.new()
	doorbell.name = "Doorbell"
	doorbell.position = Vector3(DOORBELL_PANEL_X, DOORBELL_HEIGHT, DOORBELL_WALL_Z[variant] - DOORBELL_REACH)
	var bell_shape := SphereShape3D.new()
	bell_shape.radius = 1.6
	var bell_collider := CollisionShape3D.new()
	bell_collider.shape = bell_shape
	doorbell.add_child(bell_collider)
	add_child(doorbell)
	_build_doorbell_visual()
	doorbell.rung.connect(_on_doorbell_rung)
	waiting_marker = HouseWaitingMarker.new()
	waiting_marker.name = "WaitingMarker"
	waiting_marker.house_index = house_index
	waiting_marker.house_bounds = _visual_bounds()
	add_child(waiting_marker)
	waiting_marker.set_number(house_index + 1)
	waiting_marker.set_order(assigned_label)


## The doorbell panel (tareas de Nacho N-302) on the wall beside the door, at
## the doorbell's height: plate, house number, intercom grille and the bell
## push. The number window and the push glow while the house waits for its
## box and go dark once it's resolved -- the same moment the porch light goes
## out, from the record the host relays to everyone (as HouseWaitingMarker).
## Ringing still happens at `doorbell`, a reach in front of it.
func _build_doorbell_visual() -> void:
	var variant: int = posmod(visual_variant, HOUSE_VISUALS.size())
	doorbell_panel = (load(DOORBELL_PANEL) as PackedScene).instantiate() as Node3D
	doorbell_panel.name = "DoorbellPanel"
	doorbell_panel.position = Vector3(DOORBELL_PANEL_X, DOORBELL_HEIGHT, DOORBELL_WALL_Z[variant])
	add_child(doorbell_panel)
	for part: Array in [["NumberPlate", DOORBELL_WINDOW], ["Button", DOORBELL_BUTTON]]:
		var mesh := doorbell_panel.find_child(part[0], true, false) as MeshInstance3D
		var material := _material(part[1])
		material.emission = part[1]
		material.emission_energy_multiplier = 1.3
		_doorbell_materials.append(material)
		if mesh != null:
			mesh.material_override = material
	# On the number window, whose face stands 3.6 cm off the wall.
	doorbell_number = Label3D.new()
	doorbell_number.name = "DoorbellNumber"
	doorbell_number.text = str(house_index + 1)
	doorbell_number.font = DOORBELL_FONT
	doorbell_number.font_size = 64
	doorbell_number.pixel_size = 0.0008
	doorbell_number.modulate = DOORBELL_INK
	doorbell_number.outline_size = 0
	doorbell_number.double_sided = false
	doorbell_number.position = Vector3(0.0, 0.08, -0.0375)
	doorbell_number.rotation.y = PI
	doorbell_panel.add_child(doorbell_number)
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"house_delivery_recorded", _on_house_delivery_recorded)
	set_doorbell_lit(doorbell_lit)


func _on_delivery_reaction(index: int, result: StringName, _package_id: StringName) -> void:
	if index == house_index and REACTION_LINES.has(result):
		reaction.react(result, tr(DoorReaction.pick_line(REACTION_LINES[result], _session_seed(), house_index, result)))


func _on_refused_reaction(index: int, expected_label: String) -> void:
	if index != house_index:
		return
	var line: String = tr(DoorReaction.pick_line(REACTION_LINES[&"wrong"], _session_seed(), house_index, &"wrong"))
	reaction.refuse(line % expected_label if line.contains("%s") else line)


func _session_seed() -> int:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	return int(network.get(&"world_seed")) if network != null else 0


func _on_house_delivery_recorded(index: int, _outcome: StringName, _package_id: StringName) -> void:
	if index == house_index:
		set_doorbell_lit(false)


func set_doorbell_lit(value: bool) -> void:
	doorbell_lit = value
	for material: StandardMaterial3D in _doorbell_materials:
		material.emission_enabled = value


func _tint_first_mesh(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var material := _material(color)
		(node as MeshInstance3D).set_surface_override_material(0, material)
		return
	for child: Node in node.get_children():
		_tint_first_mesh(child, color)


## The house model's extent in this node's space, porch and eaves included.
func _visual_bounds() -> AABB:
	var visual := get_node_or_null(^"HouseVisual") as Node3D
	if visual == null:
		return HouseWaitingMarker.DEFAULT_BOUNDS
	var result := AABB()
	var first: bool = true
	for child: Node in visual.find_children("*", "VisualInstance3D", true, false):
		var box: AABB = (global_transform.affine_inverse() * (child as Node3D).global_transform) * (child as VisualInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return HouseWaitingMarker.DEFAULT_BOUNDS if first else result


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
