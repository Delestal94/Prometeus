# Economía, mejoras y contramedidas

## Bucle de recompensa

Cada entrega otorga dinero compartido por lo que pasó en las puertas y en el
camión: paquetes entregados (150 intacto, 75 abollado, 20 arruinado, o lo que
valga su rescate), fotos de entrega (+25), plazos cumplidos (+40) y la carga
que volvió sana en el camión (100 / 50). Se descuenta por casas sin entregar
(-60), plazos vencidos (-15) y reclamos sin foto (-40); el pago nunca baja de 0.
Los eventos de ruta suman o restan aparte y se gastan consumibles en el
depósito. No hay bono de tiempo: la rapidez solo se paga con los plazos. El
multiplicador de caos (x1.2) afecta el puntaje, **no** el dinero. Endless no
paga dinero (solo distancia). El dinero mejora la empresa; no es un requisito
para empezar una partida.

| Entra / sale | Cuánto | Por qué |
| --- | ---: | --- |
| Pago de la entrega | puntos de puerta + de carga (típico 300-450) | Línea "Pago del equipo" de los resultados |
| Recompensa / multa de evento de ruta | +10..25 / -15..30 | Aviso del evento |
| Suministros del depósito | -100 a -160 (acolchado 160, seguro 140, gancho 120, repuesto 100) | Votación de la tienda, cobra el depósito |
| Accesorios (depósito) | -60 a -150 (gorra 60, chaleco 90, casco 120, mochila 150; todo el estante 420) | Fila de la tienda, aviso "Compraron X para <color>" |
| Accesorios (parada de servicio) | -84 a -210 (precio del depósito x1,4, sin sorteo: todo el catálogo) | Fila de la parada, aviso de la estación |
| Seguro de envío | +50 por caja arruinada entregada | Aviso del depósito |
| Multa de fauna | -20 / -30 | Aviso en ruta |

### Contramedidas (qué exploit se cerró y cuál no)

- **Reclamo determinista.** Una caja entregada abollada o arruinada siempre genera
  reclamo (antes 50 % de azar para la abollada): lo único que lo cierra es la foto. Ya
  no se puede "esperar la suerte" de que no se queje.
- **Suicidar la corrida para recomprar.** Una corrida abandonada paga solo los puntos de
  puerta ya ganados (las casas sin alcanzar restan -60 cada una y el pago no baja de 0) y la
  carga perdida no paga: cobrar el mínimo y recomprar es peor que entregar (un pedido intacto
  vale 150 en la puerta).
- **Seguro.** Arruinar cajas a propósito para cobrar el seguro no conviene: una caja arruinada
  paga 20 + 50 de seguro = 70, menos que una abollada (75) y mucho menos que una intacta (150);
  además el seguro cuesta 140. Regla: reembolso + pago de arruinada < pago de abollada
  (`Depot.INSURANCE_REFUND` + `POINTS_DELIVERED_RUINED` < `POINTS_DELIVERED_AT_RISK`, lo verifica `test_depot`).
- **Ruta fácil.** El pago crece con las casas (150 por casa intacta, mínimo 2 por N-119) y
  no depende del tiempo: repetir la ruta mínima rinde lo mismo por casa que una larga. No se
  midió el dinero por minuto de cada largo; si hace falta, medirlo con
  `tests/bench_delivery_time.gd`.
- **Cliente impaciente.** El castigo (plazo más corto) solo toca un plazo aún abierto,
  nunca deja menos de 10 s y nunca se aplica al cerrar la corrida.
- **Votar en bloque.** Sin cambios: la tienda la resuelve el anfitrión, el empate va al más barato
  y solo el depósito cobra, una vez por suministro.
- **Accesorios (N-923.3/.4).** Son cosméticos: no cambian nada de la entrega. Solo se
  cobran si el otorgamiento va a funcionar (`CrewProgression.buy_accessory` valida dueño,
  plata y carta antes de gastar): ni una copia ya comprada, ni un id desconocido, ni sin plata
  ni sin la carta de Descuento cobran, y una compra fallida no gasta la carta. Hay un solo
  ejemplar de cada uno: quien lo tiene lo bloquea para todos. Solo, uno puede comprarse el
  estante entero; online hace falta que la votación lo apruebe (votar en bloque no abre nada
  nuevo: la plata es del grupo igual). No hay
  reembolso ni venta: farmear una ruta fácil o tirar la corrida no devuelve plata
  gastada en accesorios. La parada cuesta x1,4 el depósito, así que comprar en ruta nunca
  conviene más que antes de salir. El comprador es quien pidió la oferta (id con su peer),
  no el ganador de la votación; Prioridad y Descuento valen igual que con los suministros
  y la carta solo se gasta si la compra se hizo. Pendiente de N-923.11: contrastar los
  precios con lo que paga una entrega (el estante entero, 420, es una entrega típica).
- **Pendiente:** premios y multas de eventos (10..30) y las multas de fauna (20/30) quedaron
  iguales; frente a un pago de 300+ pesan poco y conviene revisarlos con `critico-diseno`.

## Ramas de mejora

| Rama | Ejemplos |
| --- | --- |
| Carga | Anaqueles acolchados, barandillas, cinchas, bandejas impermeables y compartimentos aislados. |
| Conducción | Frenos, suspensión, neumáticos y motor. Más velocidad puede reducir estabilidad. |
| Supervivencia | Luces interiores, radio, máscaras, botiquín y herramientas de rescate. |

## Paquetes especiales

| Riesgo | Respuesta activa | Mejora asociada |
| --- | --- | --- |
| Explosivo | Pedir el código al conductor (lo ve en el tablero, distinto en cada caja) y tocarlo bajo presión. | Caja blindada o temporizador más lento. |
| Apestoso/tóxico | Sellarlo, ventilar o usar máscara. | Extractor, filtros y compartimento aislado. |
| Líquido | Fregar el derrame alternando izquierda y derecha, rápido, sin botón. | Bandejas y material absorbente. |
| Frágil | Un toque justo antes del bache que avisa la caja; conducir suave. | Anaquel acolchado y cinchas. |
| Ruidoso/hostil | Calmarlo entre varios jugadores. | Jaula insonorizada o sedante limitado. |
| Peso creciente | Resolver su secuencia antes de que sea inmanejable. | Elevador y anaquel reforzado. |

## Desbloqueo gradual

Las primeras entregas presentan Frágil y Equilibrio. Después llegan Peso
creciente (1 entrega), Ruidoso (2 entregas y 100 puntos), Líquido (4/250),
Explosivo (8/750) y Hostil (13/1500). Así cada riesgo nuevo agrega una sola
idea a la vez: anticipación, control, contención, presión de tiempo y por último
coordinación intensa, sin convertir el juego en una rutina de farmeo.
