extends RefCounted
## Host-owned recovery and handling simulation. Trap danger remains separate
## from permanent delivery quality; calming a hen never erases an accident.
##
## Tools (docs/jugabilidad-paquetes-rescate.md, "Kit y reparación común"):
##   tape        closes the box and softens the next hits
##   repair      puts the contents back together -- glue for a vase, restack
##               for a cake, defuse for a bomb, a mended cage for a creature
##   filler      pads the contents: fewer hits reach them, no quality back
##   rag         contains a leak: the only rescue a liquid has
##   strap       ties the box down so it holds itself while hands work
##   substitute  a toy hen for a hen that got away

const TOOLS: Array[StringName] = [&"tape", &"repair", &"filler", &"rag", &"strap", &"substitute"]
## Tool -> strings_ui.csv key; tool_name() translates it.
const TOOL_NAMES: Dictionary = {&"tape": "HUD_CARE_TOOL_TAPE", &"repair": "HUD_CARE_TOOL_REPAIR",
	&"filler": "HUD_CARE_TOOL_FILLER", &"rag": "HUD_CARE_TOOL_RAG", &"strap": "HUD_CARE_TOOL_STRAP",
	&"substitute": "HUD_CARE_TOOL_SUBSTITUTE"}
## What "repair" is called for each content, so the HUD names the actual job
## (strings_ui.csv keys, like TOOL_NAMES).
const REPAIR_NAMES: Dictionary = {&"fragile": "HUD_CARE_REPAIR_FRAGILE", &"balance": "HUD_CARE_REPAIR_BALANCE",
	&"noisy": "HUD_CARE_REPAIR_NOISY", &"hostile": "HUD_CARE_REPAIR_HOSTILE",
	&"explosive": "HUD_CARE_REPAIR_EXPLOSIVE", &"growing_weight": "HUD_CARE_REPAIR_GROWING_WEIGHT"}
## Best a rescued box can be worth again, per content: a glued vase is never
## intact, a mopped-up liquid is only partial, a late-neutralized bomb is scrap.
const RESCUE_CAPS: Dictionary = {&"fragile": 85.0, &"balance": 80.0, &"noisy": 75.0,
	&"hostile": 75.0, &"growing_weight": 80.0, &"liquid": 60.0, &"explosive": 35.0}
## Seconds of work each tool takes, holding the tool button; repair is the
## long one.
const TOOL_SECONDS: Dictionary = {&"tape": 3.0, &"repair": 5.0, &"filler": 3.0, &"rag": 4.0,
	&"strap": 2.5, &"substitute": 5.0}
const DIRECTIONS: Array[Vector2] = [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN]
## A rescue window: long enough to stabilise, short enough to matter.
const CRISIS_SECONDS: float = 15.0
## An impact at least this hard (m/s) can loosen the strap and tear tape.
const LOOSENING_HIT: float = 7.0
## Hands on the box (the primary action held): how much of each hit they
## soak up. One hold, no aiming (playtest 2026-09-28: the old "WASD onto the
## green dot" balance on top of every trap's own action was one control too
## many to learn on the road).
const HOLD_PROTECTION: float = 0.9
var phase: StringName = &"intact"
var quality_cap: float = 100.0
var worst_quality: float = 100.0
var tape: int = 0
var repairs: int = 0
var substituted: bool = false
var needs_restore: bool = false
var missing_parts: int = 0
var crisis_left: float = 0.0
var padded: bool = false
var strapped: bool = false
## On a seated passenger's lap rather than its rack.
var in_lap: bool = false
var balance_target := Vector2.ZERO
var balance_cursor := Vector2.ZERO
var balance_error: float = 0.0
var protection: float = 0.0
var strain: float = 0.0
var work: float = 0.0
var work_tool: StringName = &""
var work_step: int = 0
## A LocText line ([key, args...]): the host builds it, each peer translates it.
var message: Array = []
var recent_hit: float = 0.0
var elapsed: float = 0.0


func observe(quality: float, failed: bool, kind: StringName) -> bool:
	worst_quality = minf(worst_quality, quality)
	if failed and not needs_restore and phase != &"lost" and not substituted:
		begin_crisis(kind)
		return true
	if quality < 85.0 and phase == &"intact":
		phase = &"damaged"
	return false


func begin_crisis(kind: StringName, spilled: bool = false) -> void:
	if needs_restore or phase == &"lost":
		return
	phase = &"crisis"
	needs_restore = true
	crisis_left = CRISIS_SECONDS
	quality_cap = minf(quality_cap, 80.0)
	worst_quality = minf(worst_quality, 20.0)
	# What ends up out of the box: a creature is one thing to catch, a vase
	# or cake is pieces; a leak, a bomb or a heavy box has nothing to pick up.
	missing_parts = 0
	if kind in [&"noisy", &"hostile"]:
		missing_parts = 1
	elif kind in [&"fragile", &"balance"] or (spilled and kind not in [&"liquid", &"explosive", &"growing_weight"]):
		missing_parts = 3
	if kind == &"explosive":
		quality_cap = minf(quality_cap, RESCUE_CAPS[&"explosive"])
	message = crisis_prompt(kind)


func crisis_prompt(kind: StringName) -> Array:
	match kind:
		&"liquid":
			return LocText.make("HUD_CARE_CRISIS_LIQUID")
		&"explosive":
			return LocText.make("HUD_CARE_CRISIS_EXPLOSIVE")
		&"growing_weight":
			return LocText.make("HUD_CARE_CRISIS_GROWING_WEIGHT")
		&"noisy", &"hostile":
			return LocText.make("HUD_CARE_CRISIS_ESCAPED")
	return LocText.make("HUD_CARE_CRISIS_RESCUE")


## A player dropped out mid-rescue: their box is held for a while instead of
## running out while nobody can reach it (never an instant loss).
func hold_crisis(seconds: float) -> void:
	if phase == &"crisis":
		crisis_left = maxf(crisis_left, seconds)


func advance(delta: float, acceleration: Vector3, input: Dictionary, assisted: bool = false) -> bool:
	elapsed += delta
	var force := Vector2(-acceleration.x, -acceleration.z) / 8.0
	# The sway the truck puts on the box: still drawn (the carried box leans
	# with it), no longer something to aim at.
	balance_target = balance_target.lerp(force.limit_length(1.0), minf(1.0, delta * 7.0))
	var holding: bool = bool(input.get("steady", false)) and not bool(input.get("work", false))
	balance_cursor = balance_target if holding else balance_cursor.move_toward(Vector2.ZERO, delta * 3.0)
	balance_error = 0.0 if holding else balance_cursor.distance_to(balance_target)
	protection = HOLD_PROTECTION if holding else 0.0
	if assisted:
		protection = maxf(protection, 0.65)
	if in_lap:
		# Cushioned by a body that reacts: better than a bare rack.
		protection = maxf(protection, 0.4)
	if strapped:
		# Tied down, it holds itself -- not as well as a steady pair of hands.
		protection = maxf(protection, 0.5)
	var force_strength: float = maxf(force.length(), absf(acceleration.y) / 12.0)
	if force_strength > 0.35 and protection < 0.65 and phase != &"lost":
		strain += delta * minf(force_strength, 2.0) * (1.0 - protection)
	else:
		strain = maxf(0.0, strain - delta * 1.5)
	if phase == &"crisis":
		crisis_left = maxf(0.0, crisis_left - delta)
		if is_zero_approx(crisis_left):
			phase = &"lost"
			message = LocText.make("HUD_CARE_MSG_LOST")
	if strain >= 1.8 and recent_hit <= 0.0:
		strain = 0.0
		return true
	return false


func impact_scale() -> float:
	return (1.0 - protection * 0.8) * (0.65 if tape > 0 else 1.0) * (0.75 if padded else 1.0)


## A hard hit wears the fixes: one layer of tape tears, the strap slips.
func on_hard_hit(strength: float) -> void:
	if strength < LOOSENING_HIT:
		return
	if tape > 0:
		tape -= 1
	if strapped:
		strapped = false
		message = LocText.make("HUD_CARE_MSG_STRAP_LOOSE")


func collect_part() -> bool:
	if missing_parts <= 0 or phase == &"lost":
		return false
	missing_parts -= 1
	crisis_left = maxf(crisis_left, 8.0)
	if missing_parts == 0:
		message = LocText.make("HUD_CARE_MSG_RECOVERED")
	else:
		message = LocText.make("HUD_CARE_MSG_PIECES_LEFT", [missing_parts])
	return true


func tool_name(tool: StringName, kind: StringName) -> String:
	return tr(tool_name_key(tool, kind))


func tool_name_key(tool: StringName, kind: StringName) -> String:
	if tool == &"repair":
		return String(REPAIR_NAMES.get(kind, TOOL_NAMES[&"repair"]))
	return String(TOOL_NAMES.get(tool, tool))


## Why this tool can't be used right now (a LocText line), or [] if it can.
## `helped` is a second player steadying the same box this moment.
func tool_blocker(tool: StringName, kind: StringName, speed: float, helped: bool = false) -> Array:
	if in_lap and tool in [&"repair", &"filler", &"rag", &"strap"]:
		return LocText.make("HUD_CARE_BLOCK_LAP")
	var blocker: Array = []
	match tool:
		&"tape":
			blocker = LocText.make("HUD_CARE_BLOCK_ALREADY_TAPED") if tape >= 2 and phase != &"crisis" else []
		&"filler":
			if padded:
				blocker = LocText.make("HUD_CARE_BLOCK_ALREADY_PADDED")
			elif phase in [&"crisis", &"lost"]:
				blocker = LocText.make("HUD_CARE_BLOCK_RESCUE_FIRST")
		&"strap":
			blocker = LocText.make("HUD_CARE_BLOCK_ALREADY_STRAPPED") if strapped else []
		&"rag":
			if kind != &"liquid":
				blocker = LocText.make("HUD_CARE_BLOCK_NOTHING_TO_ABSORB")
			elif phase != &"crisis":
				blocker = LocText.make("HUD_CARE_BLOCK_NO_LEAK")
		&"substitute":
			if kind != &"noisy" or phase != &"lost" or substituted:
				blocker = LocText.make("HUD_CARE_BLOCK_TOY_ONLY_HEN")
		&"repair":
			blocker = _repair_blocker(kind, speed, helped)
		_:
			blocker = LocText.make("HUD_CARE_BLOCK_UNKNOWN_TOOL")
	return blocker


func _repair_blocker(kind: StringName, speed: float, helped: bool) -> Array:
	if phase == &"lost":
		return LocText.make("HUD_CARE_BLOCK_UNRECOVERABLE")
	if kind == &"liquid":
		return LocText.make("HUD_CARE_BLOCK_LIQUID" if phase == &"crisis" else "HUD_CARE_BLOCK_NO_REPAIR_NEEDED")
	if missing_parts > 0:
		return LocText.make("HUD_CARE_BLOCK_PIECES_FIRST", [missing_parts])
	if repairs >= 2:
		return LocText.make("HUD_CARE_BLOCK_MAX_REPAIRS")
	if phase == &"intact" or not needs_restore and phase != &"damaged":
		return LocText.make("HUD_CARE_BLOCK_NO_REPAIR_NEEDED")
	if kind == &"growing_weight" and not helped:
		return LocText.make("HUD_CARE_BLOCK_TOO_HEAVY")
	if speed > 9.0:
		return LocText.make("HUD_CARE_BLOCK_TOO_FAST")
	return []


func work_direction() -> Vector2:
	return DIRECTIONS[work_step % DIRECTIONS.size()]


## The tool that helps this box right now, or &"" when none does: what the
## care panel picks for the player instead of making them cycle through six.
## `supplies` maps tool -> units left in the crew's kit.
func suggested_tool(kind: StringName, supplies: Dictionary = {}) -> StringName:
	var order: Array[StringName] = []
	match phase:
		&"crisis":
			if kind == &"liquid":
				order = [&"rag"]
			elif missing_parts > 0:
				order = [&"tape"]
			else:
				order = [&"repair", &"tape"]
		&"lost":
			order = [&"substitute"]
		&"intact":
			# A sound box needs hands, not the crew's kit.
			order = []
		_:
			order = [&"repair", &"tape", &"filler", &"strap"]
	for tool: StringName in order:
		if int(supplies.get(tool, 1)) > 0 and tool_blocker(tool, kind, 0.0, true).is_empty():
			return tool
	return &""


## Progress is earned by holding the tool button, with partial progress
## retained on release. Supplies are spent atomically by the package on completion.
func advance_work(delta: float, tool: StringName, input: Dictionary, kind: StringName, speed: float,
		available: bool, helped: bool = false) -> bool:
	if not bool(input.get("work", false)):
		return false
	message = tool_blocker(tool, kind, speed, helped)
	if not message.is_empty():
		return false
	if not available:
		message = LocText.make("HUD_CARE_MSG_NO_SUPPLIES")
		return false
	if work_tool != tool:
		work_tool = tool
		work = 0.0
		work_step = 0
	if recent_hit > 0.3:
		message = LocText.make("HUD_CARE_MSG_MOVING")
		return false
	work = minf(1.0, work + delta / float(TOOL_SECONDS.get(tool, 5.0)))
	work_step = mini(3, int(work * 4.0))
	message = LocText.make("%s · %d%%", [[tool_name_key(tool, kind)], roundi(work * 100.0)])
	return work >= 1.0


func complete_tool(tool: StringName, kind: StringName = &"") -> void:
	match tool:
		&"tape":
			tape = mini(2, tape + 1)
			if phase == &"crisis" and kind != &"liquid":
				phase = &"damaged"
			if needs_restore:
				message = LocText.make("HUD_CARE_MSG_TAPED_PENDING")
			else:
				message = LocText.make("HUD_CARE_MSG_TAPED")
		&"repair":
			repairs += 1
			quality_cap = minf(quality_cap, float(RESCUE_CAPS.get(kind, 85.0)) - 10.0 * (repairs - 1))
			phase = &"rescued"
			needs_restore = false
			message = LocText.make("HUD_CARE_MSG_REPAIRED")
		&"filler":
			padded = true
			message = LocText.make("HUD_CARE_MSG_PADDED")
		&"strap":
			strapped = true
			message = LocText.make("HUD_CARE_MSG_STRAPPED")
		&"rag":
			# A leak stopped is saved, but what already ran out is gone.
			repairs += 1
			quality_cap = minf(quality_cap, RESCUE_CAPS[&"liquid"])
			phase = &"rescued"
			needs_restore = false
			message = LocText.make("HUD_CARE_MSG_LEAK_CONTAINED")
		&"substitute":
			substituted = true
			needs_restore = false
			missing_parts = 0
			quality_cap = 20.0
			phase = &"rescued"
			message = LocText.make("HUD_CARE_MSG_TOY_HEN")
	work = 0.0
	work_step = 0
	work_tool = &""


func snapshot() -> Dictionary:
	return {"phase": phase, "cap": quality_cap, "worst": worst_quality, "tape": tape,
		"repairs": repairs, "substituted": substituted, "restore": needs_restore,
		"missing": missing_parts, "seconds": crisis_left, "target": balance_target,
		"cursor": balance_cursor, "error": balance_error, "protection": protection,
		"work": work, "tool": work_tool, "step": work_step, "message": message,
		"padded": padded, "strapped": strapped, "lap": in_lap}


func apply_snapshot(data: Dictionary) -> void:
	phase = StringName(data.get("phase", "intact"))
	quality_cap = float(data.get("cap", 100.0))
	worst_quality = float(data.get("worst", 100.0))
	tape = int(data.get("tape", 0))
	repairs = int(data.get("repairs", 0))
	substituted = bool(data.get("substituted", false))
	needs_restore = bool(data.get("restore", false))
	missing_parts = int(data.get("missing", 0))
	crisis_left = float(data.get("seconds", 0.0))
	balance_target = data.get("target", Vector2.ZERO)
	balance_cursor = data.get("cursor", Vector2.ZERO)
	balance_error = float(data.get("error", 0.0))
	protection = float(data.get("protection", 0.0))
	work = float(data.get("work", 0.0))
	work_tool = StringName(data.get("tool", ""))
	work_step = int(data.get("step", 0))
	var line: Variant = data.get("message", [])
	message = line if line is Array else []
	padded = bool(data.get("padded", false))
	strapped = bool(data.get("strapped", false))
	in_lap = bool(data.get("lap", false))
