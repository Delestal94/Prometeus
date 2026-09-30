extends Interactable
## The radio's knob on the dashboard (tareas de Nacho N-406), hung on the van
## from outside by TruckRadio like the fault repair spots: the same node path
## on every peer, so a client's request_interact reaches the host. Anyone on
## foot in the cab can turn it; the host cycles the mode through
## TruckRadio.cycle() and sends it to everyone.

## The TruckRadio that owns the mode.
var radio: Node


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
	var current: StringName = radio.get(&"mode")
	var next: StringName = radio.call(&"next_mode", current)
	var names: Array[String] = [tr(String(radio.call(&"mode_key", current))), tr(String(radio.call(&"mode_key", next)))]
	return tr("WORLD_RADIO_PROMPT") % names


func can_interact(player: Node) -> bool:
	return radio != null and player.get(&"carried_package") == null


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	if radio.call(&"cycle") != &"":
		interacted.emit(player)
