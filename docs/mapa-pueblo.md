# Ciudad procedural — primer paso de desarrollo

Decisiones del equipo, 2026-10-02: una ciudad continua con seis distritos;
contorno asimétrico que varía por semilla, calles diagonales y manzanas de
tamaños distintos. Plazas, parques, jardines y monumentos forman parte del
trazado. Una campaña conservará su mundo al continuar; una campaña nueva
tendrá otra semilla. El guardado y la campaña todavía no están conectados.

## Distritos

1. Barrio del depósito: inicio, viviendas bajas, taller, plaza y parque.
2. Centro: comercios, plazas y calles más ajustadas.
3. Industrial: fábricas y cargas pesadas.
4. Campo: caminos rurales y barro.
5. Puerto: muelles y costa.
6. Sierra: pendientes, bosque y nieve.

Conexiones previstas: 1–2, 1–4, 2–3, 3–5, 5–4, 4–6, 6–3.
Se abren por progresión/capacidad del vehículo en un paso posterior.
El trazado completo se genera antes de abrir distritos: desbloquear una zona
no debe cambiar las calles ni mover las casas existentes.

## Implementado en esta rama

`modules/town_gen/town_plan.gd` devuelve datos, sin escenas ni autoloads:

- Semilla y `generator_version = 1`.
- Seis distritos de contorno irregular, con escala, orientación y vértices
  variados por semilla. Las conexiones funcionales son estables.
- Grafo de cruces y calles de 12 m: circuitos locales, diagonales y conexiones
  entre distritos. Las calles que se cruzan comparten un nodo del grafo.
- Lotes con frente a una calle, posición, tamaño, orientación y dirección.
- Plaza y parque reservados antes de colocar edificios. Lotes y vegetación
  respetan el espacio de circulación.
- Un depósito, tres casas de clientes y un taller en el distrito inicial.

Flujos RNG separados para forma, áreas verdes y lotes; no usa el RNG global
ni el roster de jugadores. Mismo generador y semilla producen el mismo plano.

`scenes/gameplay/town/town_prototype.tscn` construye **solo el primer barrio**:
calles, patios, edificios con colisión, árboles agrupados en MultiMesh,
bancos, farolas y una plaza con monumento de paquetes. Las salidas a Centro
y Campo tienen barreras. Los edificios son volúmenes de prototipo, no arte final.

### Abrir y recorrer

Abrir la escena en Godot y pulsar **F6**. Cámara libre: WASD mueve, Q/E cambia
altura, botón derecho permite mirar y Shift acelera. La escena acepta
`--town-seed=4242` después de `--` para repetir un mundo. También puede
fijarse `world_seed` en el inspector. Con valor cero toma la semilla de la
sesión si existe y genera una nueva en una prueba independiente.

No está todavía en el menú ni sustituye Reparto/Endless. Es una escena de
inspección del mapa; no ejecuta pedidos, conducción, GPS ni progresión.

## Validación

- `modules/town_gen/tests/test_town_plan.gd`: 100 semillas, conectividad de
  los seis distritos, variación, determinismo, roles iniciales, parques y
  lotes fuera de las calles y cruces unidos en el grafo. Portable.
- `tests/test_town_prototype.gd`: escena real, edificios con colisión,
  barreras, plaza/monumento, árboles agrupados y centros de calle despejados.
- `tests/render_town_prototype.gd`: dos semillas desde arriba y plaza a
  altura de calle para revisión visual.

## Siguientes pasos del spike N-950

Conectar el camión y entregas de orden libre; navegación por el grafo y GPS;
medir duración, esfuerzo de carga, visibilidad de las casas y presupuesto de
render. Luego conectar campaña/guardado con semilla y versión del generador,
accesos desbloqueables y ambientación específica de los demás distritos.
El arroyo/corredor de ribera del diseño visual requiere terreno y geometría
adicional; todavía no está construido en la escena.
