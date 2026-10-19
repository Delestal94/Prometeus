# Crítica de alcance de la expansión contra la capacidad del equipo (D-0112)

> Pasada de `critico-diseno` a los 20 grupos (`NN-*.md`) contra lo que el equipo puede construir de verdad. Se aplica el límite de la fila 5 de
> [decisiones delegadas](../../decisiones/2026-10-04-expansion-decisiones-delegadas.md) (D-0113): **no se recorta nada de lo que nombró el usuario**.
> Fuentes: [vision.md](vision.md), [corte-vertical.md](corte-vertical.md), [roles-tripulacion.md](roles-tripulacion.md),
> [referencia-schedule-1.md](referencia-schedule-1.md), [referencias-logistica.md](referencias-logistica.md),
> [supuestos.md](../detalle/supuestos.md), `docs/decisiones/2026-10-*.md`, [plan-desarrollo.md](../../plan-desarrollo.md).
> Los conteos se tomaron de las tablas el 2026-10-19. Los recortes de §7 ya están tachados en las tablas de grupo
> (decisión [2026-10-19-recortes-expansion](../../decisiones/2026-10-19-recortes-expansion.md)).

## Resumen

**Veredicto: CONSTRUIR CON CAMBIOS.** Hay que aplicar los recortes de §4, arrancar ya el arte de la PC (no esperar a F5) y pedirle al usuario que decida qué parte de la expansión llega al Early Access.

- Las tablas tienen **1000 tareas** (20 × 50): 87 hechas (8 son decisiones sin trabajo), 3 a medias (◐) y **913 abiertas**.
- **Ritmo medido.** Las 87 cerradas desde el 2026-10-04 equivalen a unas 55 corridas por día con su mezcla de esfuerzo. Lo abierto son unas 6 350 corridas en la nube:
  - **16,5 semanas** en el mejor caso (2027-02-11);
  - unas 25 semanas aplicando un margen de 1,5 por la física y la red nuevas (2027-04-09);
  - contando tareas a 5 por día, 183 días (2027-04-20);
  - aparte, unos **510 assets** en la única rutina de la PC.
- **Los recortes sacan 287 IDs**: 42 se recortan, 148 se posponen a post-lanzamiento y 97 se fusionan con otra tarea. Quedan **626 abiertas**.
- **Ahorro: alrededor del 20 % del esfuerzo.** Son unas 58 de 328 semanas-persona y unas 1 250 corridas, más unas 110 corridas de la PC.
  - Mejor caso: 2027-01-20.
  - Caso realista: **2027-03-08**, cuatro días antes del Early Access (2027-03-12). No queda lugar para la revisión de build de Steam ni para el playtesting que quedó al final.
- **El ahorro es chico porque lo caro es justo lo que pidió el usuario**: tres vehículos con física nueva, nueve zonas, empleados con IA en red y automatización. Eso no se toca. Las palancas que quedan son dos:
  - el **orden**: arte en paralelo desde ya;
  - el **alcance del Early Access**: ⏸ decide el usuario, porque la fecha y la página de Steam son suyas.

## 1. Cómo se midió

| Unidad | Definición |
|---|---|
| **SPH** (semana-persona humana equivalente) | 5 días de una persona que conoce Godot y este repo, a tiempo completo. Pesos por esfuerzo: low 0,5 día, medium 1,5, high 3, xhigh 6. Sirve para comparar tamaños, no para planificar a humanos: la expansión la construyen las rutinas. |
| **Corridas de rutina (nube)** | low 3, medium 6, high 12, xhigh 20. **Calibración**: las 87 hechas (14 xhigh, 30 high, 27 medium, 8 low y 8 decisiones) suman 826 corridas-equivalentes en 15 días, o sea 55 por día. Es la capacidad nominal (5 carriles × 8-12 corridas). |
| **Corridas de PC** | Una por asset (un modelo, una textura, un clip o un ícono), contados del "Hecho cuando" de cada tarea con `*`. Ritmo útil: 6 a 10 por día, con una corrida cada 2 h y la PC no siempre prendida. |
| **Fusión** | Ahorra un tercio de la tarea fundida (PR, detalle y test aparte). El resto del trabajo pasa a la tarea destino. |
| **Margen 1,5** | Cubre la física y el terreno nuevos, con 11 tareas xhigh: D-1207, D-1301, D-1302, D-1304, D-1310, D-1401, D-1404, D-1411, D-1420, D-1608 y D-1711. Cada una tiene un "bot que lo hace 10 veces sin fallar" como cierre. También cubre el playtesting diferido, que esconde retrabajo. |

Las tareas que quedan son **más livianas en promedio** que las hechas: 1,8 contra 2,5 días-persona por tarea, porque lo hecho fue el núcleo F0/F1. Por eso la cuenta por esfuerzo (115 días) da menos que la cuenta por tareas (183 días). La verdad está entre las dos, y el margen 1,5 cubre esa diferencia.

## 2. Estimación por grupo

R/P/F = recortar / posponer / fusionar (§4). SPH y corridas, antes → después de los recortes.

| Grupo | Fase | Abiertas | R/P/F | Quedan | SPH | Corridas nube | Corridas PC (assets) | Cuello de botella | Riesgo |
|---|---|---|---|---|---|---|---|---|---|
| 01 Diseño | F0 | 33 | 3/2/1 | 27 | 9,5 → 8,3 | 198 → 172 | — | diseño | bajo |
| 02 Arquitectura | F0 | 36 | 3/4/13 | 16 | 16,4 → 10,9 | 321 → 211 | — | código (base de vehículo: D-0208, D-0209 xhigh) | medio |
| 03 Mapa | F1/F2 | 48 | 3/9/7 | 29 | 22,8 → 17,9 | 446 → 345 | 10 → 9 | código + red (D-0304, D-0305, D-0316, D-0318 xhigh) | alto |
| 04 Hitos | F2 | 50 | 1/8/7 | 34 | 16,5 → 13,2 | 341 → 272 | 30 → 0 | código (D-0408 toca `UnlockManager` de Slatex) | medio |
| 05 Economía | F1/F2 | 42 | 4/12/1 | 25 | 12,7 → 9,3 | 266 → 190 | — | balance (falta `sim_economy`, D-0540) | bajo |
| 06 Stock | F1 | 45 | 2/14/4 | 25 | 17,0 → 12,6 | 343 → 247 | — | código + red (D-0606, D-0619 xhigh) | medio |
| 07 Armado | F1 | 38 | 2/4/1 | 31 | 14,4 → 12,2 | 290 → 243 | — | red (D-0715 xhigh) + dominio de Slatex (trampas) | medio |
| 08 Pedidos | F1/F2 | 46 | 2/16/4 | 24 | 11,1 → 7,2 | 240 → 152 | 26 → 8 | datos | bajo |
| 09 Galpón | F1/F2 | 36 | 1/8/8 | 19 | 11,0 → 7,5 | 231 → 156 | 15 → 0 | código | bajo |
| 10 Empleados | F2 | 50 | 1/8/3 | 38 | 18,4 → 16,6 | 376 → 334 | 13 → 13 | IA + red (D-1012 xhigh) + animaciones | alto |
| 11 Automatización | F2 | 50 | 2/8/4 | 36 | 17,7 → 14,9 | 354 → 294 | 22 → 22 | red (D-1115 xhigh) + rendimiento (D-1102) | alto |
| 12 Bici y carrito | F2 | 50 | 1/5/1 | 43 | 20,7 → 17,9 | 415 → 357 | 5 → 5 | física (D-1207) + red (D-1213, D-1225) | alto |
| 13 Lancha e Islas | F3 | 50 | 5/6/6 | 33 | 20,4 → 17,1 | 404 → 332 | 9 → 9 | agua en GL Compatibility (D-1301) + física (D-1302) + red (D-1304) | muy alto |
| 14 Avioneta | F4 | 50 | 6/6/3 | 35 | 19,7 → 17,1 | 392 → 332 | 2 → 2 | vuelo (D-1401, D-1420) + terreno (D-1411) + red (D-1404) | muy alto |
| 15 Tierra | F1/F2 | 50 | 0/11/5 | 34 | 17,4 → 15,2 | 355 → 303 | 44 → 24 | tránsito NPC (D-1504) + kits de arte | alto |
| 16 Montaña y Nieve | F3 | 50 | 2/10/7 | 31 | 18,9 → 15,2 | 385 → 303 | 16 → 16 | terreno (D-1608) + arte | alto |
| 17 Volcán | F4 | 50 | 2/6/12 | 30 | 16,7 → 14,6 | 340 → 290 | 8 → 8 | terreno (D-1711) + shader de lava (D-1712) | alto |
| 18 Modelos y arte | F1-F5 | 50 | 0/3/5 | 42 | 17,4 → 16,5 | 57 → 53 | ≈ 310 → ≈ 284 | **PC (un solo carril)** | alto |
| 19 UI, audio, VFX | F1-F5 | 50 | 1/7/3 | 39 | 14,7 → 12,7 | 308 → 265 | — | UI (dominio de Slatex; D-1902 xhigh) | medio |
| 20 Red y lanzamiento | F0/F5 | 39 | 1/1/2 | 35 | 14,1 → 12,3 | 287 → 255 | — | red (D-2002 sin medir) + QA | medio |
| **Total** | | **913** | **42/148/97** | **626** | **327,5 → ≈ 269** | **≈ 6 350 → ≈ 5 100** | **≈ 510 → ≈ 400** | | |

Lectura:

- **Para cerrar el corte faltan unas 37 tareas** del §2 de [corte-vertical.md](corte-vertical.md), más D-1501 (Barrio Centro en gris). Son unas 410 corridas: entre una y dos semanas al ritmo medido. El corte puede cerrar a principios de noviembre.
- **Lo más caro que queda son los grupos 03, 12, 13 y 14**: mapa continuo y vehículos con física propia. Son núcleo protegido y no bajan con recortes. Solo bajan si se construyen más barato (§4.5).
- **Arte**:
  - Con la PC a 6-10 assets por día, los unos 400 assets que quedan son 40 a 67 días, más un 25 % de retoques (D-1843, D-1844).
  - Si el arte arranca ahora, en paralelo, entra.
  - Si espera a F5, que en el mejor caso empieza en febrero, termina entre abril y mayo.

## 3. Las tres features con peor costo/valor

### 3.1 Tránsito NPC con IA en Barrio Centro (CONSTRUIR CON CAMBIOS)

**Cuánto cuesta.** D-1504 (xhigh), D-1505 (high), D-1503 (high), D-1515 (high) y D-1549 (high) suman unos 18 días-persona (3,6 SPH) y unas 68 corridas. A eso se le agrega un costo de red permanente: autos que el host simula y replica, con 8 jugadores y hasta 2 vehículos propios fuera del galpón (mapa continuo, punto 6).

**Evidencia:**
- [plan-desarrollo.md](../../plan-desarrollo.md), "Fuera del MVP", ya descartó "Tráfico en movimiento (autos con IA de waypoints)" por IA, colisión dinámica y playtesting propio.
- [vision.md](vision.md) §9 dice: "No es un simulador de tráfico".

**Qué aporta.** Es el peligro que define a Barrio Centro, una zona protegida.

**Versión mínima.** Tránsito **en rieles y determinista**:
- autos que recorren aristas del grafo de calles con un horario calculado del reloj del host (D-0219, hecha), así que cada cliente los calcula solo y no hay nada que replicar;
- sin evitación ni IA;
- un choque cuenta como un bache fuerte para la carga (mide igual que D-1511).
- D-1504 baja a medium y D-1549 a low. Ahorra unos 10 días-persona sin sacar el tránsito.

### 3.2 Repartidores, choferes y pilotos NPC (zona gris; recomendación: POSPONER)

**Cuánto cuesta.** D-1027 (high), D-1028 (high), D-1037 (medium), D-1239 (medium) y D-1440 (low) son unos 9,5 días-persona y unas 39 corridas, más su balance.

**Qué aporta: valor negativo.**
- Entregan sin la tripulación, que es el núcleo del juego. [referencia-schedule-1.md](referencia-schedule-1.md) §8, punto 5, lo dice así: "El repartidor NPC come el núcleo".
- Una salida automática a un distrito ya dominado es ingreso pasivo. Es exactamente la estrategia degenerada que D-0543 tiene que impedir.
- Rompe la regla de 2 min de [roles-tripulacion.md](roles-tripulacion.md) §1: si el NPC entrega, el jugador mira.

**Por qué no se tacha.** Son "empleados" en sentido amplio (fila 5). Queda en §4.4 para que decida el usuario.

**Versión mínima, si se quieren.** Que solo lleven pedidos **sin trampa** y **paguen la mitad**. Así la entrega difícil sigue siendo siempre de la tripulación.

### 3.3 Módulos portables extraídos que nadie reutiliza (FUSIONAR / POSPONER)

**Cuánto cuesta.** D-0221, D-0222, D-0224, D-0225, D-0227, D-0228, D-0229 (high), D-0226 (xhigh), D-0230 (medium) y D-0250 (low) son unos 29 días-persona (5,8 SPH) y unas 113 corridas. Además, cada módulo suma para siempre una pasada de `portability-check.sh` en CI.

**Qué aporta al jugador: nada.**
- D-0221, D-0222 y D-0225 extraen código que **ya anda** en `scripts/gameplay/business/` (`inventory.gd`, `order_book.gd`, `build_placement.gd`), sin cambiar la API (decisión [2026-10-12-modulos-expansion](../../decisiones/2026-10-12-modulos-expansion.md)).
- D-0224 y D-0226 a D-0229 son tareas "módulo" separadas de la tarea que igual tiene que escribir ese código: D-1013, D-1101, D-1302, D-1401 y D-0401.

**Versión mínima.** La regla de `CLAUDE.md` ("un script nuevo que no sabe del juego va en un módulo") se cumple igual: la tarea constructora escribe el módulo directamente (fusión). Las extracciones de lo que ya existe esperan a post-lanzamiento.

## 4. Recortes propuestos

"Post-lanzamiento" quiere decir después de que la expansión salga completa (F5 cerrada). Esas tareas van al plan de D-2035. Ningún ID de esta sección está hecho en las tablas.

### 4.1 Recortar (42)

| # | Bloque | Acción | IDs | Motivo | Fila 5 |
|---|---|---|---|---|---|
| R1 | Lo que la fila 5 da como recortable | Recortar | D-0125, D-0132, D-0433, D-0533, D-1326, D-1431 | Rival, sabotaje, prestigio, mercado negro, kayak y helicóptero: los nombra la propia fila 5 y ninguno cambia cómo se cuida una caja. | No toca: son sus ejemplos |
| R2 | Contradicen una decisión ya tomada | Recortar | D-0323, D-1329, D-1427, D-1435 (combustible, fila 6); D-1131 (electricidad, `2026-10-04-sin-electricidad-en-galpon.md`); D-1230 (zorra como vehículo, fila 2); D-0733 (cronómetro por caja, fila 3); D-1739 (Endless sin cambios, fila 1); D-2029 (Remote Play Together, `2026-10-04-lanzamiento-steam.md` punto 5); D-0341, D-1927 (fundidos y pantallas de carga, mapa continuo punto 5; el portón que se abre va en D-0302); D-0336 (saltar el trayecto pagando, mapa continuo punto 5); D-1439 (entregas fuera del mapa, mapa continuo punto 2); D-1135 (meta "galpón 100 % automático", choca con la regla de 2 min de `roles-tripulacion.md` §1) | Construir esto es deshacer una decisión escrita. Si alguien lo quiere, primero se cambia la decisión. | No toca: la zorra sigue como herramienta (D-0605); carrito, lancha, avioneta y automatización quedan enteros |
| R3 | Decisiones "sí o no" que este informe contesta "no" | Recortar | D-0735, D-0827, D-0537 (queda compra única de licencias, D-0407), D-1333, D-1426 (dependía de D-1333), D-1339, D-1424, D-1637, D-1726 | Cada una abre un sistema nuevo (hidroavión, oruga, esquí, pesca, gancho aéreo, montaje en casa) para un solo caso. D-0735 además es un fallo ilegible: el pedido no dice qué quiere. | No toca: D-1425 (esquís) se queda |
| R4 | Fallos que parecen arbitrarios o tedio sin decisión | Recortar | D-0632, D-0638, D-1036, D-1338, D-1629, D-0529, D-0535 | Robo de stock, huelga, zona cerrada un día entero, conteo semanal, impuestos y "pago adelantado o contra entrega" quitan plata o días sin que el jugador pueda hacer nada distinto (`vision.md` §9). D-1338 y D-1629 duplican D-1321 y D-1616, que sí avisan. | No toca: Islas y Nieve conservan su clima, oleaje y avalanchas |
| R5 | Obsoletas o redundantes con algo que existe | Recortar | D-0146 (el README dice que las D- no se promueven), D-0234 (el juego no salió: no hay perfiles viejos de jugadores, y `unlock_profile` sigue para la partida rápida, S8), D-0242 (el lint ya corre en pre-push y en CI), D-0230 (cada tarea que crea un módulo trae su adaptador, §4.3), D-0835 (es el requisito "urgente" de D-0806, hecha), D-0938 (colocar sin grilla solo para decorar) | Trabajo sin efecto en el juego. | No toca |

### 4.2 Posponer a post-lanzamiento (148)

| # | Bloque | Acción | IDs | Motivo | Fila 5 |
|---|---|---|---|---|---|
| P1 | Economía de planilla (14) | Posponer post-lanzamiento | D-0133, D-0521, D-0522, D-0523, D-0524, D-0525, D-0526, D-0528, D-0530, D-0531, D-0532, D-0536, D-0637, D-1238 | Préstamos, seguros, precios variables, compra mayorista, contratos, demanda dinámica, reventa, publicidad, gráficos y pronóstico: ninguno pone una caja en las manos. `vision.md` §9 y el corte (§3) ya los sacan de F1. El costo operativo decidido es el mantenimiento (D-0527, se queda). | No toca: los camiones de mercadería siguen (D-0601, D-0603, D-0618, D-0621) |
| P2 | Logística inversa (5) | Posponer post-lanzamiento | D-0329, D-0826, D-0534, D-0633, D-1733 | Devoluciones del cliente y al proveedor: un flujo entero nuevo (pedido, stock, plata, red) que es la entrega al revés. | No toca |
| P3 | Clientes con historia (9) | Posponer post-lanzamiento | D-0122, D-0821, D-0823, D-0425, D-0338, D-0339, D-0839, D-0847, D-1830 | Personajes recurrentes, cadenas, VIP y memoria del distrito no cambian cómo se cuida la caja. Los 18 retratos aparecen dos veces (D-0847 y D-1830) y cuestan 18 corridas de PC. Los mensajes con humor (D-0822) se quedan. | No toca: los retratos son imágenes 2D, no modelos |
| P4 | Variantes de pedido (12) | Posponer post-lanzamiento | D-0424, D-0810, D-0818, D-0819, D-0824, D-0825, D-0830, D-0831, D-0832, D-0833, D-0834, D-0837 | Cada regla suma texto a la hoja y casos borde a la red. Con 6 requisitos (D-0806) y una ventana de 4 h sobra variedad para 16 pedidos por día. D-0830 y D-0832 son fallos ilegibles. Del núcleo F1 salen D-0810, D-0818 y D-0819; ninguna está en el §2 del corte. | No toca |
| P5 | Desafíos, estadísticas y récords (7) | Posponer post-lanzamiento | D-0422, D-0429, D-0430, D-0431, D-1924, D-0432, D-1738 | Metajuego de retención que se diseña mejor con jugadores reales. D-1924 duplica D-0431. | No toca: los hitos que abren zonas (D-0401 a D-0420, D-0434 a D-0440) quedan enteros |
| P6 | Mercadería exótica y variantes de stock (12) | Posponer post-lanzamiento | D-0615, D-0623, D-1337, D-0624, D-0625, D-0627, D-0629, D-0630, D-0635, D-0639, D-0647, D-0648 | Contenedores y grúa portuaria, granel, peligrosos, vivos (Hostil ya los cubre), escáner, ubicación sugerida, apilado, chofer que se queja, animación de rampa y luz nocturna de una dársena que se usa a las 08:30. El bucle de stock cierra sin nada de esto. | No toca: los camiones de mercadería siguen (D-0601, D-0618, D-0621, D-0622, D-0640) con su modelo (D-1814) |
| P7 | Galpón de dos pisos y galpones extra (5) | Posponer post-lanzamiento | D-0631, D-0929, D-1129, D-0330, D-0937 | Mezanine, ascensor de cajas y hubs en otras zonas: navmesh de dos niveles y una segunda sede replicada. `referencia-schedule-1.md` §7 ya marca los hubs como recortables. | No toca: empleados y automatización siguen en un piso |
| P8 | Galpón decorativo y cosméticos extra (11) | Posponer post-lanzamiento | D-0922, D-0924, D-0928, D-0930, D-1033, D-1828, D-1829, D-1925, D-0344, D-0446, D-1543 | Unas 60 corridas de la PC, que es el cuello de botella, para pulido que no mueve la aguja. Queda el mínimo cosmético: D-0137, D-0437 y D-1234 (pintura de la flota por hitos). | No toca: ninguno es un modelo 3D (el modelo de la oficina, D-1826, va a §4.4) |
| P9 | Optimización tipo *shapez* (5) | Posponer post-lanzamiento | D-0921, D-0934, D-1127, D-1128, D-1136 | Planos, mapa de calor, lógica programable, separadores y modo turbo. `referencias-logistica.md` §8 los marca como "galpón *shapez*" y candidatos a este recorte. Quedan la herramienta de tiempos (D-0935) y el supervisor (D-1029). | No toca: cintas, curvas, clasificador y rampas siguen (D-1101 a D-1108) |
| P10 | Máquinas extra (4) | Posponer post-lanzamiento | D-1124, D-1125, D-1126, D-1134 | Paletizadora, envolvedora, cámara de control y máquinas de zona. La automatización queda con las 10 máquinas del núcleo (D-1101 a D-1110) más el robot de picking y el AGV (D-1121, D-1123). | No toca: se posponen piezas del catálogo, no el sistema |
| P11 | Capas sociales de los empleados (8) | Posponer post-lanzamiento | D-1022, D-1932, D-1023, D-1024, D-1025, D-1026, D-1032, D-1039 | Experiencia, moral, renuncias, necesidades, turnos, capacitación y rescate: es el micromanejo que `referencia-schedule-1.md` decidió no tomar. Con días de 18 min, los turnos no tienen dónde vivir. | No toca: los empleados siguen enteros (D-1001 a D-1021, D-1029, D-1030, D-1034, D-1035, D-1038, vestuario como cupo D-0923) |
| P12 | Trampas y cajas extra que no salen de una zona (5) | Posponer post-lanzamiento | D-0736, D-0737, D-0740, D-1731, D-0728 | `plan-desarrollo.md` ("Fuera del MVP: más de siete trampas") pide balancear las 7 juntas antes de sumar. "Mal cerrada" y "Sobrecargada" ya pesan en la calidad `Q` (supuestos.md), "Viva" duplica Hostil, y la caja a medida trivializa la grilla. Las trampas de zona se quedan (D-0738, D-0739, D-1423). | No toca: el armado sigue entero (D-0701 a D-0727, D-0729, D-0731 a D-0750) |
| P13 | Vehículos y variantes que nadie nombró (9) | Posponer post-lanzamiento | D-1232, D-1325, D-1430, D-1623, D-1235, D-1236, D-1237, D-1327, D-1434 | Camión grande, lancha grande, avioneta grande, moto de nieve, remolque, cambio de vehículo en un hub, vehículo dentro de otro, ferry y paracaídas personal: cada uno es física y red nuevas. Alternativa barata: el carrito de Islas y la 4x4 de Montaña "ya están allá", estacionados en la zona como dice el mapa continuo. | No toca: bici (con tándem y trailer), carrito, lancha, avioneta y 4x4 quedan enteros |
| P14 | Peligros y eventos extra por zona (33) | Posponer post-lanzamiento | Mapa: D-0321, D-0322, D-0334, D-0335. Tierra: D-1522, D-1523, D-1524, D-1525, D-1529, D-1530, D-1531, D-1533, D-1534, D-1537. Islas: D-1324, D-1332, D-1336. Aire: D-1429, D-1432, D-1433, D-1437. Montaña y Nieve: D-1621, D-1622, D-1625, D-1626, D-1627, D-1628, D-1630, D-1631, D-1639. Volcán: D-1723, D-1727, D-1732 | Cada zona conserva su núcleo de peligros (`vision.md` §6) y las ampliaciones que dan rol o clip (§5.3). Lo que sale es variedad que se suma mejor con feedback. | No toca: las 9 zonas siguen y ninguna queda como "otro decorado" |
| P15 | UI y audio de ambiente extra (4) | Posponer post-lanzamiento | D-1921, D-1922, D-1938, D-1939 | Radio, diario, atajos configurables y texto a voz no hacen falta para jugar con mando y teclado (D-1948). | No toca |
| P16 | Refactors y optimizaciones que ninguna medición pidió (5) | Posponer post-lanzamiento (se reabren si la medición falla) | D-0221, D-0222, D-0225, D-0233, D-2022 | Extraer a módulo lo que ya anda, un pool de objetos y el interest management (xhigh), antes de que `bench_company` (D-2011) o el presupuesto de red (D-2002) digan que hacen falta. | No toca |

### 4.3 Fusionar (97)

En las fusiones no se pierde nada: el trabajo pasa a la tarea destino, que suma lo que decía la fundida en su "Hecho cuando". Fila 5: no toca. Ninguna tarea destino está recortada ni pospuesta.

| Destino | Se funden | Motivo |
|---|---|---|
| D-0102 (hecha) | D-0128 | La fila 1 ya contestó: Endless queda como partida rápida, sin cambios |
| D-0147 | D-1820 | Mismo inventario de assets |
| D-0244 | D-0850, D-0950, D-1050, D-1150, D-1250 | Una sola guía "agregar contenido de la expansión" en vez de seis |
| D-0310 | D-0327 | El GPS de varias paradas es el mapa del tablero |
| D-0311 | D-0247 | Las variantes de `DeliveryHouse` ya son D-0311 (no agranda el corte: la decisión es su primer párrafo) |
| D-0312 | D-0326, D-0345 | Direcciones, carteles y nombres de calles son un solo sistema |
| D-0328 | D-1521 | La obra en la calle es el desvío |
| D-0332 | D-1937 | Pings de mapa y pings de negocio, un solo sistema de comunicación |
| D-0350 | D-1350, D-1550, D-1650, D-1750 | Un test de humo que recorre `DistrictRegistry` cubre cada zona nueva al sumar su `.tres` (D-1513 queda aparte: Centro va con el corte) |
| D-0401 | D-0229 | El módulo `milestones` lo escribe la tarea que lo usa |
| D-0410 | D-0411 | El árbol de progreso es una vista del tablero de hitos |
| D-0426 | D-1614, D-1718 | Abrigo e ignífugo son ítems del sistema de mejoras de tripulación |
| D-0438 | D-1735 | Misma escena de cierre de campaña |
| D-0440 | D-0421, D-2028 | Hitos secretos y logros de Steam viven juntos; D-2028 era un duplicado exacto |
| D-0444 | D-1933 | Mismo efecto de desbloqueo de zona |
| D-0518 | D-0428 | El voto de compra es el "host o voto" de D-0518 (y D-0910.1) |
| D-0527 | D-1132, D-1436 | Mantenimiento de máquinas y de avioneta es el mismo costo operativo |
| D-0540 | D-0231 | `sim_day` y `sim_economy` son la misma herramienta |
| D-0616 | D-0628 | Vencimiento y producto frío vencido, misma regla |
| D-0626 | D-0730 | Productos enormes y paquetes sin caja, misma tarea |
| D-0640 | D-0932 | Patio de maniobras y estacionamiento ampliado |
| D-0722 | D-1717 | Duplicado exacto |
| D-0738 | D-1635, D-1704 | "Derretible" y su inverso "congelable" son una trampa de temperatura; su prueba en Volcán va adentro |
| D-0739 | D-1340 | Duplicado exacto ("Mojable" en Islas) |
| D-0828 | D-1331, D-1532, D-1633 | Pedidos especiales por zona, un solo lugar |
| D-0935 | D-1133 | Throughput y tiempos por estación, misma herramienta |
| D-0947 | D-0248 | Memoria y FPS del galpón grande, mismo benchmark |
| D-0948 | D-0940 | Mover con productos adentro es un caso del test de layouts (el `uid` de D-0910 ya lo resuelve) |
| D-1013 | D-0224 | El módulo `job_board` lo escribe la tarea de reservas |
| D-1018 | D-1818 | Duplicado exacto: el modelo del empleado base se hace una vez |
| D-1030 | D-1031 | El accidente es el rasgo "torpe" |
| D-1101 | D-0226 | El módulo `conveyor_graph` lo escribe la tarea de la cinta |
| D-1103 | D-0634 | Duplicado exacto |
| D-1138 | D-0933 | La alarma es la trampa activa en el galpón |
| D-1202 | D-0836 | Pedido que exige vehículo se valida al elegir vehículo en el despacho |
| D-1205 | D-0925 | Duplicado exacto (garaje) |
| D-1224 | D-1334 | Hundirse en la arena es la tracción del carrito |
| D-1302 | D-0227 | El módulo `buoyancy` lo escribe la tarea de la lancha |
| D-1305 | D-0927 | Duplicado exacto (muelle) |
| D-1330 | D-1538 | Mismo proveedor de pescado |
| D-1401 | D-0228 | El módulo `simple_flight` lo escribe la tarea del vuelo |
| D-1405 | D-0926 | Duplicado exacto (pista) |
| D-1411 | D-1438 | El mapa visto desde el aire es el terreno de impostores |
| D-1445 | D-1644, D-1743 | Un shader de cielo con parámetros por zona |
| D-1507 | D-0333 | Zonas peatonales y callejones de bici, mismo tramo |
| D-1535 | D-1313 | Duplicado exacto (Puerto en tierra) |
| D-1604 | D-1736 | Rocas que ruedan y desprendimientos, misma mecánica |
| D-1613 | D-1634 | El fogón es parte del frío del jugador |
| D-1705 | D-1730 | El sismógrafo es el aviso del temblor |
| D-1706 | D-1734 | Ceniza en tierra y en el aire, mismo sistema |
| D-1714 | D-1737 | La señalización de evacuación entra en el kit volcánico |
| D-1843 | D-1746, D-1823 | Una auditoría de arte en vez de tres |
| D-1845 | D-0945 | Íconos del catálogo de construcción renderizados por script, en la nube: 15 corridas menos de PC |
| D-1903 | D-0519 | La plata es parte del HUD del día |
| D-1918 | D-0447, D-0846 | Daltonismo y texto además del ícono, misma pasada |
| D-1920 | D-0443, D-0649, D-0845 | Un test de `tr()` para todo lo nuevo |
| D-1923 | D-0331 | El mapa en el celular es la app del celular |
| D-1926 | D-1140 | Tutoriales por sistema |
| D-1928 | D-1043 | Mismos murmullos de `SynthAudio` |
| D-1929 | D-0343 | Música por zona |
| D-1941 | D-1934 | Las transiciones entran en la pasada de pulido de UI |
| D-2002 | D-0317 | El mapa continuo (punto 6) ya decidió "máx. 2 vehículos fuera"; queda medirlo |
| D-2010 | D-0237 | Rutas de Auto-Cloud y guardado en la nube, misma tarea |
| D-2027 | D-0646 | El fuzz de agarrar y soltar cubre el stock duplicado |
| D-2031 | D-0450, D-1347, D-1447, D-1546, D-1646, D-1745, D-1846 | Capturas y textos para Steam se hacen juntos al actualizar la página |
| D-2039 | D-0249, D-2040 | Una auditoría por fase en vez de tres tareas de auditoría |
| D-2041 | D-0240, D-0241 | Una pasada de `revisor-gdscript` sobre las carpetas nuevas |
| D-2044 | D-0250 | El catálogo de módulos se actualiza con la arquitectura final |
| D-2045 | D-0449 | Duplicado (flags de dev en release) |
| D-2046 | D-1849 | Misma revisión de licencias |

### 4.4 Zona gris: no se tacha, decide el usuario

Estas tareas rozan algo que nombró el usuario. La recomendación es posponerlas, pero la decisión es suya (issue `decide-usuario`).

| IDs | Qué es | Recomendación | Por qué no se tacha |
|---|---|---|---|
| D-1027, D-1028, D-1037, D-1239, D-1440 | Repartidor, choferes y piloto NPC; empleados especializados por zona | Posponer (§3.2) o reducir a pedidos sin trampa con media paga | Son "empleados" |
| D-1122 | Brazo robótico armador | Construir con tope de calidad (por ejemplo, `Q` máx. 70) para que el armado a mano siga importando, o posponer | Automatización |
| D-1139 | Empleado técnico que repara máquinas | Posponer: el atasco que destraba un jugador (D-1113) es el momento coop | Empleados |
| D-1826 | Modelo de la oficina del jefe | Al final de la cola de la PC, o posponerlo junto con D-0924 | Modelos nuevos |
| D-1834, D-1835 | Modelos y animaciones de animales nuevos | Al final de la cola de la PC, o posponerlos junto con D-1324 y D-1626 | Modelos nuevos |

### 4.5 Cambios de alcance sin tachar

- **D-0223: marcada como hecha.** `modules/day_clock/` ya existe (decisión `2026-10-12-modulos-expansion.md`, D-0219).
- **D-1504 y D-1505: tránsito y peatones en rieles**, deterministas por reloj (§3.1).
- **D-0307, D-0313 y D-0318: reescribir para el mapa continuo.** No hay carga de escena ni "instancias de distrito": son celdas de `world_cells` alrededor de cada vehículo.
- **D-0127: una sola dificultad** con "armado asistido" (`referencias-logistica.md` §7), en vez de tres tamaños de empresa.
- **Arreglar `corte-vertical.md`**:
  - la fila 9 cita D-0217 (`FleetRegistry`); probablemente va D-0213;
  - el §3 cita D-0306 (GPS) como "el sistema de hitos se prepara";
  - el §4 asigna `test_company_cells` a D-0303 (despacho) en vez de D-0313.
- **Urgentes y baratas: D-0150** (calendario con fecha de corte), **D-0139** (qué promete la página) y **D-2033** (qué demo va al Next Fest). Son 3 tareas medium que destraban la decisión de §6.

## 5. Lo que no se recorta y por qué

### 5.1 Lo que nombró el usuario (fila 5)

| Nombrado | Dónde vive y qué queda |
|---|---|
| **Zonas: Islas, Montaña, Nieve, Volcán** (y las otras cinco) | El núcleo de los grupos 13, 15, 16 y 17, completo. Solo salen variedad extra (P14) y duplicados (§4.3) |
| **Bici** | D-1201 a D-1220 enteros, con tándem (D-1210) y trailer (D-1211). El tándem es la respuesta al "rol muerto" de la bici: uno pedalea y otro cuida la caja |
| **Carrito** | D-1221 a D-1229 enteros |
| **Lancha** | D-1301 a D-1320 enteros |
| **Avioneta** | D-1401 a D-1420, más D-1421 a D-1423 y D-1425 |
| **Armado de paquetes** | D-0701 a D-0727, D-0729 y D-0731 a D-0750, incluida la mesa compartida (D-0715). Salen solo la caja a medida, el temporizador, el pedido ambiguo y tres trampas fuera de zona |
| **Camiones de mercadería** | D-0601, D-0603, D-0618, D-0621, D-0622 y D-0640, con su modelo (D-1814) |
| **Empleados** | D-1001 a D-1021, D-1029, D-1030, D-1034, D-1035, D-1038 y D-1040 a D-1049 |
| **Automatización** | D-1101 a D-1121, D-1123, D-1130, D-1137, D-1138 y D-1141 a D-1149. D-1122 queda en zona gris |
| **Desbloqueos por hitos** | D-0401 a D-0420 y D-0434 a D-0440 |
| **Modelos nuevos** | No se tacha ninguna tarea de `modelador-blender`. D-1818 se funde con D-1018 (el modelo se hace una vez). D-1826, D-1834 y D-1835 quedan en zona gris |

### 5.2 El corte vertical

Ninguna tarea del §2 de [corte-vertical.md](corte-vertical.md) se recorta ni se pospone.

Del núcleo de F0/F1 salen solo:
- dos fusiones: D-0317, D-0519;
- cuatro posposiciones fuera del corte: D-0615, D-0810, D-0818, D-0819.

### 5.3 Lo accesorio que se queda porque es el pilar

Estas tareas no las nombró el usuario, pero le dan algo que hacer al que no maneja o generan un clip:
- D-0332 (pings) y D-0734 (control de calidad por otro jugador);
- D-1421 (el copiloto apunta el lanzamiento);
- D-1309 (rescatar la caja del agua) y D-1328 (puente colgante a pie);
- D-1528 (bajar a abrir la tranquera) y D-1638 (raspar el parabrisas);
- D-1636 (la bocina dispara la avalancha) y D-1722 (géiseres que lanzan cajas);
- D-1137 (cajas que se caen de la cinta) y D-1138 (la trampa explota en el galpón);
- D-0822 (mensajes de clientes con humor).

### 5.4 Riesgos que quedan

1. **Calendario contra Early Access.** Ni siquiera el caso realista con recortes deja margen antes del 2027-03-12 (§Resumen). [plan-desarrollo.md](../../plan-desarrollo.md) fija "Contenido cerrado 2026-10-30" y su lista "Fuera del MVP" choca con la expansión en tres puntos:
   - tránsito (D-1504);
   - más trampas (D-0736 a D-0740);
   - tutorial jugable (D-0720, D-1901, D-1926).

   Nadie reconcilió los dos planes. Es decisión del usuario (§6).
2. **El arte va por un solo carril.** Son unos 400 assets a 6-10 por día. Las guías que lo ordenan (D-1801, D-0147 y D-0148) están abiertas: se hacen primero. Después, la PC toma lo estable (productos D-1802 a D-1805, cajas D-1806, bici D-1217, carrito D-1227, lancha D-1316, avioneta D-1414) sin esperar a F5.
3. **Física nueva concentrada en F2-F4.** Son 11 tareas xhigh de vehículos y terreno (§1), cada una con un bot que tiene que pasar 10 veces. Si una se traba, frena su zona entera.
4. **Red sin medir.** D-2002 todavía no tiene número con empleados (D-1012), cintas (D-1115) y 2 vehículos fuera. El interest management (D-2022) queda pospuesto a condición de que esa medición pase.
5. **Playtesting al final.** Unas 626 tareas se van a validar solo con bots. Los indicadores que adelantan si es divertido son tres:
   - la regla de 2 min (`roles-tripulacion.md` §1);
   - 20-40 s por caja con mando (D-0745);
   - ganancia por jugador dentro de ±25 % (D-0539).

   Si alguno falla, se corrige el diseño antes de sumar contenido.
6. **Dominio de Slatex.** El armado y las trampas (grupo 07) y la UI (grupo 19) tocan sus carpetas. Se hacen con aviso, pero pueden chocar con su lista (S-311).

## 6. Preguntas abiertas (solo las contesta el equipo)

1. **¿Qué parte de la expansión entra al Early Access del 2027-03-12?**
   - Opción A, recomendada: F0-F2 completos (Centro, Suburbio, Campo, bici, carrito, empleados, cintas, hitos) y F3-F4 como actualizaciones gratuitas de Early Access, que `plan-desarrollo.md` ya prevé.
   - Opción B: correr la fecha.

   Ninguna de las dos recorta lo nombrado: es calendario, y la fecha es del usuario.
2. **¿Qué demo va al Next Fest?** La build es del 2026-12-18 (D-2033). Para esa fecha, el modo Empresa va a tener Centro y Campo en gris.
3. **¿Cuántas horas por día queda prendida la PC de arte?** Define si el arte entra.
4. **Zona gris (§4.4):** ¿repartidores NPC sí o no? ¿El brazo robótico puede armar con calidad máxima?
5. **¿El "Contenido cerrado 2026-10-30" de `plan-desarrollo.md` aplica a la expansión o solo al juego base?**

## 7. IDs a tachar

Son 287 en total: 42 R (recortar), 148 P (posponer post-lanzamiento) y 97 F (fusionar; el destino está en §4.3). No incluyen D-0223 (se marca como hecha) ni los 10 de la zona gris (§4.4).

- **01:** D-0122 P, D-0125 R, D-0128 F, D-0132 R, D-0133 P, D-0146 R
- **02:** D-0221 P, D-0222 P, D-0224 F, D-0225 P, D-0226 F, D-0227 F, D-0228 F, D-0229 F, D-0230 R, D-0231 F, D-0233 P, D-0234 R, D-0237 F, D-0240 F, D-0241 F, D-0242 R, D-0247 F, D-0248 F, D-0249 F, D-0250 F
- **03:** D-0317 F, D-0321 P, D-0322 P, D-0323 R, D-0326 F, D-0327 F, D-0329 P, D-0330 P, D-0331 F, D-0333 F, D-0334 P, D-0335 P, D-0336 R, D-0338 P, D-0339 P, D-0341 R, D-0343 F, D-0344 P, D-0345 F
- **04:** D-0411 F, D-0421 F, D-0422 P, D-0424 P, D-0425 P, D-0428 F, D-0429 P, D-0430 P, D-0431 P, D-0432 P, D-0433 R, D-0443 F, D-0446 P, D-0447 F, D-0449 F, D-0450 F
- **05:** D-0519 F, D-0521 P, D-0522 P, D-0523 P, D-0524 P, D-0525 P, D-0526 P, D-0528 P, D-0529 R, D-0530 P, D-0531 P, D-0532 P, D-0533 R, D-0534 P, D-0535 R, D-0536 P, D-0537 R
- **06:** D-0615 P, D-0623 P, D-0624 P, D-0625 P, D-0627 P, D-0628 F, D-0629 P, D-0630 P, D-0631 P, D-0632 R, D-0633 P, D-0634 F, D-0635 P, D-0637 P, D-0638 R, D-0639 P, D-0646 F, D-0647 P, D-0648 P, D-0649 F
- **07:** D-0728 P, D-0730 F, D-0733 R, D-0735 R, D-0736 P, D-0737 P, D-0740 P
- **08:** D-0810 P, D-0818 P, D-0819 P, D-0821 P, D-0823 P, D-0824 P, D-0825 P, D-0826 P, D-0827 R, D-0830 P, D-0831 P, D-0832 P, D-0833 P, D-0834 P, D-0835 R, D-0836 F, D-0837 P, D-0839 P, D-0845 F, D-0846 F, D-0847 P, D-0850 F
- **09:** D-0921 P, D-0922 P, D-0924 P, D-0925 F, D-0926 F, D-0927 F, D-0928 P, D-0929 P, D-0930 P, D-0932 F, D-0933 F, D-0934 P, D-0937 P, D-0938 R, D-0940 F, D-0945 F, D-0950 F
- **10:** D-1022 P, D-1023 P, D-1024 P, D-1025 P, D-1026 P, D-1031 F, D-1032 P, D-1033 P, D-1036 R, D-1039 P, D-1043 F, D-1050 F
- **11:** D-1124 P, D-1125 P, D-1126 P, D-1127 P, D-1128 P, D-1129 P, D-1131 R, D-1132 F, D-1133 F, D-1134 P, D-1135 R, D-1136 P, D-1140 F, D-1150 F
- **12:** D-1230 R, D-1232 P, D-1235 P, D-1236 P, D-1237 P, D-1238 P, D-1250 F
- **13:** D-1313 F, D-1324 P, D-1325 P, D-1326 R, D-1327 P, D-1329 R, D-1331 F, D-1332 P, D-1333 R, D-1334 F, D-1336 P, D-1337 P, D-1338 R, D-1339 R, D-1340 F, D-1347 F, D-1350 F
- **14:** D-1424 R, D-1426 R, D-1427 R, D-1429 P, D-1430 P, D-1431 R, D-1432 P, D-1433 P, D-1434 P, D-1435 R, D-1436 F, D-1437 P, D-1438 F, D-1439 R, D-1447 F
- **15:** D-1521 F, D-1522 P, D-1523 P, D-1524 P, D-1525 P, D-1529 P, D-1530 P, D-1531 P, D-1532 F, D-1533 P, D-1534 P, D-1537 P, D-1538 F, D-1543 P, D-1546 F, D-1550 F
- **16:** D-1614 F, D-1621 P, D-1622 P, D-1623 P, D-1625 P, D-1626 P, D-1627 P, D-1628 P, D-1629 R, D-1630 P, D-1631 P, D-1633 F, D-1634 F, D-1635 F, D-1637 R, D-1639 P, D-1644 F, D-1646 F, D-1650 F
- **17:** D-1704 F, D-1717 F, D-1718 F, D-1723 P, D-1726 R, D-1727 P, D-1730 F, D-1731 P, D-1732 P, D-1733 P, D-1734 F, D-1735 F, D-1736 F, D-1737 F, D-1738 P, D-1739 R, D-1743 F, D-1745 F, D-1746 F, D-1750 F
- **18:** D-1818 F, D-1820 F, D-1823 F, D-1828 P, D-1829 P, D-1830 P, D-1846 F, D-1849 F
- **19:** D-1921 P, D-1922 P, D-1924 P, D-1925 P, D-1927 R, D-1932 P, D-1933 F, D-1934 F, D-1937 F, D-1938 P, D-1939 P
- **20:** D-2022 P, D-2028 F, D-2029 R, D-2040 F
