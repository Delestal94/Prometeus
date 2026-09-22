extends "res://scripts/gameplay/interaction/interactable.gd"
class_name DoorbellPoint
## The doorbell at a DeliveryHouse's door. Extends Slatex's Interactable base
## (docs/colaboracion-equipo.md) read-only, same pattern package_mount_point.gd
## already uses -- doesn't touch that file at all.
##
## Always ring-able, even empty-handed: showing up without the right package
## is a real, intended outcome ("tenés que bajarte a tocar el timbre y dar
## las explicaciones"), not something to block. DeliveryHouse (the parent)
## decides what actually happens; this only reports what the ringing player
## was carrying.

signal rung(carried_package: Node)


func get_prompt() -> String:
	return "Tocar timbre"


func can_interact(_player: Node) -> bool:
	return true


func interact(player: Node) -> void:
	var carried: Node = player.get(&"carried_package")
	rung.emit(carried)
	interacted.emit(player)
