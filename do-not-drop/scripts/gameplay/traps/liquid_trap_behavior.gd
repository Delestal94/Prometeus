class_name LiquidTrapBehavior
extends "res://scripts/gameplay/traps/i_trap_behavior.gd"
## A leaky package is not Balance 2.0: small tilts create a manageable
## puddle, impacts make it surge, and a passenger can mop it down before the
## leak becomes a full loss.  Cleaning lowers current spill, never restores
## integrity already lost.
##
## "Fregá" (N-117): the mop is a scrub, left-right-left-right (A and D, the
## stick swung from side to side) with no button held; the one trap whose
## gesture is fast. Each swing to the other side dries a little
## (`scrub_amount`); the same side twice, or holding anything, dries nothing.

## A scrub that pauses longer than this starts over (s).
const SCRUB_MEMORY: float = 0.8

var spill_amount: float = 0.0
var tilt_degrees: float = 0.0
var _safe_angle: float = 10.0
var _danger_angle: float = 24.0
var _leak_per_second: float = 7.0
var _surge_per_second: float = 24.0
var _impact_threshold: float = 4.0
var _impact_spill: float = 18.0
var _scrub_amount: float = 2.0
## Faster than this a swing is the same one twice (s): it stops a jittery stick
## from drying more than a hand can.
var _scrub_gap: float = 0.08
var _integrity_loss_per_spill: float = 0.23
var _had_large_spill: bool = false
## The side of the last swing (-1 left, +1 right, 0 none yet), how long ago,
## and swings that counted so far.
var _last_side: float = 0.0
var _since_swing: float = 99.0
var scrubs: int = 0


func on_setup(_package: Node, config: Dictionary) -> void:
	super.on_setup(_package, config)
	_safe_angle = float(config.get("safe_angle", 10.0))
	_danger_angle = float(config.get("danger_angle", 24.0))
	_leak_per_second = float(config.get("leak_per_second", 7.0))
	_surge_per_second = float(config.get("surge_per_second", 24.0))
	_impact_threshold = float(config.get("impact_threshold", 4.0))
	_impact_spill = float(config.get("impact_spill", 18.0))
	_scrub_amount = float(config.get("scrub_amount", 2.0))
	_scrub_gap = maxf(float(config.get("scrub_gap", 0.08)), 0.0)
	_integrity_loss_per_spill = float(config.get("integrity_loss_per_spill", 0.23))
	spill_amount = 0.0
	_had_large_spill = false
	_last_side = 0.0
	_since_swing = 99.0
	scrubs = 0


func on_physics_process(package: Node, delta: float, context: Dictionary) -> void:
	if get_state() == TrapState.RUINED:
		return
	if spill_amount > 30.0:
		_had_large_spill = true
	tilt_degrees = _measure_tilt(package)
	var tilt_ratio: float = clampf((tilt_degrees - _safe_angle) / maxf(_danger_angle - _safe_angle, 0.01), 0.0, 1.0)
	if tilt_ratio > 0.0:
		var rate: float = lerpf(_leak_per_second, _surge_per_second, tilt_ratio)
		spill_amount = minf(integrity_max, spill_amount + rate * delta)
	_since_swing += delta
	var input: Dictionary = context.get("input", {}) as Dictionary
	var pressed: Variant = input.get("direction_pressed")
	_scrub(StringName(pressed) if pressed != null else &"")
	if spill_amount > 30.0:
		_had_large_spill = true
	elif _had_large_spill and is_zero_approx(spill_amount):
		_had_large_spill = false
		_add_milestone(&"dried")
	# The wetness is the danger buffer.  Once it gets serious, it converts
	# into permanent package damage at a pace a teammate can still fight.
	if spill_amount > integrity_max * 0.14:
		damage((spill_amount / integrity_max) * _integrity_loss_per_spill * 100.0 * delta)


## One swing of the scrub: it dries only when it comes from the other side of
## the last one, and that one was not long ago (a lone swing after a pause
## just starts a new scrub).
func _scrub(direction: StringName) -> void:
	if direction != &"left" and direction != &"right":
		return
	var side: float = -1.0 if direction == &"left" else 1.0
	if side == _last_side and _since_swing < SCRUB_MEMORY:
		return
	var continuing: bool = _last_side != 0.0 and side != _last_side and _since_swing < SCRUB_MEMORY
	if continuing and _since_swing < _scrub_gap:
		return
	_last_side = side
	_since_swing = 0.0
	if continuing:
		scrubs += 1
		spill_amount = maxf(0.0, spill_amount - _scrub_amount)


func on_impact(delta_velocity: float) -> float:
	if delta_velocity >= _impact_threshold:
		spill_amount = minf(integrity_max, spill_amount + _impact_spill * (delta_velocity / _impact_threshold))
		if spill_amount > 30.0:
			_had_large_spill = true
	return 0.0


## The published gesture: the side of the last swing (the next one has to be
## the other) and, while it keeps going, the body's sway.
func gesture_state() -> Dictionary:
	var going: bool = _since_swing < 0.4
	return {"kind": &"scrub", "last": _last_side if _since_swing < SCRUB_MEMORY else 0.0,
		"push": _last_side if going else 0.0, "scrubs": scrubs}


func care_action() -> StringName:
	return &"scrub"


func get_state() -> int:
	if integrity <= 0.0 or spill_amount >= integrity_max:
		return TrapState.RUINED
	if spill_amount >= integrity_max * 0.30 or tilt_degrees > _safe_angle:
		return TrapState.AT_RISK
	return TrapState.OK


func hint_text() -> Array:
	if get_state() == TrapState.RUINED:
		return LocText.make("HUD_HINT_LIQUID_RUINED")
	if spill_amount >= integrity_max * 0.30:
		return LocText.make("HUD_HINT_LIQUID_DANGER")
	if tilt_degrees > _safe_angle:
		return LocText.make("HUD_HINT_LIQUID_TILTED", [roundi(tilt_degrees)])
	return LocText.make("HUD_HINT_LIQUID_OK")


func _measure_tilt(package: Node) -> float:
	if package == null:
		return tilt_degrees
	var up: Vector3 = (package.get(&"global_basis") as Basis).y
	return rad_to_deg(up.angle_to(Vector3.UP))
