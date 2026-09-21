# Controles y flujo de UI/lobby — Do Not Drop

> Última actualización: 2026-09-20
> Cada jugador juega desde su propio dispositivo/cliente (no split-screen local) —
> esto simplifica el esquema de controles: cada uno usa su teclado+mouse o gamepad
> completo, no hay que repartir un solo teclado entre varios jugadores.

## 1. Esquema de controles

### Conductor
| Acción | Teclado | Gamepad |
|---|---|---|
| Acelerar | W | Gatillo derecho (RT) |
| Frenar/retroceder | S | Gatillo izquierdo (LT) |
| Girar izquierda/derecha | A / D | Stick izquierdo |
| Freno de mano | Espacio | Botón A/X (según plataforma) |
| Bocina (feedback/comedia) | Click medio / H | Botón B/círculo |
| Mirar alrededor (asiento, primera persona) | Mouse | Stick derecho |
| Centrar la vista | C | Clic del stick derecho |

### Pasajero (interacción con su paquete)
Diseño unificado para que los 4 tipos de trampa usen el mismo lenguaje de controles
(consistencia = menos fricción para nuevos jugadores en una sesión de fiesta):

| Acción genérica | Teclado | Gamepad | Uso según trampa |
|---|---|---|---|
| Acción primaria (mantener) | Click izquierdo (mantener) | Gatillo derecho (mantener) | Equilibrio: sostener: Ruidoso: calmar |
| Acción secundaria (tap) | Click derecho / E | Botón A/X | Confirmar paso de secuencia (Peso creciente) |
| Movimiento/dirección | WASD o mouse | Stick izquierdo | Input de secuencia (Peso creciente), dirección de corrección (Equilibrio) |

### General (todos los jugadores)
| Acción | Input |
|---|---|
| Ping/emote rápido | Rueda del mouse click / D-pad | Sistema de comunicación no verbal para MVP (ver nota abajo) |
| Pausa/menú | Esc / Start | — |

### Nota sobre comunicación entre jugadores
Para el MVP **no se implementa voice chat propio** (agrega complejidad de red y de
librerías externas no justificada para una v1) — se asume que los grupos usan Discord/
voice chat externo, como la mayoría de los juegos coop chicos de este tipo. El juego sí
incluye un **sistema simple de pings/emotes** (ej. "¡ayuda!", "¡cuidado!") para
jugadores que jueguen sin voice chat externo. Voice chat propio queda como posible
mejora post-launch, no bloqueante para el MVP.

---

## 2. Flujo de UI

```
Main Menu
  ├── Jugar
  │     ├── Crear partida (host)
  │     │     └── Lobby (esperando jugadores)
  │     └── Unirse a partida (por código/IP)
  │           └── Lobby (esperando al host)
  ├── Cómo jugar (tutorial/explicación de trampas)
  ├── Progreso (desbloqueos, ver docs/requerimientos-tecnicos.md sección 3.2)
  └── Opciones (audio, controles, video)
```

### Lobby
- Lista de jugadores conectados (nombre + listo/no listo).
- Host elige: vehículo (si hay más de uno desbloqueado) y ruta/modo (normal vs.
  endless, si ya está implementado).
- Botón "Listo" por jugador; el host inicia cuando todos están listos.
- **MVP de conexión**: código de sala simple o IP directa (Godot ENet) — sin
  integración con matchmaking de Steam en el MVP, para no sumar esa complejidad antes
  de validar el juego. Se evalúa sumar Steam networking/matchmaking después del EA si
  hace falta.

### Asignación de roles y paquetes
- Al empezar la partida, un jugador es conductor (rotable entre partidas o elegido en
  el lobby, a definir con playtesting) y el resto recibe un paquete cada uno.
- Las trampas asignadas a cada paquete salen de las desbloqueadas hasta el momento,
  con las reglas de balance de `requerimientos-tecnicos.md` sección 3.3 (no combinar
  demasiadas trampas de alta dificultad en partidas tempranas).

### HUD durante la partida
- **Conductor**: velocímetro simple, indicador de distancia/tiempo restante a destino.
- **Pasajero**: su propio paquete en pantalla con el medidor de integridad/agitación
  visible (barra de color: verde=OK, amarillo=EnRiesgo, rojo=Arruinado), y el prompt de
  la acción correspondiente a su trampa.
- **Compartido**: mini resumen del estado de todos los paquetes (iconos chicos) para
  que todos vean cuándo un compañero está en problemas — esto refuerza la tensión
  social/cooperativa (mecánica #8 del banco: riesgo compartido).

### Pantalla de resultados
- Desglose de puntaje por paquete (según fórmula de `parametros-diseno.md`).
- Progreso de desbloqueos ganado en esta partida.
- Botones: "Jugar de nuevo" (mismo lobby) / "Volver al lobby" / "Salir".

## Próximo paso
Con esto ya están definidos controles y flujo de UI necesarios para implementar la
Fase 5 del plan de desarrollo (meta-progresión y UI) sin ambigüedad, y suficiente
información para armar el Input Map de Godot (ver `docs/convenciones-godot.md`).
