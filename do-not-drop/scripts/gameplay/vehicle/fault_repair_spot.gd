extends Interactable
## Where a truck fault gets fixed (tareas de Nacho N-214.3): one per fault,
## hung on the van from outside (vehicle.gd is frozen) by VehicleFaults, so
## its node path is the same on every peer. It only offers itself while its
## fault is active. The client sends the intent (Interactable.request_interact)
## and the host fixes it through VehicleFaults.fix(): the spare part from the
## depot if the crew bought one, otherwise the improvised fix from the shared
## kit when this fault has one. The mirror's is a passenger holding their
## phone up (VehicleFaults.hold_phone()), which the driver can't do.

## The fault this spot fixes (VehicleFaults.FAULTS).
var fault_id: StringName
## The VehicleFaults that owns the list and the spares.
var faults: Node


func _ready() -> void:
	super._ready()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	add_child(shape)


func get_prompt() -> String:
	if faults == null:
		return ""
	return tr(String(faults.call(&"repair_prompt", fault_id)))


func can_interact(player: Node) -> bool:
	if faults == null or player.get(&"carried_package") != null:
		return false
	var method: StringName = faults.call(&"repair_method", fault_id)
	if method == &"phone":
		return not bool(faults.call(&"is_driver", player.get_multiplayer_authority()))
	return not method.is_empty()


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	if bool(faults.call(&"fix", fault_id, player)):
		interacted.emit(player)
