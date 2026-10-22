# La expansión (modo Empresa) en la página de Steam y el tráiler: qué promete y qué no (D-0139)

> Escrito 2026-10-22 por `estratega-steam`, sin respuesta humana: las decisiones están en §7. No toca la
> página real, no decide precio ni fecha (son del usuario, `docs/decisiones/2026-10-04-lanzamiento-steam.md`) y
> no gasta plata. Fuentes del juego: [README de la expansión](../expansion-distritos/README.md),
> [vision.md](../expansion-distritos/diseno/vision.md), [corte-vertical.md](../expansion-distritos/diseno/corte-vertical.md),
> [critica-alcance.md](../expansion-distritos/diseno/critica-alcance.md), [flota.md](../expansion-distritos/diseno/flota.md),
> [roles-tripulacion.md](../expansion-distritos/diseno/roles-tripulacion.md), decisiones D-0102 (2026-10-04) y modo
> solo (2026-10-22). Se apoya en [estado-steam.md](estado-steam.md), [trailer.md](trailer.md) y
> [logros-expansion.md](logros-expansion.md).

## 0. Dónde está la expansión hoy (2026-10-22)

Conteo de tareas marcadas ✅ en las tablas de grupo y `[x]` en `detalle/`:

| Fase | Qué trae | Estado real | ¿Se puede mostrar? |
|---|---|---|---|
| F0 Base | decisiones, arquitectura, guardado, red | casi entera (grupos 01, 02, 20: 34 + 32 + 12 ✅) | no hay nada visible |
| F1 Corte vertical | día completo: proveedor, stock, pedidos, armado, despacho, Barrio Centro, cierre | código casi entero (03: 11 ✅ y 5 ◐; 05: 19; 06: 16 y 4 ◐; 07: 26; 08: 17; 09: 21). `bot_company_day` llega a `BOT_OK` (D-2016.2, PR pendiente), pero falta el piloto por el grafo de calles (D-2016.3), la etapa de manejo del benchmark (D-2011.1), las calles de Barrio Centro (D-1501, 0 ✅) y la van en el Campo (D-0315.b). **No está declarado cerrado.** | **No.** Todo en gris: galpón (`arte-pendiente/D-0911`), Barrio Centro (`D-0314`), camión del proveedor (`D-0601`), zorra, autoelevador, carrito de picking, tableros e impresora (`D-0603` a `D-0805`). Grupo 18 (arte): 0 ✅ |
| F2 Crecer | hitos, empleados, máquinas, Suburbio, bici, carrito | grupos 04, 10, 11, 12 y 15: **0 ✅** | no |
| F3 Agua y altura | lancha, Puerto, Islas, Montaña, Nieve | grupos 13 y 16: 0 ✅; riesgo "muy alto" (agua en GL Compatibility, D-1301) | no |
| F4 Aire y fuego | avioneta, Volcán | grupos 14 y 17: 0 ✅; riesgo "muy alto" (vuelo, D-1401/D-1420) | no |
| F5 Lanzamiento | arte final, UI, audio, VFX | grupos 18 y 19: 0 ✅ | no |

Contexto de calendario (critica-alcance.md, Resumen): con los recortes quedan 626 tareas abiertas y el caso
realista de terminar la expansión entera es **2027-03-08**, cuatro días antes del Early Access del
**2027-03-12**. Qué parte entra al Early Access sigue abierto para el usuario (issue #470; recomendado F0-F2 y
F3-F4 como actualizaciones gratis). El plan general todavía dice que el Early Access sale "con 1 vehículo, 1
set de tramos" (`docs/plan-desarrollo.md`, fila Early Access): los dos planes no están reconciliados.

## 1. La regla

**En la página, el tráiler y las capturas solo entra lo que cumple las dos cosas: su fase está cerrada (o la
pieza tiene sus tareas ✅ y su test o bot verde) y existe una captura o clip real del juego con arte que no
sea placeholder gris.** Lo demás va, como mucho, en la sección "planeado" de las preguntas de Early Access, sin
fechas ni números. Si no está en ninguna fase vigente (recortado o pospuesto), no aparece en ningún lado.

Por qué tan estricto:
- Steamworks pide no comprometer resultados futuros en Early Access: no se puede saber si las adiciones
  planeadas van a pasar ("Early Access", `partner.steamgames.com/doc/store/earlyaccess`, vía búsqueda
  2026-10-22; la página la bloquea el proxy, **verificar**). Cobertura de la regla: PC Gamer, "Steam's secret
  Early Access rules" (2017).
- Las capturas tienen que mostrar el juego, sin arte conceptual ni renders, y hacen falta al menos 5
  ("Store graphical assets", `partner.steamgames.com/doc/store/assets/standard`, vía búsqueda 2026-10-22;
  **verificar**). La regla nació del caso *No Man's Sky* (2016): capturas reales con cosas que no
  llegaron al juego (TechRaptor y PC Gamer, 2016-2017). Un placeholder gris muestra el juego, pero
  vende peor que no mostrar nada.

## 2. Qué promete la página

### 2.1 Gancho: no cambia

El diferencial que vende sigue siendo el del juego base (`docs/definicion-proyecto.md`): asimetría entre
pasajeros, la carga como protagonista. La expansión **suma una etapa antes** ("lo que armaste en el galpón
es lo que vas a sufrir en la ruta", vision.md §1); no reemplaza el gancho. La primera frase es la de S-901.

**Descripción corta, versión A** (página "Próximamente" de noviembre y demo de Next Fest; la Empresa
todavía no se puede mostrar):

- es (217 caracteres): *Uno maneja. Los demás intentan que nada explote. Take My Package es un cooperativo en línea de reparto
  donde cada pasajero cuida una caja con su propia trampa, y el conductor no ve lo que su manejo le hace a la carga.*
- en (229): *One drives. Everyone else tries to keep things from exploding. Take My Package is an online co-op delivery
  game where every passenger guards a box with its own trap, and the driver never sees what their driving does to the cargo.*

**Descripción corta, versión B** (cuando se cumpla la condición de la fila 1 de §3):

- es (238): *Uno maneja. Los demás intentan que nada explote. En Take My Package llevan una empresa de reparto
  cooperativa: reciben la mercadería, arman cada caja y la cuidan en el camino. Lo que armaste en el galpón es lo
  que vas a sufrir en la ruta.*
- en (243): *One drives. Everyone else tries to keep things from exploding. In Take My Package you run a co-op delivery
  company: unload the stock, pack every box and guard it on the road. Whatever you pack in the warehouse is what
  you'll suffer on the way.*

### 2.2 Bullets de "Acerca de este juego" que suma la expansión

Cada bullet lleva entre corchetes la fila de §3 que lo habilita. Sin la condición cumplida, no se publica.

| # | es | en | [§3] |
|---|---|---|---|
| 1 | **Tu propia empresa de reparto.** Un día de trabajo de 08:00 a 20:00: llega el camión del proveedor, guardan la mercadería, entran los pedidos y al cierre se cobra y se paga el alquiler. | **Your own delivery company.** A working day from 8 AM to 8 PM: the supplier truck arrives, you shelve the stock, orders come in, and at closing time you get paid and pay the rent. | 1, 4 |
| 2 | **Armá cada caja.** Elegí el tamaño, acomodá los productos, poné relleno y cinta. Una caja mal armada pega más fuerte en la ruta. | **Pack every box yourself.** Pick the size, fit the products, add padding and tape. A badly packed box hits harder on the road. | 2 |
| 3 | **Solo o con hasta N amigos.** Repártanse el galpón y la ruta; jugando solo, el galpón espera mientras vos entregás. | **Solo or with up to N friends.** Split the warehouse and the road; playing solo, the warehouse waits while you deliver. | 5, 6 |
| 4 | **Una ciudad que se abre.** Empezás en el centro y el campo; con los hitos se abren barrios nuevos. | **A town that opens up.** Start downtown and in the countryside; milestones unlock new neighborhoods. | 3, 8 |
| 5 | **Contratá y automatizá.** Empleados en cada estación y máquinas que arman y etiquetan mientras ustedes salen a las entregas difíciles. | **Hire and automate.** Staff every station and add machines that pack and label while you take the tough deliveries. | 9, 10 |
| 6 | **Partida rápida.** Una entrega sola de 10 minutos, o el modo sin fin, para cuando no hay tiempo para un día entero. | **Quick Play.** A single 10-minute delivery, or Endless mode, for when there's no time for a full day. | 13 |

"N" del bullet 3: 8 solo cuando se cumpla la fila 6; si no, el número que esté probado con gente por Steam
(decisión del usuario del 2026-10-04, punto 5). Los bullets 4 y 5 solo cuando haya algo de F2 construido y
capturado; antes no se mencionan. Los bullets 1 y 2 van **arriba** del bullet de la asimetría en la versión B,
nunca en lugar de él.

### 2.3 Etiquetas

Base de S-901 (`docs/tareas/S-901.md`): Co-op, Online Co-Op, Physics, Driving, Funny, Party Game. Steam ordena
por peso; las primeras son las que más pesan en las recomendaciones.

| Etiqueta | Cambio | Cuándo | Por qué |
|---|---|---|---|
| Online Co-Op, Co-op, Physics, Funny | se quedan arriba | ya | Es lo que se juega en la demo y en la primera hora. |
| Driving | baja al fondo | versión B | Con la Empresa, manejar es la mitad del día; vision.md §9: "no es un juego de conducción". |
| Party Game | se queda solo si la Partida rápida sigue en el menú | — | Un día de 18 min no es partida de fiesta; la Partida rápida sí. |
| **Management** | se suma, debajo de las cuatro primeras | versión B | La Empresa tiene plata, stock y pedidos desde F1. *Schedule I*, la referencia de gestión del galpón (`referencia-schedule-1.md`), figura con Simulation, Crime, Co-op, Management y Multiplayer en un agregador de terceros (gamegeeker.com, consultado 2026-10-22; la tienda la bloquea el proxy, **verificar**). |
| **Automation** | se suma | solo con F2 grupo 11 construido y capturado | Atrae a un público que espera fábricas: si no hay máquinas, reseña negativa segura. |
| Base Building | no, por ahora | con el modo construcción del galpón (D-0901 a D-0910) capturado | Hoy el galpón tiene un layout fijo. |
| Open World | **nunca** | — | vision.md §9: trazado fijo, ≤ 6 × 6 km, no es mundo abierto. |

## 3. Promesa → tarea que la respalda → condición para mostrarla

| # | Promesa | Fase · tareas D- | Estado hoy | Condición para la página |
|---|---|---|---|---|
| 1 | Modo Empresa: un día completo jugable | F1 · D-0111 (criterio), D-2016, D-2011, D-0214 | `BOT_OK` con PR pendiente; falta D-2016.3, D-2011.1 | Corte de F1 **declarado cerrado** (corte-vertical.md §4, sin stubs) **y** captura del galpón con arte de `arte-pendiente/D-0911` hecho |
| 2 | Armado de paquetes en grilla, la caja define cuánto pega la trampa | F1 · D-0701 a D-0712, D-0715 | ✅ en código; cajas y relleno en gris | Clip real de la mesa de armado con cajas y relleno con arte final (D-1806) |
| 3 | Barrio Centro | F1 · D-0314, D-1501 | D-1501 sin hacer; gris | D-1501 ✅ y arte de `arte-pendiente/D-0314` |
| 4 | Proveedor, palets y estantes | F1 · D-0601 a D-0611 | ✅ en código, 4 ◐; gris | Arte de D-0601 (camión del proveedor), D-0605 y D-0606 |
| 5 | Jugar solo | D-0126, D-0151 | diseñado; D-0151.3 abierta | Bot de un jugador cerrando con ganancia (D-2016, 1 jugador) y D-2024 (20 días) verde |
| 6 | "Hasta 8 jugadores" en Empresa | D-2002.5, D-2017, D-2023 | D-2002.5 abierta (8 jugadores pasan de 40 KB/s); D-2023 sin hacer | D-2002.5 y D-2023 ✅ **y** prueba con gente por Steam (decisión 2026-10-04, punto 5) |
| 7 | Campo como zona de la Empresa | F1 · D-0315 | ◐ (falta D-0315.b) | D-0315 ✅; el Campo ya tiene arte del juego base |
| 8 | Zonas que se desbloquean (Suburbio) | F2 · grupo 04, D-15xx | 0 ✅ | Hitos ✅ y Suburbio con arte capturado |
| 9 | Empleados | F2 · grupo 10 | 0 ✅ | Grupo 10 núcleo ✅ y clip de un empleado trabajando con su modelo |
| 10 | Máquinas | F2 · grupo 11 | 0 ✅ | Grupo 11 núcleo ✅ y clip de una cinta andando |
| 11 | Bici y carrito | F2 · grupo 12 | 0 ✅ | D-1207 (bot 10 corridas) y modelo D-1217 / D-1227 |
| 12 | Logros de Steam (30 de la Empresa) | D-0440, N-901 | diseño hecho, cero código, sin AppID | AppID propio y D-0440 ✅; Steam muestra la cantidad sola, no hace falta decirla |
| 13 | Partida rápida (Entrega y Endless) | D-0102 | decidido, sin cambios de comportamiento | Botón real en el menú |

### 3.1 Qué NO se promete (en ningún lado de la página)

- **Lancha, Puerto, Islas, Montaña, Nieve, avioneta, 4x4 y Volcán** (F3-F4). Riesgo "muy alto" según
  critica-alcance.md §2 y fuera del caso realista antes del Early Access. Si el usuario decide la opción A
  del #470, van solo en la respuesta de Early Access "¿Qué se planea?", sin fecha: *"Planeamos sumar zonas
  nuevas con otros vehículos durante el Early Access"*. Sin nombrarlos uno por uno, sin cantidades ("9
  zonas", "6 vehículos", "6 km") y sin capturas.
- **Recortado o pospuesto** (critica-alcance.md §4 y §7; decisión 2026-10-19): combustible, helicóptero,
  kayak, ferry, camión grande, lancha y avioneta grandes, moto de nieve, rival, prestigio, mercado negro,
  impuestos, robo de stock, galpón 100 % automático, Remote Play Together (D-2029 recortada).
- **Zona gris sin decidir** (#470): repartidores NPC, brazo robótico que arma con calidad máxima.
- **Lo que no existe por decisión**: voces de personajes (D-1928: murmullos y texto), telemetría o servicio
  en línea propio (D-2036), mapa abierto o generado infinito.
- **Números de diseño** (precios de vehículos, pedidos por día, 30 hitos): viven en `company_tuning.gd` y
  cambian con el balance. En la página no van cifras que el balance pueda mover.
- **Empleados y automatización como característica**, mientras F2 no tenga nada construido. El usuario los
  nombró y no se recortan (fila 5 de D-0113), pero eso garantiza que se construyan, no que lleguen al Early
  Access.

## 4. Tráiler

**Decisión: el tráiler actual (`trailer.md`, 75 s) no cambia para la página de noviembre ni para el Next Fest.**
Muestra el juego base, que es lo que se puede grabar sin gris y lo que trae la demo ("una entrega completa y
el depósito", plan-desarrollo, fila Build de demo). **La Empresa va en un segundo video, "Modo Empresa", de 40-50 s**,
que se graba cuando se cumplan las filas 1 y 2 de §3, y pasa a primer video cuando salga el Early Access, si
la Empresa entra. Un tráiler de gancho que explica stock y pedidos pierde los primeros 5 s, que son los que
deciden (`trailer.md`, Reglas).

Planos del video "Modo Empresa" (los primeros 5 s siguen la regla: caos sin contexto):

| # | s | Qué se ve | Condición (sin esto, el plano no se graba) |
|---|---|---|---|
| E1 | 0-4 | Primera persona en la mesa de armado: alguien mete un jarrón en una caja XL sin relleno; corte a la ruta, la caja golpea y suena el vidrio | Fila 2 de §3 + D-1806 (cajas) |
| E2 | 4-9 | Logo sobre el portón del galpón abriéndose a la mañana; entra el camión del proveedor | Fila 1 + D-0601 + `arte-pendiente/D-0911` |
| E3 | 9-15 | Tripulación descargando el palet con la zorra; otro guarda en los estantes | Fila 4 + D-0605 |
| E4 | 15-21 | El tablero de pedidos; mano agarrando un pedido; armado rápido con cinta y etiqueta. Texto: "Armá. Cargá. Rezá." | Fila 2 + D-0805 |
| E5 | 21-30 | La camioneta sale del galpón y entra a Barrio Centro; atrás, cada pasajero con su caja | Fila 3 |
| E6 | 30-36 | La puerta del cliente: un pedido llega bien, el siguiente con el contenido equivocado | D-0815.b y D-0817.b ✅ |
| E7 | 36-42 | Pantalla de cierre del día: cobro, alquiler, ganancia | Fila 1 (D-0320 con UI final, grupo 19) |
| E8 | 42-48 | Logo, "Acceso anticipado" o "Wishlist" | — |

Planos de F2 (después de que se cumplan las filas 8 a 11): empleado en la mesa mientras la tripulación sale
(reemplaza E3), bici con dos cajas en una calle angosta (suma después de E5). **Nunca** un plano de F3-F4 ni
de ningún placeholder gris; si una condición no está, el plano se saca y el video se acorta.

## 5. Capturas que faltan

Las de tienda las saca la sesión de arte en la PC (`.claude/rutinas/sesion-arte.md`) con `revisor-visual`
(`tests/render_store_shots.gd`), en 1920×1080. Las 7 del juego base de `estado-steam.md` §3.2 siguen primero:
son las de la página de noviembre.

| # | Escena | `--mood=` | Cámara | Momento | Se puede sacar cuando |
|---|---|---|---|---|---|
| C1 | Galpón a la mañana, 4 jugadores | día | plano general alto desde el tablero | el camión del proveedor en la dársena, uno baja un palet | Filas 1 y 4 |
| C2 | Mesa de armado (con el HUD de calidad: muestra la mecánica) | día | primera persona | metiendo el último producto, relleno a medio poner | Fila 2 |
| C3 | Despacho | tarde | tercera persona, detrás de la camioneta | cargando cajas armadas por la puerta trasera | Filas 1 y 2 |
| C4 | Barrio Centro | atardecer | tercera persona baja | la camioneta en una esquina angosta, una caja asomando | Fila 3 |
| C5 | Cierre del día | — | pantalla | resumen con ganancia | Fila 1 + UI del grupo 19 |
| C6 | (F2) Empleado en la mesa, tripulación saliendo por el portón | día | plano general | — | Fila 9 |

Steam pide 5 como mínimo (§1); la página llega a 10-12 en total. Si la Empresa entra al Early Access, en la
versión B van C1 y C2 entre las tres primeras, después de la caja de carga en una curva (`estado-steam.md`
§3.2, captura 1).

## 6. Riesgos de reseñas

1. **Prometer zonas y vehículos que no llegan.** Con el caso realista (critica-alcance.md: 2027-03-08 para
   la expansión entera) y la física nueva de F3-F4 en riesgo muy alto, cualquier mención de lancha, avioneta
   o volcán en la página es la reseña negativa más probable del Early Access. Por eso §3.1.
2. **Etiquetas que traen otro público.** Management o Automation sin un galpón que se gestione de verdad
   atraen a gente que busca un *factory game*; la reseña es "es un juego de manejar con un menú". Por eso
   las etiquetas van atadas a capturas (§2.3).
3. **"Hasta 8" en la Empresa.** D-2002.5 dice que una salida con 8 todavía pasa el presupuesto de red. Una
   tripulación de 8 que se desincroniza en el galpón deja la reseña de "no anda en coop", la peor para un coop.
4. **La demo no es el juego de la página.** Si la página versión B vende la Empresa y la demo del Next Fest
   es solo la entrega, la gente juega una cosa y compra otra. Mientras la demo sea la entrega, la página se
   queda en la versión A (decisión 3).
5. **Early Access y fecha.** `estado-steam.md` (2026-10-01) todavía muestra la fecha del plan viejo
   (2027-01-22). La vigente es 2027-03-12 con Next Fest de febrero (decisión del 2026-10-04). Qué parte de la
   expansión entra la decide el usuario (#470); esta nota no elige y deja la página lista para cualquiera de
   los dos casos: sin Empresa (versión A) o con la Empresa de F1-F2 (versión B).

## 7. Decisiones

| # | Decisión | Por qué | Descartado |
|---|---|---|---|
| 1 | Regla de §1: se promete solo lo que tiene fase o pieza cerrada **y** captura real sin gris | Regla de Early Access de Steam y de capturas; un equipo de 2 no aguanta una ola de reseñas por promesas | Mostrar el plan entero como "roadmap" en la página (muchos indies lo hacen, pero el riesgo F3-F4 es muy alto) |
| 2 | El gancho y la primera frase no cambian; la Empresa entra como segunda frase | La asimetría entre pasajeros es el diferencial frente a Backseat Drivers y RV There Yet? (`definicion-proyecto.md`); la gestión sola no nos diferencia | Abrir con "Construí tu empresa de reparto" |
| 3 | Dos versiones de la página (A sin Empresa, B con Empresa); se pasa a B recién cuando se cumplen las filas 1 y 2 de §3 **y** la Empresa está en la build que la gente puede jugar | La página no puede vender algo que la demo no tiene (riesgo 4) | Publicar B en noviembre con capturas grises |
| 4 | Tráiler actual intacto; la Empresa en un video aparte de 40-50 s | Los primeros 5 s del tráiler son caos sin contexto; explicar el galpón los rompe. Un segundo video se puede sumar sin tocar el primero | Rehacer el tráiler entero con la Empresa |
| 5 | F3-F4 (lancha, Islas, Montaña, Nieve, avioneta, Volcán) fuera de la página y el tráiler; como mucho una frase genérica en "¿Qué se planea?" | Riesgo muy alto y fuera del caso realista de calendario | Nombrarlos como "próximamente" |
| 6 | Management se suma en B; Automation y Base Building solo con su grupo construido; Open World nunca | Cada etiqueta trae un público que reseña contra ella | Sumar las tres ya, por alcance de búsqueda |
| 7 | "Hasta 8" en la Empresa atado a D-2002.5, D-2023 y la prueba con gente | Extiende la decisión del usuario del 2026-10-04 (punto 5) al modo nuevo | Heredar el "1-8" del juego base |
| 8 | Ninguna cifra de diseño en la página (zonas, km, vehículos, productos, hitos) | Cambian con el balance y los recortes; una cifra no cumplida es una reseña | "9 zonas, 6 vehículos, 30 hitos" |
| 9 | Partida rápida sí va en la página (bullet 6) | Ya existe y la demo es eso; explica por qué hay entrega de 10 min y el día de 18 min | Esconderla para que la Empresa sea lo único |

## 8. Cambios pendientes en otros documentos (para la rutina de lanzamiento)

- **`estado-steam.md`**: §0 punto 5 y §2 todavía toman el Early Access del 2027-01-22 como plan; la decisión
  del 2026-10-04 fijó 2027-03-12 con Next Fest de febrero (calendario B). Sumar un apartado "Expansión" que
  apunte a esta nota, y en §3.2 las capturas C1-C6 con sus condiciones.
- **`trailer.md`**: plano 9, "Rutas nuevas en cada partida", es cierto para la Partida rápida, pero no para la
  Empresa (trazado fijo, vision.md §6). Si el tráiler pasa a vender la Empresa, cambiarlo por "Cada día, una
  ruta distinta" o sacarlo. Plano 13, "1-8 jugadores": condicionarlo a la fila 6 de §3. Agregar una sección
  "Video 2: Modo Empresa" con la tabla de §4.
- **`docs/tareas/S-901.md`**: sumar las versiones A y B de §2 y la tabla de etiquetas de §2.3; el archivo de
  destino `steam-page.md` tiene que separar lo publicable de lo condicionado.
- **`docs/plan-desarrollo.md`** (no es de marketing; lo resuelve el usuario con el #470): la fila Early Access
  dice "1 vehículo, 1 set de tramos" y no menciona la Empresa.
- **`logros-expansion.md`**: anotar que la página no nombra logros de F3-F4 hasta que su fase cierre (Steam
  muestra la lista entera de logros: los de zonas sin construir no se suben a Steamworks antes de tiempo).
