extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_clipboard_perf.gd
##
## The clipboard without hitches (expansion D-1947), measured in the real company world:
## - a refresh with the same products in the same order keeps every row node (the Stock sheet only rewrites the
##   texts and totals; the Supplier sheet keeps its rows for the same cart), so the events that arrive while it is
##   up and turning back to a sheet build nothing; a new product does rebuild;
## - the sheets are built while the world loads (CompanyClipboard._prewarm), so the first raise finds them built;
## - with the world settled, raising it, turning a sheet and turning back each take under ACTION_BUDGET_MS, and no
##   frame while it is up runs more than SPIKE_MS over the world's own slowest frame (measured just before).
## Headless timings are loose (CI machines vary): the budgets are a frame at 60 Hz, well over what it measures
## (raise ~1-2 ms, a turn under 1 ms, D-1947 in docs/tareas-slatex.md).

const DIR: String = "user://test_clipboard_perf"
const ACTION_BUDGET_MS: float = 16.0
const SPIKE_MS: float = 16.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var world := (load("res://scenes/gameplay/company_root.tscn") as PackedScene).instantiate() as CompanyRoot
	world.save_dir = DIR
	root.add_child(world)
	for i: int in 30:
		await process_frame
	var clip := world.get_node_or_null(^"Clipboard") as CompanyClipboard
	_expect(clip != null, "the world has its clipboard")
	if clip != null:
		_test_structure(clip)
		await _test_timing(clip)
	world.queue_free()
	await process_frame
	state.call(&"reset")
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	DirAccess.remove_absolute(DIR)
	if _failures == 0:
		print("PASS: the clipboard raises and turns its sheets without rebuilding or hitching")
	quit(_failures)


func _test_structure(clip: CompanyClipboard) -> void:
	var stock: StockPanel = clip.stock_board.panel
	_expect(stock.row_count() > 0, "the Stock sheet was built while the world loaded (%d rows)" % stock.row_count())
	var first: StringName = stock.products()[0] if stock.row_count() > 0 else &""
	var before: Button = stock.row_button(first)
	clip.stock_board.show_sheet()
	_expect(stock.row_button(first) == before, "showing it again keeps the rows")
	var ctx: Dictionary = stock.get(&"_ctx")
	var inventory: Inventory = ctx.get("inventory")
	stock.refresh(ctx)
	_expect(stock.row_button(first) == before, "a refresh with the same products keeps the rows")
	if inventory != null:
		var copy := Inventory.new()
		copy.from_dict(inventory.to_dict())
		ctx["inventory"] = copy
		stock.refresh(ctx)
		_expect(stock.row_button(first) == before, "a new count of the same products keeps the rows")
	clip.stock_board.hide_sheet()
	var supplier: SupplierOrderPanel = clip.supplier_board.panel
	clip.supplier_board.show_sheet()
	var rows: Array[Node] = supplier.find_children("Row_*", "", true, false)
	clip.supplier_board.show_sheet()
	var again: Array[Node] = supplier.find_children("Row_*", "", true, false)
	_expect(not rows.is_empty() and rows == again, "the Supplier sheet keeps its rows for the same cart")
	clip.supplier_board.hide_sheet()


func _test_timing(clip: CompanyClipboard) -> void:
	var base: float = 0.0
	for i: int in 20:
		var start: int = Time.get_ticks_usec()
		await process_frame
		base = maxf(base, (Time.get_ticks_usec() - start) / 1000.0)
	var worst_action: float = 0.0
	var worst_frame: float = 0.0
	for lap: int in 3:
		var start: int = Time.get_ticks_usec()
		clip.raise(CompanyClipboard.SHEET_STOCK)
		worst_action = maxf(worst_action, (Time.get_ticks_usec() - start) / 1000.0)
		for step: int in [1, -1]:
			await process_frame
			start = Time.get_ticks_usec()
			clip.turn(step)
			worst_action = maxf(worst_action, (Time.get_ticks_usec() - start) / 1000.0)
		for i: int in 10:
			start = Time.get_ticks_usec()
			await process_frame
			worst_frame = maxf(worst_frame, (Time.get_ticks_usec() - start) / 1000.0)
		clip.stow()
		await process_frame
	print("clipboard: worst action %.1f ms, worst frame up %.1f ms, world frame %.1f ms" % [worst_action,
		worst_frame, base])
	_expect(worst_action < ACTION_BUDGET_MS, "raise and turns stay under %.0f ms (%.1f)" % [ACTION_BUDGET_MS,
		worst_action])
	_expect(worst_frame < base + SPIKE_MS, "no frame up spikes past the world's (%.1f vs %.1f)" % [worst_frame, base])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
