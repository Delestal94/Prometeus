# S-305 cerrada: chaleco reflectivo como accesorio 16 del gel

Hecho el 2026-10-31. Toca archivos de Slatex (personaje gel, S-311) y la UI de personalización.

- `docs/tareas/S-305.md` queda `[x]`: gorra, casco y mochila ya estaban (S-311.72); el desbloqueo, el panel
  y la replicación del id los cubrieron S-311.72/.76. Lo único que faltaba era el chaleco reflectivo.
- Nuevo accesorio `reflective_vest` (catálogo, constructor en `gel_accessory_library.gd`, desbloqueo
  `coral_uniform` en `unlock_manager.gd`). El panel lo lista solo, porque recorre el catálogo.
- `gel_costume_fitter.gd`: opción nueva `gel_fit_shell` para piezas que cuelgan de la superficie del torso
  (escala también su desplazamiento x/z y su altura con `torso_length`). Los disfraces existentes no la usan
  y quedan igual.
- `player_gel_appearance.gd` y `character_preview.gd`: un segundo `GelCostumeFitter` para el accesorio; los
  accesorios rígidos no tienen piezas ajustables y siguen como antes.
- Sin RPC ni campos nuevos en red: viaja por el `accessory_id` existente.
- Tests: `test_gel_accessory_library`, `test_gel_accessory_fit` (nuevo), `test_gel_cosmetic_unlocks`,
  `test_gel_character`.
