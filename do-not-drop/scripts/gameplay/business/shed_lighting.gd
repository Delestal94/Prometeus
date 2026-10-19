class_name ShedLighting
extends RefCounted
## Where the lamps of the shed hang (expansion D-0913, "Modo Empresa").
##
## Pure data over a grid size and a layout (no nodes, no autoload): the same stage and layout give the
## same lamps on every peer, and a test can check there is no dark corner before anything is drawn.
## Two kinds: a ceiling grid that grows with the stage (one lamp per tile of at most
## CompanyTuning.SHED_LAMP_SPACING_M, centered in its tile) and a task lamp over every packing
## table, which follows the table when it is moved. CompanyShed hangs one OmniLight3D per lamp.
## Lamps are in floor cells (fractional, the middle of a tile or a piece), like CompanyShed.cell_to_local.

const KIND_CEILING: StringName = &"ceiling"
const KIND_TASK: StringName = &"task"


## The ceiling grid of a floor of `grid` cells: [{at: Vector2, kind, range_m, energy}].
static func ceiling_lamps(grid: Vector2i) -> Array[Dictionary]:
	var lamps: Array[Dictionary] = []
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	var spacing: float = CompanyTuning.SHED_LAMP_SPACING_M / metres
	var tiles_x: int = maxi(1, ceili(grid.x / spacing))
	var tiles_z: int = maxi(1, ceili(grid.y / spacing))
	for tz: int in tiles_z:
		for tx: int in tiles_x:
			var at := Vector2((tx + 0.5) * grid.x / tiles_x, (tz + 0.5) * grid.y / tiles_z)
			lamps.append({"at": at, "kind": KIND_CEILING, "range_m": CompanyTuning.SHED_LAMP_RANGE_M,
				"energy": CompanyTuning.SHED_LAMP_ENERGY})
	return lamps


## One task lamp over the middle of every packing table of `layout` (CompanyState.layout dicts).
static func task_lamps(layout: Array) -> Array[Dictionary]:
	var lamps: Array[Dictionary] = []
	for piece: Variant in layout:
		if not piece is Dictionary:
			continue
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece.get("id", ""))))
		if def == null or def.role != &"assembly":
			continue
		var size: Vector2i = def.footprint_for(int(piece.get("turns", 0)))
		var at := Vector2(int(piece.get("x", 0)), int(piece.get("z", 0))) + Vector2(size) * 0.5
		lamps.append({"at": at, "kind": KIND_TASK, "range_m": CompanyTuning.SHED_TASK_LAMP_RANGE_M,
			"energy": CompanyTuning.SHED_TASK_LAMP_ENERGY})
	return lamps


static func lamps_for(grid: Vector2i, layout: Array) -> Array[Dictionary]:
	var lamps: Array[Dictionary] = ceiling_lamps(grid)
	lamps.append_array(task_lamps(layout))
	return lamps


## Floor cells whose middle no lamp lights well: farther than CompanyTuning.SHED_LAMP_REACH of a
## lamp's range from every lamp. Empty means no dark corner.
static func dark_cells(grid: Vector2i, lamps: Array[Dictionary]) -> Array[Vector2i]:
	var dark: Array[Vector2i] = []
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	for cz: int in grid.y:
		for cx: int in grid.x:
			var middle := Vector2(cx + 0.5, cz + 0.5)
			var lit: bool = false
			for lamp: Dictionary in lamps:
				var reach: float = float(lamp["range_m"]) * CompanyTuning.SHED_LAMP_REACH
				if (lamp["at"] as Vector2).distance_to(middle) * metres <= reach:
					lit = true
					break
			if not lit:
				dark.append(Vector2i(cx, cz))
	return dark


## The most lamps that reach one floor cell at once (the renderer lights a surface with a limited
## number of omni lights, CompanyTuning.SHED_MAX_LIGHTS_PER_POINT).
static func max_overlap(grid: Vector2i, lamps: Array[Dictionary]) -> int:
	var worst: int = 0
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	for cz: int in grid.y:
		for cx: int in grid.x:
			var middle := Vector2(cx + 0.5, cz + 0.5)
			var count: int = 0
			for lamp: Dictionary in lamps:
				if (lamp["at"] as Vector2).distance_to(middle) * metres < float(lamp["range_m"]):
					count += 1
			worst = maxi(worst, count)
	return worst


## What is wrong with the lamps of a floor and layout, as text; empty when it is fine.
static func problems(grid: Vector2i, layout: Array) -> Array[String]:
	var found: Array[String] = []
	var lamps: Array[Dictionary] = lamps_for(grid, layout)
	var dark: Array[Vector2i] = dark_cells(grid, lamps)
	if not dark.is_empty():
		found.append("%d dark cells, first at %s" % [dark.size(), dark[0]])
	var overlap: int = max_overlap(grid, lamps)
	if overlap > CompanyTuning.SHED_MAX_LIGHTS_PER_POINT:
		found.append("%d lamps reach one cell (max %d)" % [overlap, CompanyTuning.SHED_MAX_LIGHTS_PER_POINT])
	return found
