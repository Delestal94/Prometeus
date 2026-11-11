# Decisión: el puntaje de la corrida entra a la salida como mérito, no como plata (D-0520)

- **Qué:** una salida del modo Empresa tiene un puntaje (`TripScoring`, con las constantes de `RunScoring`:
  150 / 75 / 20 por caja intacta / abollada / rota, -60 por pedido que no llegó, piso 0) que se muestra en el
  resumen de la salida y del día y reparte el mérito de quien llevó cada caja (intacta 10, abollada 5, rota 0).
- **Por qué no es plata:** la paga del pedido ya se cobra en la puerta (D-0516). Sumar los puntos como plata
  pagaría cada caja dos veces (150 de puntos contra ~105 de margen) y rompería la curva de 20 días de
  `diseno/economia.md` §5, que `sim_economy` (D-0540) debe reproducir. S8 dice que el mérito se sigue ganando
  en las salidas: ahí entra el puntaje.
- **Cambio de números:** ninguno en `company_tuning.gd`. Cambia una regla: la caja abollada ahora da mérito
  (la mitad), antes solo la intacta.
- **Exploits considerados:**
  - *Farmear la ruta fácil:* el mérito es por pedido y se paga una vez (`award_action` por `trip:<id>:<pedido>`);
    los pedidos del día están topados (16), y un pedido cuesta mercadería: repetir una ruta corta no rinde más.
  - *Suicidar la corrida para recomprar:* el puntaje no da plata, así que no hay nada que cobrar; un pedido que no
    llega resta 60 al puntaje (piso 0) y no da mérito.
  - *Romper cajas a propósito:* la caja rota da 20 de puntaje y 0 de mérito, y su paga ya se perdió (D-0506).
  - *Votar en bloque:* no aplica, el puntaje lo calcula el host con el resumen de la salida.
  - *Mérito y cartas:* en `CrewProgression` el mérito sube la chance de carta (+1 % por punto). Con tope de 16
    pedidos por día, un jugador suma como máximo 160 de mérito por día; si en F2 se ve que satura la chance, el
    ajuste es bajar `TRIP_MERIT_INTACT` (un solo número).
- **Afuera a propósito:** foto, reclamos, plazos y carga que vuelve (ver el detalle de D-0520).
- **Se revierte con:** dejar `TripResult.build` sin la llamada a `TripScoring` (el mérito vuelve a ser solo de la
  caja intacta si `merit_for` se limita a ella).
