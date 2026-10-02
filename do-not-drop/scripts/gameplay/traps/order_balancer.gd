class_name OrderBalancer
extends RefCounted
## Pure, deterministic order selection. The caller owns the RNG so the same
## session seed and inputs produce the same house order on every peer.


## The fallback's rules: runs past the hard-pair limit and no budget at all.
const RELAXED_RUNS: int = 10
const RELAXED_BUDGET: int = 1 << 30


static func build_order(available_traps: Array, house_count: int, completed_runs: int,
		rng: RandomNumberGenerator) -> Array[StringName]:
	var traps := _unique_traps(available_traps)
	var target := maxi(house_count, 0)
	if target == 0:
		return []
	if traps.is_empty() or rng == null:
		return []
	var budget := 4 + target + mini(maxi(completed_runs, 0), 6)
	var result: Array[StringName] = []
	if _fill_order(traps, target, maxi(completed_runs, 0), budget, rng, result, 0, 0):
		return result
	# A big crew (5-7 houses) can't fit the curve: the budget is spent and the
	# cycle rule forces both hard traps in. An order for every house matters
	# more than the curve, so it's drawn again with only the cycle rule and
	# the easy box kept. Every order the curve can fit is left as it was.
	result.clear()
	if _fill_order(traps, target, RELAXED_RUNS, RELAXED_BUDGET, rng, result, 0, 0):
		return result
	return []


## Maps the balanced trap ids back to distinct physical boxes without
## mutating the caller's stock. Keeping this here leaves Depot.post_orders()
## as the tiny integration seam promised by S-107.
static func packages_for_order(packages: Array, trap_ids: Array[StringName]) -> Array:
	var remaining := packages.duplicate()
	var selected: Array = []
	for trap_id: StringName in trap_ids:
		for package: Variant in remaining:
			var box := package as DeliveryPackage
			var definition: TrapDefinition = box.trap_definition if box != null else null
			if definition != null and definition.id == trap_id:
				selected.append(package)
				remaining.erase(package)
				break
	return selected


static func _unique_traps(available_traps: Array) -> Array[TrapDefinition]:
	var by_id: Dictionary = {}
	for entry: Variant in available_traps:
		var trap := entry as TrapDefinition
		if trap == null:
			continue
		var trap_id := trap.id
		if trap_id != &"" and not by_id.has(trap_id):
			by_id[trap_id] = trap
	var ids: Array = by_id.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var result: Array[TrapDefinition] = []
	for trap_id: StringName in ids:
		result.append(by_id[trap_id])
	return result


static func _fill_order(traps: Array[TrapDefinition], target: int, completed_runs: int, budget: int,
		rng: RandomNumberGenerator, result: Array[StringName], total: int,
		hard_count: int) -> bool:
	if result.size() == target:
		return total <= budget and _has_easy(traps, result)

	# A trap may repeat only after every available distinct id had its turn.
	# Starting a new cycle resets that set while preserving the picked order.
	var cycle_start := result.size() - result.size() % traps.size()
	var used_this_cycle: Dictionary = {}
	for index: int in range(cycle_start, result.size()):
		used_this_cycle[result[index]] = true

	var candidates: Array[TrapDefinition] = []
	for trap: TrapDefinition in traps:
		if not used_this_cycle.has(trap.id):
			candidates.append(trap)
	_shuffle(candidates, rng)
	for trap: TrapDefinition in candidates:
		var difficulty := trap.difficulty
		var next_total := total + difficulty
		var next_hard_count := hard_count + (1 if difficulty == 4 else 0)
		if next_total > budget or (completed_runs < 10 and next_hard_count > 1):
			continue
		result.append(trap.id)
		if _fill_order(traps, target, completed_runs, budget, rng, result, next_total, next_hard_count):
			return true
		result.pop_back()
	return false


static func _has_easy(traps: Array[TrapDefinition], result: Array[StringName]) -> bool:
	for trap: TrapDefinition in traps:
		if trap.difficulty <= 2 and result.has(trap.id):
			return true
	return false


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap: Variant = values[index]
		values[index] = values[other]
		values[other] = swap
