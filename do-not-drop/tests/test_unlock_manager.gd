extends SceneTree

const TEST_PATH := "user://unlock_manager_test.json"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var manager := preload("res://scripts/core/unlock_manager.gd").new()
	manager.storage_path = TEST_PATH
	manager.reset_profile()
	assert(not manager.is_unlocked(&"liquid_trap"), "Líquido empieza bloqueado")
	manager.record_run(300, {"delivered": true})
	manager.record_run(0, {"delivered": false})
	manager.record_run(0, {"delivered": true})
	manager.record_run(0, {"delivered": true})
	assert(manager.is_unlocked(&"liquid_trap"), "Tres entregas y 250 puntos desbloquean Líquido")
	assert(manager.select_cosmetic(&"mint_uniform"), "El uniforme inicial se puede seleccionar")
	assert(not manager.select_cosmetic(&"sky_uniform"), "Un uniforme bloqueado no se puede seleccionar")
	manager.unlocked[&"sky_uniform"] = true
	assert(manager.select_cosmetic(&"sky_uniform"), "Un uniforme desbloqueado se puede seleccionar")
	var restored := preload("res://scripts/core/unlock_manager.gd").new()
	restored.storage_path = TEST_PATH
	restored.load_profile()
	assert(restored.successful_deliveries == 3, "Las entregas deben persistir")
	assert(restored.total_score == 300, "El puntaje debe persistir")
	assert(restored.is_unlocked(&"liquid_trap"), "El desbloqueo debe persistir")
	assert(restored.selected_cosmetic == &"sky_uniform", "La selección de uniforme debe persistir")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("PASS: unlock progression saves, loads and unlocks by delivery plus score.")
	quit(0)
