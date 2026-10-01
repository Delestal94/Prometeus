extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_rpc_guard.gd
##
## Covers N-221's defensive networking across the whole project (RpcGuard
## itself, its value checks and budget: modules/net_session/tests/test_rpc_guard.gd):
## - reads every `@rpc("any_peer"...)` function under res:// (portable modules
##   included; addons and tests aside) and fails when its body never checks
##   who sent it (get_remote_sender_id() or an RpcGuard sender check, directly
##   or in a helper it calls: same file, the class it extends, or a
##   ClassName.function());
## - a reliable any_peer RPC either comes from the host (RpcGuard.from_host)
##   or spends the sender's request budget (RpcGuard.allow_request, or
##   allow_critical_request with its reserve); letting go of a box or a seat
##   is critical (CRITICAL_RPCS), and BUDGET_EXEMPT says why one spends none;
## - float/vector/transform parameters are checked for NaN/inf, Dictionary
##   ones with RpcGuard.dict_ok(), String ones with RpcGuard.text_ok(),
##   StringName ones with RpcGuard.name_ok() and NodePath ones with
##   RpcGuard.path_ok() (unless the host sent them), arrays by size;
## - RPCs that rely on arriving in order share a reliable channel
##   (ORDERED_PAIRS: the colour slots before the campaign applied by slot);
## - EventBus only relays the requests a player can make (a callout, the
##   horn), each with its own shape: request() is itself an any_peer RPC.
## A function that can't follow a rule goes in EXCEPTIONS with the reason.

## "res://path.gd:function" -> why it can't follow the rules. Empty on purpose:
## every any_peer RPC in the project passes today.
const EXCEPTIONS: Dictionary = {}
## "res://path.gd:function" -> why a reliable request spends no budget at all
## (every other rule still applies).
const BUDGET_EXEMPT: Dictionary = {
	"res://modules/net_session/net_session.gd:_report_level_ready":
		"A lost one leaves the client's level without players; only a report the host owes does anything",
}
## Requests whose loss leaves host and peer disagreeing for good: they keep a
## reserve once the sender's budget is spent (RpcGuard.allow_critical_request).
const CRITICAL_RPCS: Array[String] = [
	"res://scripts/gameplay/package/package.gd:request_drop",
	"res://modules/interaction/seat_point.gd:release_occupant",
]
## Tokens that show a reliable request spends the sender's budget.
const BUDGET_CHECKS: Array[String] = ["RpcGuard.allow_request(", "RpcGuard.allow_critical_request("]
## Tokens that show a function looked at its sender.
const SENDER_CHECKS: Array[String] = ["get_remote_sender_id()", "RpcGuard.sender_ok(", "RpcGuard.sender(",
	"RpcGuard.from_host(", "RpcGuard.allow_request(", "RpcGuard.allow_critical_request("]
## Tokens that show a float or vector was checked for NaN/inf.
const FINITE_CHECKS: Array[String] = ["RpcGuard.finite", "is_finite(", "is_nan("]
## The project had 36 any_peer RPCs when this test was last updated: far
## fewer found means the scanner broke, not that they went away.
const MIN_RPCS: int = 34
const SKIPPED_DIRS: Array[String] = ["addons", "tests", ".godot"]
## RPCs the host sends one after the other that must arrive in that order:
## reliable, on the same channel. [path, function] each.
const ORDERED_PAIRS: Array = [
	[["res://scripts/core/network_manager.gd", "_sync_color_slots"],
		["res://scripts/core/crew_progression.gd", "_receive_campaign"]],
]

var _failures: int = 0
var _class_paths: Dictionary = {}  # class_name -> res:// path
var _function_cache: Dictionary = {}  # path -> {name: body}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scripts: Array[String] = []
	_collect_scripts("res://", scripts)
	for path: String in scripts:
		var match_: RegExMatch = RegEx.create_from_string("(?m)^class_name\\s+(\\w+)").search(
			FileAccess.get_file_as_string(path))
		if match_ != null:
			_class_paths[match_.get_string(1)] = path
	var found: Array[String] = []
	for path: String in scripts:
		for rpc: Dictionary in _any_peer_rpcs(path):
			found.append("%s:%s" % [path, rpc.name])
			_check_rpc(path, rpc)
	_expect(found.size() >= MIN_RPCS, "Finds every any_peer RPC in the project (got %d)" % found.size())
	_expect(found.has("res://modules/net_session/net_event_bus.gd:request"),
		"Portable modules are scanned too (NetEventBus.request)")
	for key: String in EXCEPTIONS:
		_expect(found.has(key), "Exception %s still names an any_peer RPC" % key)
	for key: String in BUDGET_EXEMPT:
		_expect(found.has(key), "Budget exemption %s still names an any_peer RPC" % key)
	for key: String in CRITICAL_RPCS:
		_expect(found.has(key), "Critical request %s still names an any_peer RPC" % key)

	_check_ordered_pairs()
	await _check_event_bus()

	if _failures == 0:
		print("PASS: %d any_peer RPCs check their sender, budget and values; EventBus relays only its requests"
			% found.size())
	quit(_failures)


func _check_rpc(path: String, rpc: Dictionary) -> void:
	var key: String = "%s:%s" % [path, rpc.name]
	if EXCEPTIONS.has(key):
		return
	var body: String = _expanded_body(path, rpc)
	var from_host: bool = body.contains("RpcGuard.from_host(")
	_expect(_has_any(body, SENDER_CHECKS), "%s checks who sent it (RpcGuard or get_remote_sender_id())" % key)
	if bool(rpc.reliable) and not from_host and not BUDGET_EXEMPT.has(key):
		_expect(_has_any(body, BUDGET_CHECKS),
			"%s is a reliable request: RpcGuard.allow_request() limits it per peer" % key)
	if CRITICAL_RPCS.has(key):
		_expect(body.contains("RpcGuard.allow_critical_request("),
			"%s lets go of something: RpcGuard.allow_critical_request() keeps a reserve for it" % key)
	for parameter: Dictionary in rpc.params:
		var type_name: String = parameter.type
		var name_: String = parameter.name
		if type_name in ["float", "Vector2", "Vector3", "Transform3D"]:
			_expect(_has_any(body, FINITE_CHECKS), "%s rejects NaN/inf in its %s %s" % [key, type_name, name_])
		elif type_name == "Dictionary":
			_expect(body.contains("RpcGuard.dict_ok(%s" % name_), "%s bounds its dictionary %s" % [key, name_])
		elif type_name == "String":
			_expect(body.contains("RpcGuard.text_ok(%s" % name_), "%s bounds its text %s" % [key, name_])
		elif type_name == "StringName" and not from_host:
			_expect(body.contains("RpcGuard.name_ok(%s" % name_), "%s bounds its StringName %s" % [key, name_])
		elif type_name == "NodePath" and not from_host:
			_expect(body.contains("RpcGuard.path_ok(%s" % name_), "%s bounds its NodePath %s" % [key, name_])
		elif type_name == "Array" or type_name.begins_with("Packed"):
			_expect(body.contains(".size()") or body.contains("RpcGuard.args_ok(%s" % name_),
				"%s bounds the size of %s" % [key, name_])


## The RPC's own body plus, one level down, the body of each function it
## calls in the same file, in the class it extends (by class_name), or as
## ClassName.function() (package.gd hands some to PackageRescue, player.gd
## checks through _from_host(), EventBus through NetEventBus.request()).
func _expanded_body(path: String, rpc: Dictionary) -> String:
	var body: String = rpc.body
	var own: Dictionary = _functions(path).duplicate()
	var parent: String = _parent_path(path)
	if not parent.is_empty():
		var inherited: Dictionary = _functions(parent)
		for function: String in inherited:
			if not own.has(function):
				own[function] = inherited[function]
	var parts: Array[String] = [body]
	for match_: RegExMatch in RegEx.create_from_string("\\b(\\w+)\\(").search_all(body):
		var called: String = match_.get_string(1)
		if called != rpc.name and own.has(called):
			parts.append(String(own[called]))
	for match_: RegExMatch in RegEx.create_from_string("\\b([A-Z]\\w*)\\.(\\w+)\\(").search_all(body):
		var class_path: String = String(_class_paths.get(match_.get_string(1), ""))
		if not class_path.is_empty():
			parts.append(String(_functions(class_path).get(match_.get_string(2), "")))
	return "\n".join(parts)


## The script `path` extends, when it extends a class_name (or a path).
func _parent_path(path: String) -> String:
	var match_: RegExMatch = RegEx.create_from_string("(?m)^extends\\s+(\"[^\"]+\"|\\w+)").search(
		FileAccess.get_file_as_string(path))
	if match_ == null:
		return ""
	var parent: String = match_.get_string(1)
	if parent.begins_with("\""):
		return parent.trim_prefix("\"").trim_suffix("\"")
	return String(_class_paths.get(parent, ""))


func _any_peer_rpcs(path: String) -> Array[Dictionary]:
	var rpcs: Array[Dictionary] = []
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	var signature := RegEx.create_from_string(
		"^(?:static\\s+)?func\\s+(\\w+)\\s*\\((.*)\\)\\s*(?:->\\s*[\\w\\[\\]]+\\s*)?:")
	for index: int in lines.size():
		var line: String = lines[index]
		if not line.begins_with("@rpc(") or not line.contains("\"any_peer\""):
			continue
		var at: int = index if line.contains("func ") else index + 1
		var func_line: String = line.substr(line.find("func ")) if at == index else \
			(lines[at] if at < lines.size() else "")
		var match_: RegExMatch = signature.search(func_line)
		if match_ == null:
			_expect(false, "%s:%d: can't read the function after @rpc (keep its signature on one line)"
				% [path, index + 1])
			continue
		rpcs.append({"name": match_.get_string(1), "params": _params(match_.get_string(2)),
			"reliable": line.contains("\"reliable\""), "body": _body(lines, at)})
	return rpcs


func _params(text: String) -> Array[Dictionary]:
	var params: Array[Dictionary] = []
	for raw: String in text.split(",", false):
		var declaration: String = raw.split("=")[0].strip_edges()
		var pieces: PackedStringArray = declaration.split(":")
		params.append({"name": pieces[0].strip_edges(), "type": pieces[1].strip_edges() if pieces.size() > 1 else ""})
	return params


## Every indented or blank line after the signature, up to the next top-level one.
func _body(lines: PackedStringArray, func_index: int) -> String:
	var body: PackedStringArray = []
	for index: int in range(func_index + 1, lines.size()):
		var line: String = lines[index]
		if not line.strip_edges().is_empty() and not (line.begins_with("\t") or line.begins_with(" ")):
			break
		body.append(line)
	return "\n".join(body)


func _functions(path: String) -> Dictionary:
	if _function_cache.has(path):
		return _function_cache[path]
	var functions: Dictionary = {}
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	var head := RegEx.create_from_string("^(?:static\\s+)?func\\s+(\\w+)")
	for index: int in lines.size():
		var match_: RegExMatch = head.search(lines[index])
		if match_ != null:
			functions[match_.get_string(1)] = _body(lines, index)
	_function_cache[path] = functions
	return functions


func _collect_scripts(dir_path: String, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if dir_path == "res://" and sub in SKIPPED_DIRS:
			continue
		# A module's own tests are tests too.
		if sub == "tests" and dir_path.begins_with("res://modules/"):
			continue
		_collect_scripts(dir_path.path_join(sub), into)
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			into.append(dir_path.path_join(file))


func _check_ordered_pairs() -> void:
	for pair: Array in ORDERED_PAIRS:
		var modes: Array[String] = []
		for target: Array in pair:
			var annotation: String = _annotation(String(target[0]), String(target[1]))
			_expect(annotation.contains("\"reliable\""),
				"%s:%s is reliable (%s)" % [target[0], target[1], annotation])
			modes.append(str(_channel(annotation)))
		_expect(modes[0] == modes[1], "%s and %s share a channel, so they arrive in order (channels %s)"
			% [pair[0][1], pair[1][1], modes])


## The @rpc line right above `func name(`, or "" when there's none.
func _annotation(path: String, function: String) -> String:
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	for index: int in range(1, lines.size()):
		if lines[index].begins_with("func %s(" % function):
			return lines[index - 1] if lines[index - 1].begins_with("@rpc(") else ""
	return ""


## The channel of an @rpc annotation: its integer argument, 0 when it has none.
func _channel(annotation: String) -> int:
	var inside: String = annotation.get_slice("(", 1).get_slice(")", 0)
	for argument: String in inside.split(","):
		if argument.strip_edges().is_valid_int():
			return argument.strip_edges().to_int()
	return 0


## The game's bus: a callout is a place and a short label, the horn carries
## nothing, and no other fact can be requested.
func _check_event_bus() -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.call(&"reset_request_cooldowns")
	var pings: Array = []
	var horns: Array = []
	var runs: Array = []
	var on_ping: Callable = func(peer: int, at: Vector3, label: String) -> void: pings.append([peer, at, label])
	var on_horn: Callable = func(peer: int) -> void: horns.append(peer)
	var on_run: Callable = func(_score: int, _results: Dictionary) -> void: runs.append(true)
	bus.connect(&"ping_sent", on_ping)
	bus.connect(&"horn_honked", on_horn)
	bus.connect(&"run_ended", on_run)
	bus.call(&"request", &"run_ended", [0])
	bus.call(&"request", &"package_ruined", ["box", "fire"])
	_expect(runs.is_empty(), "A fact of the game can't be requested through request()")
	bus.call(&"request", &"ping_sent", [Vector3.ONE])
	bus.call(&"request", &"ping_sent", ["here", "¡Bache!"])
	bus.call(&"request", &"horn_honked", [Vector3.ONE])
	_expect(pings.is_empty() and horns.is_empty(), "A callout or a horn with the wrong shape is refused")
	bus.call(&"request_ping", Vector3(NAN, 0.0, 0.0), "¡Bache!")
	bus.call(&"request_ping", Vector3.ONE, "x".repeat(RpcGuard.MAX_TEXT_LENGTH + 1))
	_expect(pings.is_empty(), "request_ping drops a NaN position or a long label")
	bus.call(&"request_ping", Vector3(1.0, 0.0, -4.0), "¡Bache!")
	bus.call(&"request_horn")
	bus.call(&"request_horn")
	_expect(pings.size() == 1 and horns == [1, 1], "A proper callout and every horn press go through (got %s, %s)"
		% [pings, horns])
	bus.disconnect(&"ping_sent", on_ping)
	bus.disconnect(&"horn_honked", on_horn)
	bus.disconnect(&"run_ended", on_run)
	bus.call(&"reset_request_cooldowns")
	await process_frame


func _has_any(text: String, tokens: Array) -> bool:
	for token: String in tokens:
		if text.contains(token):
			return true
	return false


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
