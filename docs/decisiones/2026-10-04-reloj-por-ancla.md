# Decisión 2026-10-04: el reloj del modo Empresa viaja como ancla, no cada 2 s

Tomada por la rutina `desarrollador` (carril 5) al hacer D-2001
([red-autoridad.md](../expansion-distritos/diseno/red-autoridad.md)).

**Decisión:** el host manda el reloj del día como un evento `clock_anchor` `{minute, speed, paused}`
por `CompanyNet` (reliable, con `seq`) solo cuando cambia la marcha: apertura, pausa, reanudación y cierre
que espera a la salida en curso. Cada peer toma como origen su propio tick al recibir el ancla (o al aplicar el snapshot), menos medio RTT de `NetStats`, y calcula la hora local desde ahí: el tick del host no vale en otra máquina.

**Por qué:** es lo que ya fijaba `docs/arquitectura.md` §10.2; D-0219 decía otra cosa (un valor cada 2 s
por `unreliable_ordered` con interpolación). El ancla no gasta ancho de banda con el día corriendo, no
necesita interpolar ni corregir desvíos, entra en el snapshot del join tardío como cualquier otro estado y
usa el mismo RPC que el resto del negocio (un RPC menos que auditar).

**Cambia:** D-0219 en `docs/expansion-distritos/detalle/F0-02-arquitectura.md` (corregida en el mismo PR).
Su test `test_game_clock` sigue igual: dos peers ven la misma hora ±1 min tras 60 s y la pausa los frena.
