# Competidores de manejo cooperativo

> Relevado el 2026-09-24 desde las páginas de Steam y sus reseñas (tareas de Nacho N-904).
> Los precios y las reseñas cambian: volver a mirar antes de fijar el precio o armar la página.
> Complementa `docs/investigacion-mercado.md`.

## Resumen

| Juego | Precio (USD) | Reseñas en Steam | Jugadores | Gancho |
|---|---|---|---|---|
| [Totally Reliable Delivery Service](https://store.steampowered.com/app/1011670/Totally_Reliable_Delivery_Service/) | 14,99 | Mayormente positivas (76 % de ~1.700); últimos 30 días 60 % | 1-4, online y pantalla dividida | Repartidores torpes con ragdoll en un mundo abierto, vehículos y gadgets raros. |
| [Drive Together](https://store.steampowered.com/app/4117320/Drive_Together/) | 3,49 | Variadas (55 % de 43) | 1-4 (parkour), hasta 8 (carrera) | "Un auto, varios conductores": cada jugador controla una parte del mismo auto (volante, acelerador, freno). |
| [Co-Drive Chaos](https://store.steampowered.com/app/4265920/CoDrive_Chaos/) | 2,69 | Sin puntaje todavía (9 reseñas) | 2-4 online | Uno solo puede girar a la derecha y otro solo a la izquierda; rutas de terror. |
| [Deliver Together](https://store.steampowered.com/app/3419270/Deliver_Together/) | Sin precio (sin lanzar, 2026) | — | Hasta 8 | Dos camiones atados a un mismo acoplado; hay que coordinar para no arrastrar al otro. |

## Qué elogian y qué critican del manejo

**Totally Reliable Delivery Service** (el más parecido en tema y el único con volumen):
- Elogian el caos físico con amigos y la libertad del mundo abierto.
- Critican controles "torpes" y poco precisos, agarrar paquetes que "terminan atrás tuyo", y
  sobre todo la red: desincronización constante, retraso de entrada y rendimiento malo jugando
  con amigos. También que se repite: "lo jugás una, dos, tres veces y nunca más". Las reseñas
  recientes bajaron porque apagaron servicios en línea.

**Drive Together**:
- Elogian que es barato y divertido para un rato ("friendslop" por menos de 5 USD).
- Critican la física impredecible (autos que salen disparados o vuelcan sin forma de
  recuperarse), poco contenido (3 niveles de parkour) y que un error de uno resetea a todos.

**Co-Drive Chaos** y **Deliver Together**: todavía sin reseñas que sirvan. Confirman que el
subgénero "un vehículo, control repartido" está de moda en 2026 y lleno de juegos baratos.

## Cómo se ven sus páginas

- Todos abren con tráiler de caos físico (vuelcos, choques, gente gritando) y capturas del
  vehículo en problemas; ninguno muestra una interfaz.
- Los chicos (Drive Together, Co-Drive Chaos) venden la frase del gancho en la primera línea
  ("One car. Multiple drivers. Zero coordination").
- Etiquetas que se repiten: Online Co-Op, Physics, Driving, Party Game.

## Qué hacemos distinto

**Una frase:** en Take My Package no se reparten los controles de un mismo auto: cada uno tiene
un rol distinto (uno maneja y los demás cuidan paquetes con trampas propias atrás), así que el
caos sale de que el conductor no ve lo que su manejo le hace a la carga.

Lecciones para nosotros:
- **La red es lo que más castiga a TRDS**: desync y retraso son su crítica número uno. Justifica
  N-207 (prueba con 3 jugadores) y N-208 (camión suave en clientes) antes del lanzamiento.
- **Física impredecible frustra si no se puede recuperar**: la detección de vuelco y el rescate
  tienen que funcionar siempre (N-803).
- **Un error de uno no debe castigar a todos**: ya es regla nuestra (arruinar una caja no
  termina la entrega, `docs/parametros-diseno.md`).
- **Rejugabilidad**: la queja "lo jugás tres veces" es el riesgo que cubren la ruta
  procedural, las trampas y la progresión.
- **Precio**: el subgénero barato está en 3 USD; TRDS, con más contenido, en 15. Nuestro rango
  de 8-15 USD (`docs/plan-desarrollo.md` Fase 7) tiene que justificarse con contenido y red
  sólida, no con el gancho solo.
