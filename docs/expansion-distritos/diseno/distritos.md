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
| 7 | `nieve` | Nieve (pueblo de esquí y cumbre) | 4x4 con cadenas; avioneta con esquís | **nuevo**: hielo, frío en la carga, avalanchas, ventisca | 3-4 | 4-5 | nevada y ventisca (**nuevo**), soleado | 120 | equipo: cadenas + abrigo |
| 8 | `volcan` | Volcán | 4x4 hasta la base; avioneta (paracaídas) a la cumbre | **nuevo**: calor, lava, ceniza, temblores | 2-3 | 4-5 | ceniza (**nuevo**), soleado; calor fijo de la zona | 150 | equipo: traje térmico + cajas térmicas, y hito final |

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

## Clima y temperatura por zona (D-0135)

Dos capas que no se mezclan: la **temperatura de la zona** es fija (es parte de la zona, como sus
peligros) y el **clima del día** sale de la semilla. Decisión completa:
`docs/decisiones/2026-10-22-clima-por-zona.md`.

### Reglas

1. **Un clima por zona y por día, todo el día.** Se elige al abrir el día con una función pura
   `ZoneWeather.pick(world_seed, day, zone)`: misma semilla y mismo día dan el mismo clima en todas las
   máquinas, sin RPC. No cambia a mitad del día y **no se guarda** (sale de la semilla, como el libro de
   pedidos en [guardado.md](guardado.md)).
2. **Un frente para el llano.** Parque Industrial, Centro, Suburbio, Campo, Puerto e Islas comparten **una**
   tirada (con las probabilidades de hoy de `WorldMood.WEATHER_ODDS`: 45 soleado, 25 nublado, 18 lluvia,
   12 niebla); si el perfil no está permitido en la zona, baja a `nublado`. Así no llueve en el portón y
   hay sol en la esquina. Montaña, Nieve y Volcán tiran cada una por su lado con su tabla (abajo).
3. **Pronóstico a la vista.** A la apertura la Jefa lo dice en el feed ("Hoy llueve en el llano") y el
   tablero y el portapapeles (D-1902) muestran una línea por zona abierta. El clima es información para
   decidir a dónde ir primero y con qué, no una sorpresa.
4. **El clima nunca rompe una caja por sí solo.** Multiplica riesgos que ya existen (agarre, visibilidad,
   oleaje, empuje). `soleado` y `nublado` no cambian nada del juego, solo la luz.
5. **Manda la zona donde está el vehículo.** El host aplica los efectos según la zona de la posición del
   vehículo (los rectángulos de `ZoneDefinition.bounds`); cada peer hace lo mismo con su copia de
   predicción, porque todo sale de la semilla y la posición, que ya se replican. La presentación (cielo,
   niebla, lluvia) sigue a la cámara local y cruza de una zona a otra en `WEATHER_BLEND_SECONDS` (8 s).
6. **Adentro del galpón no hay clima**, y el autoelevador y la zorra no lo sienten (son del galpón y el
   patio). Afecta a camioneta, 4x4, bici, carrito, lancha y avioneta.
7. **Entrega y Endless no cambian**: su `WorldMood` sigue siendo solo cosmético. Todo esto es del modo
   Empresa.

### Clima del día: qué hace cada perfil

| Perfil | Zonas | Vehículo | Carga | Visibilidad | Llega con |
|---|---|---|---|---|---|
| `soleado` | todas | — | — | — | F1 (existe) |
| `nublado` | llano, Montaña | — | — | luz más baja | F1 (existe) |
| `lluvia` | llano menos Puerto | agarre en calle `WEATHER_RAIN_SLIP` 2,6 (hoy 3,5; ripio 1,1 y barro 1,2 siguen mandando) por `GripZones` con la fuente `weather` | en Islas, oleaje ×`WEATHER_RAIN_SWELL` 1,5 (D-1321) | gotas en el parabrisas (existe) | F1 (agarre: D-0324) |
| `niebla` | Centro, Campo, Puerto, Montaña | — | — | niebla densa (existe); en Montaña la `LowVisibilityEvent` de altura sale ×1,5 más seguido (D-1605) | F1 (existe) |
| `nevada` (**nuevo**) | Nieve | agarre `WEATHER_SNOW_SLIP` 1,6 fuera de los tramos de hielo (en hielo manda D-1611) | — | copos, niebla media | F3 (D-1610) |
| `ventisca` (**nuevo**) | Nieve | lo de `nevada` + empuje lateral (D-1617) | — | niebla densa | F3 (D-1617) |
| `ceniza` (**nuevo**) | Volcán | — | — | niebla gris y parabrisas sucio (D-1706) | F4 (D-1715) |

Tablas propias de las zonas de altura (suman 100): **Montaña** soleado 50, nublado 25, niebla 25;
**Nieve** soleado 40, nevada 40, ventisca 20; **Volcán** soleado 60, ceniza 40. Van como
`mood_weights` en el `.tres` de la zona, al lado de `mood_profiles`.

### Temperatura de la zona: qué le pasa a la carga

| Temperatura | Zonas | Producto `frío` (conservadora D-0721, heladera D-0616) | Producto `calor` |
|---|---|---|---|
| `templada` | todas menos Nieve y Volcán | reloj normal (×1) | sin efecto hasta D-0738 |
| `fria` | Nieve | el reloj de la conservadora se **frena** (×0): el frío se conserva | se enfría ×`ZONE_COLD_HOT_RATE` 2 (D-0738) |
| `caliente` | Volcán | el reloj corre ×`ZONE_HOT_COLD_RATE` 2 sin caja térmica (D-0722, D-1703) | se conserva (×0) |

La temperatura se aplica al tiempo de viaje que cuenta `ColdPack.holds()` (minutos dentro de la zona ×
multiplicador). La ola de calor (evento 12) es aparte y se multiplica con esto.

### Quién lo construye

- **D-0324**: `ZoneWeather.pick` (pura, con el frente del llano y la baja a `nublado`), `mood_weights` y
  `temperature` en `ZoneDefinition` y en los `.tres`, el cruce de presentación entre zonas, el agarre de
  `lluvia` por `GripZones` y la línea de la Jefa. Test: misma semilla y día → mismo clima; Puerto nunca
  tiene `lluvia`; un vehículo en lluvia pierde agarre y lo recupera al salir de la zona o al entrar al
  galpón.
- **D-1902** (portapapeles) y el tablero: la línea del pronóstico.
- **D-1610, D-1617, D-1715, D-1321, D-1605**: los perfiles y efectos nuevos de su zona, con estas tablas.
- **D-0738, D-0722, D-1703**: la temperatura de la carga.
- Los números van a `company_tuning.gd` con estos nombres, nunca sueltos en el código.

## Decisiones

- **Decisión: Centro con 4-6 casas y 2-3 min, Campo con 3-5 y 3-5 min.** El Campo de hoy dura 2-5 min y
  tiene menos casas porque hay más ruta entre ellas; el Centro es denso y corto.
- **Decisión: el envío crece con la lejanía** (40 → 150) porque la ruta es más larga y más peligrosa; es
  un número de partida para `sim_economy`, no un balance final.
- **Decisión: Volcán con 2-3 casas.** Es la zona final: pocas paradas, la tensión viene de la zona.
- **Decisión: el hito de Campo es "reputación 60"**; el de Suburbio, "25 entregas" (README). D-0118
  define los hitos y puede ajustar los números; los `gates` de la zona solo guardan el id
  (resultado en [hitos.md](hitos.md): se mantienen los dos números).
- **Decisión: clima por zona con un frente compartido para el llano** (D-0135). Un clima independiente por
  zona da cortes absurdos en un mapa continuo; uno solo para todo el mapa no deja que Nieve y Volcán tengan
  el suyo.
- **Decisión: Volcán no tiene un clima `calor`**: el calor es la temperatura de la zona, siempre presente;
  el clima variable de Volcán es `ceniza` (D-0135).
