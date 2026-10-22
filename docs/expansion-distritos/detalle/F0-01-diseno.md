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
