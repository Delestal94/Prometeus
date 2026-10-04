# Tabla de zonas definitiva (D-0114)

> Fuente de los `.tres` de `ZoneDefinition` (D-0205, `data/zones/`), del boceto del mapa (D-0301) y de
> los bloqueos (D-0306). "Distrito" y "zona" son lo mismo: en el mapa continuo
> (`docs/decisiones/2026-10-04-mapa-continuo.md`) cada distrito es una zona del mapa. Los números van a
> `company_tuning.gd` y a los `.tres`, no al código. Fuentes: [README](../README.md#distritos-un-solo-mapa-continuo),
> [vision.md](vision.md), [economia.md](economia.md), [supuestos.md](../detalle/supuestos.md).

## Reglas de esta tabla

- **Largo de ruta** = minutos de manejo desde el portón del galpón hasta la zona **más** la ruta entre
  paradas, para una salida completa de ida. Regla de oro N-102: 2-5 min. D-0301 lo verifica sobre el
  boceto y D-0346 lo mide con el bot.
- **Casas por salida** (`houses_per_trip`): 3-6 en F1-F3. Las zonas con 1-2 paradas largas lo dicen.
- **Peligros** usan nombres de clase existentes en `scripts/gameplay/route/` cuando la cosa ya existe. Los
  marcados **nuevo** son del grupo de la zona (13-17) y no existen todavía.
- **Clima**: perfiles de `WorldMood` (`soleado`, `nublado`, `lluvia`, `niebla`; noche y atardecer
  salen del reloj del día, D-0325). Los perfiles **nuevo** los suma D-0324.
- **Envío** (`shipping_fee`): Centro 40 y Campo 60 son los de `economia.md`; el resto es decisión de
  esta tabla y lo valida `sim_economy` (D-0540) antes de F2.
- Una zona solo existe si **cambia cómo se cuida la caja** (vision.md §6).

## Las 9 zonas

| # | id | Zona | Vehículos permitidos adentro | Peligros (clase existente / **nuevo**) | Casas por salida | Ruta (min) | Clima permitido | Envío | Condición de apertura |
|---|---|---|---|---|---|---|---|---|---|
| 0 | `parque_industrial` | Parque Industrial (galpón, hub) | zorra, autoelevador (solo herramientas) | — | 0 | — | soleado, nublado, lluvia | — | abierta |
| 1 | `centro` | Barrio Centro | bici, camioneta | `ChasingDog` (poco), `LowVisibilityEvent`; **nuevo**: tránsito, peatones, semáforos, calles angostas | 4-6 | 2-3 | soleado, nublado, lluvia, niebla | 40 | abierta |
| 2 | `suburbio` | Suburbio | camioneta, carrito | `ChasingDog`, `DogDistractPoint`; **nuevo**: barrios cerrados (timbre + portón), rociadores | 4-6 | 2-4 | soleado, nublado, lluvia | 50 | barrera: hito de 25 entregas |
| 3 | `campo` | Campo (chacras) | camioneta | `MudSpot`, `MudCrane`, `FlockCrossing`, `ChasingDog`, `LowVisibilityEvent`, ripio, badén, puente | 3-5 | 3-5 | soleado, nublado, lluvia, niebla | 60 | calle cortada (obra): hito de reputación 60 |
| 4 | `puerto` | Puerto y Costa | camioneta | `CargoGull`; **nuevo**: grúas, contenedores, marea | 3-5 | 3-5 | soleado, nublado, niebla | 70 | barrera portuaria: hito + licencia náutica |
| 5 | `islas` | Islas | lancha; carrito en tierra | `CargoGull`; **nuevo**: oleaje, marea, muelles | 3-4 | 3-5 | soleado, nublado, lluvia | 90 | agua: tener la lancha |
| 6 | `montana` | Montaña | avioneta para llegar; 4x4 y a pie arriba | `LowVisibilityEvent`; **nuevo**: cornisas, desprendimientos, pendientes, niebla de altura | 3-4 | 4-5 | soleado, nublado, niebla | 100 | altura: tener la avioneta |
| 7 | `nieve` | Nieve (pueblo de esquí y cumbre) | 4x4 con cadenas; avioneta con esquís | **nuevo**: hielo, frío en la carga, avalanchas, ventisca | 3-4 | 4-5 | nieve y ventisca (**nuevo**), soleado | 120 | equipo: cadenas + abrigo |
| 8 | `volcan` | Volcán | 4x4 hasta la base; avioneta (paracaídas) a la cumbre | **nuevo**: calor, lava, ceniza, temblores | 2-3 | 4-5 | ceniza y calor (**nuevo**) | 150 | equipo: traje térmico + cajas térmicas, y hito final |

## Lo que cambia en la caja, por zona

| Zona | Qué hace distinto el cuidado del paquete |
|---|---|
| Centro | Sacudidas cortas y paradas bruscas; el peatón obliga a frenar con la caja en las manos |
| Suburbio | Cada casa pide un paso extra (timbre, portón); el perro corre mientras se sostiene la caja |
| Campo | Lo de hoy: badenes, barro, animales |
| Puerto | La marea y las grúas cortan el camino; hay que esperar o rodear con la carga fría o pesada |
| Islas | El oleaje sacude todo a la vez (Líquido y Equilibrio pegan más) |
| Montaña | Pendientes: la carga se desliza; cornisas sin margen |
| Nieve | El frío daña lo sensible (producto frío al revés: se conserva); hielo en el volante |
| Volcán | El calor degrada lo que no va en caja térmica; hay que decidir qué llevar |

## Vehículo por zona (base de D-0309)

| Zona | camioneta | bici | carrito | 4x4 | lancha | avioneta |
|---|---|---|---|---|---|---|
| parque_industrial | ✔ (galpón) | ✔ | ✔ | ✔ | — | — |
| centro | ✔ | ✔ | ✔ | ✔ | — | — |
| suburbio | ✔ | ✔ | ✔ | ✔ | — | — |
| campo | ✔ | — | — | ✔ | — | — |
| puerto | ✔ | ✔ | ✔ | ✔ | ✔ (muelles) | — |
| islas | — | — | ✔ (en tierra) | — | ✔ | — |
| montana | — | — | — | ✔ (arriba) | — | ✔ |
| nieve | — | — | — | ✔ (cadenas) | — | ✔ (esquís) |
| volcan | — | — | — | ✔ (base) | — | ✔ (paracaídas) |

El vehículo para **llegar** a una zona lo fija su bloqueo; el de arriba es el vehículo para **entregar**
adentro. En F1 solo `parque_industrial`, `centro` y `campo` tienen datos completos (D-0205).

## Decisiones

- **Decisión: Centro con 4-6 casas y 2-3 min, Campo con 3-5 y 3-5 min.** El Campo de hoy dura 2-5 min y
  tiene menos casas porque hay más ruta entre ellas; el Centro es denso y corto.
- **Decisión: el envío crece con la lejanía** (40 → 150) porque la ruta es más larga y más peligrosa; es
  un número de partida para `sim_economy`, no un balance final.
- **Decisión: Volcán con 2-3 casas.** Es la zona final: pocas paradas, la tensión viene de la zona.
- **Decisión: el hito de Campo es "reputación 60"**; el de Suburbio, "25 entregas" (README). D-0118
  define los hitos y puede ajustar los números; los `gates` de la zona solo guardan el id.
