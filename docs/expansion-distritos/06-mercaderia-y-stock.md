# Grupo 06 — Mercadería entrante, descarga y stock

> Fase **F1** (núcleo) · Dueño: Nacho · Depende de: D-0204, D-0211, D-0218.
> Camiones de proveedores llegan al patio; la tripulación (o empleados) descargan palets, los abren y
> guardan los productos en estanterías. Base del depósito actual (`scripts/gameplay/depot/`).

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0601 | Camión de proveedor NPC que entra al patio, se estaciona en la dársena y espera | constructor-mundo | high | bot: camión llega y estaciona sin chocar en 10 corridas |
| D-0602 | Calendario de entregas de proveedores (horario y contenido por día) | constructor-negocio | medium | test con calendario de 3 días |
| D-0603 | Pedido a proveedor desde el portapapeles o el tablero (qué y cuánto) | constructor-ui | high | test de UI: pedir palet y que llegue al día siguiente |
| D-0604 | ✅ Palet como objeto físico con N cajas de producto | constructor-negocio | high | palet aparece en la caja del camión con su contenido |
| D-0605 | Descargar palet con la zorra (transpaleta manual) | constructor-jugador | high | jugador mueve un palet del camión al piso (test de interacción) |
| D-0606 | Descargar con el autoelevador existente (`depot_forklift.gd`) manejado por un jugador | constructor-camion | xhigh | jugador maneja el autoelevador y deja un palet en un rack |
| D-0607 | ✅ Abrir palet: las cajas del producto pasan a ser tomables | constructor-negocio | medium | test |
| D-0608 | Estanterías con huecos etiquetados por producto | constructor-mundo | high | dejar producto en hueco lo suma al `Inventory` (test) |
| D-0609 | Tomar productos de la estantería (picking) a mano | constructor-jugador | high | test: tomar 3 unidades baja el stock en 3 |
| D-0610 | Carrito de picking empujable para llevar varios productos | constructor-jugador | high | carrito lleva 6 productos sin que se caigan en suelo plano |
| D-0611 | Stock visible: etiqueta del hueco muestra cantidad | constructor-mundo | medium | captura con números |
| D-0612 | Vista de stock en el portapapeles (lista por producto) | constructor-ui | medium | captura |
| D-0613 | Aviso de stock bajo para productos con pedidos pendientes | constructor-negocio | medium | test |
| D-0614 | Recepción: control de remito (lo que llegó vs. lo pedido) | constructor-negocio | medium | test: faltante se registra |
| D-0615 | Productos que vienen dañados del proveedor (a separar) | constructor-negocio | low | test |
| D-0616 | Productos con temperatura (frío) necesitan heladera; se echan a perder si no | constructor-negocio | high | test: producto frío fuera de heladera 2 h → vencido |
| D-0617 | Heladera/cámara de frío como estantería especial | constructor-mundo | medium | test |
| D-0618 | Camión del proveedor se va a una hora; si no se descargó, se lleva lo que quede (o cobra demora) | constructor-negocio | medium | test |
| D-0619 | Replicación del stock y de los palets en red | auditor-red | xhigh | test de red: 2 peers ven el mismo stock tras 50 movimientos |
| D-0620 | Layout inicial del depósito actual adaptado: dársena, zona de recepción, racks, armado, despacho | constructor-mundo | xhigh | captura aérea con zonas rotuladas; `test_depot_*` verdes |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0621 | Varios proveedores con productos, precios y puntualidad distintos | constructor-negocio | medium | 5 proveedores `.tres` |
| D-0622 | Proveedores por distrito (pescado de Islas, artesanías de Montaña) | constructor-negocio | medium | test de filtro |
| D-0623 | Contenedores marítimos en Puerto como entrada grande | constructor-mundo | high | contenedor se descarga en Puerto |
| D-0624 | Productos a granel que hay que fraccionar (arroz, tornillos) | constructor-negocio | medium | estación de fraccionar funciona |
| D-0625 | Productos peligrosos (garrafas, fuegos artificiales) con estante especial | constructor-negocio | medium | test de regla |
| D-0626 | Productos enormes (heladera, bici, colchón) que van sin caja o en caja especial | constructor-negocio | high | test |
| D-0627 | Productos vivos (plantas, peces, gallinas — guiño a `ReplacementHen`) | constructor-negocio | medium | test |
| D-0628 | Vencimientos (lácteos, flores) | constructor-negocio | medium | test |
| D-0629 | Inventario por escáner de mano (sumar con un clic) | constructor-jugador | medium | test |
| D-0630 | Ubicaciones dinámicas: el juego sugiere dónde guardar | constructor-negocio | medium | test |
| D-0631 | Mezanine/segundo piso de estanterías | constructor-mundo | high | escalera y estantes arriba |
| D-0632 | Robo/pérdida de stock (evento) | constructor-negocio | low | evento en sim |
| D-0633 | Devolución al proveedor | constructor-negocio | low | test |
| D-0634 | Cinta de descarga desde el camión (conecta con automatización) | constructor-negocio | medium | ver D-1103 |
| D-0635 | Palets apilables y altura máxima | constructor-negocio | medium | test de física |
| D-0636 | Pedido automático de reposición (al desbloquear) | constructor-negocio | medium | test |
| D-0637 | Pronóstico de demanda simple en el tablero | constructor-ui | medium | captura |
| D-0638 | Inventario semanal (conteo que corrige diferencias) | constructor-negocio | low | test |
| D-0639 | Camión de proveedor con chofer NPC que se queja si tardás | constructor-mundo | low | líneas de voz/burbuja |
| D-0640 | Patio de maniobras: varios camiones a la vez sin trabarse | constructor-mundo | high | bot con 3 camiones sin atascos |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0641 | Sonidos de recepción (bocina del proveedor, zorra, palet) | disenador-audio | low | SFX |
| D-0642 | Polvo y astillas al bajar palets | artista-vfx | low | partículas |
| D-0643 | Etiquetas de estante legibles a 3 m | revisor-visual | low | captura |
| D-0644 | Rendimiento con 500 productos en estantes | perfilador-rendimiento | high | FPS dentro del presupuesto en `bench_depot` |
| D-0645 | Productos en estante como MultiMesh cuando no se tocan | perfilador-rendimiento | high | draw calls bajan medido |
| D-0646 | Test de stock que no se duplica al soltar/agarrar rápido en red | escritor-tests | high | test |
| D-0647 | Animación de chofer bajando la rampa | animador | low | clip |
| D-0648 | Iluminación de dársena de noche | constructor-mundo | low | captura nocturna |
| D-0649 | Textos de remitos traducibles | constructor-ui | low | `tr()` |
| D-0650 | QA de recepción de punta a punta | probador-qa | medium | tabla sin P0-P1 |
