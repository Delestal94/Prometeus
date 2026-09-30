# Decisiones 2026-09-30: las 9 preguntas de la auditoría integral

Respuestas a "Preguntas para el usuario" de `docs/auditorias/2026-09-30-integral.md`. Las dos primeras
las dio el usuario. Para el resto pidió "la forma más eficiente sin que tenga que intervenir una persona":
las eligió la conversación principal con él y quedan como decididas. Si una rutina encuentra una razón fuerte
para cambiar alguna, la anota como hallazgo; no la cambia por su cuenta.

| # | Pregunta | Decisión | Quién la ejecuta |
|---|---|---|---|
| 1 | ¿Tope de 5 u 8 jugadores? | **8** (usuario). Ya es `NetworkManager.MAX_PLAYERS = 8`; lo que diga 5 está desactualizado. | N-228 |
| 2 | ¿De dónde sale la plata del equipo? ¿Se borra el bono de tiempo? | **La plata es compartida** (usuario): una sola billetera del equipo, se gasta en conjunto. Pago por entrega = `delivery_points` (puntos de puerta: estado de cada caja, rescates, fotos, plazos) + `cargo_points` (cajas sanas que siguen a bordo), sin el multiplicador de caos (ese sigue solo en el puntaje). **El bono de tiempo se borra** del pago y del puntaje: con el par fijo de 75 s da siempre 0 y los plazos por casa ya premian la velocidad. "Cliente impaciente" deja de quitar el bono y pasa a acortar el plazo de la casa siguiente. Precios de tienda ajustados para que una entrega completa promedio alcance para un ítem de precio medio. | N-227.2 |
| 3 | Reclamo por caja abollada: ¿50 % de azar o determinista? ¿Fórmula real de Endless? | **Determinista**: toda caja abollada genera reclamo (se lee mejor y no depende de la semilla). La fórmula actual de Endless queda como está; los docs pasan a describirla. | N-227.2 (docs) |
| 4 | ¿`gh` en la nube o MCP de GitHub? | **MCP de GitHub** (`mcp__github__*`), que es lo que las rutinas de la nube ya usan. No se instala `gh`. | README de rutinas, regla 2 |
| 5 | ¿Merge queue o "branches up to date"? ¿`cancel-in-progress`? | **Ninguna de las dos**: la merge queue no existe para repos de usuario, y "up to date" deja los auto-merge esperando a que alguien actualice la rama. Se mantiene: `main` rojo es lo primero que arregla la construcción. **`cancel-in-progress` solo en PRs**, así cada commit de `main` se prueba entero. | `.github/workflows/tests.yml` (hecho) |
| 6 | ¿Ampliar el freno a toda tarea que toque cuerpo, ragdoll o clips del personaje? | **Sí**, mientras S-311 siga abierta. | `construccion.md` (hecho) |
| 7 | Texturas de N-314: ¿reimporte a mano o script? | **Lo hace la sesión de arte de la PC** abriendo Godot con un script que cambia los parámetros de importación por la API del editor y reimporta; Godot escribe los `.import`, no se editan a mano. | N-314 |
| 8 | ¿Qué trampas salen en solo? | **Las de hoy**: Frágil y Equilibrio (`depot.gd`, `SOLO_TRAPS`), porque las demás piden un segundo par de manos. | ratificado, sin tarea |
| 9 | ¿Se mantiene el objetivo de casi-pérdidas del jugador torpe (≥ 1)? | **Sí**. El balance que sigue en "REQUIERE AJUSTE" pasa a tarea. | N-229 |
| 10 | N-109: ¿el perro y las abejas también rondan una caja cerrada? | **No**: perro y abejas solo con caja abierta; cerrar la tapa es la contramedida (decidido por Claude con delegación del usuario, 2026-09-30). | N-109 |

Pregunta 9, agregado: Ruidoso: una caja rescatada tras tocar el máximo de agitación cuenta como casi-pérdida (decidido por Claude con delegación del usuario, 2026-09-30).
