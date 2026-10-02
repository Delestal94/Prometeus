# Módulo nuevo `press_photo` (N-606.5)

- **Zona compartida**: `do-not-drop/modules/press_photo/` (nuevo: `PressPhoto` con `framing()`, `capture()` y
  `halftone_material()`, más `halftone.gdshader` y su test) y su fila en `docs/modulos.md`.
- El shader de trama `scripts/presentation/newspaper/newspaper_photo.gdshader` se mudó al módulo
  (`res://modules/press_photo/halftone.gdshader`); ahora el paso de los puntos va en píxeles del lienzo
  (uniform `pitch`). El estudio `scripts/tools/newspaper_concept/` ya apunta al nuevo.
- `scripts/gameplay/level_common.gd` agrega un `NewsPhotographer` al lado de `RunChronicle`. Sin cambios de red
  ni de `PROTOCOL_VERSION`.
- Qué hacer: nada; `git pull` antes de tocar el diario o los módulos.
