# N-950 — adaptador de barrio jugable offline

`town_delivery.tscn/gd` reutiliza jugador, camión, cajas y DeliveryHouse;
acepta pedidos de orden libre y cierra al volver al depósito. El estado
es temporal, sin recompensas/campaña. Se rechaza iniciar con sesión online.
La escena de inspección original sigue disponible; calles/cruces suman colisión.

`scripts/presentation/dashboard_gps.gd` agrega el Callable opcional
`guidance_provider`: devuelve `{distance, label, waypoint: Vector3, house}`
o `{}` para ocultar una ruta inexistente. Sin callback conserva el recorrido
lineal y Endless. Sin cambios en firmas previas, RPC ni protocolo.

Hacer pull antes de trabajar sobre el GPS. Instrucciones de F6 y validación
en `docs/mapa-pueblo.md`; integración de menú, campaña y cooperativo pendiente.
Los textos nuevos del barrio usan claves WORLD_TOWN_*/HUD_TOWN_* en las
tablas existentes `strings_world.csv`/`strings_ui.csv`, en español e inglés;
también se corrigen los literales de la escena de inspección del primer paso.
