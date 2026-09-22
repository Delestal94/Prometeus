extends "res://scripts/gameplay/interaction/interactable.gd"
## Both rear leaves are treated as one loading-door interaction.  The host
## owns the state, while the vehicle synchronizer mirrors it to every peer.

func get_prompt() -> String:
	var vehicle := get_parent()
	return "Cerrar puertas traseras" if bool(vehicle.get(&"rear_cargo_open")) else "Abrir puertas traseras"


func interact(_player: Node) -> void:
	var vehicle := get_parent()
	vehicle.call(&"set_rear_cargo_open", not bool(vehicle.get(&"rear_cargo_open")))

