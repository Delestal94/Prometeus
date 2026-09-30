# Aviso: S-310, una falla distinta por trampa (2026-09-30)

Rama `nacho/S-310-ruin-effects`. Toca `package_feedback.gd` (de Slatex), con un cambio mínimo, y agrega un
archivo nuevo. **No cambia ninguna firma pública ni la simulación**: es presentación local, cada cliente
la arma desde `package_ruined` (que ya viaja a todos).

## Qué cambió

- Nuevo `scripts/gameplay/package/package_ruin_effects.gd`: `PackageRuinEffects.spawn(trap_id, package, slow)`
  devuelve el nodo raíz del efecto (`top_level`, hijo de la escena actual, se libera solo) o `null` si la
  trampa no tiene efecto propio. Frágil: esquirlas (`RuinShards`); Líquido: salpicadura y charco (`RuinLiquid`);
  Explosivo: confeti y humo de colores (`RuinBlast`); Ruidoso y Hostil: el animal escapa 3 s (`RuinCritter`);
  Equilibrio: la torre se derrumba (`RuinTower`); Peso creciente: anillo de polvo (`RuinDust`).
- `package_feedback.gd::_on_package_ruined`: llama a `PackageRuinEffects.spawn()`; si devuelve `null` (trampa
  sin id o desconocida) sigue el confeti de siempre. Peso creciente además dispara el squash de asentado de la
  caja (`_bounce_time = 0.0`, solo la escala de `Box`). El archivo queda en exactamente 1000 líneas (tope del
  lint): lo que se agregue a ese componente va en archivos aparte.
- Test nuevo `tests/test_ruin_effects.gd`; `test_ruin_feedback.gd` solo cambió el comentario (Frágil sigue
  dando un único `GPUParticles3D` en la raíz, ahora `RuinShards`).

## Qué tiene que hacer Slatex

Nada. Si se agrega una trampa nueva, sumar su id a `PackageRuinEffects.TRAP_IDS` y su rama en `spawn()`; sin eso
usa el confeti genérico.
