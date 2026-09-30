class_name VehicleGearbox
extends Node
## The old van's manual gearbox (tareas de Nacho N-114): five forward gears the
## driver changes up and down by hand. Only trucks whose variant says so
## (vehicle.gd VARIANTS, "manual") use it; for the rest `enabled` is false and
## the truck drives exactly as before.
##
## What changes at the wheel:
##   - each gear pulls up to its own top speed (CAP_FRACTIONS of the truck's
##     top speed) and stops pulling there (rev limiter), so the driver has to
##     go up a gear to keep accelerating;
##   - low gears pull harder (TORQUE), high gears pull softly;
##   - a high gear at a crawl lugs: it pulls with LUG_FLOOR of its strength
##     until the truck is fast enough for it (forgiving: it never stalls);
##   - changing gear takes SHIFT_SECONDS with the clutch in: no pull;
##   - dropping into a gear the truck is too fast for brakes it with the
##     engine until it is back under the gear's limit.
## Reverse is not a gear: braking from a standstill still backs up.
##
## The host decides: `gear` is replicated (vehicle.tscn, "Gearbox:gear") and
## only the host's copy moves it, from the driver's shift request
## (Vehicle.request_gear_shift). Every peer reads `gear` to show and to sound.

signal gear_changed(gear: int)

## What the crew's delivery payout is multiplied by when the van has this
## box: the compensation for driving it by hand (vehicle.gd VARIANTS,
## unlock_manager.gd TRUCKS).
const PAY_MULTIPLIER: float = 1.25
const FIRST_GEAR: int = 1
const TOP_GEAR: int = 5
## Top speed of each gear as a fraction of the truck's maximum_speed_kmh.
const CAP_FRACTIONS: Array[float] = [0.3, 0.5, 0.7, 0.88, 1.0]
## Pulling power of each gear, times the truck's maximum_engine_force.
const TORQUE: Array[float] = [1.4, 1.2, 1.0, 0.85, 0.72]
## A gear runs at full strength from half of the speed the gear below tops out
## at; under that it lugs, down to this fraction of its strength.
const LUG_FLOOR: float = 0.3
const LUG_ABOVE_LOWER_CAP: float = 0.5
const SHIFT_SECONDS: float = 0.3
## Engine braking (same unit as VehicleBody3D.brake): per km/h over the gear's
## limit, never under the floor nor over the ceiling.
const ENGINE_BRAKE_PER_KMH: float = 0.9
const ENGINE_BRAKE_FLOOR: float = 1.0
const ENGINE_BRAKE_CEILING: float = 14.0

## Set by the truck from its variant, on every peer.
var enabled: bool = false
## 1..TOP_GEAR. Replicated from the host.
var gear: int = FIRST_GEAR:
	set(value):
		var clamped: int = clampi(value, FIRST_GEAR, TOP_GEAR)
		if clamped == gear:
			return
		gear = clamped
		gear_changed.emit(gear)
## Seconds left of the clutch being in after a shift (host only).
var shift_left: float = 0.0
## The one shift (+1 / -1) waiting for the clutch to come out, 0 for none.
var _queued: int = 0


## Host only: the driver asks for one gear up (+1) or down (-1). False when it
## doesn't apply (automatic truck, already at the end). A request that arrives
## with the clutch still in (two quick presses, or the packets bunched up by
## jitter: the clutch is timed when the request reaches the host) isn't lost:
## it waits in a one-place queue and is applied the moment the clutch is out.
## A newer request replaces the one waiting.
func request_shift(direction: int) -> bool:
	if not enabled or direction == 0:
		return false
	if shift_left > 0.0:
		_queued = signi(direction)
		return true
	return _shift(signi(direction))


## Host only, each physics tick.
func tick(delta: float) -> void:
	shift_left = maxf(shift_left - delta, 0.0)
	if shift_left <= 0.0 and _queued != 0:
		var waiting: int = _queued
		_queued = 0
		_shift(waiting)


func _shift(direction: int) -> bool:
	var target: int = gear + direction
	if target < FIRST_GEAR or target > TOP_GEAR:
		return false
	gear = target
	shift_left = SHIFT_SECONDS
	return true


## Back to first with the clutch out: the start of a delivery, or the variant
## changing.
func reset() -> void:
	gear = FIRST_GEAR
	shift_left = 0.0
	_queued = 0


## The fastest this gear goes, in km/h, for a truck with this top speed.
static func gear_cap_kmh(for_gear: int, top_speed_kmh: float) -> float:
	return top_speed_kmh * CAP_FRACTIONS[clampi(for_gear, FIRST_GEAR, TOP_GEAR) - 1]


## The gear whose range holds this speed: what a driver would be in. Used by
## tests and by anything that wants to hint "shift up".
static func gear_for_speed(speed_kmh: float, top_speed_kmh: float) -> int:
	for candidate: int in range(FIRST_GEAR, TOP_GEAR + 1):
		if speed_kmh < gear_cap_kmh(candidate, top_speed_kmh):
			return candidate
	return TOP_GEAR


## Multiplier on the truck's engine force at this forward speed (km/h, only
## positive going forward). 1.0 when the box is automatic.
func drive_multiplier(forward_kmh: float, top_speed_kmh: float) -> float:
	if not enabled:
		return 1.0
	if shift_left > 0.0 or forward_kmh >= gear_cap_kmh(gear, top_speed_kmh):
		return 0.0
	var lug_from: float = 0.0
	if gear > FIRST_GEAR:
		lug_from = gear_cap_kmh(gear - 1, top_speed_kmh) * LUG_ABOVE_LOWER_CAP
	var lug: float = 1.0
	if lug_from > 0.0:
		lug = lerpf(LUG_FLOOR, 1.0, clampf(maxf(forward_kmh, 0.0) / lug_from, 0.0, 1.0))
	return TORQUE[gear - 1] * lug


## Extra brake from the engine when the truck is over the gear's limit (a
## downshift taken too fast); 0 otherwise.
func engine_brake(forward_kmh: float, top_speed_kmh: float) -> float:
	if not enabled:
		return 0.0
	var over: float = forward_kmh - gear_cap_kmh(gear, top_speed_kmh)
	if over <= 0.0:
		return 0.0
	return clampf(over * ENGINE_BRAKE_PER_KMH, ENGINE_BRAKE_FLOOR, ENGINE_BRAKE_CEILING)


## Whether the truck is at the top of its gear with the pedal down: the HUD
## tells the driver to shift up.
func at_limit(forward_kmh: float, top_speed_kmh: float) -> bool:
	return enabled and gear < TOP_GEAR and forward_kmh >= gear_cap_kmh(gear, top_speed_kmh) * 0.96
