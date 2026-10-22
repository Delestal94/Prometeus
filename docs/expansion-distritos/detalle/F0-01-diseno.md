# F0 · Grupo 01 — Diseño y decisiones (detalle)

> Carril 1 de la rutina `desarrollador`. Documentos en `docs/expansion-distritos/diseno/` (carpeta nueva).
> Ninguna de estas tareas toca código. Las ⏸ no las toma ninguna rutina: abren el issue
> `decide-usuario` (regla 12) y mientras tanto rige [supuestos.md](supuestos.md).

### D-0101 · Documento de visión de la expansión — A · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-04, PR #270)** — `diseno/vision.md`: bucle de 5 pasos, crecimiento, qué se conserva, 9 zonas, flota y "Qué NO es".
**Depende de:** —
**Qué:** `diseno/vision.md` (máx. 250 líneas) con: bucle del día en 5 pasos (README de la expansión),
qué se conserva del juego actual (trampas, cuidado en el asiento, puerta del cliente, mérito/cartas),
qué es nuevo, los 9 distritos y la flota, y una sección "Qué NO es" (no es un simulador de tráfico, no es
un tycoon de planillas: siempre hay una caja en las manos).
- [x] **D-0101.1** Escribir el documento usando el README de la expansión y [supuestos.md](supuestos.md).
- [x] **D-0101.2** Enlazarlo desde `docs/definicion-proyecto.md` (sección "Documentos que desarrollan este concepto").
**Hecho cuando:** el documento existe, está enlazado y cada distrito/vehículo mencionado coincide con la
tabla del README.

### D-0102 · ⏸ decide el usuario: modo Empresa aparte o reemplazo — A · Opus 5.5 · low · Aviso: no · F0
**Depende de:** —
**Qué:** issue `decide-usuario` con tres opciones: (a) modo Empresa nuevo al lado de Entrega y Endless
(**recomendado**, S1), (b) reemplaza Entrega y deja Endless, (c) reemplaza todo. Pros y contras de cada
una, en cantidad de tests que cambian y en riesgo de perder lo jugable.
**Hecho cuando:** el issue está abierto. Cuando el usuario responda: decisión en
`docs/decisiones/AAAA-MM-DD-modo-empresa.md` y S1 actualizado.

### D-0103 · ⏸ decide el usuario: qué es el "carrito" — B · Opus 5.5 · low · Aviso: no · F0
**Depende de:** —
**Qué:** issue con opciones: carrito eléctrico tipo golf (S7, **recomendado**), zorra de mano empujada a
pie, o los dos. Con un párrafo por opción sobre qué juego genera en coop.
**Hecho cuando:** el issue está abierto. Con la respuesta: S7 y D-1221 a D-1230 ajustadas.

### ~~D-0104 · decide el usuario: mapa continuo o un nivel por distrito~~ **[x] Decidido (2026-10-04)**
El usuario eligió **un solo mapa continuo** que se desbloquea. Ver `docs/decisiones/2026-10-04-mapa-continuo.md`.
No se abre issue.

### D-0105 · ⏸ decide el usuario: duración del día — A · Opus 5.5 · low · Aviso: no · F0
**Depende de:** —
**Qué:** issue con la propuesta S3 (08-20 h, 90 s por hora = 18 min) y dos alternativas: día por cantidad
de pedidos (sin reloj), y día de 12 min.
**Hecho cuando:** el issue está abierto.

### D-0106 · ⏸ decide el usuario: galpón vacío — B · Opus 5.5 · low · Aviso: no · F0
**Depende de:** —
**Qué:** issue con la propuesta S4 (se congela sin empleados) y dos alternativas: sigue corriendo y los
proveedores se van, o el host tiene que dejar a alguien.
**Hecho cuando:** el issue está abierto.

### D-0107 · Análisis de *Schedule I* — B · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-12, PR pendiente)** — `diseno/referencia-schedule-1.md`: empleados, estaciones, crecimiento, bucle y quejas con 41 fuentes; tabla de 31 filas Tomamos/Adaptamos/No tomamos con su tarea `D-`.
**Depende de:** —
**Qué:** `diseno/referencia-schedule-1.md` con fuentes web (página de Steam, wiki, reseñas) sobre:
- empleados (contratación, cama/locker, sueldo diario, asignación con portapapeles);
- estaciones y su encadenado;
- cómo crece el negocio (propiedades, zonas);
- qué hace adictivo el bucle;
- qué se queja la gente (micromanejo, IA que se traba).
Termina en una tabla "Tomamos / Adaptamos / No tomamos", cada fila con la tarea `D-` donde impacta.
**Hecho cuando:** el documento tiene la tabla con 15+ filas y cada una cita su fuente.

### D-0108 · Referencias de armado y logística — B · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-19, PR pendiente)** — `diseno/referencias-logistica.md`: Overcooked, Unpacking y encastre, Mini Motorways, shapez, TRDS y Schedule I (crecimiento), cada uno con "lo que copiamos" y su tarea `D-`; tabla de 30 filas, riesgos para un equipo de 2 y 36 fuentes.
**Depende de:** —
**Qué:** `diseno/referencias-logistica.md`: qué hacen bien Overcooked (hojas de pedido, estaciones),
Unpacking/Box-packing (encastre), Mini Motorways/Shapez (cintas, cuellos de botella), Totally Reliable
Delivery Service (física y humor), Schedule I (crecimiento). Una sección por juego con "lo que copiamos"
en una línea y la tarea `D-` donde va.
**Hecho cuando:** 5 juegos cubiertos, con fuentes.

### D-0109 · Tabla "lo que armás es la trampa" — A · Opus 5.5 · high · Aviso: sí (`data/traps/`, `package_content.gd`) · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `diseno/armado-y-trampas.md`: 10 contenidos, fórmula y 6 ejemplos.
**Depende de:** —
**Qué:** `diseno/armado-y-trampas.md`. Para cada uno de los 10 `data/contents/*.tres`:
- su trampa actual;
- qué embalaje la baja (relleno, sello, conservadora) y qué error la sube (caja grande, sin relleno, sin
  sello, mezclado con otro producto).
Además, la fórmula de calidad y absorción de [supuestos.md](supuestos.md), con 6 ejemplos numéricos
resueltos. Y las reglas de mezcla: dos productos en una caja → manda el de mayor dificultad según
`UnlockManager.TRAP_DIFFICULTY_ORDER`; explosivo + frágil → prohibido.
**Hecho cuando:** los 10 contenidos tienen su fila, y los 6 ejemplos dan el mismo número que la fórmula
(los repite el test de D-0709).

### D-0110 · Roles de la tripulación de 1 a 8 — A · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `diseno/roles-tripulacion.md`: regla de 2 min, 4 tablas (1, 2, 3-4, 5-8), qué hace el que se queda y cómo se mide.
**Depende de:** D-0101
**Qué:** `diseno/roles-tripulacion.md` con una tabla por cantidad de jugadores (1, 2, 3-4, 5-8): quién
queda en el galpón, quién sale, cuántas salidas por día, y qué hace el que se queda mientras los otros
manejan (recibir, armar la próxima tanda). Regla: nunca un jugador más de 2 min sin una caja en las manos
o un vehículo que manejar (medible con el bot de D-0111).
**Hecho cuando:** las 4 tablas están, y cada rol nombra las estaciones de D-0904.

### D-0111 · Definición exacta del corte vertical F1 — A · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `diseno/corte-vertical.md`: 17 ítems de F1 con su tarea `D-`, lo que no entra, criterio de cierre del bot y umbrales.
**Depende de:** D-0101, D-0110
**Qué:** `diseno/corte-vertical.md` con la lista cerrada de lo que entra en F1:
- galpón por defecto, 1 proveedor y los 10 productos de `data/contents/`;
- cajas S-XL, pedidos para Barrio Centro y Campo, camioneta actual, cierre del día;
- arte gris permitido.
Criterio de cierre: el bot `tests/bot_company_day.gd` (lo crea D-2016) juega un día
completo en headless con 2 jugadores simulados. Debe recibir el palet, armar 6 cajas, despachar una
salida a Barrio Centro, volver y cerrar el día con ganancia > 0, sin `ERROR`/`SCRIPT ERROR` en el log.
`bench_company` dentro del presupuesto de D-2012.
**Hecho cuando:** el documento existe y cada ítem nombra su tarea `D-`.

### D-0112 · Crítica de alcance contra la capacidad del equipo — A · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-19, PR pendiente)** — `diseno/critica-alcance.md`: estimación por grupo, 3 peores costo/valor, 287 tareas tachadas (42 recortadas, 148 pospuestas, 97 fusionadas) sin tocar la fila 5; zona gris y alcance del Early Access en el issue #470 (D-0113).
**Depende de:** D-0101
**Qué:** pasada de `critico-diseno` a los 20 grupos. Informe `diseno/critica-alcance.md`:
- estimación en semanas-persona por grupo;
- las 3 features con peor costo/valor;
- recortes propuestos, con lista de IDs para cada uno.
**Hecho cuando:** el informe existe y D-0113 tiene su issue.

### D-0113 · ⏸ decide el usuario: recortes de D-0112 — A · Opus 5.5 · low · Aviso: no · F0
**Depende de:** D-0112
**Qué:** un issue `decide-usuario` con cada recorte como casilla. Con la respuesta, tachar (`~~D-XXXX~~`)
en las tablas de grupo lo que se recorte.
**Hecho cuando:** el issue está abierto.

### D-0114 · Tabla de distritos definitiva — B · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `diseno/distritos.md`: 9 zonas con vehículos, peligros, casas, ruta, clima, envío y apertura.
**Depende de:** D-0101
**Qué:** `diseno/distritos.md`. Por distrito:
- vehículos permitidos y peligros (los existentes por nombre de clase: `ChasingDog`, `MudSpot`,
  `FlockCrossing`, `LowVisibilityEvent`…);
- cantidad de casas por salida (3-6), largo de ruta objetivo en minutos (regla N-102: 2-5) y condición
  de desbloqueo;
- clima permitido (perfiles de `WorldMood`).
Es la fuente para los `.tres` de D-0205.
**Hecho cuando:** 9 filas completas. El README apunta a este documento.

### D-0115 · Tabla de vehículos definitiva — B · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-19, PR #487)** — `diseno/flota.md`: 8 filas (el detalle enumera 8 aunque dice 7), campos de `VehicleDefinition` para D-0207 más `fleet_key` y `amplified_trap`, regla de trampa amplificada ×1,5 y base fija por unidad.
**Depende de:** D-0101
**Qué:** `diseno/flota.md`. Por vehículo:
- asientos, capacidad (cajas y kg), velocidad máxima y quién maneja;
- qué trampa amplifica (bici → Equilibrio, lancha → Líquido, avioneta → Frágil);
- licencia, precio y distritos.
Incluye los 3 `UnlockManager.TRUCKS` actuales como variantes de la camioneta.
**Hecho cuando:** 7 filas (camioneta ×3 variantes, 4x4, bici, carrito, lancha, avioneta). Es la fuente de D-0207.

### D-0116 · Catálogo inicial de productos — A · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `diseno/catalogo-productos.md`: 10 de F1 + 30 nuevos en 3 lotes.
**Depende de:** D-0109
**Qué:** `diseno/catalogo-productos.md`. Para los 10 contenidos actuales y 30 nuevos:
- id, contenido base (`PackageContent` existente o "nuevo, necesita modelo") y celdas (X×Y×Z en celdas de 0,2 m);
- kg, frágil sí/no, temperatura (ambiente/frío/calor) y precio de compra;
- distrito donde se pide más y la trampa.
Los 10 primeros alcanzan para F1; los 30 nuevos son el pedido a `sesion-arte` (D-1802 a D-1805).
**Hecho cuando:** 40 filas, y las 10 de F1 con todos los campos que pide `ProductDefinition` (D-0204).

### D-0117 · Modelo económico en papel — A · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-04, PR pendiente)** — `diseno/economia.md`: pedido medio (210 de ingreso, ≈102 de margen), curva de 20 días para 1/2/4 jugadores, precios de mejoras y lista de constantes para `company_tuning.gd`.
**Depende de:** D-0116
**Qué:** `diseno/economia.md` con:
- ingresos por pedido promedio, costos de insumos, alquiler y precios de mejoras;
- curva de 20 días para 1, 2 y 4 jugadores, en una tabla día × plata calculada a mano o con una hoja.
Objetivos: primera mejora el día 2-3, segundo distrito el día 4-6, nunca quiebra con juego correcto.
Confirma o corrige los números de [supuestos.md](supuestos.md).
**Hecho cuando:** la tabla existe, y los números que cambian quedan listados para `company_tuning.gd`
(D-0202). `sim_economy` (D-0540) la reproduce en F2.

### D-0118 · Lista de 30 hitos — B · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-21, PR #563)** — `diseno/hitos.md`: 30 hitos con condición, recompensa y día esperado para 1/2/4 jugadores; cada distrito con su hito y tipo nuevo `shop_item`.
**Depende de:** D-0114, D-0117
**Qué:** `diseno/hitos.md`: id, condición (de los tipos de D-0402), recompensa (tipos de D-0403) y día
esperado según D-0117. Los primeros 5 enseñan el bucle (D-0412).
**Hecho cuando:** 30 filas, y cada distrito tiene su hito de desbloqueo.

### D-0119 · Qué se reutiliza y qué se reemplaza — A · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-04, PR #305)** — `diseno/reutilizacion.md`: 28 sistemas (igual / envuelto / reemplazado) con archivo:línea, archivo nuevo y tarea; decisión del flag `--autostart-company`.
**Depende de:** —
**Qué:** `diseno/reutilizacion.md`. Por sistema, cómo se usa en modo Empresa (igual / envuelto /
reemplazado) y con qué archivo nuevo:
- `Depot` (`post_orders`, `stock_shelves`, `begin_run`, `request_supply`) y `DepotStation`;
- `DepotOrderBoard`, `DepotWorker`, `DeliveryHouse` y `RouteStreamer`;
- `RunManager` y `CrewProgression` (`team_money`, `SUPPLIES`);
- `UnlockManager` (`TRUCKS`, `TRAP_UNLOCKS`), `PackageContent`, `DeliveryPackage`, `SceneLoader` y
  `NetworkManager.LEVEL_SCENES`.
Regla: modo Entrega y Endless no cambian de comportamiento (S1).
**Hecho cuando:** 15+ sistemas con su fila, y cada fila con archivo y línea de entrada.

### D-0120 · Riesgos técnicos — B · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-21, PR pendiente)** — `diseno/riesgos.md`: 16 riesgos (1 P0, 9 P1, 6 P2) con evidencia, mitigación y tarea `D-` (todos los P0-P1 con tarea abierta); 4 propuestas "sin tarea todavía".
**Depende de:** D-0119
**Qué:** `diseno/riesgos.md` con severidad P0-P3:
- red (galpón con 300+ objetos);
- guardado a mitad de día;
- rendimiento de cintas y empleados;
- `--script` que pierde autoloads al nombrar clases nuevas (N-919);
- Jolt con muchos cuerpos (N-917).
Cada riesgo con su mitigación y la tarea que la hace.
**Hecho cuando:** 10+ riesgos, cada P0-P1 con su tarea `D-`.

### D-0121 · Narrativa de la empresa — B · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-22, PR #626)** — `diseno/narrativa-empresa.md`: la Jefa sigue mandando sin cara, premisa del galpón prestado, tono de 6 tipos de mensaje y textos actuales fuera de tono.
**Depende de:** D-0101
**Qué:** `diseno/narrativa-empresa.md`, alineado con `docs/narrativa.md` (que no se edita):
- [x] D-0121.1 Quién manda (la Jefa Marta sin cara, el Jefe del depósito visible), por qué empezamos y por
  qué crece a distritos.
- [x] D-0121.2 Tono por tipo de mensaje (pedido, vencimiento, reclamo, felicitación, cierre, quiebra) con
  ejemplos, reglas para textos nuevos y tabla de qué texto del código queda fuera de tono.
Decisión: `docs/decisiones/2026-10-22-narrativa-empresa.md`. Los textos fuera de tono se reescriben en
las tareas de pedidos y cierre (D-0822 mensajes con humor).
**Hecho cuando:** `diseno/narrativa-empresa.md` alineado con `docs/narrativa.md`.

### D-0123 · Diseño de eventos del día — B · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-22, PR pendiente)** — `diseno/eventos-del-dia.md`: 15 eventos (6 Núcleo F1, 5 Ampliación F1, 4 Ampliación F2; 4 positivos, 3 negativos, 8 mixtos), reglas de frecuencia y anuncio, sorteo con la corriente `events` de la semilla del día, techo diario de 150 / 300, red por `CompanyNet` y tareas nuevas a crear en el grupo 05.
**Depende de:** D-0101, D-0110, D-0117, D-0121, D-0246, D-2001
**Qué:** `diseno/eventos-del-dia.md`, que no resucita nada de P14 ni de R4:
- [x] **D-0123.1** Propósito, qué no son (ni peligros de zona ni contratos de varios días) y cómo conviven con `RouteEventManager` (ids distintos: `shed_inspection` ≠ `inspection`).
- [x] **D-0123.2** Reglas generales: cuántos por día según el día de campaña y la tripulación, cuándo se anuncian (víspera, apertura, a una hora, al llegar), sorteo en el host con `CompanySeed.for_day(…, "events")` al cerrar el día anterior, sin repetir dos días seguidos, techo de castigo y premio por día, escalado de 1 a 8 jugadores y modo solo, constantes en `CompanyTuning` y `.tres` en `data/day_events/`.
- [x] **D-0123.3** Los 15 eventos (incluye inspección, proveedor tarde, pedido gigante, huelga de transporte y ola de calor), cada uno con anuncio en el tono de narrativa-empresa.md, sistema que toca, números, decisión, resultado, día mínimo, fase y requisitos; tabla resumen con costo.
- [x] **D-0123.4** Red y guardado (`day_event_announced/started/progress/ended`, petición `day_event_answer`, parte de snapshot `day_events`, `CompanyState.day_events` en el save), tareas que lo construyen, riesgos y "Decidir al final".
Decisión: `docs/decisiones/2026-10-22-eventos-del-dia.md`. Lo que se construye son tareas nuevas a crear
en el grupo 05, después de cerrar el corte vertical.
**Hecho cuando:** `diseno/eventos-del-dia.md` tiene los 15 eventos y su tabla resumen.

### D-0124 · Diseño de las licencias — B · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-22, PR #640)** — sección "Las licencias" de `diseno/hitos.md`: 5 licencias con precio (650 / 600 / 1 000 / 1 000 / 1 000), qué abren, compra única de la empresa en la tienda, nunca se pierden, claves de `equipment` con tipo de tienda `license` y `requires` para vehículos.
**Depende de:** D-0115, D-0117, D-0118
**Qué:** completar la sección "Las licencias" de `diseno/hitos.md` (D-0118 fijó cuándo se ofrecen):
- [x] D-0124.1 Precio y qué abre (y qué no) cada una de las cinco, sin mover los días de apertura de la tabla
  de distritos.
- [x] D-0124.2 Cómo se obtienen: hito → tienda → compra única de la empresa; sin examen, sin vencimiento, no se
  pierden con la quiebra; qué se ve en el bloqueo y en la tienda; primer vuelo guiado (D-1418).
- [x] D-0124.3 Cómo se guardan y se piden, para D-0407: claves `license_*` en `CompanyState.equipment`, tipo
  `license` en `ShopItem`, `requires` también para vehículos, `GateRequirement.equipment` en los bloqueos (`gate_puerto` cambia el hito por la licencia).
Decisión: `docs/decisiones/2026-10-22-licencias.md`.
**Hecho cuando:** `diseno/hitos.md` dice cómo se obtiene cada licencia, cuánto cuesta y qué abre.

### D-0126 · Modo solo — B · Opus 5.5 · high · Aviso: no · F0
**[x] Hecho (2026-10-22, PR #645)** — sección "Modo solo" de `diseno/roles-tripulacion.md` (§6): sin modo aparte; tres ayudas nuevas (pausa de verdad sin peers, pedidos que entran hasta las 15:00 del galpón con 1 jugador, pedido automático al proveedor al cierre para todos) y cinco que ya existen; lo construye D-0151.
**Depende de:** D-0110, D-0117, D-0123
**Qué:** escribir qué automatiza el juego para una persona sola, con la crítica de `critico-diseno`:
- [x] D-0126.1 Regla: `crew_size` al abrir el día para lo del día, en vivo para la pausa y el asistente de
  estante; se automatiza lo que hace "el que se queda" cuando el solitario está en la ruta, nunca el núcleo.
- [x] D-0126.2 Las ayudas nuevas con sus constantes (`SOLO_ORDER_LAST_ARRIVAL_MIN`, `SOLO_ORDER_CASH_RESERVE`)
  y la fórmula del pedido sugerido; las que ya existen, en una tabla aparte.
- [x] D-0126.3 Lo que no se automatiza (mesa llena al abrir, compañero IA, ventana más larga), con empleados y
  cómo se mide (D-2016, D-2024).
- [x] D-0126.4 §1 alineado con el código: los pedidos entran y vencen con la hora del galpón (D-0813.1).
Decisión: `docs/decisiones/2026-10-22-modo-solo.md`.
**Hecho cuando:** `diseno/roles-tripulacion.md` dice qué automatiza el modo solo y cómo lo mide el bot de D-2024.

### D-0127 · Dificultad y modificadores — B · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-22, PR #654)** — `diseno/dificultad.md`: una sola dificultad; dos modificadores de la empresa (armado asistido con absorción mínima 0,75, días tranquilos), elegidos por el host fuera de la partida, en `CompanyState.options` sin RPC; lo construye D-1919.
**Depende de:** D-0112, D-0123, D-0126
**Qué:** `diseno/dificultad.md` (máx. 120 líneas), dentro del recorte de D-0112 (una sola dificultad con armado
asistido, `critica-alcance.md` §4.5):
- [x] D-0127.1 Por qué una sola dificultad: qué ya ajusta el esfuerzo (tripulación, día de campaña, empresa en
  rojo) y por qué no hay tamaños de empresa.
- [x] D-0127.2 Los modificadores, con qué hacen y qué no tocan: armado asistido (`assisted_packing`) y días
  tranquilos (`calm_days`); los descartados con su motivo.
- [x] D-0127.3 Armado asistido: orden de la cinta (relleno sin dejar la caja sin cerrar), caja `assisted` con
  absorción mínima 0,75 para que lo hecho a mano valga más, aviso de relleno insuficiente.
- [x] D-0127.4 Quién los elige y cuándo (host, solo fuera de la partida: empresa nueva y lista de guardados),
  cómo se guardan (`CompanyState.options`, sin subir la versión del save), red (sin RPC), dónde se ven, y que no
  bloquean hitos ni logros.
- [x] D-0127.5 Qué construye D-1919, con sus tests. Revisado por `critico-diseno`.
Decisión: `docs/decisiones/2026-10-22-dificultad.md`.
**Hecho cuando:** `diseno/dificultad.md` existe y D-1919 lo puede construir sin preguntar.

### D-0129 · Glosario de la expansión — B · Opus 5.5 · low · Aviso: no · F0
**[x] Hecho (2026-10-22, PR #660)** — `diseno/glosario.md`: 33 conceptos del modo Empresa en ES/EN con uso y descartados; 14 con chequeo en `test_ui_translations` (`_check_company_glossary`).
**Depende de:** —
**Qué:** una palabra por concepto en los textos nuevos (pedido, remito, palet, estación, turno, hito…),
armado con lo que ya dicen `strings_ui.csv` / `strings_world.csv`:
- [x] D-0129.1 `diseno/glosario.md`: concepto, ES, EN, uso y descartados; amplía `docs/glosario.md` (que
  enlaza acá) sin repetirlo.
- [x] D-0129.2 "Lo usa `loc_text`": las claves que viajan con `LocText` salen de las mismas tablas, así que el
  chequeo va sobre la tabla de UI: si el español dice "palet" el inglés dice "pallet" (14 pares) y los
  descartados (tarima, albarán, warehouse, licence…) no aparecen.
- [x] D-0129.3 El agente `localizador` lo lee junto con `docs/glosario.md`.
**Test** `test_ui_translations` (`_check_company_glossary`).
**Hecho cuando:** `diseno/glosario.md` existe y el test lo cumple sobre las tablas actuales.

### D-0130 · Tabla de la primera semana — B · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-22, PR pendiente)** — `diseno/onboarding.md`: día 1 = el bucle en 6 objetivos (con pedido de 1 unidad a las 08:00), 12 filas más con disparador y día mínimo, progreso por jugador en `seen_tips` sin RPC ni campo de save; `teaches_key` de los hitos 1-5 queda como repaso. Lo construye D-1901.
**Depende de:** D-0111, D-0118, D-0720, D-0812
**Qué:** `diseno/onboarding.md` (máx. 120 líneas), con la crítica de `critico-diseno`:
- [x] D-0130.1 Reglas: el día 1 es el tutorial, una cosa nueva por día, se enseña por disparador y no por
  calendario, una sola línea guía, voz de la Jefa en el feed.
- [x] D-0130.2 La tabla de los 7 días (qué aprende, disparador, objetivo o nota, hecho cuando, tareas), que
  funciona igual en F1 sin hitos.
- [x] D-0130.3 El día 1 paso por paso y qué ve cada jugador con 2 o más (la línea mira primero lo que tiene en
  la mano).
- [x] D-0130.4 Estado y red para D-1901: función pura `CompanyOnboarding.current`, `mark_tip_seen` por jugador,
  claves `UI_ONBOARD_*` / `WORLD_ONBOARD_*`, cómo lo mide `bot_company_day`.
Decisión: `docs/decisiones/2026-10-22-primera-semana.md`.
**Hecho cuando:** `diseno/onboarding.md` existe y D-1901 lo puede construir sin preguntar.

### D-0131 · Portapapeles de gestión — A · Opus 5.5 · medium · Aviso: no · F0
**[x] Hecho (2026-10-22, PR pendiente)** — `diseno/portapapeles.md`: objeto en la mano desde el día 1 con hojas Stock y Proveedor (Empleados con el hito 8), guardado ↔ levantado en F1 y bajado/apuntar con D-1004, manos ocupadas definidas en código, `held_tool` replicado sin RPC. Lo construye D-1902.
**Depende de:** D-0107, D-0603, D-0612
**Qué:** `diseno/portapapeles.md` con wireframes en texto, con la crítica de `critico-diseno`:
- [x] D-0131.1 Reglas: objeto que ocupa las manos, desde el día 1, junta paneles existentes (modo `embedded`),
  leer local y decidir en el host, los tableros de la pared se quedan.
- [x] D-0131.2 Posiciones, hojas (como mucho 3), controles con los choques reales del input map y manos ocupadas.
- [x] D-0131.3 Red y presentación: `held_tool` en `Repl_player`, sin save ni snapshot; qué toma cada tarea y qué
  otros docs cambian (D-1902, D-1240 recortada, D-0838 en el tablero, red-autoridad fila 1).
Decisión: `docs/decisiones/2026-10-22-portapapeles.md`.
**Hecho cuando:** `diseno/portapapeles.md` existe y D-1902 lo puede construir sin preguntar.

### D-0134 · Qué se guarda entre sesiones — A · Opus 5.5 · medium · Aviso: no · F0 (Ampliación)
**[x] Hecho (2026-10-22, PR pendiente)** — `diseno/guardado.md`: el save siempre es la apertura de un día; un día cortado vuelve a su apertura (D-0251); el host puede cerrar el día antes (D-0253); lo suelto va a un bulto de devolución (D-0252); tabla de lo que se guarda y lo que se recalcula.
**Depende de:** D-0206, D-0236, D-2005
**Qué:** `diseno/guardado.md` con qué se guarda y qué no (empresa, stock, empleados, día en curso), contrastado con
`CompanySave`, `CompanyState` y `CompanyRoot`.
- [x] D-0134.1 Reglas: un punto de guardado por día (la apertura), un día cortado vuelve a su apertura, solo guarda
  el host, lo que sale de la semilla no se guarda, versión del save.
- [x] D-0134.2 Tabla de claves de `CompanyState` y de lo que viene (eventos, opciones, empleados, máquinas).
- [x] D-0134.3 El stock al guardar (bulto de devolución, reservas en 0) y lo que no se guarda con su origen al cargar.
- [x] D-0134.4 Tareas D-0251 a D-0253, cambios en red-autoridad y riesgos, y bug del autoelevador. Revisado por
  `critico-diseno`.
Decisión: `docs/decisiones/2026-10-22-guardado.md`.
**Hecho cuando:** `diseno/guardado.md` existe y D-0251 a D-0253 se pueden construir sin preguntar.

### D-0135 · Clima y temperatura por zona — B · Opus 5.5 · medium · Aviso: no · F0 (Ampliación)
**[x] Hecho (2026-10-22, PR pendiente)** — sección "Clima y temperatura por zona" en `diseno/distritos.md`: clima por zona y por día desde la semilla de la empresa (un frente para el llano, el evento gana, días 1-3 sin lluvia), la lluvia baja el agarre ×0,75 por `GripZones`, temperatura de la zona de destino por salida en `ColdPack`. Lo construye D-0324 (versión mínima); el cruce entre zonas, D-1610.
**Depende de:** D-0114, D-0205, D-0721
**Qué:** tabla de clima por zona con su efecto en la carga y el vehículo, contrastada con `WorldMood`,
`GripZones`, `ColdPack` y el mapa continuo.
- [x] D-0135.1 Reglas: un clima por zona y por día desde `company_seed`, frente del llano con los cuatro perfiles,
  el evento gana y días 1-3 sin lluvia, el clima no rompe cajas solo, la jugabilidad lee la zona del vehículo,
  sin clima en el galpón, Entrega y Endless sin cambios, Ampliación de F1.
- [x] D-0135.2 Tabla de perfiles (existentes y nuevos) con efecto en vehículo, carga y visibilidad, y tablas de las
  zonas de altura.
- [x] D-0135.3 Temperatura de la zona por salida sobre los productos fríos y calientes (máximo con la ola de
  calor), medida de la lluvia y qué tarea construye cada cosa. Revisado por `critico-diseno`.
Decisión: `docs/decisiones/2026-10-22-clima-por-zona.md`.
**Hecho cuando:** la sección existe y D-0324 la puede construir sin preguntar.

### D-0136 · Horario de clientes y ventanas de entrega — A · Opus 5.5 · low · Aviso: no · F0
**[x] Hecho (2026-10-22, PR pendiente)** — `diseno/clientes.md`: un solo horario para todos (reciben mientras el día está abierto), desde las 20:00 no sale ningún vehículo y la salida rechazada no frena el resumen, lo que ya está en la ruta se entrega igual, la tardanza se mide con la hora del galpón, sin tope de ventana, en `CLOSING` se sigue venciendo, al cierre lo vencido falla (−3) y lo que está en ventana se cancela gratis, el cierre anticipado falla todo. Lo construye D-0851.
**Depende de:** D-0105, D-0134, D-0807, D-0813.1
**Qué:** reglas de cuándo recibe un cliente, contrastadas con S3, S4, `guardado.md` y el código de `OrderBook`, `DayCycle` y `CompanyTrips`.
- [x] D-0136.1 Reglas 1 a 10 y lo que queda afuera (D-0825 y D-0339 siguen pospuestas; aviso de las 19:00 y línea del resumen, a Pulido).
- [x] D-0136.2 Tarea D-0851 en el grupo 08 con su detalle y su test. Revisado por `critico-diseno` (cierre en `CLOSING` y no dentro de `SUMMARY`, vencer en `CLOSING`, cierre anticipado según `guardado.md`, salida rechazada que trababa el día).
Decisión: `docs/decisiones/2026-10-22-horario-clientes.md`.
**Hecho cuando:** `diseno/clientes.md` existe y D-0851 se puede construir sin preguntar.

### D-0137 · Cosméticos de la empresa — A · Opus 5.5 · low · Aviso: no · F0
**[x] Hecho (2026-10-22, PR #700)** — `diseno/cosmeticos-empresa.md`: cuatro ranuras (pintura, franja, logo, uniforme) que salen de los hitos cumplidos, las elige el host en el cierre desde un bloque de la tienda, una pintura para toda la flota (solo carrocería), logo de lista cerrada, uniforme solo en empleados y copa fija del volcán. Lo construyen D-0437 y D-1234.
**Depende de:** D-0118 (`diseno/hitos.md`), D-0112 (P8 de la crítica de alcance)
**Qué:** qué cosméticos hay, de quién son, quién y dónde los elige, cómo se ven en cada vehículo y cómo viajan por la red, contrastado con `UnlockManager`, `CompanyShopPanel`, `vehicle.gd`, `reference_truck.gd` y `red-autoridad.md`.
- [x] D-0137.1 Reglas 1 a 9, los 10 cosméticos de los hitos más los 4 de base (18 elegibles), dónde va cada cosa en cada vehículo, datos, guardado y red.
- [x] D-0137.2 Detalle de D-0437 (`detalle/F2-04-progresion.md`) y D-1234 (`detalle/F2-12-flota.md`) con su test. Revisado por `critico-diseno` (tienda sin pestañas ni fase OPENING, uniforme fuera del jugador, color de carrocería local, logo fuera de las puertas, ayudante de red propio, repintar con el snapshot).
Decisión: `docs/decisiones/2026-10-22-cosmeticos-empresa.md`.
**Hecho cuando:** `diseno/cosmeticos-empresa.md` existe y D-0437 y D-1234 se pueden construir sin preguntar.

### D-0138 · Logros de Steam de la expansión — A · Opus 5.5 · low · Aviso: no · F0 (Ampliación)
**[x] Hecho (2026-10-22, PR #705)** — `docs/marketing/logros-expansion.md`: 30 logros `EXP_` (13 de progreso, 9 de habilidad coop, 8 graciosos; 5 ocultos), todos alcanzables con 1 y con 8 jugadores, decididos en el host y recibidos por los presentes, con condición medible, fase, 2 stats y pedido de ícono por logro. Lo construye D-0440.
**Depende de:** D-0118 (`diseno/hitos.md`), D-0127 (los modificadores no bloquean), D-0112 (lo recortado no tiene logro)
**Qué:** lista de 30 logros del modo Empresa en `docs/marketing/`, contrastada con las señales que ya existen
(`EventBus`, `CompanyNet`, `OrderBook`, `CompanyFleet`) y separada de los 15 del juego actual (S-907, prefijo `BASE_`).
- [x] D-0138.1 Reglas: 1 a 8 jugadores, ninguno perdible, sin grindeo (techo 100 entregas), banderas de desarrollo
  bloquean, logros de equipo para los presentes, el que entra tarde no recibe lo anterior.
- [x] D-0138.2 Tabla de 30 con API name, nombre y descripción es/en, condición, fase F1-F4, oculto y stat.
- [x] D-0138.3 Pedido de ícono por logro para `artista-conceptual` y la lista de lo que construye D-0440.
Decisión: `docs/decisiones/2026-10-22-logros-expansion.md`.
**Hecho cuando:** `docs/marketing/logros-expansion.md` existe y D-0440 lo puede construir sin preguntar.

### D-0151 · Ayudas del modo solo — A · Opus 5.5 · high · Aviso: no · F1 (Ampliación)
**Depende de:** D-0126, D-0603 (pedido al proveedor), D-0813.1 (pedidos del día), D-0219 (reloj)
**Qué:** las tres ayudas de `diseno/roles-tripulacion.md` §6.2, en el host y sin RPC nuevo.
- [x] D-0151.1 (2026-10-22) Pausa de verdad: con el host sin peers, la pausa del menú pausa el árbol y `GameClock`;
  despausar reanuda el reloj solo si lo pausó el menú (no en SUMMARY); un peer que entra despausa antes del
  snapshot. Online con alguien más, la pausa de hoy. Quedó en `CompanySoloPause`
  (`scripts/gameplay/company_solo_pause.gd`, hijo de `CompanyRoot`, test `test_company_solo_pause`): Esc y
  `EventBus.pause_requested` la activan, `NetworkManager.roster_changed` (antes del snapshot) la desactiva.
- [x] D-0151.2 (2026-10-22) `OrderRhythm`: con `crew_size` 1 el último pedido entra a `CompanyTuning.SOLO_ORDER_LAST_ARRIVAL_MIN`
  (15:00), comprimiendo las horas de `ORDER_HOUR_WEIGHTS`; la cantidad no cambia. Misma semilla → mismos pedidos.
- [ ] D-0151.3 Pedido sugerido (la parte pura, `SupplierOrderCart.suggested()` y `ordered_units()`, hecha el
  2026-10-22). **D-0151.3b hecha (2026-10-22):** al pasar a CLOSING (20:00 o cierre anticipado), si no hay camión
  para mañana, el host manda el sugerido una vez por día (`SupplierAutoOrder` puro + `SupplierAutoOrderHook`, que
  sigue `event_applied`), por el mismo `ask()` que un pedido de jugador y como evento `ORDERED` con `peer` 0
  (`CompanySupplierNet.AUTO_PEER`); el resumen del día dice "Pedido automático al proveedor: N unidades". Falta
  **D-0151.3c**: el carrito que se abre precargado con el sugerido menos lo ya pedido. Lo que decía D-0151.3b: el carrito precargado, **menos lo ya pedido para mañana** con la línea "ya pedido: X"
  ([portapapeles.md](../diseno/portapapeles.md) §3), y el envío del host al pasar a CLOSING con su línea en el
  resumen) (`SupplierOrderCart.suggested(...)`, puro): `max(0, pedido hoy − stock)` por
  producto, recortado desde el de menos unidades hasta `plata − RENT_PER_DAY − SOLO_ORDER_CASH_RESERVE`; el carrito
  se abre precargado; al pasar a CLOSING, si no hay pedido para mañana, el host lo manda y lo anota el resumen.
**Test** `test_company_solo_assists`: la pausa sin peers frena `minute_now()` y no la despausa el menú en SUMMARY;
con 1 jugador ningún pedido llega después de las 15:00 y con 2 sí puede; el sugerido de un día conocido da las
unidades esperadas y respeta la reserva; un cierre sin pedido deja uno en `SupplierSchedule` para mañana.
**Hecho cuando:** el test pasa y el bot de 1 jugador (D-2016) cierra el día 2 con stock comprado sin tocar el tablero.

### D-0141 · Agente `constructor-negocio` — A · Opus 5.5 · medium · Aviso: no · F0 (Ampliación)
**[x] Hecho (2026-10-22, PR #724)** — `.claude/agents/constructor-negocio.md` (Sonnet 5.5, `high`, como los demás constructores) para galpón, stock, armado, pedidos puestos en el galpón, empleados y automatización; listado en `CLAUDE.md`, en la tabla de `construccion.md` §3 y en los carriles 2 y 3 de `desarrollador.md`.
**Depende de:** D-0144 (dominios de `business/`, `fleet/`, `districts/`)
**Qué:** el agente que construye `scripts/gameplay/business/` y sus vistas, con el mapa de archivos por
familia, las reglas del modo (host autoritativo, simulación aparte, números en `CompanyTuning`, guardado
y snapshot, placeholder gris, límite de 1000 líneas) y qué devuelve. La plata, los precios y el libro de
pedidos siguen con `constructor-progresion`; la red de la Empresa, con `constructor-red`.
**Test:** no hay código; `tools/panel/build_data.py` ya lo tenía en el pilar "Sistemas". Cierra la
mitad de A-3.8 (auditoría del 2026-10-19, el agente que no existía); `fleet/`, `districts/` y `town/`
siguen sin fila en `construccion.md` §3.
**Hecho cuando:** el archivo está versionado con `model` y `effort`, y `CLAUDE.md` lo nombra.
