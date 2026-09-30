extends Interactable
class_name DogDistractPoint
## "Tirarle un palo": the way to send off the dog that has climbed onto an
## open box (N-109.2). It rides on the dog (cargo_animal_view.gd), so aiming at
## the dog and pressing interact is the whole gesture -- the same one as
## ringing a bell or using the hook, nothing new to learn. Extends Slatex's
## Interactable read-only, like doorbell_point.gd.
##
## Free hands only: you can't throw a stick with a box in your arms. Like every
## interaction, interact() runs on the host, which is where the director
## (cargo_animals.gd) decides the dog is gone.

signal thrown(peer_id: int)

## Whether the dog is there to be distracted (the view switches it).
var active: bool = false


func get_prompt() -> String:
	return tr("WORLD_DOG_THROW_PROMPT") if active else ""


func can_interact(player: Node) -> bool:
	return active and player.get(&"carried_package") == null


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	thrown.emit(int(player.get_multiplayer_authority()))
	interacted.emit(player)
