# Grupo 01 — Diseño, decisiones y agentes

> Fase **F0** · Dueño: Nacho · Depende de: — · Bloquea: todo el resto.
> Lo que hay que decidir y escribir antes de construir. Los ⏸ los decide el usuario; el resto se
> escribe en `docs/expansion-distritos/diseno/` (carpeta nueva) y lo revisa `critico-diseno`.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0101 | Documento de visión de la expansión: bucle del día, crecimiento, distritos, flota, qué se mantiene del juego actual | documentador | high | `diseno/vision.md` existe, enlazado desde el README y `definicion-proyecto.md` |
| D-0102 | ✅ Modo Empresa es el juego principal; Entrega y Endless quedan como "Partida rápida" | — | — | decidido (decidido 2026-10-04, `docs/decisiones/2026-10-04-expansion-decisiones-delegadas.md`) |
| D-0103 | ✅ Carrito = eléctrico tipo golf; la zorra es herramienta del galpón | — | — | decidido |
| D-0104 | ✅ Un solo mapa continuo que se desbloquea (usuario; `docs/decisiones/2026-10-04-mapa-continuo.md`) | — | — | decidido |
| D-0105 | ✅ Reloj de 08:00 a 20:00, 90 s reales por hora de juego | — | — | decidido |
| D-0106 | ✅ Sin nadie ni empleados, el galpón se congela; con empleados sigue | — | — | decidido |
| D-0107 | Análisis de *Schedule I* (gestión de empleados, portapapeles, automatización por estaciones, crecimiento) y qué tomar y qué no | critico-diseno | high | `diseno/referencia-schedule-1.md` con lista "tomamos / no tomamos" |
| D-0108 | Análisis de referencias de armado y logística (Box Packing, Mini Motorways, Shapez, Overcooked, Totally Reliable Delivery Service) | critico-diseno | high | `diseno/referencias-logistica.md` |
| D-0109 | ✅ Regla de diseño "lo que armás es la trampa": tabla producto × embalaje × trampa resultante | constructor-trampas | high | `diseno/armado-y-trampas.md` con la tabla completa para las 7 trampas actuales |
| D-0110 | Definir cómo se reparte la tripulación de 1-8 en el día (galpón vs. ruta) y qué hace cada uno solo, en dupla y con 8 | critico-diseno | high | `diseno/roles-tripulacion.md` con tablas por cantidad de jugadores |
| D-0111 | Definir el corte vertical F1 exacto (contenido, pantallas, qué queda gris) y su criterio de cierre medible | planificador-tareas | high | `diseno/corte-vertical.md` con lista cerrada y benchmark de cierre |
| D-0112 | Pasada de `critico-diseno` a toda la expansión contra la capacidad del equipo; recortes propuestos | critico-diseno | high | informe en `diseno/critica-alcance.md` con lista de recortes |
| D-0113 | ✅ Recortes los aplica D-0112, sin tocar nada de lo que nombró el usuario | — | — | decidido |
| D-0114 | Tabla de distritos definitiva (orden, vehículo, peligros, desbloqueo, cantidad de casas, largo de ruta en minutos) | critico-diseno | medium | `diseno/distritos.md` reemplaza la tabla del README |
| D-0115 | Tabla de vehículos definitiva (asientos, carga, velocidad, quién maneja, qué trampa amplifica) | critico-diseno | medium | `diseno/flota.md` |
| D-0116 | ✅ Catálogo inicial de productos: 40 productos con tamaño, peso, fragilidad, temperatura, precio y distrito | constructor-progresion | medium | `diseno/catalogo-productos.md` con los 40 |
| D-0117 | Modelo económico en papel: ingresos por pedido, costos, sueldos, precios de máquinas; curva de 20 días | constructor-progresion | high | `diseno/economia.md` con hoja y curva; `sim_economy` (D-0540) la reproduce |
| D-0118 | Lista de hitos (30) con condición, recompensa y qué desbloquean | constructor-progresion | medium | `diseno/hitos.md` |
| D-0119 | Mapa de qué sistemas actuales se reutilizan (depósito, RouteStreamer, DeliveryHouse, CrewProgression, UnlockManager, trampas) y cuáles se reemplazan | Plan | high | `diseno/reutilizacion.md` con archivo por sistema |
| D-0120 | Riesgos técnicos (red con muchos objetos en el galpón, agua, vuelo, guardado, rendimiento de empleados) con mitigación | auditor-integral | high | `diseno/riesgos.md` con P0-P3 |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0121 | Narrativa de la empresa: quién es el jefe, por qué empezamos, tono de los mensajes de clientes | documentador | medium | `diseno/narrativa-empresa.md` alineado con `docs/narrativa.md` |
| D-0122 | Personajes de clientes recurrentes por distrito (2-3 por distrito) con pedidos característicos | critico-diseno | medium | lista en `diseno/clientes.md` |
| D-0123 | Diseño de eventos del día (inspección, proveedor tarde, pedido gigante, huelga, ola de calor) | critico-diseno | medium | `diseno/eventos-del-dia.md` con 15 eventos |
| D-0124 | Diseño de las licencias (náutica, vuelo, 4x4, alta montaña, zona volcánica) y cómo se obtienen | constructor-progresion | medium | sección en `diseno/hitos.md` |
| D-0125 | Diseño de la competencia NPC (empresa rival que roba clientes si bajás la reputación) | critico-diseno | medium | `diseno/rival.md` o recorte justificado |
| D-0126 | Definir el modo solo: qué automatiza el juego para que una persona sola pueda llevar el negocio | critico-diseno | high | sección en `diseno/roles-tripulacion.md`; bot de D-2024 lo verifica |
| D-0127 | Definir dificultad/tamaños de partida (empresa chica, mediana, grande) y modificadores | critico-diseno | medium | `diseno/dificultad.md` |
| D-0128 | Encaje del Endless actual en la expansión (¿endless por distrito? ¿desafío diario?) | critico-diseno | medium | decisión documentada |
| D-0129 | Glosario de términos del juego (pedido, remito, palet, estación, turno, hito) en español e inglés | documentador | low | `diseno/glosario.md`; lo usa `loc_text` |
| D-0130 | Tabla de "primera vez": qué aprende el jugador cada día de los primeros 7 | critico-diseno | medium | `diseno/onboarding.md`; D-1901 la implementa |
| D-0131 | Diseñar el portapapeles de gestión (inspirado en Schedule I) como objeto en la mano, no menú | critico-diseno | medium | `diseno/portapapeles.md` con wireframes en texto |
| D-0132 | Diseño de sabotaje amistoso coop (esconder cajas, cambiar etiquetas) — sí o no | critico-diseno | low | decisión documentada |
| D-0133 | Diseño del mercado de proveedores (precios que varían por día, calidad del proveedor) | constructor-progresion | medium | sección en `diseno/economia.md` |
| D-0134 | Definir qué se guarda y qué no entre sesiones (empresa, stock, empleados, día en curso) | constructor-progresion | medium | `diseno/guardado.md`; D-0206 lo implementa |
| D-0135 | Definir reglas de clima por distrito y su efecto en la carga y el vehículo | constructor-mundo | medium | tabla en `diseno/distritos.md` |
| D-0136 | Definir reglas de horario de clientes (no reciben de noche, ventanas de entrega) | constructor-progresion | low | sección en `diseno/clientes.md` |
| D-0137 | Diseño de cosméticos de la empresa (logo, colores de la flota, uniforme) | critico-diseno | low | `diseno/cosmeticos-empresa.md` |
| D-0138 | Ideas de logros de Steam de la expansión (30) | estratega-steam | low | lista en `docs/marketing/` |
| D-0139 | Encaje de la expansión en la página de Steam y el tráiler (qué promete y qué no) | estratega-steam | medium | nota en `docs/marketing/` |
| D-0140 | Revisión de `abogado-del-diablo` del diseño completo una vez escrito D-0101 a D-0139 | abogado-del-diablo | high | informe con lista SIMPLIFICAR/REHACER y tareas ajustadas |

## Agentes y proceso

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0141 | Crear el agente `constructor-negocio` (galpón, stock, armado, empleados, automatización) en `.claude/agents/` | claude | medium | archivo versionado, con modelo y esfuerzo como los demás; listado en `CLAUDE.md` |
| D-0142 | Ampliar `constructor-camion` a toda la flota (o crear `constructor-vehiculos`) | claude | medium | descripción del agente cubre bici, carrito, lancha y avioneta |
| D-0143 | Ampliar `constructor-tramos` con tramos de agua, aire y montaña | claude | low | descripción actualizada |
| D-0144 | Agregar los dominios nuevos (`scripts/gameplay/business/`, `scripts/gameplay/fleet/`, `scripts/gameplay/districts/`) a `file_domain` en `.claude/hooks/lib.sh` y a `colaboracion-equipo.md` | claude | low | hook clasifica bien los archivos nuevos (test del hook) |
| D-0145 | Agregar la expansión a la tabla "Cobertura por etapa" de `.claude/rutinas/README.md` (cuándo la toma cada rutina) | documentador | low | tabla actualizada |
| D-0146 | Plantilla de tarea promovida (de `D-` a formato `tareas-nacho.md`) para `planificador-tareas` | planificador-tareas | low | plantilla en este README o en el agente |
| D-0147 | Inventario de assets necesarios de toda la expansión (para `sesion-arte`) | director-arte | medium | `docs/inventario-assets.md` con sección "Expansión" |
| D-0148 | Dirección visual por distrito (paleta, luz, materiales, referencias) | director-arte | medium | sección por distrito en `docs/direccion-visual.md` |
| D-0149 | Dirección sonora por distrito (ambiente, música, motores) | disenador-audio | medium | sección en `docs/audio-mundo.md` |
| D-0150 | Calendario tentativo F0-F5 con hitos medibles y fecha de corte de alcance | planificador-tareas | medium | tabla de fechas en este README |
