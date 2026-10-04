# Decisiones 2026-10-04: expansión de distritos (delegadas)

El usuario (2026-10-04): *"las decisiones de cómo se haga quiero que las decidas vos según tu entendimiento
del juego, todo hay que dejarlo documentado igual"*. Las tomó la conversación principal. El mapa continuo lo
decidió el usuario (`2026-10-04-mapa-continuo.md`). Si una rutina encuentra una razón fuerte para cambiar
alguna, la cambia con el mismo procedimiento ("Decisiones futuras", más abajo) y deja escrito por qué.

| # | Tarea | Decisión | Por qué |
|---|---|---|---|
| 1 | D-0102 | **El modo Empresa es el juego principal** (primer botón del menú, con slots de guardado). Entrega y Endless quedan como **"Partida rápida"** sin cambios de comportamiento. | La empresa es la promesa nueva. Las partidas rápidas sirven para jugar 10 minutos y mantienen vivos los tests y la demo actual. |
| 2 | D-0103 | **Carrito = carrito eléctrico tipo golf** (2-4 asientos, caja abierta, batería). La zorra de mano es **herramienta del galpón** (mover palets), no vehículo de reparto. | El golf da manejo compartido y caos coop en Islas y Suburbio. La zorra ya tiene su lugar en el galpón. |
| 3 | D-0105 | **Reloj que corre de 08:00 a 20:00; 1 h de juego = 90 s reales** (día de 18 min). A las 20:00 no se corta una salida: el cierre espera que vuelva. Valor en `company_tuning.gd`. | Un día cabe en una sesión corta. Un reloj genera urgencia sin cronómetros por caja. |
| 4 | D-0106 | **Si nadie queda en el galpón y no hay empleados, el galpón se congela** (proveedores y pedidos esperan, el reloj del galpón no avanza). Con empleados, el galpón sigue y ellos trabajan. | En F1, solo o en dupla, castigar al que sale a entregar es injusto. Desde F2 los empleados le dan sentido a "dejar el galpón andando". |
| 5 | D-0113 | **Recortes**: los aplica quien haga D-0112, con un límite. **Nunca se recorta algo que el usuario nombró**: distritos (islas, montaña, nieve, volcán), bici, carrito, lancha, avioneta, armado de paquetes, camiones de mercadería, empleados, automatización, desbloqueos por hitos, modelos nuevos. Se puede recortar o posponer lo demás (rival, prestigio, mercado negro, kayak, helicóptero…). | Cuidar el alcance sin tocar lo que el usuario pidió. |
| 6 | D-0505 | **Sin combustible ni energía como costo.** El costo operativo es el **mantenimiento** (D-0527). La batería del carrito es una mecánica de autonomía, no un costo. | Cargar nafta no es una decisión interesante. El mantenimiento sí lo es (reparar o arriesgar). |
| 7 | D-0704 | **Armado en grilla** de celdas de 0,2 m: el producto se encastra en un bloque de celdas. El relleno ocupa celdas libres. | Determinista, barato en red, jugable con mando, y la calidad se puede calcular y testear. |
| 8 | D-1928 | **Sin voces grabadas ni ElevenLabs**: el jefe y los NPC "hablan" con murmullos de `SynthAudio` y burbujas de texto. | Sin riesgo de licencia, sin costo por línea, coherente con el audio por código y traducible. |
| 9 | D-2036 | **Sin telemetría remota.** Solo el log local que ya existe (`run_log`, `RunTelemetry`). | Sin aviso de privacidad, sin servidor que mantener. Los bots y benchmarks miden lo que hace falta. |
| 10 | D-2048 | **El playtesting sigue al final** (memoria del usuario): no se hace ahora. | Sin cambios. |

Con esto, las tareas D-0102, D-0103, D-0105, D-0106, D-0505, D-0704, D-1928 y D-2036 dejan de ser ⏸.
D-0113 pasa a ser parte de D-0112.

## Decisiones futuras de la expansión

Para todo lo de `docs/expansion-distritos/` que sea **cómo se hace** (diseño de una mecánica, números,
alcance de una tarea, elegir entre opciones), quien trabaja la tarea **decide y documenta**, sin issue ni
espera:

1. Escribe `docs/decisiones/AAAA-MM-DD-<tema>.md` (o agrega una fila a la tabla del día) con la decisión,
   las opciones descartadas y el porqué en una línea.
2. Si la decisión cambia [supuestos.md](../expansion-distritos/detalle/supuestos.md) o una tarea, la
   actualiza en el mismo PR.
3. Límite: no recortar lo que el usuario nombró (fila 5), no gastar plata real, no cambiar precio, fecha ni
   página de Steam. Eso sigue como ⏸ con issue `decide-usuario` (regla 12 de las rutinas).
