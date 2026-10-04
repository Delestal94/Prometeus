# Grupo 07 — Armado de paquetes

> Fase **F1** (núcleo) · Dueño: Nacho · Depende de: D-0109, D-0204, D-0212, D-0213.
> Aviso: sí (`scripts/gameplay/package/`, trampas: archivos de Slatex).
> El corazón nuevo: con los productos del pedido, armar la caja correcta. **Lo armado define la trampa
> del viaje** (D-0109): poco relleno → se sacude; vidrio sin burbuja → Frágil; frío sin conservadora →
> Líquido; caja grande con poco peso → Equilibrio.

## Núcleo

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| ✅ D-0701 | Estación de armado (mesa) con huecos para caja, insumos y productos | constructor-negocio | high | captura y test de interacción |
| D-0702 | Elegir tamaño de caja (S, M, L, XL) del dispensador | constructor-negocio | medium | test: caja aparece abierta en la mesa |
| D-0703 | Meter productos en la caja (físico simple o encastre en grilla) | constructor-negocio | xhigh | test: 3 productos dentro, la caja conoce su contenido |
| D-0704 | ✅ Armado en grilla de celdas de 0,2 m | — | — | decidido |
| D-0705 | Relleno (papel, burbuja, espuma) llena el hueco libre y da protección | constructor-negocio | high | test: % de hueco libre baja con relleno |
| D-0706 | Cerrar con cinta (gesto de pasar el dispensador) | constructor-jugador | medium | test: caja sin cinta no se puede despachar |
| D-0707 | Etiqueta de envío impresa con dirección del pedido (reusa `package_shipping_label.gd`) | constructor-negocio | medium | etiqueta muestra calle y número del pedido |
| D-0708 | Sellos (FRÁGIL, ESTE LADO ARRIBA, FRÍO) | constructor-negocio | medium | sello queda en la caja y la puerta lo valida |
| D-0709 | Cálculo de calidad del armado (contenido correcto, hueco, protección, sellos) 0-100 | constructor-negocio | high | test con 6 cajas de calidad conocida |
| D-0710 | Calidad → trampa y su intensidad para el viaje (tabla D-0109) | constructor-trampas | xhigh | test: vidrio sin burbuja da Frágil alto; con burbuja, Frágil bajo |
| D-0711 | Caja armada sigue siendo `DeliveryPackage`: se lleva, se cuida y se entrega como hoy | constructor-trampas | xhigh | tests de paquete actuales verdes |
| D-0712 | Error de contenido (falta un producto o sobra) detectable al cerrar o en la puerta | constructor-negocio | medium | test de los dos momentos |
| D-0713 | Balanza de control: peso esperado vs. real | constructor-negocio | medium | test |
| D-0714 | Hoja de pedido visible en la mesa (qué lleva este paquete) | constructor-ui | medium | captura legible |
| D-0715 | Varias personas en la misma mesa (uno pone productos, otro cinta) | constructor-red | xhigh | test de red con 2 peers armando la misma caja |
| D-0716 | Despacho: dejar la caja armada en la zona de salida la asocia a una salida | constructor-negocio | medium | test |
| D-0717 | Cargar el vehículo desde despacho (reusa la carga actual del depósito) | constructor-mundo | high | camioneta cargada con cajas armadas sale |
| D-0718 | Insumos que se gastan (cinta, cajas, relleno) y se reponen | constructor-negocio | medium | test |
| D-0719 | Desarmar una caja mal armada (recuperar productos) | constructor-negocio | medium | test |
| D-0720 | Tutorial de la mesa (primer armado guiado) | constructor-ui | medium | flujo guiado funciona con mando |

## Ampliación

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0721 | Conservadora con hielo para productos fríos | constructor-negocio | medium | test: frío dura N min en la ruta |
| D-0722 | Caja térmica para Volcán (calor) | constructor-negocio | medium | test |
| D-0723 | Envoltorio de regalo (pedido de regalo paga más) | constructor-negocio | medium | test |
| D-0724 | Caja impermeable para Islas (agua salpica) | constructor-negocio | medium | test |
| D-0725 | Paracaídas acoplado para lanzamientos desde la avioneta | constructor-negocio | high | ver D-1420 |
| D-0726 | Productos que no se pueden juntar (químicos con comida) | constructor-negocio | medium | regla con test |
| D-0727 | Productos con orientación (líquidos de pie) | constructor-negocio | medium | test |
| D-0728 | Caja a medida (más cara, encaje perfecto) | constructor-negocio | low | test |
| D-0729 | Pedidos multi-caja (un pedido en 2-3 cajas) | constructor-negocio | high | test |
| D-0730 | Paquetes sin caja (bici, colchón) con film y esquineros | constructor-negocio | medium | test |
| D-0731 | Mensaje escrito a mano del cliente (`package_scribble.gd`) | constructor-negocio | low | dibujo/firma en la caja |
| D-0732 | Etiquetas de colores por distrito | constructor-negocio | low | test |
| D-0733 | Armado con temporizador para pedidos urgentes | constructor-negocio | low | test |
| D-0734 | Control de calidad por otro jugador (abrir y revisar antes de cerrar) | constructor-negocio | medium | test |
| D-0735 | Contenido sorpresa: el pedido dice "algo para mi abuela" (interpretación) | critico-diseno | low | decisión |
| D-0736 | Trampa nueva que nace del armado: "Mal cerrada" (la tapa se abre con los saltos) | constructor-trampas | high | trampa con test y feedback |
| D-0737 | Trampa nueva: "Sobrecargada" (fondo que cede si se lleva mal) | constructor-trampas | high | idem |
| D-0738 | Trampa nueva: "Derretible" (Volcán/Nieve: temperatura) | constructor-trampas | high | idem |
| D-0739 | Trampa nueva: "Mojable" (Islas: agua) | constructor-trampas | high | idem |
| D-0740 | Trampa nueva: "Viva" (animal/planta que se mueve, guiño a `ReplacementHen`) | constructor-trampas | high | idem |

## Pulido

| ID | Tarea | Agente | Esf. | Hecho cuando |
|---|---|---|---|---|
| D-0741 | Sonidos de cinta, relleno, sellos (satisfactorios) | disenador-audio | medium | SFX |
| D-0742 | Animación de pasar la cinta | animador | medium | clip |
| D-0743 | Partículas de relleno de papel | artista-vfx | low | partículas |
| D-0744 | Feedback de calidad al cerrar (✓ verde, ✗ con motivo) | constructor-ui | medium | captura |
| D-0745 | Que el armado de una caja promedio lleve 20-40 s a una persona (medido con bot de input) | pulidor-jugabilidad | high | medición |
| D-0746 | Ángulo de cámara útil en la mesa | constructor-jugador | medium | captura |
| D-0747 | Rendimiento con 4 mesas armando a la vez | perfilador-rendimiento | medium | dentro de presupuesto |
| D-0748 | Test de que una caja armada no pierde contenido al viajar en red | escritor-tests | high | test |
| D-0749 | Mando: armar sin mouse | constructor-ui | high | test de input con mando |
| D-0750 | QA de armado (errores raros: cerrar vacía, meter caja en caja) | probador-qa | medium | tabla sin P0-P1 |
