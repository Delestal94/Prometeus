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
## Two are edges, true for one tick only: "direction_pressed" (a sequence
## key) and "tap" (the primary action going down, N-117). The road ahead
## comes the same way (see wants_road_ahead()).

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


## What the hands on this box should be doing right now: &"hold" (the
## primary action: steady, calm, mop), &"release" (hands off), or &"" when
## it asks nothing. The care panel turns it into one instruction; a tap
## sequence (sequence_state()) is shown on top of it.
func care_action() -> StringName:
	return &"hold"


## Whether hands on the box (the primary action held) shield it from hits and
## from the truck's sway, as PackageCare.HOLD_PROTECTION says for every trap by
## default. Fragile says no (N-117: "Amortiguá" is a tap, holding does nothing);
## a rack assistant in a solo run still counts.
func hold_protects() -> bool:
	return true


## Whether this trap wants to hear about the road ahead: the package then
## adds `impact_ahead` (seconds to the next announced bump, INF when there
## is none) to the context and feeds road_jolt_strength() to apply_impact()
## as the box crosses each one. See RoadImpacts.
func wants_road_ahead() -> bool:
	return false


## What crossing a bump at `speed` (m/s) does to the box, as an impact
## strength (m/s of velocity change); 0 when the trap doesn't care.
func road_jolt_strength(_speed: float) -> float:
	return 0.0


## A trap answered by a tap of the primary action at the right moment
## (`input["tap"]`, the rising edge) says where that stands so every peer can
## draw it (published with the care state): {eta: seconds to the announced
## hit or -1, ready: a tap would count, shield: a tap is protecting it,
## wait: seconds until the next tap counts, taps, saved}. Empty for the rest.
func cushion_state() -> Dictionary:
	return {}


## A trap solved by tapping directions one at a time says where that stands,
## so the care panel can show and sound it on every peer (the behavior only
## runs on the host; PackageRescue.publish_care() replicates this):
## {steps: Array[StringName], index: next step, mistakes: wrong taps so far,
##  solved: times completed, seconds: time left (or -1), verb: what solving
##  does}. Empty for every other trap.
func sequence_state() -> Dictionary:
	return {}


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
