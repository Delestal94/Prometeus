class_name EmployeeLevels
extends RefCounted
## The wage table of the company's employees (expansion D-0515): pure functions over
## `data/employees/*.tres`, no nodes and no network. Who is hired and when the wage is
## charged are D-1001 and D-1009.

const DIR: String = "res://data/employees"

## Names of the shipped levels, spelled out so the translation table's "no dead rows" scan
## (it reads scripts, not .tres) sees them.
const NAME_KEYS: Dictionary = {
	&"novice": "WORLD_EMPLOYEE_NOVICE",
	&"regular": "WORLD_EMPLOYEE_REGULAR",
	&"expert": "WORLD_EMPLOYEE_EXPERT",
}


## Every valid level of data/employees/, cheapest first (the same order on every peer).
static func levels(dir: String = DIR) -> Array[EmployeeLevel]:
	var found: Array[EmployeeLevel] = []
	var names: PackedStringArray = DirAccess.get_files_at(dir)
	names.sort()
	for file_name: String in names:
		var clean: String = file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var level: EmployeeLevel = load(dir.path_join(clean)) as EmployeeLevel
		if level != null and level.is_valid():
			found.append(level)
	found.sort_custom(func(a: EmployeeLevel, b: EmployeeLevel) -> bool: return a.rank < b.rank)
	return found


static func find(level_id: StringName, dir: String = DIR) -> EmployeeLevel:
	for level: EmployeeLevel in levels(dir):
		if level.id == level_id:
			return level
	return null


## Daily wage of a level; 0 for an unknown one.
static func wage_for(level_id: StringName, dir: String = DIR) -> int:
	var level: EmployeeLevel = find(level_id, dir)
	return level.wage if level != null else 0


static func name_key(level: EmployeeLevel) -> String:
	return String(NAME_KEYS.get(level.id, level.display_key))
