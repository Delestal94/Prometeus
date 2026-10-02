extends RefCounted
## The owning peer's unhandled input on foot (N-225.5), split out of player.gd: the ping wheel, the card, drop
## and lid keys, standing up from a seat, looking around with the mouse and interacting. Player.gd keeps
## `_unhandled_input()` (the engine's callback) and the state; what each key does is decided in the components.

const MOUSE_SENSITIVITY: float = 0.0028


static func handle_event(p: Player, event: InputEvent) -> void:
	if not p.is_local():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not p._ping_input.wheel_open:
		return
	if p._ping_input.handle_event(event) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if handle_package_input(p, event):
		return
	if p._seated:
		if p._interaction_component.is_interact_event(event):
			# Mark this press as used, or _poll_interact() would read the
			# still-held E on the next physics tick and sit right back down.
			p._interact_was_down = true
			p.leave_seat()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		p._apply_look(event.relative * MOUSE_SENSITIVITY)
	elif event.is_action_pressed(&"look_center"):
		p._pitch = 0.0
		p._head.rotation.x = 0.0
	elif p._interaction_component.is_interact_event(event):
		# Same press must not also reach _poll_interact() on the next physics
		# tick: two interactions per E put a box on the shelf and grabbed it
		# straight back, or opened a door and shut it again.
		p._interact_was_down = true
		p._interaction_component.try_interact()


## Card, drop and lid keys; true when the event was one of them.
static func handle_package_input(p: Player, event: InputEvent) -> bool:
	if event.is_action_pressed(&"use_card"):
		p._interaction_component.use_card()
	elif p._interaction_component.is_drop_event(event):
		# Seated, "drop" moves the box you tend between your lap and its rack
		# (docs/jugabilidad-paquetes-rescate.md): never onto the floor.
		if p._seated and is_instance_valid(p.tended_package):
			p.tended_package.rpc_id(1, &"request_lap_toggle")
		else:
			p._carry_component.drop_carried()
	elif p._interaction_component.is_open_event(event):
		p._interaction_component.toggle_package_lid()
	else:
		return false
	return true
