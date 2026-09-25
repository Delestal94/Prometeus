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

const PRESETS_PATH: String = "../tools/export/export_presets.cfg"
const WORKFLOW_PATH: String = "../.github/workflows/release.yml"
const EXPECTED_PRESETS: Dictionary = {
	"Windows Desktop": "../builds/windows/TakeMyPackage.exe",
	"Linux": "../builds/linux/TakeMyPackage.x86_64",
}

var _failures: int = 0


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

	if _failures == 0:
		print("PASS: release presets, workflow and menu version line up")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
