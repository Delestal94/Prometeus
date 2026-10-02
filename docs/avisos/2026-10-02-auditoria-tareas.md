# Tareas nuevas de la auditoría integral del 2026-10-02 que tocan Slatex o zona compartida

**Fecha:** 2026-10-02 · **De:** Nacho (rutina de auditoría) · **Para:** Slatex

## Qué cambió

Solo `docs/tareas-nacho.md`: N-920, N-921 y N-922 (informe `docs/auditorias/2026-10-02-integral.md`). Ningún código.

- **N-921** (A-1.2): `HudNewspaper._exit_tree()` restaura `disable_3d` en `hud_newspaper.gd` (dominio de Slatex);
  la reverb de `modules/acoustics/` vuelve a `open` al salir (zona compartida).
- **N-922** (A-D.1 y A-D.2): auditoría de red de #239 y `PROTOCOL_VERSION` 27 en `network_manager.gd` (zona compartida).
- **N-920** (A-1.1): Endless y la detección de atascos en `level_common.gd`/`level_endless.gd`; no toca a Slatex.

## Qué tiene que hacer Slatex

Nada ahora. Cada PR que implemente estas tareas lleva su propio aviso.
