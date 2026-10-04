# Grupo 08 — Pedidos de clientes

> Fase **F1** (núcleo) / F2 · Dueño: Nacho · Depende de: D-0210, D-0116, D-0122.
> Lo que pide la gente: qué productos, con qué requisito, a qué casa, para cuándo.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0801 | Generador de pedidos por semilla, distrito desbloqueado y hora | constructor-progresion | high | test: misma semilla, mismos pedidos |
| D-0802 | ✅ Estructura del pedido: cliente, dirección, productos, requisitos, ventana, paga | constructor-progresion | medium | test de serialización |
| D-0803 | Ritmo de llegada de pedidos durante el día (curva) | constructor-progresion | medium | sim muestra la curva |
| D-0804 | Tablero de pedidos en el galpón (lista con estado) | constructor-ui | high | captura legible |
| D-0805 | Impresora de pedidos que escupe la hoja física (guiño Overcooked) | constructor-negocio | medium | hoja aparece y se puede llevar a la mesa |
| D-0806 | Requisitos: frágil, frío, regalo, urgente, pesado, "no doblar" | constructor-progresion | medium | 6 requisitos en `.tres` con test |
| D-0807 | Vencimiento del pedido y penalidad por tardanza | constructor-progresion | medium | test |
| D-0808 | Asignar pedido a una caja (la hoja va con la caja) | constructor-negocio | medium | test |
| D-0809 | Asignar caja a salida/vehículo | constructor-negocio | medium | test |
| D-0810 | Cancelación del cliente (evento raro) | constructor-progresion | low | test |
| D-0811 | Pedidos imposibles hoy (falta stock) quedan en espera | constructor-progresion | medium | test |
| D-0812 | Tamaño de pedidos acorde a los primeros días (1-2 productos) | pulidor-jugabilidad | low | sim |
| D-0813 | Pedidos replicados en red | auditor-red | high | test de red |
| D-0814 | Notificación de pedido nuevo en el celular del jugador | constructor-ui | medium | test |
| D-0815 | Pedido completado → cobro y reputación | constructor-progresion | medium | test |
| D-0816 | Calificación del cliente (1-5 estrellas) en la puerta | constructor-progresion | medium | test |
| D-0817 | Reacción del cliente en la puerta según calificación (reusa `client_complaints.gd`) | constructor-mundo | medium | 3 reacciones |
| D-0818 | Firma del cliente en el celular/remito | constructor-jugador | low | gesto |
| D-0819 | Cliente ausente: dejar en buzón, vecino o volver | constructor-progresion | medium | test de las 3 opciones |
| D-0820 | Datos de 40 pedidos plantilla por distrito | constructor-progresion | medium | `.tres` validados |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0821 | Clientes recurrentes con nombre y personalidad (D-0122) | constructor-progresion | medium | 18 clientes |
| D-0822 | Cartas/mensajes de clientes con pedidos raros y humor | documentador | low | 60 textos traducibles |
| D-0823 | Pedidos encadenados (historias de cliente en 3 entregas) | constructor-progresion | medium | 5 cadenas |
| D-0824 | Pedidos corporativos por volumen (ver D-0424) | constructor-progresion | medium | test |
| D-0825 | Pedidos con horario estricto (tienda que abre a las 9) | constructor-progresion | low | test |
| D-0826 | Pedidos de devolución (D-0329) | constructor-progresion | medium | test |
| D-0827 | Pedidos que requieren armar en el lugar (montar un mueble) | critico-diseno | low | decisión |
| D-0828 | Pedidos de distritos especiales (faro en Islas, refugio en Nieve, observatorio en Volcán) | constructor-progresion | medium | 1 especial por distrito |
| D-0829 | Clientes que ponen trampas al repartidor (perro suelto, escalera rota) — usa peligros existentes | constructor-mundo | medium | 3 variantes |
| D-0830 | Pedido "a ciegas" (no dice qué hay adentro) | constructor-progresion | low | test |
| D-0831 | Reseñas en una app ficticia que afectan reputación | constructor-ui | medium | pantalla |
| D-0832 | Clientes que llaman por teléfono para cambiar el pedido a último momento | constructor-progresion | medium | evento |
| D-0833 | Pedidos de temporada (navidad, verano) | constructor-progresion | low | calendario |
| D-0834 | Pedidos para otros negocios (restaurante, farmacia) con requisitos especiales | constructor-progresion | medium | 4 tipos |
| D-0835 | Pedido de emergencia (medicamento) con bonus alto | constructor-progresion | low | test |
| D-0836 | Pedidos que eligen vehículo (solo bici por zona peatonal) | constructor-progresion | low | test |
| D-0837 | Filtros y orden en el tablero de pedidos | constructor-ui | medium | test de UI |
| D-0838 | Prioridad marcada por el jugador | constructor-ui | low | test |
| D-0839 | Estadística de satisfacción por cliente | constructor-progresion | low | dato guardado |
| D-0840 | Generador de nombres de clientes localizado | constructor-progresion | low | lista |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0841 | Sonido de impresora de pedidos | disenador-audio | low | SFX |
| D-0842 | Hoja de pedido legible a distancia normal | revisor-visual | low | captura |
| D-0843 | Íconos de requisitos claros y consistentes | artista-conceptual* | medium | 8 íconos |
| D-0844 | Balance: cantidad de pedidos vs. capacidad de la tripulación por día | pulidor-jugabilidad | high | sim con 1-8 jugadores |
| D-0845 | Textos de pedidos traducibles | constructor-ui | low | `tr()` |
| D-0846 | Accesibilidad: requisitos con texto además del ícono | constructor-ui | low | test |
| D-0847 | Retratos de clientes recurrentes | artista-conceptual* | medium | 18 retratos |
| D-0848 | Test de golden de generación de pedidos | escritor-tests | medium | `test_order_golden` |
| D-0849 | QA de pedidos en bordes (pedido vencido mientras se entrega) | probador-qa | medium | tabla |
| D-0850 | Documentar cómo agregar un tipo de pedido | documentador | low | guía corta |
