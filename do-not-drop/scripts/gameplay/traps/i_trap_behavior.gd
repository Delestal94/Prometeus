class_name ITrapBehavior
extends Resource
## Mutable simulation state belongs to one package, never to a shared .tres.
##
## Every trap maps its own failure axis onto the same 0..integrity_max scale,
## so the HUD, the score and the EventBus contract stay identical no matter
## which trap a package carries. A trap that fails by tilting or by getting
## agitated still reports "integrity" like the fragile one does.
##
## Player input arrives inside the context dictionary of on_physics_process
## rather than as InputEvents: holds ("steady", "calm") are states, not
## events, and a plain data dictionary is what the host will receive from
## each client once networking lands (see docs/requerimientos-tecnicos.md).

enum TrapState { OK, AT_RISK, RUINED }

var integrity: float = 100.0
var integrity_max: float = 100.0
var _milestones: Array[StringName] = []


func on_setup(_package: Node, config: Dictionary) -> void:
	integrity_max = maxf(float(config.get("integrity_max", 100.0)), 1.0)
	integrity = integrity_max
	_milestones.clear()


func on_physics_process(_package: Node, _delta: float, _context: Dictionary) -> void:
	pass


func on_impact(_delta_velocity: float) -> float:
	return 0.0


func get_state() -> int:
	return TrapState.OK


## Short line the HUD shows under the cargo readout, so each trap can tell
## the player what it currently wants from them.
func get_hint() -> String:
	return ""


## Milestones are consumed by DeliveryPackage on the host. Keeping them in
## the behavior lets each trap define what "good play" means without making
## the package inspect trap-specific state.
func take_milestones() -> Array[StringName]:
	var taken: Array[StringName] = _milestones.duplicate()
	_milestones.clear()
	return taken


## A state can update more than once in one physics frame. One occurrence is
## still one action, so duplicate milestone ids wait only once in the queue.
func _add_milestone(milestone: StringName) -> void:
	if not _milestones.has(milestone):
		_milestones.append(milestone)


## Applies damage and returns how much was actually lost, so callers can
## report a real delta after clamping.
func damage(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var previous: float = integrity
	integrity = clampf(integrity - amount, 0.0, integrity_max)
	return previous - integrity
