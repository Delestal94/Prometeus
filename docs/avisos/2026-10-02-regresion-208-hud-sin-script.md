# Los `--script` vuelven a cargar el HUD con su script (N-919, regresión de #208)

**Fecha:** 2026-10-02 · **De:** Nacho · **Para:** Slatex

## Qué cambió

Un `--script` (tests, benchs, capturas) compila el árbol de dependencias estáticas antes de que existan los
autoloads. Si un script de esa cadena nombra un autoload (`NetworkManager`, `EventBus`...), no compila y el nodo
que lo usa queda sin script, sin error de salida. El juego normal y el exportado no se afectaban.

- `scripts/gameplay/player/player_cargo_care.gd` (de Slatex): `Hud.EDGE_MARGIN` pasa a una constante local
  `EDGE_MARGIN: int = 40`, igual que ya hacía con `BASE_HEIGHT`. Era la única referencia de afuera a `Hud`, y
  desde el #208 (`DeliveryHouse` tipa la caja) metía `hud.gd` en todo `--script` que llega a la ruta: el nodo
  `HUD` de `level_base.tscn` quedaba como `CanvasLayer` sin script (`bench_drive` medía sin HUD).
- `scripts/gameplay/depot/depot.gd`: deja de precargar como tipo `run_manager.gd`, `crew_progression.gd`,
  `rescue_hook.gd` y `vehicle_faults.gd` (nombran `EventBus`, del #202): todo test que nombra `Depot` dejaba
  `/root/RunManager` sin script. Se usan como `Node`, como ya hacía `PackageAutoloads`.

Test nuevo `tests/test_hud_script_loads.gd`: llega a `DeliveryHouse` y `Depot` estáticamente y exige que el HUD
y `RunManager` tengan su script y que los dos `EDGE_MARGIN` coincidan.

## Qué tiene que hacer Slatex

Nada. Regla para lo que venga: un script al que se llega por tipos desde `Player`, `DeliveryPackage`, `Depot` o
la ruta no nombra un autoload por su nombre ni una clase que lo haga (como `Hud`); usá
`get_node_or_null(^"/root/X")` o una constante local.
