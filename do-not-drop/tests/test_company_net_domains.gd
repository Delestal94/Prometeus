extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_net_domains.gd
##
## The split of the company mode's two biggest scripts (expansion D-0254; company_net.gd, company_root.gd and what
## came out of them: company_units_net.gd, company_snapshot_sync.gd, company_crew.gd, company_backdrop.gd,
## shed_use.gd), with nothing the peers see changed:
## - the protocol: CompanyNet keeps exactly its four @rpc methods (_request, _apply_event, _snapshot, _rejected; RPC
##   ids go by name) and the kinds it takes, applies, lets the host publish and counts as critical are the same
##   sets as before the split (FROZEN_*, the network contract's whitelist);
## - every kind belongs to one domain: each domain script declares its own REQUEST_KINDS / EVENT_KINDS (and
##   HOST_EVENT_KINDS, CRITICAL_KINDS, a part of those), no kind is in two domains, and CompanyNet's lists are their
##   union with its own (snapshot_request, clock_anchor, day_phase), so a new kind of a domain touches that domain only;
## - CompanyNet routes by domain: _handle_request() and _apply_state() have one branch per domain list (or per own
##   kind) and no catch-all `else:` (read from the source), and every domain with a list has its branch;
## - units_moved is never a host event (units move because someone asked, or left);
## - the old names still answer: CompanyRoot's crew constants and statics (CREW_GROUP, SPAWN, crew_spawn(),
##   free_spawn()) are CompanyCrew's, and CompanyNet.within_reach() / UNITS_DROP are CompanyUnitsNet's;
## - company_net.gd and company_root.gd stay under MAX_LINES (gdlint cuts at 1000), and so does every new piece.

const NET_SCRIPT: String = "res://scripts/core/company/company_net.gd"
const MAX_LINES: int = 850
const SPLIT_FILES: Array[String] = [
	NET_SCRIPT, "res://scripts/gameplay/company_root.gd", "res://scripts/core/company/company_units_net.gd",
	"res://scripts/core/company/company_snapshot_sync.gd", "res://scripts/gameplay/company_crew.gd",
	"res://scripts/gameplay/company_backdrop.gd", "res://scripts/gameplay/shed_use.gd",
]
## The domains CompanyNet puts together (its variables of the same classes).
const DOMAINS: Array[String] = [
	"CompanyUnitsNet", "CompanyLayoutNet", "CompanyTableNet", "CompanyPackages", "CompanyCarts", "CompanyPallets",
	"CompanyTripsView", "CompanyOrdersNet", "CompanySupplierNet", "CompanyWalletNet", "CompanyShopNet",
	"CompanyTowNet", "CompanyColdNet",
]
## Top-level tests of _apply_state() that are no domain's branch: the guard before it and the prune after it.
const NOT_ROUTING: Array[String] = ["inventory == null or not EVENT_KINDS.has(kind)", "applied"]
const RPC_METHODS: Array[String] = ["_request", "_apply_event", "_snapshot", "_rejected"]
## The lists as they were in company_net.gd before D-0254 (main 9204182f), as sets.
const FROZEN_REQUEST: Array[String] = [
	"units_take", "units_store", "units_drop", "snapshot_request", "layout_place", "layout_move", "layout_rotate",
	"layout_sell", "box_start", "box_place", "box_take_out", "box_fill", "box_label", "box_stamp", "box_tape",
	"package_ack", "cart_push", "supplier_order", "jack_pick", "jack_put", "jack_push", "fork_act", "shop_buy",
	"box_restock", "box_discard", "trip_tow", "shed_expand",
]
const FROZEN_CRITICAL: Array[String] = ["units_drop", "package_ack"]
const FROZEN_EVENT: Array[String] = [
	"units_moved", "clock_anchor", "day_phase", "layout_placed", "layout_moved", "layout_sold", "box_started",
	"box_placed", "box_taken_out", "box_filled", "box_labeled", "box_stamped", "box_sealed", "cart_moved",
	"jack_picked", "jack_placed", "jack_moved", "jack_loaded", "fork_state", "jack_departed", "jack_cleared",
	"trip_started", "trip_refused", "trip_closed", "order_added", "order_expired", "order_closed",
	"supplier_ordered", "wallet_moved", "shop_bought", "box_restocked", "box_discarded", "units_spoiled",
	"shed_expanded",
]
const FROZEN_HOST_EVENT: Array[String] = [
	"clock_anchor", "day_phase", "jack_loaded", "jack_departed", "jack_cleared", "fork_state", "trip_started",
	"trip_refused", "trip_closed", "order_added", "order_expired", "order_closed", "supplier_ordered",
	"wallet_moved", "units_spoiled",
]

var _failures: int = 0
var _class_paths: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_class_paths[String(entry["class"])] = String(entry["path"])
	var source: String = FileAccess.get_file_as_string(NET_SCRIPT)
	_check_protocol(source)
	_check_domains()
	_check_routing(source, "_handle_request", "REQUEST_KINDS", ["SNAPSHOT_REQUEST"])
	_check_routing(source, "_apply_state", "EVENT_KINDS", ["CLOCK_ANCHOR", "DAY_PHASE"])
	_check_old_names()
	_check_sizes()
	if _failures == 0:
		print("PASS: CompanyNet and CompanyRoot split by domain, same protocol and kinds, both under %d lines"
			% MAX_LINES)
	quit(_failures)


func _check_protocol(source: String) -> void:
	var rpcs: Array[String] = []
	var lines: PackedStringArray = source.split("\n")
	for index: int in range(lines.size() - 1):
		if lines[index].begins_with("@rpc("):
			rpcs.append(lines[index + 1].trim_prefix("func ").get_slice("(", 0))
	_expect(_sorted(rpcs) == _sorted(RPC_METHODS),
		"CompanyNet keeps exactly its four @rpc methods %s (got %s)" % [RPC_METHODS, rpcs])
	var lists: Dictionary = {
		"REQUEST_KINDS": [CompanyNet.REQUEST_KINDS, FROZEN_REQUEST],
		"CRITICAL_KINDS": [CompanyNet.CRITICAL_KINDS, FROZEN_CRITICAL],
		"EVENT_KINDS": [CompanyNet.EVENT_KINDS, FROZEN_EVENT],
		"HOST_EVENT_KINDS": [CompanyNet.HOST_EVENT_KINDS, FROZEN_HOST_EVENT],
	}
	for list_name: String in lists:
		var now: Array = lists[list_name][0]
		var before: Array = lists[list_name][1]
		var got: Array[String] = _strings(now)
		_expect(_sorted(got) == _sorted(before) and _unique(got),
			"CompanyNet.%s is the same set as before the split, without repeats (got %s)" % [list_name, got])


func _check_domains() -> void:
	var owner_of: Dictionary = {}
	var overlaps: Array[String] = []
	var union: Dictionary = {"REQUEST_KINDS": ["snapshot_request"], "EVENT_KINDS": ["clock_anchor", "day_phase"],
		"HOST_EVENT_KINDS": ["clock_anchor", "day_phase"], "CRITICAL_KINDS": []}
	for domain: String in DOMAINS:
		var consts: Dictionary = _consts_of(domain)
		_expect(not consts.is_empty(), "%s is a class with constants (path %s)" % [domain, _class_paths.get(domain)])
		var requests: Array[String] = _strings(consts.get("REQUEST_KINDS", []))
		var events: Array[String] = _strings(consts.get("EVENT_KINDS", []))
		var host: Array[String] = _strings(consts.get("HOST_EVENT_KINDS", []))
		var critical: Array[String] = _strings(consts.get("CRITICAL_KINDS", []))
		_expect(not (requests.is_empty() and events.is_empty()),
			"%s declares its own REQUEST_KINDS or EVENT_KINDS" % domain)
		_expect(host.all(func(kind: String) -> bool: return events.has(kind)),
			"%s's HOST_EVENT_KINDS %s are among its EVENT_KINDS %s" % [domain, host, events])
		_expect(critical.all(func(kind: String) -> bool: return requests.has(kind)),
			"%s's CRITICAL_KINDS %s are among its REQUEST_KINDS %s" % [domain, critical, requests])
		for kind: String in requests + events:
			if owner_of.has(kind):
				overlaps.append("%s in %s and %s" % [kind, owner_of[kind], domain])
			owner_of[kind] = domain
		union["REQUEST_KINDS"].append_array(requests)
		union["EVENT_KINDS"].append_array(events)
		union["HOST_EVENT_KINDS"].append_array(host)
		union["CRITICAL_KINDS"].append_array(critical)
	_expect(overlaps.is_empty(), "Every kind belongs to one domain only (overlaps %s)" % [overlaps])
	var net_lists: Dictionary = {
		"REQUEST_KINDS": CompanyNet.REQUEST_KINDS, "EVENT_KINDS": CompanyNet.EVENT_KINDS,
		"HOST_EVENT_KINDS": CompanyNet.HOST_EVENT_KINDS, "CRITICAL_KINDS": CompanyNet.CRITICAL_KINDS,
	}
	for list_name: String in net_lists:
		var joined: Array[String] = []
		joined.assign(union[list_name])
		_expect(_sorted(_strings(net_lists[list_name])) == _sorted(joined),
			"CompanyNet.%s is CompanyNet's own kinds plus each domain's, nothing else (got %s, domains give %s)"
			% [list_name, net_lists[list_name], joined])
	_expect(not CompanyNet.HOST_EVENT_KINDS.has(CompanyUnitsNet.MOVED),
		"units_moved is never a host event (HOST_EVENT_KINDS %s)" % [CompanyNet.HOST_EVENT_KINDS])


## `func_name`'s body in CompanyNet: one branch per domain whose `list` (REQUEST_KINDS or EVENT_KINDS) is not empty,
## `if <Domain>.<list>.has(kind):` / `elif ...`, or `kind == <own constant>` for each of `own`; no `else:`.
func _check_routing(source: String, func_name: String, list: String, own: Array) -> void:
	var start: int = source.find("\nfunc %s(" % func_name)
	var end: int = source.find("\nfunc ", start + 1)
	_expect(start >= 0 and end > start, "%s() is in %s" % [func_name, NET_SCRIPT])
	if start < 0 or end <= start:
		return
	var branches: Array[String] = []
	var catch_all: bool = false
	for line: String in source.substr(start, end - start).split("\n"):
		if not (line.begins_with("\t") and not line.begins_with("\t\t")):
			continue
		var test: String = line.strip_edges()
		catch_all = catch_all or test == "else:" or test.begins_with("match ")
		if (test.begins_with("if ") or test.begins_with("elif ")) and test.ends_with(":"):
			branches.append(test.trim_prefix("el").trim_prefix("if ").trim_suffix(":"))
	var expected: Array[String] = []
	for domain: String in DOMAINS:
		if not _strings(_consts_of(domain).get(list, [])).is_empty():
			expected.append("%s.%s.has(kind)" % [domain, list])
	for name_: String in own:
		expected.append("kind == %s" % name_)
	var missing: Array[String] = []
	for branch: String in expected:
		if not branches.has(branch):
			missing.append(branch)
	var extra: Array[String] = []
	for branch: String in branches:
		if not expected.has(branch) and not NOT_ROUTING.has(branch):
			extra.append(branch)
	_expect(missing.is_empty() and extra.is_empty() and not catch_all,
		"%s() has one branch per domain's %s and per own kind, no catch-all (missing %s, extra %s, catch-all %s)"
		% [func_name, list, missing, extra, catch_all])


func _check_old_names() -> void:
	_expect(CompanyRoot.CREW_GROUP == CompanyCrew.GROUP and CompanyRoot.SPAWN == CompanyCrew.SPAWN
		and CompanyRoot.CREW_SPACING == CompanyCrew.SPACING and CompanyRoot.SPAWN_CLEARANCE == CompanyCrew.CLEARANCE
		and CompanyRoot.PLAYER_PREFIX == CompanyCrew.PLAYER_PREFIX
		and CompanyRoot.PLAYER_SCENE == CompanyCrew.PLAYER_SCENE,
		"CompanyRoot's crew constants are CompanyCrew's (group %s, spawn %s)"
		% [CompanyRoot.CREW_GROUP, CompanyRoot.SPAWN])
	var spots: Array[Vector3] = []
	for slot: int in range(4):
		spots.append(CompanyRoot.crew_spawn(slot))
	var expected: Array[Vector3] = [CompanyCrew.SPAWN, CompanyCrew.SPAWN + Vector3(0.8, 0.0, 0.0),
		CompanyCrew.SPAWN - Vector3(0.8, 0.0, 0.0), CompanyCrew.SPAWN + Vector3(1.6, 0.0, 0.0)]
	_expect(spots == expected,
		"CompanyRoot.crew_spawn() still gives SPAWN and then 0.8 m to either side in turn (got %s)" % [spots])
	_expect(CompanyRoot.free_spawn([CompanyCrew.SPAWN]) == CompanyCrew.spawn_spot(1),
		"CompanyRoot.free_spawn() skips a taken spot (got %s)" % CompanyRoot.free_spawn([CompanyCrew.SPAWN]))
	_expect(CompanyNet.UNITS_DROP == CompanyUnitsNet.DROP
		and CompanyNet.within_reach(Vector3.ZERO, Vector3(Interactable.REMOTE_REACH, 0.0, 0.0))
		and not CompanyNet.within_reach(Vector3.ZERO, Vector3(Interactable.REMOTE_REACH + 0.5, 0.0, 0.0)),
		"CompanyNet.UNITS_DROP and within_reach() answer as before, through CompanyUnitsNet")


func _check_sizes() -> void:
	for path: String in SPLIT_FILES:
		var text: String = FileAccess.get_file_as_string(path)
		var lines: int = text.split("\n").size() - (1 if text.ends_with("\n") else 0)
		_expect(not text.is_empty() and lines < MAX_LINES, "%s has under %d lines (got %d)" % [path, MAX_LINES, lines])


func _consts_of(class_title: String) -> Dictionary:
	if not _class_paths.has(class_title):
		return {}
	var script: Script = load(_class_paths[class_title]) as Script
	return script.get_script_constant_map() if script != null else {}


static func _strings(kinds: Variant) -> Array[String]:
	var out: Array[String] = []
	if kinds is Array:
		for kind: Variant in kinds:
			out.append(String(kind))
	return out


static func _sorted(values: Array) -> Array:
	var copy: Array = []
	copy.append_array(values)
	copy.sort()
	return copy


static func _unique(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value: String in values:
		if seen.has(value):
			return false
		seen[value] = true
	return true


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
