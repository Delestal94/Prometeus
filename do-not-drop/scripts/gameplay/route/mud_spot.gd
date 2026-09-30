extends Interactable
## A place on a bogged truck where the crew gets it out of the mud (N-108):
## "push" behind the rear doors, "strap" at the front bumper. MudSegment moves
## both onto the truck while it is stuck and answers for them: this only asks
## it, so the prompt, the reach and the host-only effect live in one place.
## Built by name in every peer's copy of the segment, so its node path is the
## same everywhere (Interactable.request_interact travels by path).

## &"push" or &"strap".
var kind: StringName = &"push"
## The MudSegment this spot belongs to.
var mud: Node
var _status: Label3D


func _ready() -> void:
	super._ready()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5 if kind == &"push" else 0.9
	shape.shape = sphere
	add_child(shape)
	_status = Label3D.new()
	_status.name = "Status"
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.no_depth_test = true
	_status.font_size = 40
	_status.pixel_size = 0.006
	_status.outline_size = 8
	_status.modulate = Color("f2d26b")
	_status.position = Vector3(0.0, 1.3, 0.0)
	_status.visible = false
	add_child(_status)


func get_prompt() -> String:
	return tr(String(mud.call(&"spot_prompt", kind))) if mud != null else ""


func can_interact(player: Node) -> bool:
	return mud != null and bool(mud.call(&"can_use_spot", kind, player))


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	mud.call(&"use_spot", kind, player)
	interacted.emit(player)


## The board over the spot ("Empujando 40 % · grúa en 31 s"); "" hides it.
func show_status(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	_status.visible = not text.is_empty()
