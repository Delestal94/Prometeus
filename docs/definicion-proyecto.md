# Definición de proyecto — Take My Package (vigente)

> Última actualización: 2026-09-20
> Este es el concepto **definitivo** del proyecto. El proceso de exploración previo
> (candidatos de MVP, banco de ideas, y un concepto de puzzle/narrativa descartado) se
> conserva en `docs/historial-exploracion/` solo como registro histórico.

## Concepto

**Take My Package** (nombre oficial desde 2026-09-22; nombre de trabajo anterior: "Do Not Drop"): delivery cooperativo de hasta 5 jugadores. Uno
conduce una camioneta, los demás (hasta 4) llevan un paquete cada uno. Cada paquete
tiene una "trampa" — una regla individual que el pasajero debe manejar mientras el
vehículo se mueve. El caos surge del cruce entre la conducción (afecta físicamente a
todos los paquetes a la vez) y las reglas individuales de cada pasajero.

Propuesto directamente por el usuario, no derivado del banco de ideas generado
previamente — coincide con el patrón más fuerte de toda la investigación de mercado:
el dev hace el juego que él mismo quiere jugar (ver `docs/checklist-exito.md`).

## Por qué este concepto (resumen de la evaluación)
- Cruza dos referencias con demanda actual probada: el "caos físico cooperativo" tipo
  **PEAK** (5M copias en menos de un mes, 2025) y el género de delivery físico
  cooperativo tipo **Totally Reliable Delivery Service** (14M descargas).
- Diferenciación real frente a la ola de "chaos co-op" reciente (Drive Together,
  Co-Drive Chaos, Deliver Together): esos juegos son de **control compartido
  simétrico** de un mismo vehículo; Take My Package propone **roles asimétricos** (un
  conductor normal + pasajeros con mini-puzzles individuales), que no encontramos
  replicado en ningún juego existente al momento de la investigación.
- Rating de evaluación: 8/10 (ver el análisis completo en el historial de la
  conversación de diseño — no está en un documento de "ideas candidatas" porque nació
  fuera de ese proceso).

## Documentos que desarrollan este concepto
- `docs/requerimientos-tecnicos.md` — stack técnico (Godot), arte (estilo PEAK),
  diseño de adicción/rejugabilidad.
- `docs/arquitectura.md` — arquitectura de software (componentes, patrones).
- `docs/plan-desarrollo.md` — plan de desarrollo por fases + Definition of Done.
- `docs/parametros-diseno.md` — valores numéricos iniciales de cada trampa.
- `docs/controles-y-ui.md` — controles y flujo de UI/lobby.
- `docs/convenciones-godot.md` — convenciones técnicas concretas del proyecto Godot.

## Estado de decisiones abiertas
- Nombre definitivo: **cerrado el 2026-09-22 — "Take My Package"**. Reemplaza al nombre de
  trabajo "Do Not Drop"; la carpeta `do-not-drop/` conserva el nombre viejo a propósito
  (renombrarla toca rutas en todo el repo sin beneficio para el jugador).
- Resto de las decisiones de diseño (parámetros, controles, arquitectura) ya están
  cerradas en los documentos listados arriba.
