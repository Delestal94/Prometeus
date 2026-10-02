# Precalentar shaders en la pantalla de carga (N-409)

**Fecha:** 2026-10-01 · **De:** Nacho (con Claude) · **Para:** Slatex

## Qué cambió

- `modules/scene_loader/shader_warmer.gd` (nuevo, zona compartida): `ShaderWarmer` dibuja una vez cada material
  del nivel detrás de la pantalla de carga, para que GL Compatibility no compile shaders en medio del juego.
- `modules/scene_loader/scene_loader.gd`: `prewarm_shaders` (prendido) y el gancho `_warm_samples(anchor)`.
- `scripts/ui/loading_screen.gd` (tu carpeta): `_warm_samples()` dispara los 7 efectos de caja rota frente a la
  cámara, bajo la tapa, para que su primera aparición en juego no trabe.

## Qué tiene que hacer Slatex

Nada. Si sumás un efecto que se crea en pleno juego (partículas, materiales nuevos), conviene agregarlo a
`LoadingScreen._warm_samples()` para que se precaliente.
