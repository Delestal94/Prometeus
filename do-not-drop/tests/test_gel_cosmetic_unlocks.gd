extends SceneTree
## S-311.76: new gel cosmetics use existing unlocks, persist and preview on the real mannequin.

const Profile := preload("res://scripts/core/unlock_manager.gd")
const HairCatalog := preload("res://scripts/gameplay/player/gel/gel_hair_catalog.gd")
const CostumeCatalog := preload("res://scripts/gameplay/player/gel/gel_costume_catalog.gd")
const AccessoryCatalog := preload("res://scripts/gameplay/player/gel/gel_accessory_catalog.gd")
const PROFILE_PATH: String = "user://gel_cosmetic_unlocks_test.json"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_profile()
	await _check_panel()
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	if _failures == 0:
		print("PASS: gel cosmetics share progression, persist and preview on the real mannequin")
	quit(_failures)


func _check_profile() -> void:
	var profile := Profile.new()
	profile.storage_path = PROFILE_PATH
	profile.reset_profile()
	_expect(profile.gel_style_choices(&"gel_hair").size() == HairCatalog.HAIRSTYLES.size(),
		"all ten hairstyles are progression choices")
	_expect(profile.gel_style_choices(&"gel_costume").size() == CostumeCatalog.COSTUMES.size(),
		"all twelve costumes are progression choices")
	_expect(profile.gel_style_choices(&"gel_accessory").size() == AccessoryCatalog.ACCESSORIES.size() + 1,
		"all fifteen accessories plus none are progression choices")
	_expect(profile.select_gel_style(&"gel_hair", &"quiff"), "a starter hairstyle can be selected")
	_expect(not profile.select_gel_style(&"gel_hair", &"long"), "a late hairstyle stays locked")
	_unlock_all_gel_choices(profile)
	_expect(profile.select_gel_style(&"gel_hair", &"long"), "an earned hairstyle can be selected")
	_expect(profile.select_gel_style(&"gel_eyebrows", &"split"), "earned eyebrows can be selected")
	_expect(profile.select_gel_style(&"gel_moustache", &"curled"), "an earned moustache can be selected")
	_expect(profile.select_gel_style(&"gel_costume", &"skeleton"), "an earned costume can be selected")
	_expect(profile.select_gel_style(&"gel_accessory", &"fairy_wings"), "an earned accessory can be selected")
	var restored := Profile.new()
	restored.storage_path = PROFILE_PATH
	restored.load_profile()
	_expect(restored.selected_gel_hair == &"long" and restored.selected_gel_eyebrows == &"split"
		and restored.selected_gel_moustache == &"curled", "hair selections survive save/load")
	_expect(restored.selected_gel_costume == &"skeleton"
		and restored.selected_gel_accessory == &"fairy_wings", "outfit selections survive save/load")
	profile.free()
	restored.free()


func _check_panel() -> void:
	var profile: Node = root.get_node(^"/root/UnlockManager")
	profile.call(&"reset_profile")
	_unlock_all_gel_choices(profile)
	profile.call(&"select_gel_style", &"gel_hair", &"long")
	profile.call(&"select_gel_style", &"gel_eyebrows", &"split")
	profile.call(&"select_gel_style", &"gel_moustache", &"curled")
	profile.call(&"select_gel_style", &"gel_costume", &"skeleton")
	profile.call(&"select_gel_style", &"gel_accessory", &"fairy_wings")
	var panel: Control = load("res://scripts/ui/cosmetics_panel.gd").new()
	root.add_child(panel)
	await process_frame
	_expect(panel.find_children("Hair_*", "Button", true, false).size() == 10,
		"the style page contains every hairstyle")
	_expect(panel.find_children("Eyebrows_*", "Button", true, false).size() == 6,
		"the style page contains five eyebrows plus none")
	_expect(panel.find_children("Moustache_*", "Button", true, false).size() == 6,
		"the style page contains five moustaches plus none")
	_expect(panel.find_children("Costume_*", "Button", true, false).size() == 12,
		"the style page contains every costume")
	_expect(panel.find_children("Accessory_*", "Button", true, false).size() == 16,
		"the style page contains every accessory plus none")
	var preview: Control = panel.find_child("CharacterPreview", true, false)
	var rounded: Node3D = preview.get(&"mannequin")
	var gel: Node3D = preview.get(&"gel_mannequin")
	_expect(not rounded.visible and gel.visible, "the panel uses the real gel mannequin, not the rounded placeholder")
	var costume := preview.get(&"_costume") as Node3D
	var accessory := preview.get(&"_accessory") as Node3D
	_expect(costume != null and costume.get_meta(&"gel_costume_id") == &"skeleton",
		"the selected costume appears on the live mannequin")
	_expect(accessory != null and accessory.get_meta(&"gel_accessory_id") == &"fairy_wings",
		"the selected accessory appears on the live mannequin")
	var quiff := panel.find_child("Hair_quiff", true, false) as Button
	quiff.pressed.emit()
	await process_frame
	_expect(profile.get(&"selected_gel_hair") == &"quiff", "picking a style card saves immediately")
	var hair_attachment: BoneAttachment3D = preview.get(&"_hair_attachment")
	_expect(hair_attachment.call(&"hair_root").get_meta(&"gel_style_id") == &"quiff",
		"picking a style card rebuilds the live gel preview")
	panel.free()
	profile.call(&"reset_profile")


func _unlock_all_gel_choices(profile: Node) -> void:
	for table: Dictionary in [Profile.GEL_HAIR_UNLOCKS, Profile.GEL_EYEBROW_UNLOCKS,
			Profile.GEL_MOUSTACHE_UNLOCKS, Profile.GEL_COSTUME_UNLOCKS,
			Profile.GEL_ACCESSORY_UNLOCKS]:
		for unlock_id: StringName in table.values():
			profile.get(&"unlocked")[unlock_id] = true


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
