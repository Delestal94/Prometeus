extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_protocol_version.gd
##
## PROTOCOL_VERSION (scripts/core/network_manager.gd) keeps a history in the
## comment above it, one "N: what changed" entry per version. Two branches
## that both bump to the same number write an identical `const` line, so git
## merges them without a conflict and two incompatible builds would share a
## version. This test reads the history and requires the entries to be
## unique, consecutive from the first one, and to end at PROTOCOL_VERSION:
## the second branch to merge fails here and has to bump again. No entry may
## say "reserved": a number held for a branch that has not merged is how 25
## ended up skipped and 26 shipped without N-218 (N-922). A branch writes its
## own entry when it bumps.

const SOURCE: String = "res://scripts/core/network_manager.gd"

var _failures: int = 0


func _initialize() -> void:
	var text: String = FileAccess.get_file_as_string(SOURCE)
	var lines: PackedStringArray = text.split("\n")
	var declared: int = -1
	var block: Array[String] = []
	for index: int in range(lines.size()):
		var line: String = lines[index]
		if line.begins_with("const PROTOCOL_VERSION"):
			declared = int(line.get_slice("=", 1).strip_edges())
			var back: int = index - 1
			while back >= 0 and lines[back].begins_with("##"):
				block.push_front(lines[back])
				back -= 1
			break
	_expect(declared > 0, "network_manager.gd declares PROTOCOL_VERSION (got %d)" % declared)
	# An entry starts a comment line ("## 12: ...") or follows the opening
	# parenthesis of the first one ("(3: ...").
	var entry := RegEx.create_from_string("(?:^## |\\()(\\d+): ")
	var versions: Array[int] = []
	var reserved: Array[int] = []
	for line: String in block:
		for found: RegExMatch in entry.search_all(line):
			versions.append(int(found.get_string(1)))
			if line.substr(found.get_end()).to_lower().begins_with("reserved"):
				reserved.append(int(found.get_string(1)))
	_expect(not versions.is_empty(), "The comment above PROTOCOL_VERSION lists its history")
	_expect(reserved.is_empty(),
		"No history entry is a reservation (%s): the branch that bumps writes its own entry" % [reserved])
	var repeated: Array[int] = []
	for version: int in versions:
		if versions.count(version) > 1 and not repeated.has(version):
			repeated.append(version)
	_expect(repeated.is_empty(),
		"Every version appears once in the history (duplicates %s): bump to the next free number" % [repeated])
	if not versions.is_empty():
		var expected: Array[int] = []
		for version: int in range(versions[0], versions[0] + versions.size()):
			expected.append(version)
		_expect(versions == expected, "The history is consecutive (got %s)" % [versions])
		_expect(versions[-1] == declared,
			"The last history entry (%d) is the declared PROTOCOL_VERSION (%d)" % [versions[-1], declared])
	if _failures == 0:
		print("PASS: PROTOCOL_VERSION %d with a unique, consecutive history" % declared)
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
