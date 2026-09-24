# Guion del tráiler

> Tareas de Nacho N-903, 2026-09-24. Borrador para grabar con la cámara de tráiler (N-902) y
> los efectos de falla por trampa de Slatex (S-310). Duración objetivo: **75 s** (entra en el
> rango de 60-90 s y deja margen para cortar). Formato 1920×1080 a 60 FPS, sin HUD salvo donde
> se indica. Pensado para la página de Steam: tiene que funcionar **sin sonido** (texto en
> pantalla) y engancharse en los **primeros 5 segundos**.

## Idea en una línea

Uno maneja, los demás cuidan cajas con trampas atrás, y el conductor no ve lo que su manejo le
hace a la carga. El tráiler alterna **cabina tranquila** con **caja de carga en llamas
(figuradas)** hasta que las dos cosas se juntan.

## Plano por plano

| # | Tiempo | Qué se ve | Qué suena | Texto en pantalla |
|---|---|---|---|---|
| 1 | 0:00-0:03 | **Gancho.** Primera persona en la caja de carga: un pasajero sostiene una caja Frágil; el camión pasa un badén y la caja sale volando por la puerta trasera abierta. | Golpe seco, grito corto, silencio. | — |
| 2 | 0:03-0:05 | Corte a la cabina: el conductor, tranquilo, mano en la bocina. | Bocina alegre. | **"Todo bien por acá."** |
| 3 | 0:05-0:09 | Logo sobre el camión saliendo del depósito, portón subiendo (plano N-902 "salida del depósito"). | Entra la música (`mus_ingame_loop`), motor. | **TAKE MY PACKAGE** |
| 4 | 0:09-0:15 | Adentro del depósito: la pizarra con los pedidos, alguien agarra una caja del estante con su código, la sube al camión. | Pasos, carretilla de fondo. | "Cargá los pedidos." |
| 5 | 0:15-0:21 | Curva en el bosque desde afuera (plano N-902): el camión se inclina, la cámara se mete por la puerta trasera y se ven las cajas deslizarse. | Chirrido de gomas. | "Uno maneja." |
| 6 | 0:21-0:27 | Primera persona de un pasajero atendiendo una caja Ruidosa que se sacude; otro agarra la de Equilibrio. | Ruido de la trampa, respiración. | "Los demás cuidan la carga." |
| 7 | 0:27-0:33 | Cruce de tren (plano N-902): barreras bajando, el camión frena en seco, las cajas golpean la mampara. | Campana del cruce, bocina del tren. | "Cada caja tiene su trampa." |
| 8 | 0:33-0:39 | Montaje rápido de fallas (S-310), 1 s cada una: esquirlas de porcelana (Frágil), torre que se derrumba (Equilibrio), animal que salta y escapa (Ruidoso), charco (Líquido), confeti de colores (Explosivo). | Un golpe de música por cada falla. | — |
| 9 | 0:39-0:45 | Puente angosto con lluvia (plano N-902): el camión entra justo, limpiaparabrisas, gotas. | Lluvia, motor bajo. | "Rutas nuevas en cada partida." |
| 10 | 0:45-0:50 | Ciervo cruzando: el conductor toca bocina y el ciervo escapa; corte a una segunda toma donde no toca y lo choca. | Bocina / golpe y multa. | — |
| 11 | 0:50-0:57 | Llegada a una casa de noche (plano N-902): porche encendido, un pasajero baja con la caja, toca el timbre, el vecino abre y se agarra la cabeza. | Timbre, puerta, reacción. | "Entregá lo que quede." |
| 12 | 0:57-1:05 | **Clímax.** Vuelco en una curva con cajas volando en cámara lenta (plano N-902 "vuelco"); corte a la cabina, el conductor mirando por el espejo. | La música se corta en el vuelco; vuelve en el corte. | — |
| 13 | 1:05-1:10 | Pantalla de resultados con la tripulación frente al camión volcado; foto de la entrega con una caja rota. | Risa, fanfarria corta. | "1-4 jugadores · cooperativo en línea" |
| 14 | 1:10-1:15 | Logo, "Agregalo a tu lista de deseos", fecha o "Próximamente". | Última nota. | **TAKE MY PACKAGE · Wishlist en Steam** |

## Reglas para grabar

- **Los primeros 5 s deciden.** El plano 1 tiene que ser una caja perdiéndose sin contexto: el
  espectador de Steam ve el tráiler en silencio y en automático.
- **Sin interfaz** salvo el plano 13 (resultados). Nada de prompts de interacción en pantalla:
  desactivar el HUD en la build de grabación.
- **Clima y hora forzados** con `--mood=` (`docs/qa-recorrido.md`): plano 9 `lluvia_dia`, plano
  11 `soleado_noche`, el resto `soleado_dia` o `nublado_atardecer`.
- **Voces:** si hay chat de voz en la grabación, que sean reacciones reales de gente jugando,
  bajas en la mezcla. Nunca voz en off explicando.
- Los textos se traducen con el juego (inglés primero para Steam); los de acá son la versión en
  español.

## Pendientes para poder grabarlo

| Qué | Tarea |
|---|---|
| Cámara de tráiler con rieles y los 6 planos guardados | N-902 |
| Fallas distintas por trampa (plano 8) | S-310 (Slatex) |
| Lluvia en el parabrisas y limpiaparabrisas (plano 9) | N-303 |
| Porche encendido y casa que espera entrega (plano 11) | N-501 |
| Reacción del vecino en la puerta (plano 11) | N-604 |
| Logo en imagen para el cierre | `docs/inventario-assets.md` (logo 🟡) |
