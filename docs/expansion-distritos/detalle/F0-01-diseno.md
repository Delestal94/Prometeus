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
**Depende de:** D-0101
**Qué:** `diseno/roles-tripulacion.md` con una tabla por cantidad de jugadores (1, 2, 3-4, 5-8): quién
queda en el galpón, quién sale, cuántas salidas por día, y qué hace el que se queda mientras los otros
manejan (recibir, armar la próxima tanda). Regla: nunca un jugador más de 2 min sin una caja en las manos
o un vehículo que manejar (medible con el bot de D-0111).
**Hecho cuando:** las 4 tablas están, y cada rol nombra las estaciones de D-0904.

### D-0111 · Definición exacta del corte vertical F1 — A · Opus 5.5 · high · Aviso: no · F0
**Depende de:** D-0101, D-0110
**Qué:** `diseno/corte-vertical.md` con la lista cerrada de lo que entra en F1:
- galpón por defecto, 1 proveedor y los 10 productos de `data/contents/`;
- cajas S-XL, pedidos para Barrio Centro y Campo, camioneta actual, cierre del día;
- arte gris permitido.
Criterio de cierre: el bot `tools/bot_company_day.gd` (lo crea D-2016) juega un día
completo en headless con 2 jugadores simulados. Debe recibir el palet, armar 6 cajas, despachar una
salida a Barrio Centro, volver y cerrar el día con ganancia > 0, sin `ERROR`/`SCRIPT ERROR` en el log.
`bench_company` dentro del presupuesto de D-2012.
**Hecho cuando:** el documento existe y cada ítem nombra su tarea `D-`.

### D-0112 · Crítica de alcance contra la capacidad del equipo — A · Opus 5.5 · high · Aviso: no · F0
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
**Depende de:** D-0116
**Qué:** `diseno/economia.md` con:
- ingresos por pedido promedio, costos de insumos, alquiler y precios de mejoras;
- curva de 20 días para 1, 2 y 4 jugadores, en una tabla día × plata calculada a mano o con una hoja.
Objetivos: primera mejora el día 2-3, segundo distrito el día 4-6, nunca quiebra con juego correcto.
Confirma o corrige los números de [supuestos.md](supuestos.md).
**Hecho cuando:** la tabla existe, y los números que cambian quedan listados para `company_tuning.gd`
(D-0202). `sim_economy` (D-0540) la reproduce en F2.

### D-0118 · Lista de 30 hitos — B · Opus 5.5 · medium · Aviso: no · F0
**Depende de:** D-0114, D-0117
**Qué:** `diseno/hitos.md`: id, condición (de los tipos de D-0402), recompensa (tipos de D-0403) y día
esperado según D-0117. Los primeros 5 enseñan el bucle (D-0412).
**Hecho cuando:** 30 filas, y cada distrito tiene su hito de desbloqueo.

### D-0119 · Qué se reutiliza y qué se reemplaza — A · Opus 5.5 · high · Aviso: no · F0
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
**Depende de:** D-0119
**Qué:** `diseno/riesgos.md` con severidad P0-P3:
- red (galpón con 300+ objetos);
- guardado a mitad de día;
- rendimiento de cintas y empleados;
- `--script` que pierde autoloads al nombrar clases nuevas (N-919);
- Jolt con muchos cuerpos (N-917).
Cada riesgo con su mitigación y la tarea que la hace.
**Hecho cuando:** 10+ riesgos, cada P0-P1 con su tarea `D-`.
