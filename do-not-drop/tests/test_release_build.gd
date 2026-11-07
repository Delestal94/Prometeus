extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_release_build.gd
##
## N-210, release builds on every v* tag (.github/workflows/release.yml):
## - project.godot carries application/config/version and the main menu footer
##   shows it (main_menu.gd), so a player can tell which build they have.
## - tools/export/export_presets.cfg (the presets the job copies in, since the
##   local export_presets.cfg is gitignored) parses, has the two presets the job
##   exports by name, and keeps tests/ and .blend files out of the build.
## - The workflow exports exactly those preset names and stamps the version with
##   tools/export/stamp_version.py.
## - D-2019: no path the game names is left out of a build unless it is debug-only and looked for first
##   (DEBUG_ONLY_PATHS); tools/export/probe_company.gd compiles, and the PC build routine runs the smoke
##   (tools/export/smoke-company.sh).
## - D-2019 (expansion): every preset exports all resources and its exclude_filter leaves in
##   everything the Modo Empresa loads at run time (the data/ registries, company_root.tscn and
##   the company scripts), matched like Godot does: the path from res:// or the bare file name.

const PRESETS_PATH: String = "../tools/export/export_presets.cfg"
const WORKFLOW_PATH: String = "../.github/workflows/release.yml"
## What the Modo Empresa needs in a build (D-2019): folders are walked recursively.
const COMPANY_PATHS: Array[String] = [
	"data/products", "data/zones", "data/vehicles", "data/gates", "data/suppliers", "data/boxes",
	"data/placeables", "data/shed", "data/world", "data/order_requirements", "scenes/company",
	"scenes/gameplay/company_root.tscn", "scripts/gameplay/company_root.gd",
	"scripts/gameplay/company_shed.gd", "scripts/gameplay/shed_builder.gd",
	"scripts/gameplay/supplier_truck_view.gd", "scripts/core/company", "scripts/gameplay/business",
	"scripts/gameplay/districts", "scripts/gameplay/fleet",
]
## Left out by the presets and still named by the game: each is debug-only and looked for first (see
## _check_excluded_paths()). A new line here needs the same two guards.
const DEBUG_ONLY_PATHS: Array[String] = ["scripts/tools/trailer_camera.gd", "scripts/tools/capture_mode.gd"]
## Where the game names its files.
const GAME_FOLDERS: Array[String] = ["scripts", "scenes", "modules", "data"]
## The smoke of an exported build (D-2019): it lives outside res://, so neither the lint nor the editor hook see it.
const SMOKE_SCRIPT: String = "../tools/export/smoke-company.sh"
const SMOKE_PROBE: String = "../tools/export/probe_company.gd"
const PC_ROUTINE: String = "../.claude/rutinas/pc-build.md"
const EXPECTED_PRESETS: Dictionary = {
	"Windows Desktop": "../builds/windows/TakeMyPackage.exe",
	"Linux": "../builds/linux/TakeMyPackage.x86_64",
}

var _failures: int = 0
var _named: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	_expect(RegEx.create_from_string("^[0-9]+\\.[0-9]+\\.[0-9]+").search(version) != null,
		"project.godot has a semantic config/version (got '%s')" % version)

	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var shown: bool = false
	for label: Node in menu.find_children("*", "Label", true, false):
		if version != "" and (label as Label).text.contains(version):
			shown = true
	_expect(shown, "The main menu shows the build version '%s' somewhere" % version)
	menu.queue_free()
	await process_frame

	var repo: String = ProjectSettings.globalize_path("res://")
	var presets := ConfigFile.new()
	var err: Error = presets.load(repo.path_join(PRESETS_PATH))
	_expect(err == OK, "tools/export/export_presets.cfg parses (error %d)" % err)
	var found: Dictionary = {}
	for section: String in presets.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var name: String = str(presets.get_value(section, "name", ""))
		found[name] = true
		var filter: String = str(presets.get_value(section, "exclude_filter", ""))
		_expect(str(presets.get_value(section, "export_filter", "")) == "all_resources",
			"Preset '%s' exports all resources (D-2019)" % name)
		_check_excluded_paths(name, filter)
		var excluded: Array[String] = _excluded(_company_files(), filter)
		_expect(excluded.is_empty(),
			"Preset '%s' keeps the Modo Empresa in the build (excluded: %s)" % [name, excluded])
		_expect(filter.contains("tests/*") and filter.contains("*.blend") and filter.contains("scripts/tools/*") and filter.contains("scenes/tools/*"),
			"Preset '%s' keeps tests/, the debug tools and .blend files out of the build (got '%s')" % [name, filter])
		if EXPECTED_PRESETS.has(name):
			_expect(str(presets.get_value(section, "export_path", "")) == EXPECTED_PRESETS[name],
				"Preset '%s' exports to %s" % [name, EXPECTED_PRESETS[name]])
			_expect(presets.get_value(section + ".options", "binary_format/architecture", "") == "x86_64",
				"Preset '%s' builds x86_64" % name)
	for name: String in EXPECTED_PRESETS:
		_expect(found.has(name), "The CI presets include '%s' (got %s)" % [name, found.keys()])

	var workflow: String = FileAccess.get_file_as_string(repo.path_join(WORKFLOW_PATH))
	_expect(workflow.contains("tags: ['v*']"), "The release job runs on v* tags")
	for name: String in EXPECTED_PRESETS:
		_expect(workflow.contains("--export-release \"%s\"" % name),
			"The release job exports the '%s' preset" % name)
	_expect(workflow.contains("stamp_version.py") and workflow.contains("gh release upload"),
		"The release job stamps the version and attaches the zips to the release")

	_check_smoke(repo)

	if _failures == 0:
		print("PASS: release presets, workflow and menu version line up")
	quit(_failures)


## A path the game names and the build leaves out only fails in the build. Whatever a preset drops must be on
## DEBUG_ONLY_PATHS, and whoever names it asks OS.is_debug_build() and ResourceLoader.exists() first.
func _check_excluded_paths(preset: String, filter: String) -> void:
	var named: Dictionary = _named_paths()
	var paths: Array[String] = []
	paths.assign(named.keys())
	for path: String in _excluded(paths, filter):
		_expect(DEBUG_ONLY_PATHS.has(path),
			"Preset '%s' leaves out %s, which %s needs" % [preset, path, named[path]])
		var code: String = FileAccess.get_file_as_string("res://" + str(named[path]))
		_expect(code.contains("OS.is_debug_build() and ResourceLoader.exists("),
			"%s only reaches %s in a debug build, once it knows it is there" % [named[path], path])


## path from res:// -> the first game file (res://-relative) that names it. A build's own folders of tools and
## tests may name each other: they are left out too, or never load.
func _named_paths() -> Dictionary:
	if not _named.is_empty():
		return _named
	var files: Array[String] = []
	for folder: String in GAME_FOLDERS:
		_collect(folder, files)
	var quoted: RegEx = RegEx.create_from_string("res://([^\"'\\s]+\\.[A-Za-z0-9]+)\"")
	for file: String in files:
		if file.get_extension() not in ["gd", "tscn", "tres"] or file.begins_with("scripts/tools/") \
				or file.begins_with("scenes/tools/") or file.contains("/tests/"):
			continue
		for found: RegExMatch in quoted.search_all(FileAccess.get_file_as_string("res://" + file)):
			if not _named.has(found.get_string(1)):
				_named[found.get_string(1)] = file
	_expect(_named.size() > 100, "The game's res:// paths are found (%d)" % _named.size())
	return _named


func _check_smoke(repo: String) -> void:
	_expect(FileAccess.file_exists(repo.path_join(SMOKE_SCRIPT)), "tools/export/smoke-company.sh is in the repo")
	var probe: GDScript = load(repo.path_join(SMOKE_PROBE)) as GDScript
	_expect(probe != null and probe.can_instantiate(), "tools/export/probe_company.gd compiles")
	var routine: String = FileAccess.get_file_as_string(repo.path_join(PC_ROUTINE))
	_expect(routine.contains("tools/export/smoke-company.sh"), "The PC build routine runs the smoke of the build")


## Every file under COMPANY_PATHS (res://-relative), minus the editor's .uid/.import companions.
func _company_files() -> Array[String]:
	var files: Array[String] = []
	for path: String in COMPANY_PATHS:
		if FileAccess.file_exists("res://" + path):
			files.append(path)
		else:
			_collect(path, files)
	_expect(files.size() > 20, "The Modo Empresa files are found (%d)" % files.size())
	return files


func _collect(dir: String, into: Array[String]) -> void:
	for file: String in DirAccess.get_files_at("res://" + dir):
		if not file.ends_with(".uid") and not file.ends_with(".import"):
			into.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at("res://" + dir):
		_collect(dir.path_join(sub), into)


## The files an exclude_filter drops: Godot matches each pattern (case-insensitive) against
## the path from res:// and against the file name alone.
func _excluded(files: Array[String], exclude_filter: String) -> Array[String]:
	var dropped: Array[String] = []
	for raw: String in exclude_filter.split(",", false):
		var pattern: String = raw.strip_edges().trim_prefix("res://")
		if pattern.is_empty():
			continue
		for file: String in files:
			if (file.matchn(pattern) or file.get_file().matchn(pattern)) and not dropped.has(file):
				dropped.append(file)
	return dropped


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
