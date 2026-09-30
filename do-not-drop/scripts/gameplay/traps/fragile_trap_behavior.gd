class_name FragileTrapBehavior
extends ITrapBehavior
## Loses integrity on impacts. "Amortiguá" (N-117): the road announces its
## bumps a moment before the truck reaches them (`impact_ahead` in the
## context, from RoadImpacts), and one tap of the primary action inside a
## short window before a bump takes most of the sting out of it.
##
## Only the rising edge counts (`input["tap"]`): holding the button does
## nothing, and after every tap there is a wait, so mashing is no use. A
## hit nobody announced (a crash) cannot be softened, on purpose.
##
## The truck's suspension swallows a bump at any sensible speed (measured in
## docs/parametros-diseno.md, "Golpes por tipo de tramo"), so on its own a
## bump would never hurt a box. road_jolt_strength() is what makes it do so
## when taken fast: the package feeds it to apply_impact() as the box
## crosses the bump, above `bump_safe_speed`, and set `bump_jolt_per_speed`
## to 0 to turn that off.

## What a tap has to do to count, and what it leaves behind.
var _threshold_light: float = 3.0
var _threshold_heavy: float = 7.0
var _damage_light: float = 10.0
var _damage_heavy: float = 35.0
var _at_risk_at: float = 40.0
var _ruined_at: float = 0.0
## How long after a tap a announced hit is softened, s.
var _cushion_window: float = 0.35
## Wait after a tap before the next one counts, s.
var _cushion_cooldown: float = 1.0
## Share of a softened hit's damage that still gets through.
var _cushion_leak: float = 0.1
## How far ahead of a hit the box starts showing it, s.
var _warn_lead: float = 0.7
## Above this speed (m/s) a bump hurts; below it the truck absorbs it.
var _bump_safe_speed: float = 9.7
## Impact strength (m/s of velocity change) per m/s over the safe speed.
var _bump_jolt_per_speed: float = 1.8
## Integrity lost per running step with the box in the arms (N-115): the most of
## any trap, the vase feels every footfall.
var _run_step_damage: float = 1.4

## Seconds a tap still shields, and the wait before the next one.
var _cushion_left: float = 0.0
var _cooldown_left: float = 0.0
## A hit is announced (or just landed): the only time a tap can soften it.
var _warn_left: float = 0.0
## Seconds to the announced hit, INF when the road ahead is quiet.
var _eta: float = INF
## Hits softened so far: presentation flashes when it goes up.
var saved_hits: int = 0
var tap_count: int = 0


func on_setup(package: Node, config: Dictionary) -> void:
	super.on_setup(package, config)
	_threshold_light = float(config.get("impact_threshold_light", 3.0))
	_threshold_heavy = float(config.get("impact_threshold_heavy", 7.0))
	_damage_light = float(config.get("impact_damage_light", 10.0))
	_damage_heavy = float(config.get("impact_damage_heavy", 35.0))
	_at_risk_at = float(config.get("at_risk_at", 40.0))
	_ruined_at = float(config.get("ruined_at", 0.0))
	_cushion_window = maxf(float(config.get("cushion_window", 0.35)), 0.01)
	_cushion_cooldown = maxf(float(config.get("cushion_cooldown", 1.0)), 0.0)
	_cushion_leak = clampf(float(config.get("cushion_leak", 0.1)), 0.0, 1.0)
	_warn_lead = maxf(float(config.get("warn_lead", 0.7)), _cushion_window)
	_bump_safe_speed = maxf(float(config.get("bump_safe_speed", 9.7)), 0.0)
	_bump_jolt_per_speed = maxf(float(config.get("bump_jolt_per_speed", 1.8)), 0.0)
	_run_step_damage = maxf(float(config.get("run_step_damage", 1.4)), 0.0)
	_cushion_left = 0.0
	_cooldown_left = 0.0
	_warn_left = 0.0
	_eta = INF
	saved_hits = 0
	tap_count = 0


func on_physics_process(_package: Node, delta: float, context: Dictionary) -> void:
	_cushion_left = maxf(0.0, _cushion_left - delta)
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_warn_left = maxf(0.0, _warn_left - delta)
	_eta = float(context.get("impact_ahead", INF))
	if _eta <= _warn_lead:
		# Stays up a moment past the hit: it lands on the tick the road
		# reports zero, after this one.
		_warn_left = _cushion_window
	var input: Dictionary = context.get("input", {}) as Dictionary
	if bool(input.get("tap", false)) and _cooldown_left <= 0.0:
		_cooldown_left = _cushion_cooldown
		_cushion_left = _cushion_window
		tap_count += 1


func on_impact(delta_velocity: float) -> float:
	if get_state() == TrapState.RUINED:
		return 0.0
	var amount: float = 0.0
	if delta_velocity >= _threshold_heavy:
		amount = _damage_heavy
	elif delta_velocity >= _threshold_light:
		amount = _damage_light
	if amount <= 0.0:
		return 0.0
	if _cushion_left > 0.0 and _warn_left > 0.0:
		amount *= _cushion_leak
		saved_hits += 1
	return damage(amount)


func on_carried_step(strength: float) -> float:
	if get_state() == TrapState.RUINED:
		return 0.0
	return damage(_run_step_damage * strength)


## What crossing a bump at `speed` (m/s) does to this box, as the impact
## strength apply_impact() takes; 0 when the truck takes it slowly enough.
func road_jolt_strength(speed: float) -> float:
	return maxf(0.0, speed - _bump_safe_speed) * _bump_jolt_per_speed


func wants_road_ahead() -> bool:
	return true


## Holding the button does nothing for Fragile: only the tap does.
func hold_protects() -> bool:
	return false


## What the box shows and the passenger reads: {eta: seconds to the
## announced hit (-1 none), ready: a tap would count, shield: a tap is
## still protecting it, wait: seconds until the next tap counts, taps, saved,
## lead: how far ahead it shows, window: how long a tap protects}.
func cushion_state() -> Dictionary:
	return {"eta": _eta if _eta <= _warn_lead else -1.0, "ready": _cooldown_left <= 0.0,
		"shield": _cushion_left > 0.0, "wait": _cooldown_left, "taps": tap_count, "saved": saved_hits,
		"lead": _warn_lead, "window": _cushion_window}


## Whether the box is asking for a tap right now (a bump is close and the
## hands are free): the card and the ring on the box read it.
func cushion_due() -> bool:
	return _eta <= _warn_lead and _cooldown_left <= 0.0


func care_action() -> StringName:
	return &""


func get_state() -> int:
	if integrity <= _ruined_at:
		return TrapState.RUINED
	if integrity <= _at_risk_at:
		return TrapState.AT_RISK
	return TrapState.OK


func hint_text() -> Array:
	return LocText.make("HUD_HINT_FRAGILE")
