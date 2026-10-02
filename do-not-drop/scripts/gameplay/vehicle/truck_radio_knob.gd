extends Interactable
## The radio's knob on the dashboard (tareas de Nacho N-406), hung on the van
## from outside by TruckRadio like the fault repair spots: the same node path
## on every peer, so a client's request_interact reaches the host. Anyone on
## foot in the cab can turn it; the host cycles the mode through
## TruckRadio.cycle() and sends it to everyone.

## The TruckRadio that owns the mode. Typed like truck_radio_view.gd: only
## truck_radio.gd preloads this file, so naming it here adds nothing to the
## compile graph of a --script.
var radio: TruckRadio


func _ready() -> void:
	super._ready()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	add_child(shape)


func get_prompt() -> String:
	if radio == null:
		return ""
	var current: StringName = radio.mode
	var next: StringName = TruckRadio.next_mode(current)
	var names: Array[String] = [tr(TruckRadio.mode_key(current)), tr(TruckRadio.mode_key(next))]
	return tr("WORLD_RADIO_PROMPT") % names


## By name: the interactable contract hands over any node in the player group,
## and the tests' stand-ins carry a box without being a Player.
func can_interact(player: Node) -> bool:
	return radio != null and player.get(&"carried_package") == null


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	if radio.cycle() != &"":
		interacted.emit(player)
