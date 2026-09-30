# Aviso: N-109, animales que se meten con la carga (2026-09-30)

Rama `nacho/N-109-cargo-animals`. Una gaviota, un perro y abejas que van por una caja (ver `docs/tareas-nacho.md`,
N-109). Toca archivos de Slatex (`package.gd`, `package_rescue.gd`) y de la zona compartida (`event_bus.gd`,
`network_manager.gd`, `level_base.gd`), todo con cambios chicos y **sin cambiar ninguna firma existente**.

## Qué cambió

- **Paquete (Slatex).** Nueva `DeliveryPackage.apply_external_damage(amount, ruin_cause_key)` (solo host; la lógica
  vive en `PackageRescue.apply_external_damage()` para no pasar las 1000 líneas de `package.gd`). Es el mismo camino
  del daño del parásito, que ahora la usa: suma a `_parasite_damage`, avisa `package_damaged` /
  `package_integrity_changed` / `package_state_changed` y, si arruina la caja, `package_ruined` con esa causa
  (una clave de traducción). Sin cambios de comportamiento para el parásito.
- **`EventBus` (compartida).** Dos señales nuevas, ambas por `EventBus.relay()`:
  `cargo_animal_alert(kind, package_id, warn_seconds, act_seconds)` y
  `cargo_animal_ended(kind, package_id, outcome, peer_id)`. `kind`: `gull`, `dog`, `bees`. `outcome`: `scared`,
  `held`, `distracted`, `sealed`, `left`, `snatched`.
- **`NetworkManager.PROTOCOL_VERSION` 11 → 12** (compartida): un cliente sin las señales nuevas no entendería el
  relay. Otras ramas también lo suben: al mezclar, dejar el valor más alto.
- **Niveles.** `level_common.gd` crea un nodo `CargoAnimals` (el director, en `scripts/gameplay/route/`) en cada
  peer; `level_base.gd::_prepare_mode()` le pasa las casas y una función "¿es campo abierto?" (`_is_open_country`);
  `level_endless.gd` lo marca `endless` (solo viene la gaviota). El host decide y hace el daño; todos dibujan.
- **Interacción nueva** (`dog_distract_point.gd`, extiende `Interactable` sin tocarlo, como `doorbell_point.gd`):
  "Tirarle un palo al perro", solo con las manos libres. Es un `Interactable` más: `player_interaction.gd` lo
  encuentra solo, sin cambios.
- Textos nuevos en `strings_world.csv` (`WORLD_GULL_*`, `WORLD_DOG_*`, `WORLD_BEES_*`, `WORLD_ANIMAL_OUTCOME_*`,
  `WORLD_CARGO_*_RUINED`), sonidos en `presentation/cargo_animal_sounds.gd` y niveles en `world_mix.gd`.
- **Prompt del palo (Slatex, `player_interaction.gd`).** `closest_interactable()` suma `aim_bonus` al puntaje de
  un `Interactable` que lo declare (`area.get(&"aim_bonus")`; el resto no cambia). Lo usa `dog_distract_point.gd`:
  el control de las puertas traseras, al lado del perro, le ganaba el prompt.
- **`wildlife_animal.gd`** (presentación): `standing_clip` opcional, el clip que el perro mantiene quieto en vez de
  mirar alrededor (el perro de la carga se queda parado). Por defecto vacío: el resto de los perros no cambia.
- Tests: `test_cargo_animals.gd` nuevo; captura `tests/render_cargo_animals.gd`.

## Qué tiene que hacer Slatex

- `git pull` antes de seguir (por el `PROTOCOL_VERSION`). Nada más.
- Si algún día `DeliveryPackage` cambia cómo se cuentan el daño y la integridad, `apply_external_damage()` es el
  único punto por el que entra el daño de los animales. El director lee `is_loaded`, `is_held`, `is_open`,
  `contents_spilled`, `player_input["steady_strength"]`, `carrier`, `tender_peer_id` y `trap_state`; si se
  renombran, hay que ajustar `cargo_animals.gd`.
