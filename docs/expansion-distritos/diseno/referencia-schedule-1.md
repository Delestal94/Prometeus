# Referencia: *Schedule I*, qué tomamos para el galpón (D-0107)

> Análisis de *Schedule I* (TVGS, 2025, Steam) como referencia para empleados, estaciones y crecimiento del
> galpón. Alimenta los grupos 09, 10 y 11 y los diseños pendientes D-0131 (portapapeles) y D-0126 (modo solo).
> Fuentes al final, citadas como [n]. Investigado el 2026-10-12.
>
> **Cómo se investigó:** con el buscador web. Ese día la herramienta para abrir páginas no resolvía DNS, así
> que no se abrió cada página: los datos salen de los resúmenes que devolvió el buscador sobre guías, foros y
> prensa. Schedule I está en Acceso anticipado y cambia con cada parche, y varias guías se contradicen. Cuando
> pasa, lo marcamos **sin confirmar**. Antes de citar un número en marketing, abrir el link.
>
> **Tomamos la gestión, no el tema.** Schedule I es un simulador de narcotráfico. De eso no entra nada a Take My
> Package: ni drogas, ni policía, ni carteles, ni armas. Lo que estudiamos es cómo se contrata, se asigna, se
> encadenan estaciones y crece el negocio.

**Veredicto:** CONSTRUIR CON CAMBIOS. Tomamos la forma de crecer (contratar, asignar en el mundo, automatizar,
ampliar). No tomamos el micromanejo que la comunidad le critica: rutas a mano, pago a mano, IA frágil.

## 1. Qué es, en cinco líneas

- Simulador en primera persona: arrancás sin nada y armás un negocio que produce, vende y se expande comprando
  propiedades y contratando empleados [2].
- La tienda promete *"comprar propiedades y contratar empleados para ampliar la escala"*, *"trabajar con
  proveedores para armar una cadena de producción y distribución totalmente automatizada"* y *"contratar
  dealers que distribuyan por vos"* [2].
- Acceso anticipado desde el 25 de marzo de 2025 [3][4]. Co-op de hasta **4** jugadores, con invitación por
  amigos de Steam [3]. Plan de unos 2 años de Acceso anticipado, con mapa más grande y más procesos de
  producción [1].
- Pico de 116 408 jugadores simultáneos el primer día y reseñas "Extremadamente positivas" [4]; 98 % de reseñas
  positivas [33]. Ventas de unos 8 M, que reporta PC Gamer [5]; GameGeeker da la misma cifra sin respaldo
  oficial [40].
- Lo hizo una sola persona; el equipo creció después del éxito [5]. Es el patrón que sigue
  `docs/investigacion-mercado.md`.

## 2. Empleados

| Aspecto | Cómo es en Schedule I | Fuente |
|---|---|---|
| Dónde se contrata | Con un NPC (Manny) en un edificio del mapa (el Warehouse), al que solo se entra de noche (18:00-06:00 de juego) | [9][41][8] |
| Tipos | Cuatro, fijos por función: limpiador (junta basura), botánico (cultiva), handler (mueve y empaqueta), químico (estaciones de mezcla y hornos) | [6][7][8] |
| Costo | Alta de 1 000 a 2 000 y sueldo diario de 100 a 300, según el tipo. Una guía da 1 500 de alta para el limpiador: **sin confirmar** | [6][7][8] |
| Cama o locker | Sin cama asignada, el empleado no trabaja. Al contratarlo aparece frente al edificio y espera a que le asignes una | [10][11] |
| Cómo se paga | Se deja la plata **a mano** en un maletín al pie de la cama. Si no alcanza, deja de trabajar y espera afuera | [7][10] |
| Del colchón al locker | El parche v0.3.6 (primero en beta pública) agregó lockers que reemplazan la cama: ocupan menos lugar y guardan el sueldo. Los empleados que ya tenían cama no se pasan al locker | [12][13] |
| Portapapeles | Se desbloquea con el primer empleado y se equipa con la tecla 9. Con él se asignan cama o locker, estaciones y rutas | [9] |
| Reasignar | Una guía temprana dice que no se podía; una posterior dice que sí, con "editar". Hoy se puede | [14] |
| Pasar a otra propiedad | Una guía: con el portapapeles, hablando con el empleado. Otra (más vieja): hay que despedirlo y recontratarlo. **Sin confirmar** cuál vale hoy | [15][16] |
| Horario | Según jugadores, todo trabajo se corta a las 04:00. Los empleados no duermen en la cama: la cama solo existe para el pago | [36] |
| Habilidad por empleado | **Sin confirmar** que dos empleados del mismo tipo rindan distinto. Nuestras stats (D-1021) son idea propia, no copia | — |

## 3. Estaciones y su encadenado

| Aspecto | Cómo es en Schedule I | Fuente |
|---|---|---|
| Asignación | Cada tipo trabaja en sus estaciones (el handler, en la de empaquetado). Se elige empleado → "estaciones asignadas" → estación | [9][17] |
| Rutas | El handler mueve cosas entre puntos: en el portapapeles se crea una ruta "Desde → Hasta" (por ejemplo, estante → empaquetado) | [17] |
| Destino de salida | Cada estación tiene un **destino** para lo que produce. Sin destino no se vacía y la cadena se traba | [17][19] |
| Encadenado | Estación → estación: cada una apunta a la siguiente y la última a un estante o al empaquetado | [18] |
| Fallas típicas | No se pueden mezclar dos tipos de envase en la misma ruta; una ruta hacia un estante vacío traba al handler; se recomienda separar estantes por tipo | [19] |

**Lectura:** en Schedule I el jugador **dibuja el flujo** con rutas y destinos porque la producción es genérica.
Nuestra cadena es fija (Dársena → Estantes → Mesa → Control → Despacho, `roles-tripulacion.md` §1): el
flujo ya está dado por las zonas del galpón y no hace falta que el jugador lo dibuje.

## 4. Cómo crece el negocio

| Aspecto | Cómo es en Schedule I | Fuente |
|---|---|---|
| Propiedades | Motel de arranque (gratis; una guía dice 75: **sin confirmar**) → Sweatshop (~800, 1 empleado, sin bahía de carga) → Bungalow (~6 000, 5 empleados, 1 bahía) → Barn (25 000, 10 empleados, 2 bahías) → Docks Warehouse (50 000, 10 empleados, 2 bahías) | [20][21][22] |
| Tope de empleados | Por propiedad. Se ve en el tablero de contratación. Un hilo dice que no hay tope y otro lo contradice | [22][23] |
| Proveedores | App de Entregas: tienda, ítems, propiedad y bahía. Recargo fijo de 200, tarda horas, y la camioneta espera en la bahía hasta que se descargue (también la puede descargar un empleado) | [24][25] |
| Zonas del mapa | Se abren por **rango de experiencia**: Northtown al arrancar, Westville en Hoodlum I, Docks en Enforcer I, Suburbia en Block Boss I, Uptown en Baron I. Las guías no coinciden en cuántos niveles tiene cada rango | [26][27] |
| Distribución | Dealers NPC: se les asignan clientes desde el celular, cobran el 20 % y atienden hasta 8 clientes. Se desbloquean abriendo clientes en zonas nuevas | [28][29] |

## 5. Qué hace adictivo el bucle

1. **Producir → vender → reinvertir → expandir.** Prensa y reseñas lo señalan como el gancho [30][31]. Steam
   resume "jugabilidad adictiva" como el principal punto a favor [33].
2. **Fácil de aprender, con lugar para optimizar.** Es el resumen de las reseñas de jugadores [31].
3. **La automatización saca estrés al final.** Primero hacés todo; después lo delegás y el juego cambia de
   ritmo [32].
4. **Cada compra cambia lo que podés hacer**: una propiedad nueva trae más empleados y más bahías de carga
   [20][22].
5. **Es divertido de mirar.** El empujón vino de streamers, no de publicidad paga
   (`docs/investigacion-mercado.md`, [5]). En nuestro caso eso pide momentos clip en el galpón, no solo en la
   ruta.

Hay una voz en contra en los foros: el bucle "no tiene metas" y los guardados se rompen [30]. La lección es que
el crecimiento necesita objetivos visibles. En nuestro caso son los hitos (D-0401, D-0410).

## 6. De qué se queja la gente

| Queja | Detalle | Fuente |
|---|---|---|
| **IA que se traba** | Empleados quietos frente a la estación. Un objeto pegado a la estación (aunque no estorbe) los clava; un pasillo de 2 celdas lo arregla | [34] |
| **Uno trabado frena todo** | "Un empleado trabado y se para todo el negocio." Arreglos de jugadores: recargar, pegarle para moverlo, resetear tareas y cama, despedir y recontratar. Y ni así es seguro | [34] |
| **Micromanejo a escala** | "Anda bien en chico y se vuelve tedioso cuando crece el volumen." Los empleados tienen alcance muy limitado: el químico no repone su propia estación | [35] |
| **Mover cosas a mano igual** | Por el tope de empleados, el jugador termina transportando ítems él mismo | [35] |
| **Asignaciones ilegibles** | Todos los estantes y mesas se llaman igual. Piden renombrarlos y resaltar el que está ligado | [35] |
| **Piden un gerente** | Asignar zonas a etapas y contratar un gerente por propiedad | [35] |
| **Desincronización en co-op** | Objetos colocados que se corren para todos menos el host; asignaciones del host que el cliente ve vacías; estantes que se vacían raro | [39] |
| **Exploits** | Ítems infinitos que salen de estantes y estaciones; duplicación de plata | [35][39] |
| **Horario** | El trabajo se corta a las 04:00; hay mods que lo estiran y sacan el requisito de cama o locker | [36][37] |
| **Topes** | Un mod popular amplía el tope de empleados | [38] |

## 7. Tomamos / Adaptamos / No tomamos

| Qué | Decisión | Cómo en Take My Package | Tarea D- | Fuente |
|---|---|---|---|---|
| Contratar con un NPC en un edificio, solo de noche | Adaptamos | Tablero de contratación **dentro del galpón**, usable durante el día (08:00-20:00), con 3 candidatos por día. No hay que viajar ni esperar la noche | D-1003, D-0413 | [9][41] |
| Tipos fijos por función (limpiador, botánico, handler, químico) | Adaptamos | 5 roles atados a nuestras estaciones (descargador, repositor, armador, controlador, despachante). El rol se cambia con el portapapeles, sin recontratar | D-1002 | [6][7] |
| Costo de alta (1 000-2 000) + sueldo diario | Adaptamos | Solo sueldo diario (60 / 90 / 130, `economia.md` §4), sin costo de alta: el novato se paga solo si cierra 1 pedido más por día | D-0515, D-1045 | [6][7][8] |
| Pago a mano en un maletín; sin plata, el empleado no trabaja | No tomamos | Descuento **automático** al cierre. Si la caja no alcanza, entra la regla de quiebra y el resumen dice a quién no se le pagó | D-1009, D-0510, D-0547 | [7][10] |
| Cama o locker obligatorio por empleado | Adaptamos | Un **locker** en el vestuario por empleado: es el cupo, visible en el mundo y colocable. Sin cama: se van a las 20:00 | D-0923, D-1017 | [10][12] |
| Pasar de cama a locker para ahorrar espacio | Tomamos (la lección) | Arrancamos directo con lockers de 1 celda. El presupuesto de objetos por etapa los cuenta | D-0923, D-0915 | [12][13] |
| Portapapeles que se equipa y aparece con el primer empleado | Adaptamos | Objeto en la mano (decidido). Está **desde el día 1** con las hojas de stock y proveedor; el hito "Primer empleado" le suma la hoja de empleados. Sin libro contable ([portapapeles.md](portapapeles.md), D-0131) | D-0131, D-0413, D-0603, D-0612 | [9] |
| Asignar por lista (empleado → estaciones asignadas) | Adaptamos | **Apuntar en el mundo**: con el portapapeles se mira al empleado y después a la estación, y queda una línea resaltada entre los dos. Sin listas de nombres | D-1004, D-0131 | [9][17] |
| Estaciones que se llaman todas igual | Adaptamos (lo corregimos) | Nombre automático con número ("Mesa 2"), resaltado de la estación ligada y vista de plantilla | D-1038, D-0131 | [35] |
| Reasignar sin despedir (al principio no se podía) | Tomamos desde el día 1 | Reasignar es la misma acción que asignar, con su test | D-1004 | [14] |
| Rutas "Desde → Hasta" y destino por estación | No tomamos (como interfaz) | Flujo **implícito**: `job_board` crea el trabajo cuando una estación lo necesita (estante bajo → reponer; caja lista → despachar). El orden lo dan las zonas del galpón | D-0224, D-1013, D-0918 | [17][18][19] |
| Encadenar estaciones (cada una apunta a la siguiente) | Adaptamos | Cadena fija de 5 pasos. El encadenado que **sí** se dibuja es el de las cintas y el clasificador, en el piso y a la vista | D-1101, D-1107, D-1108 | [18] |
| Estación sin destino que no se vacía y traba todo | Adaptamos (lo evitamos) | Una máquina llena o sin insumos muestra un aviso **en el mundo**. El atasco lo destraba un jugador con un golpe o una palanca | D-1112, D-1113, D-1114 | [19] |
| Pedir insumos por app; la camioneta espera en la bahía hasta que la descarguen; recargo de 200 | Adaptamos | Pedido desde el portapapeles; el camión llega a las 08:30 y **se va a las 3 h** (genera urgencia). No hay recargo aparte | D-0601, D-0603, D-0618 | [24][25] |
| Un empleado puede descargar al proveedor | Tomamos | Descargador con zorra; más adelante, cinta de descarga | D-1005, D-1103 | [24] |
| Propiedades con tope de empleados y bahías (1/5/10 y 0/1/2) | Adaptamos | **Etapas** de un solo galpón: cada una sube el tope de empleados y suma zona de carga | D-0905, D-1017, D-0931, D-0436 | [20][21][22] |
| Varias propiedades y transferir empleados entre ellas | No tomamos (en F2) | Un galpón. Los hubs secundarios quedan para después y son recortables | D-0937, D-0330 | [15][16] |
| Zonas que se abren por rango de experiencia | Adaptamos | Zonas por **hitos** medibles más vehículo o equipo (mapa continuo decidido). Sin barra de XP | D-0401, D-0118 | [26][27] |
| Dealers: NPC con cartera de clientes, 20 % y hasta 8 clientes | Adaptamos (Ampliación, con tope) | Repartidor NPC **simulado** solo para pedidos sin trampa fuerte en zonas ya dominadas. La entrega difícil es siempre de la tripulación | D-1027, D-1028 | [28][29] |
| Bucle producir → vender → reinvertir | Tomamos | Cierre del día con 2-3 compras deseables siempre a la vista | D-0508, D-0511, D-0542 | [30][31][33] |
| La automatización baja el estrés | Adaptamos | Automatizar libera manos para salir, pero la máquina se traba y **la trampa sigue viva en la cinta** (explosiva que salta en el galpón): momento clip | D-1113, D-1138, D-1135 | [32] |
| Empleado trabado que para todo; arreglos a mano | Adaptamos (lo prevenimos) | Validación de caminos y navmesh que se rehornea. Si no avanza en N s, suelta el trabajo. Bot de 8 empleados durante un día entero | D-0907, D-0908, D-1011, D-1046 | [34] |
| Objetos pegados a la estación traban; el pasillo de 2 celdas lo arregla | Tomamos (la regla) | El modo construcción exige una celda de acceso libre frente a cada estación (vista previa roja si no está) | D-0902, D-0907, D-0948 | [34] |
| Tedioso a escala; piden un gerente | Adaptamos | Supervisor que reasigna según el cuello de botella, más la herramienta de tiempos por estación | D-1029, D-0935 | [35] |
| Ítems infinitos y duplicación de plata | Adaptamos (con test) | Reservas en `job_board`; la plata la toca solo el host; auditoría de exploits | D-1013, D-0518, D-0550 | [35][39] |
| Desincronización host/cliente en objetos y asignaciones | Adaptamos (lo prevenimos) | Layout y asignaciones con autoridad del host, con test de red y auditoría | D-0910, D-1012, D-1049 | [39] |
| El trabajo se corta a las 04:00; no duermen | Adaptamos | Los empleados trabajan 08:00-20:00 y se van. Sin noche ni sueño | D-1015, D-0223 | [36] |
| Mods que suben topes y horario | Tomamos (la señal) | Topes y horarios como números en `company_tuning.gd`, nunca constantes sueltas | D-1017, D-0202 | [37][38] |
| Tema: drogas, policía, carteles, armas | No tomamos | Empresa de reparto. La presión viene de la ruta, el reloj y la puerta del cliente. La página de Steam no promete nada de eso | D-0101, D-0121, D-0139 | [2] |
| Recetas para descubrir mezclando | No tomamos | La profundidad está en el armado y en la trampa que resulta | D-0709, D-0710 | [2][18] |
| Co-op de hasta 4, todos haciendo lo mismo | Adaptamos | De 1 a 8 con roles asimétricos. Jugando solo, los empleados son la forma de crecer sin más gente | D-0126, D-2024 | [3] |

## 8. Puntos de crítica

1. **Las rutas a mano no le sirven a nuestra cadena.** En Schedule I existen porque la producción es genérica
   [17][18]. En la nuestra el flujo está fijo por las zonas. Una interfaz de rutas en el portapapeles más su
   guardado y su red cuesta unos 6-10 días (estimado) y es justo lo que la gente llama tedioso [35]. El
   `job_board` (D-0224) da el 80 % del valor sin interfaz nueva.
2. **El pago a mano es un fallo silencioso.** Un empleado que espera afuera porque nadie llenó el maletín
   [7][10] es un fallo que no se entiende. Pagar automáticamente al cierre y explicarlo en el resumen
   (D-0547) cuesta menos de un día y no le saca ninguna decisión interesante al jugador.
3. **Un empleado trabado no puede frenar el galpón.** Es la queja número uno [34]. La mitigación es
   barata si se hace desde el principio: celda de acceso obligatoria (D-0902), soltar el trabajo por
   tiempo (D-1011) y bot de un día entero. Agregada después, es cara.
4. **Rol muerto al revés.** Si los empleados hacen todo, la tripulación se queda sin caja en las manos y
   rompe la regla de los 2 min (`roles-tripulacion.md` §1). El tope de empleados (D-1017) y las reservas
   (D-1013) son parte del diseño, no solo del rendimiento. Que el jugador "termine moviendo cosas a mano"
   [35] en Schedule I es una queja; en nuestro juego es el pilar, siempre que se sienta como elección y no
   como un hueco de la IA.
5. **El repartidor NPC come el núcleo.** Los dealers [28] funcionan en Schedule I porque vender no es el
   corazón de ese juego. En el nuestro, la entrega con trampa **es** el juego. D-1027 y D-1028 solo para
   pedidos sin trampa fuerte, o se recortan en D-0112.
6. **El co-op multiplica el costo.** Schedule I tiene co-op de 4 y aun así se desincroniza en objetos y
   asignaciones [39]. Nosotros vamos a 8 con empleados replicados (D-1012, xhigh). Cada cosa que el
   portapapeles cambia tiene que ser una orden al host con su test de red.

## 9. Riesgos que nos llevamos si copiamos mal

| Riesgo | Cómo se ve | Mitigación | Tarea |
|---|---|---|---|
| Micromanejo | El jugador pasa más tiempo en el portapapeles que con una caja | Sin rutas a mano: flujo implícito por `job_board`; asignar es mirar y mirar | D-0224, D-1004 |
| IA trabada | Un armador quieto frente a la mesa y la cadena entera parada | Celda de acceso obligatoria, navmesh que se rehornea, soltar trabajo por tiempo, ícono "!" sobre la cabeza | D-0902, D-0908, D-1011, D-1044 |
| Empleados que dejan sin trabajo a la tripulación | Jugadores mirando cómo trabajan los NPC | Tope por etapa, reservas, regla de 2 min medida por bot | D-1017, D-1013, D-0126 |
| Paro silencioso por falta de pago | "¿Por qué no trabaja?" | Pago automático al cierre, explicado en el resumen | D-1009, D-0547 |
| Desincronización en red | El cliente ve asignaciones distintas que el host | Host autoritativo, test de red, auditoría | D-0910, D-1012, D-1049 |
| Rendimiento con muchos NPC | Caen los FPS con 20 empleados | Presupuesto medido y LOD de empleados lejanos | D-1020, D-1040 |
| Automatización que mata el caos | El galpón se vuelve una pantalla que se mira | Atascos que destraba un jugador y trampas activas en la cinta | D-1113, D-1138 |
| Tema copiado sin querer | Textos o arte que remiten a lo criminal | Narrativa y página de Steam revisadas contra este documento | D-0121, D-0139 |

## 10. Versión mínima que probaríamos primero (F2)

Un solo rol, el **repositor** (dársena → estantes), más el **armador básico**:

- Contratación desde el tablero (D-1003).
- Un locker por empleado (D-0923, como cupo).
- Asignación con el portapapeles apuntando en el mundo (D-1004).
- Sueldo automático al cierre (D-1009).
- Reservas en `job_board` (D-1013).
- Bot de un día entero con 2 empleados y 1 jugador, que mida que nadie se traba y que el jugador nunca pasa
  más de 120 s sin caja (D-1011).

Sin cintas, sin supervisor, sin repartidor NPC. Si eso anda, entran los otros 3 roles.

## 11. Para revisar al final

Las mismas cuatro elecciones están en [revisar/D-0107.md](../revisar/D-0107.md).

1. **Sin costo de alta.** Elegí solo sueldo diario porque `economia.md` ya cierra sin él. Alternativa: alta de
   2 días de sueldo, como un Schedule I más liviano (D-0515).
2. **Locker obligatorio como cupo.** Elegí que el tope se vea en el mundo, con un locker por empleado.
   Alternativa más barata: un tope abstracto por etapa (D-1017), sin vestuario hasta Ampliación (D-0923).
3. **Sin rutas a mano.** Elegí el flujo implícito. Alternativa: rutas como opción avanzada del portapapeles
   para quien quiera optimizar, más adelante, junto a la lógica programable (D-1127).
4. **Repartidor NPC acotado.** Elegí dejarlo solo para pedidos sin trampa fuerte en zonas dominadas.
   Alternativa: recortarlo del todo en D-0112 para que ninguna entrega se haga sin la tripulación
   (D-1027, D-1028).

## Fuentes

Consultadas el 2026-10-12 a través del buscador. Los hilos de Steam son reportes de jugadores, no declaraciones
oficiales; cuando se agrupan varios hilos, la cita puede estar en cualquiera de ellos.

1. Steam, página de *Schedule I*: https://store.steampowered.com/app/3164500/Schedule_I/
2. Instant Gaming, copia de la descripción de Steam: https://www.instant-gaming.com/en/18918-buy-schedule-i-pc-game-steam/
3. Prima Games, cuántos jugadores entran en el co-op: https://primagames.com/tips/how-many-players-can-join-co-op-in-schedule-1-answered
4. TweakTown, *Schedule I* número 1 en ventas de Steam: https://www.tweaktown.com/news/104215/schedule-i-is-the-1-seller-on-steam-blowing-past-ac-shadows/index.html
5. PC Gamer, TVGS pasa a ser estudio (citado en `docs/investigacion-mercado.md`): https://www.pcgamer.com/games/life-sim/schedule-1-developer-tvgs-is-an-actual-game-studio-now-with-an-office-desks-and-a-new-guy-named-rob-by-the-end-of-the-year-there-will-likely-be-4-people-working-on-schedule-1/
6. number13, todos los empleados: https://en.number13.de/schedule-1-all-employees-in-the-overview/
7. Deltia's Gaming, guía de empleados: https://deltiasgaming.com/?p=334358
8. Prima Games, cómo contratar empleados: https://primagames.com/tips/how-to-hire-employees-in-schedule-1
9. Destructoid, cómo usar el portapapeles de gestión: https://destructoid.com/how-to-use-the-management-clipboard-in-schedule-1
10. Destructoid, cómo asignar una cama a un empleado: https://www.destructoid.com/how-to-assign-a-worker-to-a-bed-in-schedule-1/
11. GIGA (alemán), contratar y asignar cama: https://www.giga.de/entertainment/schedule-1-mitarbeiter-einstellen-und-bett-zuweisen--01JQXMV45TYKMFP889DWH8YK8C
12. Destructoid, notas del parche v0.3.6 (lockers): https://www.destructoid.com/schedule-1-v0-3-6-patch-notes-lockers-slot-filters-and-more/
13. Deltia's Gaming, guía de lockers: https://deltiasgaming.com/?p=333616
14. Destructoid, cómo reasignar empleados: https://www.destructoid.com/how-to-reassign-workers-in-schedule-1/
15. Prima Games, transferir empleados a otra propiedad: https://primagames.com/tips/how-to-transfer-employees-to-other-properties-in-schedule-1
16. GamerBlurb, mover empleados: https://gamerblurb.com/articles/how-to-move-employees-in-schedule-1
17. GamesFuze, cómo usar al handler (rutas y destino): https://gamesfuze.com/guides/how-to-use-handler-in-schedule-1/
18. Deltia's Gaming, automatizar el encadenado de estaciones: https://deltiasgaming.com/?p=190748
19. Steam, foro: rutas del handler y estaciones que no se vacían: https://steamcommunity.com/app/3164500/discussions/1/599648400266262535
20. Deltia's Gaming, todas las propiedades: https://deltiasgaming.com/?p=187504
21. GamerBlurb, propiedades: https://gamerblurb.com/articles/all-properties-in-schedule-1
22. Selphie1999, empleados y topes por propiedad: https://selphie1999gaming.com/game-guides/schedule-i/schedule-1-employees-and-how-to-hire-them/
23. Steam, foro: tope de empleados: https://steamcommunity.com/app/3164500/discussions/1/599648134182787090
24. Selphie1999, guía de entregas: https://selphie1999gaming.com/game-guides/schedule-i/schedule-1-delivery-guide-how-to-order-items/
25. Destructoid, bahía de carga: https://destructoid.com/how-to-get-a-loading-dock-in-schedule-1
26. Dot Esports, rangos en orden: https://dotesports.com/indies/news/schedule-1-ranks-in-order-all-ranks-listed
27. Prima Games, qué desbloquea cada nivel: https://primagames.com/tips/what-does-each-level-unlock-in-schedule-1
28. Schedule1Wiki, plantel de dealers: https://www.schedule1wiki.org/dealers
29. Prima Games, asignar clientes a dealers: https://primagames.com/?p=309447
30. Outsider Gaming, nota sobre el juego: https://outsidergaming.com/schedule-i-game-drug-tycoon-simulator-indie/
31. Vaporlens, resumen de reseñas: https://vaporlens.app/app/3164500/schedule_i/stats
32. 3DJuegos, columna sobre el bucle: https://www.3djuegos.com/juegos/schedule-i/noticias/me-precoupa-qu-juego-que-simula-trafico-drogas-me-haya-enganchado-te-dire-cosa-tienes-que-jugar-a-schedule-i
33. Gamepressure, ficha con el resumen de reseñas de Steam: https://www.gamepressure.com/games/schedule-i/z46cc8
34. Steam, foro: empleados trabados: https://steamcommunity.com/app/3164500/discussions/1/599648400266244360 · https://steamcommunity.com/app/3164500/discussions/1/830459135855266569 · https://steamcommunity.com/app/3164500/discussions/1/599649349440390473
35. Steam, foro: feedback de empleados y micromanejo: https://steamcommunity.com/app/3164500/discussions/1/599648768444377523 · https://steamcommunity.com/app/3164500/discussions/0/599651305036763457
36. Steam, foro: el trabajo se corta a las 04:00 y los empleados no duermen: https://steamcommunity.com/app/3164500/discussions/1/599649197566827993
37. Thunderstore, mod LateShift: https://thunderstore.io/c/schedule-i/p/lasersquid/LateShiftMono/
38. Thunderstore, mod ExtendedEmployees: https://thunderstore.io/c/schedule-i/p/Leigue/ExtendedEmployees/
39. Steam, foro: desincronización en co-op: https://steamcommunity.com/app/3164500/discussions/1/599650254291206948
40. GameGeeker, ficha con ventas (**sin confirmar**): https://gamegeeker.com/games/schedule-i-3164500
41. Destructoid, contratar en el Warehouse después de las 18:00: https://www.destructoid.com/?p=1040672
