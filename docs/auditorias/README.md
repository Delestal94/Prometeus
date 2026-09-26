# Registro de auditorías de calidad

Este directorio conserva las conclusiones que deben seguir disponibles en el repositorio aunque caduquen los artefactos de GitHub Actions.

## Evidencia automática

El workflow **Tests** adjunta evidencia por iteración (commit, intento del workflow):

- **Tests headless:** CSV `godot-headless-audit-*`, una fila por prueba con nombre, estado, código de salida y duración.
- **Runtime audit:** metadatos del runner, log de render y cinco capturas del HUD; además, log de `bench_drive` con FPS, tiempo de frame p50/p95/p99/máximo, hitches, carga de physics, draw calls, objetos, primitivas y memoria estática/de video.
- **Network pair:** log de la prueba de dos procesos con RTT ENet medio, varianza y pérdida observada en loopback (se marca `NA` si el intervalo no alcanza para medir pérdida con validez).

Los artefactos se conservan durante 90 días. Para consultarlos, abrir la ejecución en **Actions → Tests → job correspondiente → Artifacts**. Los logs de los jobs también quedan en la página de la ejecución según la retención configurada en GitHub.

Los logs completos y los tiempos en vivo quedan también en la salida del job. Los jobs de red (dos y tres peers) publican su diagnóstico directamente en esos logs cuando fallan.

## Cómo interpretar las métricas

- El benchmark gráfico corre en Ubuntu 24.04 con pantalla virtual y renderizador de software, usando siempre la semilla 4242. Sirve para comparar cambios en un entorno más fijo, pero sus FPS no representan los de una PC de jugador ni sustituyen pruebas en hardware objetivo.
- El RTT informado es el tiempo de ida y vuelta de ENet entre procesos en `localhost`; comprueba el camino de red del juego y detecta regresiones del transporte. No es el ping de Internet ni mide latencia bajo congestión. La pérdida de paquetes solo se informa cuando ENet ya completó un intervalo de medición de al menos 10 segundos; de lo contrario figura como `NA`.
- Las capturas del HUD son evidencia para revisar texto cortado, solapamientos y jerarquía visual; su generación no certifica automáticamente que la interfaz sea correcta. La matriz exige además revisión de teclado/mando y resoluciones objetivo.
- No aplicar umbrales de FPS/RTT todavía. Primero recopilar ejecuciones comparables y definir hardware/condiciones de referencia; investigar variaciones grandes repitiendo el mismo commit y semilla.

## Registro duradero

Después de cada auditoría de rendimiento o revisión importante, añadir aquí un archivo con fecha (por ejemplo, `2026-10-15.md`) siguiendo esta estructura:

- Alcance y commit revisado.
- Ejecución de GitHub Actions enlazada.
- Entorno y versión de Godot.
- Resultados: pass/fail/skip, duración total, pruebas más lentas y cambios respecto de la línea base.
- Errores, regresiones o intermitencias con semillas y pasos para reproducirlos.
- Decisiones, responsable y estado de cada acción pendiente.
- Revisión manual pendiente o completada (visual, mando y hardware objetivo).

No declarar una regresión solo por una ejecución aislada: comparar ejecuciones equivalentes y repetir resultados sospechosos. Mantener separados los fallos funcionales, intermitencias y límites de rendimiento.

## Estado inicial

La matriz de comportamiento está en [`../matriz-comportamiento-cobertura.md`](../matriz-comportamiento-cobertura.md). Aún no existe una línea base de duración, rendimiento o RTT generada por el workflow actualizado; se establecerá tras varias ejecuciones verdes y comparables en GitHub Actions. La evidencia detallada es temporal (90 días); las conclusiones y decisiones aceptadas se conservan en este directorio mediante control de versiones.
