# Dificultad del modo Empresa (D-0127) — 2026-10-22

## Decisión
Diseño en `docs/expansion-distritos/diseno/dificultad.md`:
- **Una sola dificultad.** Sin tamaños de empresa (chica, mediana, grande) ni niveles fácil / normal / difícil.
- **Dos modificadores** de la empresa, apagados al crearla, que elige el host **solo fuera de la partida** (al
  crearla o desde la lista de guardados):
  - **Armado asistido** (`assisted_packing`): al sellar con cinta, la mesa rellena sola los huecos libres,
    cobrando el relleno como siempre, sin que el relleno deje la caja sin cerrar. La caja queda `assisted` y
    amortigua como mínimo 0,75 (el relleno de la partida rápida), así lo armado a mano (0,6) sigue valiendo más
    en la ruta. `Q` y la paga no cambian.
  - **Días tranquilos** (`calm_days`): sin eventos del día.
- Se guardan en `CompanyState.options` con valores por defecto, sin subir la versión del save y sin RPC: las dos
  reglas corren en el host. No bloquean hitos, logros ni récords. Lo construye D-1919.

## Por qué
- La crítica de alcance (D-0112, `critica-alcance.md` §4.5) ya lo pedía: una dificultad con armado asistido.
- El esfuerzo ya escala con la tripulación (pedidos, ayudas del modo solo, eventos por tramo), con el día de
  campaña y con la quiebra suave. Tres tamaños serían tres curvas de economía que balancear y medir con un
  equipo de 2.
- Cada modificador saca una sola fricción que a cierta gente le arruina el juego (encastre fino con mando,
  sorpresas del día) sin tocar números de la economía, así la curva de `sim_economy` sigue siendo una.

## Alternativas
- Tres tamaños de empresa (la tarea original): triplica balance y tests de economía.
- Niveles fácil / difícil que cambian plata inicial, alquiler o ventanas: son otra curva; las ventanas además
  chocan con `roles-tripulacion.md` §6.5.
- Marcar las partidas con modificadores o bloquear logros: castiga al que lo necesita en un coop sin tabla de
  posiciones.
- Cambiar los modificadores con la empresa abierta (pausa o resumen del día): cambia la regla de una caja a medio
  armar, necesita un hecho de red para los clientes y choca con el sorteo de eventos, que se hace al cerrar el día
  anterior en la misma pantalla del resumen.
- Caja asistida con la absorción máxima (0,6): más simple, pero el relleno a mano dejaría de tener sentido.
