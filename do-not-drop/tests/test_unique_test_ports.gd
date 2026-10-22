extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_unique_test_ports.gd
## Covers N-986: tools/run-tests.sh runs the suite in parallel, so no two test scripts may bind the
## same localhost ENet port (three company tests shared 24681 and failed to bind, issue #661).
## - Reads every .gd in tests/ and modules/*/tests/ and collects its ports: each `const ...PORT:
##   int = N`, plus the next PORT_SPAN - 1 when the script declares a PORT_SPAN, and every literal
##   port given to create_server, create_client or host_session.
## - Fails when a port belongs to more than one script, naming the scripts.

const DIRS: Array[String] = ["res://tests"]
const MODULES_DIR: String = "res://modules"
## Fewer ports than this means the patterns stopped matching how the tests declare them.
const MIN_PORTS: int = 20

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var declared := RegEx.create_from_string("(?m)^const \\w*PORT: int = (\\d+)")
	var span := RegEx.create_from_string("(?m)^const PORT_SPAN: int = (\\d+)")
	var base := RegEx.create_from_string("(?m)^const PORT: int = (\\d+)")
	var literal := RegEx.create_from_string(
		"(?:create_server|host_session)\\((\\d+)|create_client\\(\"[^\"]*\", (\\d+)")
	var owners: Dictionary = {}
	for path: String in _scripts():
		var source: String = FileAccess.get_file_as_string(path)
		var ports: Array[int] = []
		for found: RegExMatch in declared.search_all(source):
			ports.append(int(found.get_string(1)))
		var spanned: RegExMatch = span.search(source)
		var first: RegExMatch = base.search(source)
		if spanned != null and first != null:
			for step: int in range(1, int(spanned.get_string(1))):
				ports.append(int(first.get_string(1)) + step)
		for found: RegExMatch in literal.search_all(source):
			ports.append(int(found.get_string(1) if found.get_string(1) != "" else found.get_string(2)))
		for port: int in ports:
			var users: Array = owners.get_or_add(port, [])
			if not users.has(path):
				users.append(path)
	_expect(owners.size() >= MIN_PORTS, "The scan finds the tests' ENet ports (got %d)" % owners.size())
	var ports: Array = owners.keys()
	ports.sort()
	for port: int in ports:
		var users: Array = owners[port]
		_expect(users.size() == 1, "Port %d belongs to one test, the suite runs in parallel (got %s)"
			% [port, ", ".join(users)])
	if _failures == 0:
		print("PASS: %d test ports, none shared between scripts" % owners.size())
	quit(_failures)


## Every .gd under tests/ and each module's tests/.
func _scripts() -> Array[String]:
	var dirs: Array[String] = DIRS.duplicate()
	for module: String in DirAccess.get_directories_at(MODULES_DIR):
		dirs.append("%s/%s/tests" % [MODULES_DIR, module])
	var paths: Array[String] = []
	for dir: String in dirs:
		for file: String in DirAccess.get_files_at(dir):
			if file.ends_with(".gd"):
				paths.append("%s/%s" % [dir, file])
	return paths


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)
