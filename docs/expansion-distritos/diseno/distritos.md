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
| 0 | `parque_industrial` | Parque Industrial (galpón, hub) | zorra, autoelevador (solo herramientas) | — | 0 | — | soleado, nublado, lluvia, niebla | — | abierta |
| 1 | `centro` | Barrio Centro | bici, camioneta | `ChasingDog` (poco), `LowVisibilityEvent`; **nuevo**: tránsito, peatones, semáforos, calles angostas | 4-6 | 2-3 | soleado, nublado, lluvia, niebla | 40 | abierta |
| 2 | `suburbio` | Suburbio | camioneta, carrito | `ChasingDog`, `DogDistractPoint`; **nuevo**: barrios cerrados (timbre + portón), rociadores | 4-6 | 2-4 | soleado, nublado, lluvia, niebla | 50 | barrera: hito de 25 entregas |
| 3 | `campo` | Campo (chacras) | camioneta | `MudSpot`, `MudCrane`, `FlockCrossing`, `ChasingDog`, `LowVisibilityEvent`, ripio, badén, puente | 3-5 | 3-5 | soleado, nublado, lluvia, niebla | 60 | calle cortada (obra): hito de reputación 60 |
| 4 | `puerto` | Puerto y Costa | camioneta | `CargoGull`; **nuevo**: grúas, contenedores, marea | 3-5 | 3-5 | soleado, nublado, lluvia, niebla | 70 | barrera portuaria: hito + licencia náutica |
| 5 | `islas` | Islas | lancha; carrito en tierra | `CargoGull`; **nuevo**: oleaje, marea, muelles | 3-4 | 3-5 | soleado, nublado, lluvia, niebla | 90 | agua: tener la lancha |
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
peligros) y el **clima del día** sale de la semilla. Revisado por `critico-diseno`. Decisión completa:
`docs/decisiones/2026-10-22-clima-por-zona.md`.

### Reglas

1. **Un clima por zona y por día, todo el día.** Se elige al abrir el día con una función pura
   `ZoneWeather.pick(company_seed, day, zone, day_event)` sobre `CompanySeed.for_day(company_seed, day,
   &"weather")` (corriente propia, para no correr los sorteos de pedidos). La semilla es la de la empresa,
   no `world_seed` (que cambia en cada sesión, D-0246): el mismo día guardado tiene el mismo clima al
   recargar. No cambia a mitad del día, **no se guarda** ([guardado.md](guardado.md)) y no necesita RPC
   (`company_seed` y el día ya viajan en el snapshot).
2. **Un frente para el llano.** Parque Industrial, Centro, Suburbio, Campo, Puerto e Islas comparten **una**
   tirada con las probabilidades de hoy (`WorldMood.WEATHER_ODDS`: 45 soleado, 25 nublado, 18 lluvia, 12
   niebla) y admiten los cuatro perfiles: el clima no corta en la esquina. Montaña, Nieve y Volcán tiran
   cada una por su lado con su tabla (`mood_profiles` + `mood_weights` del `.tres`; en el llano esos campos
   quedan vacíos).
3. **Manda el evento del día.** Si el día tiene un evento que fija el clima (la ola de calor fuerza
   `soleado`, [eventos-del-dia.md](eventos-del-dia.md) §12), gana el evento. **Días 1 a 3 sin lluvia ni
   niebla** (solo `soleado` o `nublado`), como la semana guiada sin eventos (eventos-del-dia.md §2.1).
4. **El clima nunca rompe una caja por sí solo.** Multiplica riesgos que ya existen (agarre, oleaje,
   visibilidad). `soleado` y `nublado` no cambian nada del juego, solo la luz.
5. **La jugabilidad lee la zona del vehículo, nunca `WorldMood.active`.** El host aplica los efectos según la
   zona de la posición de cada vehículo (`ZoneDefinition.bounds`), aunque simule vehículos lejos de su
   cámara; cada peer hace lo mismo con su copia de predicción. La presentación sigue siendo **un perfil
   global** como hoy (el del llano mientras solo haya llano abierto); el cruce entre zonas de distinto clima
   llega con la primera zona de altura (D-1610).
6. **Adentro del galpón no hay clima**, y el autoelevador y la zorra no lo sienten. Afecta a camioneta, 4x4,
   bici, carrito, lancha y avioneta.
7. **Entrega y Endless no cambian**: su `WorldMood` sigue siendo solo cosmético. Todo esto es del modo
   Empresa, y es **Ampliación de F1**: el corte vertical (camioneta de hoy, sin cambios de manejo,
   [corte-vertical.md](corte-vertical.md) §2) y su bot no dependen del clima.

### Clima del día: qué hace cada perfil

El agarre es un **multiplicador** del `wheel_friction_slip` base de cada vehículo (no un valor absoluto:
`GripZones` se queda con el mínimo, y con un número fijo un 4x4 perdería más y una bici nada). Entra por
`GripZones` con la fuente `weather` al salir del galpón y sale al volver; ripio y barro siguen mandando
cuando son más bajos.

| Perfil | Zonas | Vehículo | Carga | Visibilidad | Llega con |
|---|---|---|---|---|---|
| `soleado` | todas | — | — | — | existe |
| `nublado` | llano, Montaña | — | — | luz más baja | existe |
| `lluvia` | llano | agarre ×`WEATHER_RAIN_GRIP_MULT` 0,75 (camioneta 3,5 → 2,6) | en Islas, oleaje ×`WEATHER_RAIN_SWELL` 1,5 (D-1321) | gotas en el parabrisas (existe) | D-0324 |
| `niebla` | llano, Montaña | — | — | niebla densa (existe) | existe |
| `nevada` (**nuevo**) | Nieve | agarre ×`WEATHER_SNOW_GRIP_MULT` 0,45 fuera de los tramos de hielo (en hielo manda D-1611) | — | copos, niebla media | D-1610 |
| `ventisca` (**nuevo**) | Nieve | lo de `nevada` + empuje lateral (D-1617) | — | niebla densa | D-1617 |
| `ceniza` (**nuevo**) | Volcán | — | — | niebla gris y parabrisas sucio (D-1706) | D-1715 |

Tablas de las zonas de altura (suman 100): **Montaña** soleado 50, nublado 25, niebla 25; **Nieve** soleado
40, nevada 40, ventisca 20; **Volcán** soleado 60, ceniza 40. La niebla de Montaña es solo la de
`WorldMood`; la `LowVisibilityEvent` de altura (D-1605) es una variante aparte, no se apila con el clima.

**Medida de la lluvia** (test headless de D-0324): distancia de frenado desde 50 km/h y velocidad máxima en
una curva fija, en seco y con lluvia. Si la diferencia es menor al 10 %, el multiplicador baja a 0,65.

### Temperatura de la zona: qué le pasa a la carga

Se aplica **por salida**, con la zona de destino del despacho: `ColdPack.holds(box, trip_minutes ×
tasa)` y lo mismo en `ice_needed()`, para que el tutorial y los bots sigan sugiriendo cuánto hielo poner.

| Temperatura | Zonas | Producto `frío` (conservadora D-0721) | Producto `calor` |
|---|---|---|---|
| `templada` | todas menos Nieve y Volcán | ×1 | — |
| `fria` | Nieve | ×0: no hace falta hielo | se enfría ×`ZONE_COLD_HOT_RATE` 2 (`hot_stew_pot`, `thermal_soup`; D-0738) |
| `caliente` | Volcán | ×`ZONE_HOT_COLD_RATE` 2 sin caja térmica (D-0722, D-1703) | — (sus productos `calor` son de ahí) |

Con la ola de calor (evento 12, ×2 en la ruta) se toma **el máximo** de las dos tasas, no el producto: ×4
con el tope de hielo (`ICE_PACKS_MAX`) dejaría pedidos fríos imposibles.

### Quién lo construye

- **D-0324** (Ampliación F1, la versión mínima): `ZoneWeather.pick` con la semilla de la empresa, el frente
  del llano, el evento que gana y los días 1-3; `mood_weights` y `temperature` en `ZoneDefinition` y los
  `.tres` (el llano con los cuatro perfiles); el agarre de lluvia por `GripZones`; la línea de la Jefa a la
  apertura ("Hoy llueve en el llano") y una línea en el portapapeles (D-1902). Tests: misma semilla y día →
  mismo clima en todas las zonas del llano; días 1-3 sin lluvia; ola de calor → `soleado`; un vehículo con
  lluvia pierde agarre y lo recupera al entrar al galpón; la medida de frenado de arriba.
- **D-1610**: el cruce de presentación entre zonas (`WEATHER_BLEND_SECONDS` 8 s) y la línea por zona del
  pronóstico en el tablero, cuando haya zonas de altura. **D-1617, D-1715, D-1321**: sus perfiles y efectos.
- **D-0738, D-0722, D-1703**: la temperatura de la carga, con la tabla de arriba.
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
- **Decisión: el llano admite los cuatro perfiles en todas sus zonas** (D-0135): Puerto sin lluvia y
  Parque, Suburbio e Islas sin niebla cortaban el frente compartido. La columna "Clima permitido" lo dice.
- **Decisión: Volcán no tiene un clima `calor`**: el calor es la temperatura de la zona, siempre presente;
  el clima variable de Volcán es `ceniza` (D-0135).
