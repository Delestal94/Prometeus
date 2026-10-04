# Grupo 05 — Economía y crecimiento del negocio

> Fase **F1** (núcleo) / F2 · Dueño: Nacho · Depende de: D-0117, D-0202, D-0210.
> Aviso: sí (`run_manager.gd`, `run_scoring.gd` zona compartida; plata compartida heredada de Slatex).
> Todo número se valida con `sim_economy` (D-0540), no a ojo.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0501 | Billetera de la empresa (reemplaza o envuelve la plata compartida actual) con historial de movimientos | constructor-progresion | high | test: movimientos suman el saldo |
| D-0502 | Precio de un pedido = productos + envío por distrito + urgencia + bonus por estado | constructor-progresion | high | test con 10 pedidos contra la tabla de D-0117 |
| D-0503 | Costo de compra de mercadería al proveedor | constructor-progresion | medium | test: recibir palet descuenta plata |
| D-0504 | Costo de materiales de embalaje (cajas, cinta, relleno, etiquetas) | constructor-progresion | medium | test: armar una caja consume insumos |
| D-0505 | ✅ Sin combustible ni energía; el costo operativo es el mantenimiento (D-0527) | — | — | decidido |
| D-0506 | Penalidades: rotura, producto equivocado, tarde, caja mal etiquetada | constructor-progresion | high | test por tipo |
| D-0507 | Propinas por entrega perfecta y rápida | constructor-progresion | low | test |
| D-0508 | Resumen financiero del cierre del día (ingresos, costos, ganancia) | constructor-ui | high | captura y test de los números |
| D-0509 | Gastos fijos diarios (alquiler del galpón, luz) | constructor-progresion | medium | test |
| D-0510 | Quiebra: qué pasa con saldo negativo N días (préstamo forzado, reinicio, aviso) | constructor-progresion | medium | test del caso |
| D-0511 | Tienda de la empresa (máquinas, vehículos, ampliaciones, licencias) con catálogo de `.tres` | constructor-progresion | high | comprar ítem en test descuenta y otorga |
| D-0512 | Precios de vehículos (bici < carrito < camioneta 4x4 < lancha < avioneta) | constructor-progresion | low | tabla en `.tres` |
| D-0513 | Precios de máquinas de automatización | constructor-progresion | low | tabla en `.tres` |
| D-0514 | Precios de ampliaciones del galpón | constructor-progresion | low | tabla en `.tres` |
| D-0515 | Sueldos de empleados por rol y nivel | constructor-progresion | low | tabla en `.tres` |
| D-0516 | Cobro al cierre del día o al entregar (según D-0105) | constructor-progresion | medium | test |
| D-0517 | Plata replicada: todos los clientes ven el mismo saldo | auditor-red | high | test de red |
| D-0518 | Solo el host (o un voto) puede gastar en compras grandes | constructor-red | high | test: cliente no puede comprar solo |
| D-0519 | Número de plata en el HUD durante el día | constructor-ui | low | captura |
| D-0520 | Integrar puntaje de corrida actual (`run_scoring`) como parte del cobro de la salida | constructor-progresion | xhigh | tests de puntaje actuales verdes |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0521 | Préstamos del banco con interés | constructor-progresion | medium | test de cuotas |
| D-0522 | Seguro de carga (paga una parte de las roturas) | constructor-progresion | medium | test |
| D-0523 | Precios de proveedores que varían por día y evento | constructor-progresion | medium | sim muestra variación acotada |
| D-0524 | Compra al por mayor con descuento | constructor-progresion | low | test |
| D-0525 | Contratos de suministro fijo (palet diario a precio fijo) | constructor-progresion | medium | test |
| D-0526 | Precio dinámico por demanda del distrito | constructor-progresion | medium | sim |
| D-0527 | Mantenimiento de vehículos y máquinas como costo | constructor-progresion | medium | test de desgaste y reparación |
| D-0528 | Venta de vehículos y máquinas usadas | constructor-progresion | low | test |
| D-0529 | Impuestos semanales simples | constructor-progresion | low | test |
| D-0530 | Inversiones en publicidad (sube pedidos de un distrito) | constructor-progresion | medium | sim |
| D-0531 | Libro contable en el portapapeles (gráfico de los últimos 7 días) | constructor-ui | medium | captura |
| D-0532 | Gráfico de ganancias por distrito | constructor-ui | medium | captura (skill dataviz) |
| D-0533 | Mercado negro de productos raros (opcional, gracioso) | critico-diseno | low | decisión |
| D-0534 | Devoluciones y reembolsos | constructor-progresion | medium | test |
| D-0535 | Pedidos pagados por adelantado vs. contra entrega | constructor-progresion | low | test |
| D-0536 | Bonificación por racha de días sin roturas | constructor-progresion | low | test |
| D-0537 | Costo de licencias renovables (¿o compra única?) | critico-diseno | low | decisión |
| D-0538 | Economía en modo solo escalada | pulidor-jugabilidad | medium | bot solo no quiebra en 20 días |
| D-0539 | Economía escalada por cantidad de jugadores (1-8) | pulidor-jugabilidad | high | sim con 1, 2, 4, 8: ganancia por jugador dentro de ±25 % |
| D-0540 | `tools/sim_economy.gd`: simula N días con un bot de decisiones y saca CSV | constructor-progresion | high | corre 30 días en < 10 s; CSV en `tests/output/` |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0541 | Balance de la primera semana: el jugador puede comprar su primera mejora el día 2-3 | pulidor-jugabilidad | medium | sim lo confirma |
| D-0542 | Balance a mitad de campaña: hay siempre 2-3 compras deseables | pulidor-jugabilidad | medium | sim + lista |
| D-0543 | Que ninguna estrategia degenerada (solo un distrito) gane siempre | pulidor-jugabilidad | high | sim con 4 estrategias |
| D-0544 | Sonido de caja registradora al cobrar | disenador-audio | low | SFX en `SynthAudio` |
| D-0545 | Animación de números al cobrar | constructor-ui | low | tween |
| D-0546 | Moneda con formato localizado | constructor-ui | low | test con 2 locales |
| D-0547 | Explicar penalidades en el resumen (por qué perdiste plata) | constructor-ui | medium | cada penalidad con texto |
| D-0548 | Documentar el modelo económico final | documentador | low | `docs/economia-y-contramedidas.md` actualizado |
| D-0549 | Test de regresión de la economía (CSV de referencia) | escritor-tests | medium | `test_economy_golden` |
| D-0550 | Auditoría de exploits de plata en red (doble cobro, compras simultáneas) | auditor-red | high | sin hallazgos |
