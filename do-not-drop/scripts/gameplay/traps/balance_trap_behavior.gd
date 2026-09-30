class_name BalanceTrapBehavior
extends "res://scripts/gameplay/traps/i_trap_behavior.gd"
## Must stay upright. Tilting past the safe angle bleeds integrity, and
## staying past the danger angle spills it outright. "Contrapesá" (N-117): its
## passenger holds the primary action and pushes (WASD, the left stick, as the
## seat's own view sees them) toward the side opposite to where the box leans
## to push it back level -- enough to
## fight a normal corner, not enough to save an emergency brake. Holding
## without leaning does nothing, and leaning the wrong way does nothing
## either (no penalty beyond the box not coming back).
##
## An input with no "lean" axis at all is the solo rack assistant's plain
## steadying (package_rescue.gd), which still works the old way.

var tilt_degrees: float = 0.0

var _angle_ok_max: float = 15.0
var _angle_at_risk_max: float = 30.0
var _fail_seconds: float = 1.5
var _damage_per_second: float = 20.0
var _correction_degrees_per_second: float = 20.0
var _seconds_past_danger: float = 0.0
var _is_steadying: bool = false
var _steady_strength: float = 0.0
## Which way the box leans, looking along the truck: +1 to its right, -1 to
## its left, 0 upright (what the passenger has to lean against).
var tilt_side: float = 0.0
## The same tilt as a unit direction in the truck's frame (x to its right,
## y forward), zero when upright: what the push is measured against, in every
## direction, so a box pitched by a hard brake asks for a push along the truck.
var tilt_dir := Vector2.ZERO
## What the passenger's body does (-1..1, +1 = right): the lean they hold.
var _push: float = 0.0
## Running with the box in the arms (N-115) rocks it: each step adds a few
## degrees of lean on top of the real tilt, which settle once the carrier
## stops. Kept under the danger angle: a cake tips, it is not thrown.
const RUN_TILT_PER_STEP: float = 2.5
const RUN_TILT_SETTLE: float = 4.0
var _run_tilt: float = 0.0


func on_setup(package: Node, config: Dictionary) -> void:
	super.on_setup(package, config)
	_angle_ok_max = float(config.get("angle_ok_max", 15.0))
	_angle_at_risk_max = float(config.get("angle_at_risk_max", 30.0))
	_fail_seconds = float(config.get("angle_fail_seconds", 1.5))
	_damage_per_second = float(config.get("damage_per_second_at_risk", 20.0))
	_correction_degrees_per_second = float(config.get("correction_strength", 20.0))
	tilt_degrees = 0.0
	tilt_side = 0.0
	tilt_dir = Vector2.ZERO
	_push = 0.0
	_run_tilt = 0.0
	_seconds_past_danger = 0.0


func on_physics_process(package: Node, delta: float, context: Dictionary) -> void:
	if get_state() == TrapState.RUINED:
		return
	var before_state: int = get_state()
	var input: Dictionary = context.get("input", {}) as Dictionary
	var held: float = float(input.get("steady_strength", 1.0 if bool(input.get("steady", false)) else 0.0))
	_run_tilt = maxf(_run_tilt - RUN_TILT_SETTLE * delta, 0.0)
	tilt_degrees = _measure_tilt(package) + _run_tilt
	tilt_dir = _measure_direction(package, context)
	tilt_side = signf(tilt_dir.x) if absf(tilt_dir.x) > 0.02 else 0.0
	# The push, already in the truck's frame (the host turns what the passenger
	# pressed on their own view into it): `lean` to the truck's right and
	# `lean_long` forward.
	var lean: float = float(input.get("lean", 0.0))
	var push := Vector2(lean, float(input.get("lean_long", 0.0)))
	_push = clampf(lean, -1.0, 1.0) if held > 0.0 else 0.0
	# Holding is not enough: the correction is however much they push against
	# the tilt, up to how hard they hold.
	_steady_strength = held
	if input.has("lean"):
		_steady_strength = clampf(-tilt_dir.dot(push), 0.0, held)
	_is_steadying = _steady_strength > 0.0
	if _is_steadying:
		_apply_correction(package, delta, _steady_strength)
	if tilt_degrees > _angle_at_risk_max:
		_seconds_past_danger += delta
	else:
		_seconds_past_danger = 0.0
	if _seconds_past_danger >= _fail_seconds:
		damage(integrity)
		return
	if tilt_degrees > _angle_ok_max:
		damage(_damage_per_second * delta)
	if before_state == TrapState.AT_RISK and get_state() == TrapState.OK:
		_add_milestone(&"leveled")


func on_carried_step(strength: float) -> float:
	if get_state() == TrapState.RUINED:
		return 0.0
	_run_tilt = minf(_run_tilt + RUN_TILT_PER_STEP * strength, _angle_at_risk_max - 6.0)
	return damage(0.4 * strength)


func get_state() -> int:
	if integrity <= 0.0:
		return TrapState.RUINED
	if tilt_degrees > _angle_ok_max or integrity <= integrity_max * 0.4:
		return TrapState.AT_RISK
	return TrapState.OK


func hint_text() -> Array:
	if get_state() == TrapState.RUINED:
		return LocText.make("HUD_HINT_BALANCE_RUINED")
	if tilt_degrees > _angle_at_risk_max:
		return LocText.make("HUD_HINT_BALANCE_DANGER")
	if tilt_degrees > _angle_ok_max:
		return LocText.make("HUD_HINT_BALANCE_TILTED", [roundi(tilt_degrees)])
	return LocText.make("HUD_HINT_BALANCE_OK")


## The published gesture: which side to lean to and what the body is doing.
func gesture_state() -> Dictionary:
	return {"kind": &"lean", "side": tilt_side, "dir": tilt_dir, "push": _push, "tilt": tilt_degrees}


func care_action() -> StringName:
	return &"lean"


## Which way the box's top leans, along the truck (the context carries the
## truck's right and forward; a bare test without them uses the world's).
func _measure_direction(package: Node, context: Dictionary) -> Vector2:
	if package == null:
		return tilt_dir
	var right: Vector3 = context.get("truck_right", Vector3.RIGHT)
	var forward: Vector3 = context.get("truck_forward", Vector3.FORWARD)
	var up: Vector3 = (package.get(&"global_basis") as Basis).y
	var lean := Vector2(up.dot(right), up.dot(forward))
	return lean.normalized() if lean.length() > 0.002 else Vector2.ZERO


func _measure_tilt(package: Node) -> float:
	if package == null:
		return tilt_degrees
	var up: Vector3 = (package.get(&"global_basis") as Basis).y
	return rad_to_deg(up.angle_to(Vector3.UP))


func _apply_correction(package: Node, delta: float, strength: float = 1.0) -> void:
	if package == null or tilt_degrees <= 0.01:
		return
	var basis: Basis = package.get(&"global_basis") as Basis
	var axis: Vector3 = basis.y.cross(Vector3.UP)
	if axis.length_squared() < 0.000001:
		return
	# Rotate the box back toward upright, capped so it can fight a corner
	# but never instantly undo a real slam.
	var step: float = minf(deg_to_rad(_correction_degrees_per_second * strength * delta), deg_to_rad(tilt_degrees))
	var corrected: Basis = Basis(axis.normalized(), step) * basis
	var transform: Transform3D = package.get(&"global_transform") as Transform3D
	package.set(&"global_transform", Transform3D(corrected.orthonormalized(), transform.origin))
	tilt_degrees = _measure_tilt(package)
