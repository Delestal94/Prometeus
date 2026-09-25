# Cartas, mérito y eventos de ruta

## Economía

El dinero es cooperativo: se gana por completar entregas y se vota para comprar
pinzas, mopas, máscaras, cajas blindadas, filtros y mejoras de la furgoneta.
El mérito es individual y se obtiene solo por acciones útiles, como recuperar
una caja caída, desactivar una bomba, contener un derrame o asistir a otro
jugador. Desbloquea cosméticos, nunca ventajas de juego.

## Cartas

Al completar una entrega, cada jugador puede recibir una carta. La probabilidad
parte de una base, aumenta por mérito y se garantiza tras varias entregas sin
recibir ninguna. Máximo una carta activa por persona.

| Carta | Efecto | Estado MVP |
| --- | --- | --- |
| Re-voto | Repite una votación. | Se reparte y se usa en Suministros. |
| Descuento | Reduce 50 % el costo de una compra cooperativa. | Se reparte y se usa en Suministros. |
| Rescate | Resuelve una emergencia activa una vez. | Se reparte y se usa con G / D-pad izquierda. |
| Prioridad | Reemplaza el resultado de una votación. | Reservada: conserva su id, pero no se reparte. |
| Información | Revela las ofertas de una tienda confusa. | Reservada: conserva su id, pero no se reparte. |

Cada jugador conserva como máximo una carta. Rescate no se consume si no hay
un evento activo; Descuento y Re-voto solo aparecen como acciones en el mostrador
de suministros cuando el jugador tiene la carta correspondiente.

En una sesión online, abrir Suministros inicia una votación: cada oferta muestra
los colores de quienes la eligieron y el reloj de 20 segundos empieza con el
primer voto. La votación termina antes si ya votaron todos; gana la mayoría y,
si empatan, la opción más barata. En solitario la compra sigue siendo directa.

## Eventos de ruta

| Orden | Evento | Efecto |
| ---: | --- | --- |
| 1 | Inspección sorpresa | Exige carga asegurada, material peligroso aislado o cabina sin olor. Fallar aplica multa, no termina la partida. |
| 2 | Cliente impaciente | Reduce el bono de tiempo. |
| 3 | Puerta trasera trabada | Una caja bloquea la salida y debe liberarse desde dentro. |
| 4 | Etiquetas mezcladas | Un golpe confunde etiquetas y el equipo debe identificar la caja correcta. |
| 5 | Paquete mimético | Revela su riesgo real al recibir un impacto. |
| 6 | Caja parásita | Dos jugadores separan cajas enganchadas antes de que ambas se dañen. |
| 7 | Tienda confusa | Evento raro que mezcla descripciones de dos compras. |

## Implementación

1. Mérito individual y dinero cooperativo.
2. Votación de compras.
3. Cartas Rescate, Descuento y Re-voto; Prioridad e Información quedan fuera del MVP.
4. Inspección sorpresa y Cliente impaciente.
5. Puerta trabada, Etiquetas mezcladas, Paquete mimético, Caja parásita y Tienda confusa.
