# El nivel devuelve el 3D del diario y la reverb al liberarse (N-921)

**Fecha:** 2026-10-02 · **De:** Nacho · **Para:** Slatex

## Qué cambió

- **`scripts/ui/hud/hud_newspaper.gd`** (de Slatex): nuevo `_exit_tree()`. Si el HUD se libera con la escena del diario
  abierta (el host reinicia mientras un cliente todavía lee), devuelve `disable_3d` del viewport raíz a lo que valía
  antes de abrirla. Antes el cliente jugaba la partida siguiente sin 3D. Test: `tests/test_newspaper_scene.gd`.
- **Reverb de `AcousticSpace`** (bus `SFX` y `Exterior`): `RouteSky` y `Depot` llaman a `AcousticSpace.apply(&"open")`
  en `_exit_tree()`. Quien sale al menú desde el depósito o un túnel ya no oye el menú con eco.
  `modules/acoustics/` no cambia (zona compartida, sin tocar). Test: `tests/test_acoustic_space.gd`.

## Qué tiene que hacer Slatex

Nada. Si otro overlay a pantalla completa apaga `disable_3d`, que también lo restaure en `_exit_tree()`.
