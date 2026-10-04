# Grupo 04 — Progresión, hitos, licencias y desbloqueos

> Fase **F2** (el núcleo mínimo entra en F1) · Dueño: Nacho · Depende de: D-0118, D-0202, D-0229.
> Aviso: sí (`crew_progression.gd`, `unlock_manager.gd`, progresión heredada de Slatex).
> Las zonas se abren por **hitos** (logros medibles), no por nivel de experiencia suelto.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0401 | `MilestoneTracker`: evalúa condiciones de hitos al cierre de cada día y al instante para las simples | constructor-progresion | high | test: 5 hitos de distinto tipo se cumplen en sim |
| D-0402 | Tipos de condición: entregas totales, entregas por distrito, plata, reputación, sin roturas N días, empleados, máquinas | constructor-progresion | high | cada tipo con su test |
| D-0403 | Tipos de recompensa: desbloquear distrito, vehículo, máquina, producto, proveedor, plata, cosmético | constructor-progresion | high | cada tipo con su test |
| D-0404 | Cargar los 30 hitos de D-0118 como `.tres` | constructor-progresion | medium | `test_milestones_data` valida los 30 |
| D-0405 | Reputación de la empresa (0-100) con subidas por entregas buenas y bajadas por roturas, tardanzas y errores de armado | constructor-progresion | high | test: curva de reputación en sim de 10 días |
| D-0406 | Reputación por distrito además de la global | constructor-progresion | medium | test: entregas en Centro no suben Islas |
| D-0407 | Licencias como ítems comprables con requisito (hito + plata) | constructor-progresion | medium | test: comprar licencia sin hito falla |
| D-0408 | Integrar desbloqueos con `UnlockManager` existente sin romper lo de hoy | constructor-progresion | xhigh | tests actuales de desbloqueos verdes + nuevos |
| D-0409 | Aviso en pantalla cuando se cumple un hito (tarjeta, sonido) | constructor-ui | medium | captura y test del evento |
| D-0410 | Tablero de hitos en el galpón (qué falta para el próximo distrito) | constructor-ui | high | captura legible; cada hito muestra progreso |
| D-0411 | Árbol de progreso visual (distritos y vehículos conectados por requisitos) | constructor-ui | high | captura del árbol completo |
| D-0412 | Primera semana guiada: hitos 1-5 enseñan el bucle (ver D-0130) | constructor-progresion | medium | sim de los primeros 5 días cumple los 5 hitos con bot simple |
| D-0413 | Hito "Primer empleado" desbloquea contratación | constructor-progresion | low | test |
| D-0414 | Hito "Primera máquina" desbloquea la tienda de automatización | constructor-progresion | low | test |
| D-0415 | Hito de Puerto (licencia náutica) | constructor-progresion | low | test |
| D-0416 | Hito de Montaña (4x4 comprada + 50 entregas en Campo) | constructor-progresion | low | test |
| D-0417 | Hito de Nieve (Montaña + abrigo de la tripulación + conservadoras) | constructor-progresion | low | test |
| D-0418 | Hito de Volcán (aeródromo + licencia de vuelo + reputación 80) | constructor-progresion | low | test |
| D-0419 | Guardar el progreso de hitos en el save de empresa | constructor-progresion | medium | test de guardar y cargar |
| D-0420 | Hitos replicados: los clientes ven el mismo progreso que el host | auditor-red | high | test de red con 2 peers |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0421 | Hitos secretos (entregar un paquete en llamas, entrega perfecta en ventisca) | constructor-progresion | medium | 8 secretos en `.tres` |
| D-0422 | Hitos de tripulación (cada jugador aporta) vs. de empresa | constructor-progresion | medium | ambos tipos con test |
| D-0423 | Rangos de la empresa (Garage → Pyme → Distribuidora → Logística Nacional) | constructor-progresion | medium | rango visible en tablero |
| D-0424 | Contratos grandes: un cliente corporativo pide 30 cajas en 3 días | constructor-progresion | high | contrato completo en sim |
| D-0425 | Clientes VIP que se desbloquean con reputación y pagan más | constructor-progresion | medium | test |
| D-0426 | Mejoras de tripulación (ropa de abrigo, guantes, botas antideslizantes) desbloqueables | constructor-jugador | high | efecto medible en nieve/volcán |
| D-0427 | Cartas de mérito actuales (`CrewProgression`) integradas al día de empresa | constructor-progresion | high | cartas se ganan en las salidas |
| D-0428 | Votación de tienda (`ShopVoteManager`) para compras grandes de la empresa | constructor-progresion | high | voto para comprar máquina en test |
| D-0429 | Desafíos diarios generados (entregar 5 frágiles en Centro) | constructor-progresion | medium | 1 desafío por día por semilla |
| D-0430 | Desafíos semanales con recompensa cosmética | constructor-progresion | low | test |
| D-0431 | Estadísticas de empresa (entregas, roturas, km, mejor día) | constructor-progresion | medium | pantalla de estadísticas |
| D-0432 | Récords por distrito (entrega más rápida, más cajas en una salida) | constructor-progresion | low | guardados |
| D-0433 | Prestigio/franquicia: reiniciar la empresa con bonus (post-juego) | critico-diseno | medium | decisión; si sí, diseño |
| D-0434 | Desbloqueo de productos nuevos por distrito (Islas trae pescado, Nieve trae equipos de esquí) | constructor-progresion | medium | catálogo filtra por desbloqueo |
| D-0435 | Desbloqueo de proveedores mejores (más baratos, más rápidos) | constructor-progresion | medium | test |
| D-0436 | Desbloqueo de tamaños de galpón | constructor-progresion | low | conectado con D-0905 |
| D-0437 | Desbloqueo de cosméticos de flota por hitos | constructor-progresion | low | 10 cosméticos |
| D-0438 | Final de campaña: "Logística Nacional" con escena de cierre | constructor-progresion | medium | se dispara al cumplir el último hito |
| D-0439 | Modo libre post-final (seguir jugando con todo abierto) | constructor-progresion | low | flag en save |
| D-0440 | Logros de Steam ligados a hitos (D-0138) | constructor-red | medium | logros se otorgan en build de Steam |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0441 | Curva de progreso: tiempo hasta cada distrito medido con bot (objetivo en D-0117) | pulidor-jugabilidad | high | tabla de días por distrito dentro de ±20 % del objetivo |
| D-0442 | Ningún hito imposible para un jugador solo | pulidor-jugabilidad | medium | bot solo cumple todos en sim |
| D-0443 | Textos de hitos traducibles y cortos | constructor-ui | low | todos por `tr()` |
| D-0444 | Celebración al desbloquear distrito (confeti, jefe que habla) | artista-vfx | medium | captura |
| D-0445 | Jefe (`boss_lines.gd`) comenta hitos y desbloqueos | constructor-mundo | low | 30 líneas nuevas |
| D-0446 | Íconos de hitos | artista-conceptual* | medium | 30 íconos |
| D-0447 | Revisar que el árbol se lea con daltonismo | revisor-visual | low | captura con filtro |
| D-0448 | Test de regresión: save viejo con hitos cumplidos sigue abriendo lo mismo | escritor-tests | medium | test |
| D-0449 | Auditoría de que no se puede saltear la progresión con flags en build de release | auditor-red | medium | flags de dev deshabilitados en release |
| D-0450 | Documento de progresión final para Steam y prensa | documentador | low | `diseno/progresion.md` |
