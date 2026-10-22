# Cerrar el día antes: la lógica ahora, el botón con el menú de pausa (D-0253)

**Decisión:** D-0253 se cierra en parte. `DayCycle.close_early()` y `DayClose` (estado del botón, confirmación,
"Lo cierra el host" para el cliente y el aviso de las dos salidas, con sus textos en `strings_ui.csv`) quedan
hechos y probados. Dibujar el botón y el aviso pasa a la subtarea D-0253.a, que se hace junto con D-1909.

**Por qué:** el modo Empresa todavía no tiene menú de pausa. Jugando solo, `CompanySoloPause` muestra solo
el cartel "PAUSA", y en cooperativo no hay pausa (la del HUD es del modo reparto). Armar un menú de pausa
entero para un botón es el trabajo de D-1909 (`constructor-ui`), y hacerlo acá lo duplicaría. Con `DayClose`,
D-1909 solo tiene que dibujar lo que ya está decidido y probado.

**Lo que se mantiene de D-0134:** lo pide solo el host, sin voto. El cierre va por la misma transición que a
las 20:00, así que no esquiva penalidades ni el alquiler. El aviso de salir sale solo en el host (un cliente que
se va no pierde nada del día del host).
