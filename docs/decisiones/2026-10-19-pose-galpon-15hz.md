# Decisión 2026-10-19: el jugador manda su pose a 15 por segundo en el mundo de la empresa (D-2002.3)

**Decisión:** en el modo Empresa, el jugador a pie manda su pose a 15 por segundo en vez de 30
(`CompanyTuning.SHED_POSE_RATE_HZ`). El juego normal sigue a 30. Así un galpón con 8 jugadores entra en
el presupuesto de 24 KB/s por cliente de D-2002 (los números medidos están en
[`rendimiento-pc.md`](../rendimiento-pc.md), "Ancho de banda del modo Empresa").

**Por qué:** con 8 jugadores lo que se pasaba eran las poses de los otros clientes que reenvía el host, un
paquete por jugador y por envío. Adentro del galpón nadie va rápido y `NetPoseSmoother` mide el intervalo que
le llega, así que los demás se siguen viendo suaves (con unos 66 ms más de colchón). Es un número en
`company_tuning.gd`: si se nota a mano, se sube.

**Descartado:**
- Que el host junte las poses de todos en sus propios paquetes (~21,6 KB/s): cambia quién manda las poses
  (un espejo de cada jugador en el host o un RPC por lote) y suma un tick de latencia. Mucho más código para
  un ahorro parecido; queda como opción si 15 por segundo se ve mal.
- Aceptar un presupuesto aparte para 8 jugadores: deja el problema para cuando el galpón tenga más cosas
  sincronizadas (cajas armadas, zorras).
