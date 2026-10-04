# Expansión: distritos, flota y negocio — backlog de 1000 tareas

> Pedido del usuario (2026-10-04). Nuevo alcance: el juego pasa de "una entrega por corrida" a
> **una empresa de reparto que crece**: recibir mercadería, **armar** los paquetes según lo que pide
> cada cliente, entregarlos en **distritos** que se desbloquean por hitos (islas, montaña, nieve,
> volcán…), con **vehículos nuevos** (bici, carrito, lancha, avioneta) y un **galpón que se
> automatiza** con empleados y máquinas (inspirado en *Schedule I*).
>
> **Estado: en construcción (desde 2026-10-04).** La trabajan cinco rutinas `desarrollador`
> (`.claude/rutinas/desarrollador.md`), una por carril, cada 2 o 3 h y escalonadas (horarios en `.claude/rutinas/README.md`). Las decisiones de cómo se
> hace las toman ellas y quedan en `docs/decisiones/`. Lo que hay que probar a mano o revisar queda en
> `revisar/` para el final. El detalle de las tareas está en `detalle/`.

## La idea en una pantalla

> Versión larga, con qué se conserva del juego actual y qué **no** es: [diseno/vision.md](diseno/vision.md) (D-0101).

**Bucle del día (un turno de juego, 15-25 min reales):**

1. **Llega mercadería.** Camiones de proveedores entran al patio del galpón; hay que descargar
   palets y guardar productos en estanterías (stock).
2. **Entran pedidos.** Clientes de los distritos desbloqueados piden combinaciones de productos con
   requisitos (frágil, frío, regalo, urgente, pesado).
3. **Se arman los paquetes.** Elegir caja del tamaño justo, meter los productos correctos, relleno,
   cinta, etiqueta y sellos. **Lo que se arma define la trampa del viaje**: una caja grande con poco
   relleno se sacude; vidrio sin burbuja es Frágil; un helado sin conservadora es Líquido. Así el
   corazón actual del juego (cada pasajero cuida su caja) sigue intacto y gana una etapa previa.
4. **Se despacha y se entrega.** Cargar el vehículo que pide el distrito (camioneta, bici, carrito,
   lancha, avioneta) y hacer la ruta con sus peligros propios. La puerta del cliente revisa el
   paquete como hoy.
5. **Cierre del día.** Cobros, sueldos, reputación, hitos. Con la plata: ampliar galpón, contratar,
   comprar máquinas y vehículos, sacar licencias para distritos nuevos.

**Crecimiento (estilo Schedule I):** al principio la tripulación hace todo a mano. Después se
contratan empleados y se les asigna una estación (descarga, picking, armado, control, despacho) con
un portapapeles; luego se compran cintas, encintadoras, etiquetadoras, clasificadores y robots.
Los jugadores pasan de "hacer cada caja" a "diseñar el galpón y salir a las entregas difíciles".

## Distritos: un solo mapa continuo

**Decidido por el usuario (2026-10-04, `docs/decisiones/2026-10-04-mapa-continuo.md`):** el mundo es
**un mapa continuo** con trazado fijo (≤ 6 × 6 km, el galpón cerca del centro). Las zonas se abren con
barreras y calles cortadas (hitos), agua (lancha), equipo (Nieve y Volcán) y altura (avioneta para las
montañas). No hay pantallas de carga entre zonas.

| # | Zona | Vehículo para moverse adentro | Peligros propios | Qué la bloquea / se abre con |
|---|---|---|---|---|
| 0 | **Parque Industrial** (el galpón, hub) | — (zorra, autoelevador) | — | abierta |
| 1 | **Barrio Centro** | bici, camioneta | tránsito, calles angostas, peatones, semáforos | abierta |
| 2 | **Suburbio** | camioneta, carrito | perros, barrios cerrados, rociadores | **barrera**: hito de 25 entregas |
| 3 | **Campo** (las chacras, ripio, barro y animales de hoy) | camioneta | lo que ya existe | **calle cortada** (obra): hito de reputación |
| 4 | **Puerto y Costa** | camioneta | grúas, contenedores, marea | **barrera** portuaria: hito + licencia náutica |
| 5 | **Islas** | lancha; carrito en tierra | oleaje, marea, muelles, gaviotas | **agua**: tener la lancha |
| 6 | **Montaña** | avioneta para llegar; a pie/4x4 arriba | cornisas, desprendimientos, pendientes, niebla | **altura**: tener la avioneta |
| 7 | **Nieve** (pueblo de esquí y cumbre) | 4x4 con cadenas, avioneta con esquís | hielo, frío en la carga, avalanchas, ventisca | **equipo**: cadenas + abrigo |
| 8 | **Volcán** | 4x4 hasta la base; avioneta (paracaídas) a la cumbre | calor, lava, ceniza, temblores | **equipo**: traje térmico + cajas térmicas, y hito final |

## Fases (el orden importa más que el número de tareas)

| Fase | Objetivo | Grupos (núcleo primero) |
|---|---|---|
| **F0 — Base** | Decisiones, arquitectura, guardado de empresa, multi-vehículo. Sin contenido nuevo visible. | 01, 02, 20 (núcleo) |
| **F1 — Corte vertical** | Un día completo jugable: proveedor → stock → pedido → armado → camioneta → Barrio Centro → cierre del día. Con el arte gris. | 03, 05, 06, 07, 08, 09 (núcleo) |
| **F2 — Crecer** | Hitos y desbloqueos, empleados, primeras máquinas, Suburbio y Campo, bici y carrito. | 04, 10, 11, 12, 15 |
| **F3 — Agua y altura** | Lancha, Puerto, Islas; Montaña y Nieve. | 13, 16 |
| **F4 — Aire y fuego** | Avioneta, aeródromos, Volcán. | 14, 17 |
| **F5 — Contenido y lanzamiento** | Modelos finales, UI, audio, VFX, rendimiento, Steam. | 18, 19, 20 |

Regla: **no se arranca F2 sin el corte vertical de F1 cerrado y medido** (bots y benchmarks, no
playtesting; ver memoria "playtesting al final").

## Grupos

| Grupo | Archivo | Tema |
|---|---|---|
| 01 | [01-diseno-y-decisiones.md](01-diseno-y-decisiones.md) | Diseño, decisiones del usuario, agentes nuevos |
| 02 | [02-arquitectura.md](02-arquitectura.md) | Arquitectura, datos, guardado, módulos |
| 03 | [03-mapa-y-distritos.md](03-mapa-y-distritos.md) | Mapa del mundo, viajes y sistema de distritos |
| 04 | [04-progresion-e-hitos.md](04-progresion-e-hitos.md) | Hitos, reputación, licencias y desbloqueos |
| 05 | [05-economia.md](05-economia.md) | Plata, costos, precios, crecimiento y balance |
| 06 | [06-mercaderia-y-stock.md](06-mercaderia-y-stock.md) | Proveedores, descarga, stock e inventario |
| 07 | [07-armado-de-paquetes.md](07-armado-de-paquetes.md) | La estación de armado y la calidad del paquete |
| 08 | [08-pedidos-de-clientes.md](08-pedidos-de-clientes.md) | Generación, tipos y requisitos de pedidos |
| 09 | [09-galpon-construible.md](09-galpon-construible.md) | Modo construcción, ampliaciones y layout |
| 10 | [10-empleados.md](10-empleados.md) | Contratación, roles, IA, sueldos y moral |
| 11 | [11-automatizacion.md](11-automatizacion.md) | Cintas, máquinas, clasificadores y robots |
| 12 | [12-flota-bici-carrito.md](12-flota-bici-carrito.md) | Base común de vehículos, garaje, bici y carrito |
| 13 | [13-lancha-e-islas.md](13-lancha-e-islas.md) | Lancha, agua, Puerto e Islas |
| 14 | [14-avioneta-y-aerodromos.md](14-avioneta-y-aerodromos.md) | Avioneta, vuelo, pistas y lanzamientos |
| 15 | [15-distritos-de-tierra.md](15-distritos-de-tierra.md) | Barrio Centro, Suburbio, Campo y Puerto en tierra |
| 16 | [16-montana-y-nieve.md](16-montana-y-nieve.md) | Montaña y Nieve |
| 17 | [17-volcan.md](17-volcan.md) | Volcán |
| 18 | [18-modelos-y-arte.md](18-modelos-y-arte.md) | Modelos 3D, texturas y arte compartido |
| 19 | [19-ui-audio-vfx.md](19-ui-audio-vfx.md) | UI, tutorial, audio y efectos |
| 20 | [20-red-calidad-lanzamiento.md](20-red-calidad-lanzamiento.md) | Red, rendimiento, QA, tests, Steam |

Cada grupo tiene 50 tareas en tres bloques: **Núcleo** (lo mínimo para su fase), **Ampliación**
(suma valor claro) y **Pulido**. Los modelos 3D de cada vehículo y distrito están en su propio grupo;
el 18 junta el arte compartido (productos, cajas, empleados, máquinas, bibliotecas de props).

## Cómo leer las tareas

- **ID** `D-GGNN`: grupo `GG`, tarea `NN` (D-0712 = grupo 07, tarea 12). Sin choque con `N-`/`S-`.
- **Agente**: el que la construye según la tabla de `CLAUDE.md`. `constructor-negocio` es un agente
  nuevo (lo crea D-0141) para galpón, stock, armado, empleados y automatización; hasta que exista,
  esas tareas van con `constructor-mundo` (galpón) o `constructor-progresion` (plata y pedidos).
  `*` = necesita Blender/ComfyUI en la PC (rutina `sesion-arte`).
- **Esf.**: esfuerzo de razonamiento (`low` · `medium` · `high` · `xhigh`), como en `tareas-nacho.md`.
- **Hecho cuando**: criterio verificable con test, captura, bot o benchmark. Nada se marca por
  sensación de juego; lo que necesita gente jugando está marcado ⏸ playtesting y no se hace ahora.
- **⏸ decide el usuario**: decisión que tiene que tomar el usuario antes de construir lo que depende.
- Los tests nuevos siguen la skill `nuevo-test`; las capturas van con `revisor-visual`.

## Cómo avanza

Las rutinas `desarrollador` toman tareas de `detalle/` y de las tablas de grupo, por carril y por fase
(F0 → F5). Si una tarea no tiene detalle, primero lo escriben, en el mismo PR. No se pasan a
`docs/tareas-nacho.md`: esa lista sigue siendo de la rutina de construcción.

## Dueño: Nacho (las 1000)

Pedido del usuario (2026-10-04): **todas las tareas de esta carpeta son de Nacho**; ninguna va a
`docs/tareas-slatex.md`. Cuando una toca archivos de Slatex se hace igual, sin esperarlo, con el aviso
en `docs/avisos/` en el mismo commit (como ya se trabajan las `S-xxx` heredadas): armado y contenido del
paquete (`scripts/gameplay/package/`), jugador (`scripts/gameplay/player/`), UI (`scripts/ui/`) y
progresión heredada. `run_manager.gd`, `network_manager.gd`, `event_bus.gd` y `modules/` son zona
compartida. `guardian-dominios` antes de cada PR que cruce carpetas.
