# Referencias de armado y logística: qué tomamos de cinco juegos (D-0108)

> Qué hacen bien *Overcooked* 1/2, *Unpacking* y los juegos de encastre de cajas, *Mini Motorways*, *shapez* y
> *Totally Reliable Delivery Service* (TRDS) en pedidos, armado, cintas, cuellos de botella y física cómica.
> Para crecer, *Schedule I*, que ya está analizado en [referencia-schedule-1.md](referencia-schedule-1.md)
> (D-0107). Alimenta los grupos 07, 08, 09, 10, 11 y 19. Fuentes al final, citadas como [n].
> Investigado el 2026-10-19.
>
> **Cómo se investigó:** con el buscador web. Ese día la herramienta para abrir páginas no resolvía DNS
> (`getaddrinfo ENOTFOUND`), así que no se abrió cada página: los datos salen de los resúmenes que devolvió el
> buscador sobre entrevistas, reseñas, guías y foros. Las guías de fans (puntaje de *Overcooked*) y los
> resúmenes automáticos de reseñas (Vaporlens) son señales, no hechos: cuando algo depende solo de ellos va
> **sin confirmar**. Antes de citar un número en marketing, abrir el link.

**Veredicto:** CONSTRUIR CON CAMBIOS. Tomamos la hoja de pedido como objeto (*Overcooked*), el encastre con
encaje y sonido (*Unpacking*), el aviso en el mundo antes del fallo (*Mini Motorways*) y las cintas simples y a la
vista (*shapez*). La física cómica (TRDS) va solo en el fallo. No tomamos el combo, las reglas ocultas, la
lógica programable ni el control del personaje con ragdoll.

## 1. Overcooked 1 y 2: pedidos y estaciones

**Qué hace bien**

- **El pedido es una ficha con reloj.** Los pedidos aparecen arriba de la pantalla, con los íconos de lo que
  llevan y una barra de tiempo. La propina es mayor cuanto más tiempo queda [8][9].
- **Racha.** Servir en el orden de llegada sube un multiplicador; un pedido vencido lo corta. Las guías no
  coinciden en la penalidad exacta: **sin confirmar** [9].
- **Estaciones de un solo verbo** (cortar, cocinar, lavar, servir). Los creadores dicen que los controles
  simples son lo que les permitió hacer cocinas complejas [6].
- **Recursos en circuito.** Hay unos pocos platos, que vuelven sucios; sin plato limpio no se sirve [8].
- **Peligro por descuido.** Lo que se deja en el fuego se incendia, el fuego se esparce y hay un extintor a mano [8].
- **Un elemento por nivel**: separar jugadores, un embudo. El primer prototipo permitía demasiados errores
  chicos y trabajaron para que no frustraran [4].
- **Todos pueden hacer todo**: los roles se reparten hablando [5]. Eligieron una cocina porque ahí la
  comunicación importa, y buscaron que nadie pudiera cargar solo al equipo [6].
- Lo hicieron **dos fundadores** que venían de Frontier [1][2]. Es el patrón de `docs/investigacion-mercado.md`.

**Qué critica la gente:** el lag online arruina controles que piden precisión. Tirar ingredientes solo sirve
si todos conocen el nivel. Sin voz cuesta coordinar. Lavar platos jugando solo es tedioso. Alinear objetos con
precisión hace perder tiempo [10]. Los empujones generan rencor de verdad [7]: es fricción, pero también es el clip.

**Lectura:** el antagonista de *Overcooked* es la cocina. Nuestro galpón lo arma el jugador y lo va a optimizar.
El antagonista lo ponen los eventos del día y las trampas activas, no el plano.

**Lo que copiamos:** la hoja de pedido como objeto con íconos y barra de tiempo, que viaja pegada a la caja, y
estaciones de un solo verbo.
**Va en:** D-0805, D-0808, D-0714, D-0804.

## 2. Unpacking y los juegos de encastre: el armado

**Qué hace bien**

- **Encastre que se siente.** En *Unpacking* se rota y se encaja cada objeto. El diseñador le atribuye a la
  foley (el sonido de cada objeto) la sensación física del encaje [12]. La crítica lo compara con *Tetris* y con
  el maletín de *Resident Evil 4* [13].
- ***Resident Evil 4*** usa una grilla de 6×10 donde cada objeto ocupa celdas fijas y se rota. La tensión sale
  de qué dejás afuera [16].
- **Diseño sustractivo.** Wren Brier (GDC 2023) cuenta que sacaron todo lo que no servía al núcleo, ya en el
  prototipo. No hay puntaje ni estado de fallo; las elecciones se guían por consecuencias [11].
- **Vende.** Pasó el millón de copias en su primer año [15].
- ***Box Flow*** (página de Steam): se escanean productos, se elige caja S a XXL, se encastra en una grilla 3D,
  se cierra, se sella, se etiqueta y se despacha. Las mejoras automatizan cada paso, hasta el armado entero. Es
  para un jugador. La página decía 11-09-2026 y otra ficha dice "por confirmar": **sin confirmar** que haya
  salido [17].
- ***Outpacked*** suma restricciones de mezcla, por ejemplo lo caliente lejos de lo que se derrite [18].

**Qué critica la gente (*Unpacking*):** lo mal ubicado se marca en rojo **recién al vaciar las cajas**. Hay
reglas rígidas que no se ven: una planta junto a la ventana puede no "valer" y el nivel no termina. Cuesta
reconocer los últimos objetos y la gente pide pistas. El resaltado se puede apagar y hay una opción para colocar
en cualquier lado [14].

**Lectura:** *Box Flow* es nuestro armado casi literal, en solitario. Lo nuestro no es armar cajas: es que la
caja que armaste es la trampa que otro sufre en el asiento.

**Lo que copiamos:** encastre en grilla con encaje y sonido, y las reglas a la vista mientras se arma, no al
cerrar.
**Va en:** D-0703, D-0741, D-0744, D-0727, D-0726.

## 3. Mini Motorways: el cuello de botella legible

**Qué hace bien**

- **El fallo avisa antes.** Los destinos acumulan "pines" (viajes pendientes). Si se juntan demasiados, aparece
  un reloj circular sobre el edificio: si llega a cero, la partida termina; si los pines bajan, el reloj se
  vacía solo [19].
- **Recurso escaso.** Los tramos de calle son limitados. Cada semana se elige 1 de 2 mejoras: las dos traen
  calles y una trae siempre una herramienta (rotonda, autopista, semáforo) [19].
- **Cuesta hacerlo divertido.** Dedicaron casi un año de prototipo y balance para que manejar tránsito fuera
  divertido y accesible [20]. Cambiaron de dibujar líneas a un modo construcción con grilla [21].
- **El fallo se entiende**: autos que se traban detrás de otros y calles que no dan abasto [22].

**Qué critica la gente:** la aparición aleatoria de edificios se siente "rencorosa" y a veces deja la partida
sin salida. Además la mejora que ofrecen no siempre es la que hace falta [23][22].

**Lo que copiamos:** el atraso se avisa en el mundo con un reloj sobre la estación, antes de costar, y se
recupera si alguien lo atiende.
**Va en:** D-1907, D-1044, D-1112, D-0807.

## 4. shapez: cintas a la vista

**Qué hace bien**

- **Fábrica de figuras.** Se extraen, se cortan, se rotan, se apilan y se pintan figuras. Sin enemigos, sin
  temporizadores y sin límite de recursos [24].
- **El flujo se ve en el piso.** Un cuello de botella es una cinta llena o una vacía. La profundidad sale de
  balancear: un proceso que descarta un cuarto obliga a repartir de nuevo [28].
- ***shapez 2*** salió en Acceso anticipado con 98 % de unas 5 000 reseñas; lo hace un estudio de 7 personas [25].

**Qué critica la gente:** se vuelve repetitivo manejar cintas, es lento (velocidad de cinta y progresión) y el
rendimiento cae con fábricas grandes [26]. Sobre el co-op, una sugerencia de la comunidad dice que en papel
podría andar, pero que el juego "no da incentivos para que los jugadores interactúen" [27].

**Lectura:** la automatización tiende a ser de un solo cerebro. Si el galpón se vuelve un *shapez*, uno diseña y
siete miran. La cinta tiene que fallar de forma que llame a otro jugador.

**Lo que copiamos:** cintas como piezas simples en grilla, con el flujo y el cuello de botella a la vista sin
abrir un menú.
**Va en:** D-1101, D-1107, D-1108, D-0226, D-0935.

## 5. Totally Reliable Delivery Service: física y humor

**Qué hace bien**

- **Repartidores con ragdoll**, gadgets (cama elástica, jetpack, gancho), vehículos y co-op de 1 a 4 local y
  online. La plata abre zonas, vehículos y cosméticos [29].
- **Las misiones "frágil" dan medalla según el daño**: oro con daño bajo, plata y bronce más abajo [31]. Es un
  fallo graduado y legible.
- **Alcance.** Fue gratis en Epic en abril de 2020: 2 M de copias reclamadas en días. Según tinyBuild, 14 M de
  descargas en 2021 [30].
- **Clip.** En 2019 ya había videos "Funny Moments" de VanossGaming y Moo, antes del lanzamiento [35].

**Qué critica la gente:** controles torpes. El personaje agarra los paquetes "por detrás de la espalda" [33] y
el movimiento queda en un punto medio "donde nada anda bien" [34]. Los objetivos no varían y muchas veces "no
hace falta cooperar" [33][32]. Al principio la plata no tenía en qué gastarse, y los avatares quedan trabados
bajo máquinas [32]. La red es su crítica número uno (`docs/marketing/competidores-manejo.md`).

**Lo que copiamos:** la física cómica en el fallo (la caja que se cae, la bici que vuelca), nunca en el control
básico; y el daño convertido en medalla legible.
**Va en:** D-1212, D-1137, D-0816, D-0817.

## 6. Schedule I: solo crecimiento

El análisis completo es [referencia-schedule-1.md](referencia-schedule-1.md) [36]. Lo que importa acá: el bucle
producir → vender → reinvertir, y que **cada compra cambia lo que podés hacer** (una propiedad nueva trae más
empleados y bahías). La automatización baja el estrés al final. La voz en contra: "no tiene metas".

**Lo que copiamos:** cada compra abre una capacidad nueva que se ve en el galpón (etapa, empleado, máquina), con
el próximo hito siempre a la vista.
**Va en:** D-0905, D-0542, D-0410.

## 7. Tomamos / Adaptamos / No tomamos

| Qué | Decisión | Cómo en Take My Package | Tarea D- | Fuente |
|---|---|---|---|---|
| Ficha de pedido con íconos y barra de tiempo | Tomamos | Hoja con íconos de producto y requisito, texto además del ícono y barra de la ventana | D-0804, D-0843, D-0846 | [8] |
| Pedido en pantalla | Adaptamos | Impresora que escupe la hoja; la hoja se pega a la caja y viaja con ella | D-0805, D-0808, D-0714 | [8] |
| Propina por tiempo restante | Adaptamos | Pago completo dentro de la ventana y penalidad por tardanza; sin propina por segundo | D-0807, D-0815 | [9] |
| Racha por servir en orden | No tomamos | Castiga al que juega solo y sale con pocas cajas. El orden lo marca el jugador | D-0838 | [9] |
| Estaciones de un verbo y controles simples | Tomamos | Mesa: agarrar, rotar, soltar y usar herramienta (cinta, sello, etiqueta), con mando | D-0701, D-0749 | [6] |
| Platos limitados que vuelven sucios | Adaptamos | Cajas e insumos que se gastan y se reponen: tarea del que se queda | D-0718 | [8] |
| Fuego por descuido y extintor | Adaptamos | Trampa activa en el galpón (explosiva en la cinta) con alarma y respuesta física | D-1138, D-0933 | [8] |
| Nivel armado alrededor de un elemento | Adaptamos | El galpón lo arma el jugador: el elemento lo ponen los eventos del día | D-0123 | [4] |
| Tirar ingredientes | No tomamos (F1) | Tirar productos contradice "no se te caiga" y cuesta en red. Si se propone, que pase por la crítica de alcance | D-0112 | [10] |
| Encastre en grilla con rotación | Tomamos (decidido) | Celdas de 0,2 m y rotación de a 90° | D-0703, D-0704 | [12][16] |
| Sonido de encaje (foley) | Tomamos | Sonido por celda que encastra, cinta y sello | D-0741 | [12] |
| Error marcado en rojo recién al final | Adaptamos (lo corregimos) | Hueco libre y reglas de mezcla visibles mientras se arma; motivo al cerrar | D-0744, D-0712 | [14] |
| Reglas de colocación que no se ven | No tomamos | Orientación e incompatibles se marcan en la grilla antes de soltar | D-0727, D-0726 | [14] |
| Opción para apagar el resaltado o colocar donde sea | Adaptamos | "Armado asistido" en dificultad: relleno automático, como en la partida rápida | D-1919, D-0127 | [14] |
| Sin puntaje ni fallo | Adaptamos | Hay `Q`, pero la caja mala igual sale: la consecuencia es la trampa en la ruta (bloquea solo explosivo + frágil) | D-0710 | [11] |
| Caja S-XXL y mejoras que automatizan pasos | Tomamos la forma, no el gancho | S-XL ya están; las máquinas toman pasos en F2 | D-0702, D-1104, D-1105 | [17] |
| Restricciones de mezcla | Tomamos | Productos que no se juntan | D-0726 | [18] |
| Reloj sobre el edificio saturado, recuperable | Tomamos | Anillo sobre la estación con atraso, que se vacía si se atiende | D-1907, D-1044, D-1112 | [19] |
| Pocos tramos de calle | Adaptamos | Límite de objetos por etapa como decisión de diseño, no solo de rendimiento | D-0915 | [19] |
| Elegir 1 de 2 mejoras por semana | Adaptamos | Cierre con 2-3 compras destacadas, sin elección forzada | D-0542, D-0508 | [19] |
| Aparición que deja la partida sin salida | No tomamos | Pedidos por semilla, siempre cumplibles con el stock y los vehículos que hay | D-0801, D-0811, D-0844 | [23] |
| Cintas simples con el flujo a la vista | Tomamos | Recta, curva, subida; clasificador y rampas por zona | D-1101, D-1107, D-1108 | [24][28] |
| Balanceadores, separadores, lógica | No tomamos (postergar) | Fuera hasta después del lanzamiento; candidatos a recorte | D-1127, D-1128, D-0112 | [26][28] |
| Lento y pesado con fábricas grandes | Adaptamos | Grafo + MultiMesh con presupuesto medido; mejoras de velocidad | D-1102, D-1120, D-1130 | [26] |
| Co-op sin motivo para interactuar | Adaptamos (lo evitamos) | Atascos que destraba otro, cajas que se caen, trampas vivas en la cinta | D-1113, D-1137, D-1138 | [27] |
| Ragdoll como humor | Adaptamos | Solo en el fallo (caída de bici, caja que cae); el control del personaje sigue firme | D-1212, D-1137 | [29][34] |
| Medalla por daño en entregas frágiles | Tomamos | Integridad → 1-5 estrellas y reacción en la puerta | D-0816, D-0817 | [31] |
| Objetivos que no varían | Adaptamos | Requisitos de pedido y zonas que cambian cómo se cuida la caja | D-0806, D-0828 | [33] |
| Agarrar torpe | Adaptamos (lo prevenimos) | Interacción con objetos colocados y con la cinta igual que con los fijos, con test | D-0914, D-1111 | [33][34] |
| Crecer con metas visibles | Tomamos | Etapas del galpón y tablero de hitos | D-0905, D-0410 | [36] |

## 8. Riesgos para un equipo de 2: qué NO hacer

| Tentación | Por qué no | Qué hacemos | Tarea |
|---|---|---|---|
| Convertir el galpón en un *shapez* (lógica, balanceadores, separadores, planos) | Es un juego de un solo cerebro [27]; choca con "no es un tycoon de planillas" (`vision.md` §9); semanas de UI, guardado y red | Cintas rectas, curvas y clasificador fijo. El resto, a la crítica de alcance | D-1127, D-1128, D-0921, D-0112 |
| Física real para todo lo que va en la cinta | Rendimiento y red [26]; 300 ítems por tick | Grafo + MultiMesh; física solo cuando algo se cae | D-0226, D-1102, D-1115 |
| Control del personaje con ragdoll | Es la queja número uno de TRDS [33][34] | Control firme; ragdoll solo en caídas | D-1212 |
| Armado 3D libre (cualquier ángulo, física dentro de la caja) | Con mando no se puede y sube el tiempo por caja | Grilla de 0,2 m, rotación de a 90°, medir 20-40 s por caja | D-0704, D-0745, D-0749 |
| Racha o combo de *Overcooked* | Castiga al solitario y suma UI y balance | Ventana de 4 h y prioridad que marca el jugador | D-0807, D-0838 |
| Reglas que se descubren al cerrar | Fallo que parece arbitrario [14] | Toda regla visible en la grilla, con motivo al cerrar | D-0744, D-0726, D-0727 |
| Dos jugadores en la misma caja en red ya en el corte | Lag y precisión [10]; está en xhigh | Después del corte F1, con su test de red | D-0715 |
| Vender "armar cajas" como gancho | *Box Flow* ya lo hace en solitario [17] | La página vende el co-op y la trampa que sale del armado | D-0139, D-2032 |
| Pedidos imposibles por azar | Frustración de *Mini Motorways* [23] | Generador por semilla con stock y vehículos verificados; sim de 1-8 jugadores | D-0811, D-0844 |

## 9. Versión mínima que probaríamos primero (F1)

Sobre el armado que ya existe (D-0701 a D-0712):

1. La impresora escupe la hoja (D-0805). Se agarra y se pega en la caja (D-0808), con barra de ventana (D-0807).
2. La grilla marca el hueco libre y las reglas de mezcla mientras se arma; al cerrar dice el motivo (D-0744).
3. Un sonido de encaje por celda y uno de cinta (D-0741).

Estimado: 4-6 días entre los tres puntos, sin red nueva más allá de replicar la hoja como dato del pedido
(D-0813). Sin cintas, sin combo, sin armado compartido. Si el bot del corte (D-0745) mide 20-40 s por caja, lo
siguiente es el anillo de atraso en las estaciones (D-1907).

## 10. Para revisar al final

Las elecciones de este documento, con su alternativa, están en [revisar/D-0108.md](../revisar/D-0108.md).

## Fuentes

Consultadas el 2026-10-19 a través del buscador. Los hilos de Steam y las guías son de jugadores, no
declaraciones oficiales. Cuando una cita agrupa varios links, el dato puede estar en cualquiera de ellos.

1. Wikipedia, *Overcooked*: https://en.wikipedia.org/wiki/Overcooked
2. MCV/Develop, Ghost Town Games no quiere ser un estudio grande: https://www.mcvuk.com/business-news/ghost-town-games-weve-no-interest-in-being-a-big-studio/
3. Push Square, entrevista a Ghost Town Games (*Overcooked 2*): https://pushsquare.com/news/2018/08/interview_chewing_the_fat_with_overcooked_2_developer_ghost_town_games
4. Game Developer, *Road to the IGF: Overcooked*: https://gamedeveloper.com/design/road-to-the-igf-ghost-town-games-i-overcooked-i-
5. Game Maker's Toolkit, "How Overcooked's Kitchens Force You to Communicate" (transcripción): https://amara.org/en-gb/videos/1kyGmzeQjsv6
6. Play UK (PressReader), aniversario de *Overcooked* con Phil Duncan: https://www.pressreader.com/australia/play-uk-1/20210921/284485756649452
7. Unwinnable, "Juggling the Chaos in Overcooked": https://unwinnable.com/2017/10/03/juggling-the-chaos-in-overcooked-and-at-home/
8. TrueAchievements, consejos generales de *Overcooked* (platos, ventanilla, fuego): https://www.trueachievements.com/game/Overcooked/walkthrough/2
9. ludo.guide, puntaje y estrellas de *Overcooked 2* (guía de fans): https://www.ludo.guide/guide/overcooked-2/tips-secrets/advanced-efficiency-techniques/scoring-star-system
10. Reseñas de *Overcooked 2*: https://www.thesixthaxis.com/2018/08/07/overcooked-2-review/ · https://www.godisageek.com/reviews/overcooked-2-review/
11. Charla de Wren Brier en la GDC 2023 (diseño sustractivo, sin fallo ni puntaje): https://gonintendo.com/comments/9269 · https://www.gamedeveloper.com/gdc2022/gdc-2022-unpacking-a-narrative-through-1-000-household-items
12. Limited Run Games, entrevista a Tim Dawson: https://limitedrungames.com/blogs/news/unpacking-unpacking-with-designer-tim-dawson
13. Comparaciones con *Tetris* y *RE4*: https://www.videogamer.com/?p=180496 · https://blacknerdproblems.com/?p=95717
14. Quejas sobre el resaltado en rojo y las reglas rígidas: https://pcinvasion.com/?p=297065 · https://checkpointgaming.net/reviews/2021/11/unpacking-review-home-sweet-home/ · https://vaporlens.app/app/1135690/unpacking.md
15. Nintendo Life, *Unpacking* pasa el millón: https://nintendolife.com/news/2022/11/cosy-indie-darling-unpacking-has-sold-over-1-million-copies-since-launch
16. Bloody Disgusting, el inventario de *Resident Evil 4*: https://bloody-disgusting.com/video-games/3658221/resident-evil-4-perfected-inventory-system-resident-evil-25/
17. *Box Flow* (fecha **sin confirmar**): https://store.steampowered.com/app/4909100 · https://gg.deals/ca/game/box-flow/
18. *Outpacked*: https://gg.deals/gb/game/outpacked/
19. Wikipedia, *Mini Motorways* (pines, reloj, mejoras semanales): https://en.wikipedia.org/wiki/Mini_Motorways
20. Gfinity, cómo se hizo *Mini Motorways*: https://www.gfinityesports.com/features/the-making-of-mini-motorways-steam/
21. Superjump, de idea de game jam a clásico: https://www.superjumpmagazine.com/from-game-jam-idea-to-mobile-classic/
22. Reseñas de *Mini Motorways*: https://traxion.gg/mini-motorways-review · https://scientificgamer.com/thoughts-mini-motorways/
23. Steam, foro: azar que traba la partida: https://steamcommunity.com/app/1127500/discussions/0/4410795316954451666 · https://steamcommunity.com/app/1127500/discussions/0/7195113615743664715 · https://steamcommunity.com/app/1127500/discussions/0/3044982312809098748
24. Descripción de *shapez*: https://thinkygames.com/games/shapez · https://gg.deals/gb/game/shapezio/
25. *shapez 2*, Steam y lanzamiento en Acceso anticipado: https://store.steampowered.com/app/2162800/shapez_2/ · https://galaxus.be/en/page/shapez-2-a-great-automation-game-but-not-for-me-34470
26. Vaporlens, resumen de reseñas (automático): https://vaporlens.app/app/1318690/shapez · https://vaporlens.app/app/2162800/shapez_2
27. Sugerencias de *shapez 2*, co-op: https://shapez-2.nolt.io/1864
28. Steam, foro de *shapez 2*: balancear cintas: https://steamcommunity.com/app/2162800/discussions/0/6929437446237974171
29. Steam, página de TRDS: https://store.steampowered.com/app/1011670/Totally_Reliable_Delivery_Service/
30. Gratis en Epic y 14 M de descargas (según tinyBuild): https://www.gamerevolution.com/news/641620-totally-reliable-delivery-service-free-epic-games-store-xbox-game-pass · https://www.techradar.com/news/epic-game-stores-new-exclusive-game-is-free-for-pc-gamers-but-its-dollar15-on-consoles
31. TrueAchievements, misiones frágiles y medallas de TRDS: https://www.trueachievements.com/game/Totally-Reliable-Delivery-Service/walkthrough/3
32. Reseñas de TRDS: https://wegotthiscovered.com/?p=892412 · https://www.gamepitt.co.uk/?p=24849
33. Reseñas de TRDS (controles, objetivos, cooperar): https://www.nintendoworldreport.com/review/53513 · https://www.nintendolife.com/reviews/switch-eshop/totally_reliable_delivery_service · https://couchcoopfavorites.com/totally-reliable-delivery-service
34. Steam, foro de la beta de TRDS: controles: https://steamcommunity.com/app/1106850/discussions/0/1640915206463486838
35. TheTVDB, videos "Funny Moments" de 2019: https://thetvdb.com/series/vanossgaming/episodes/7258612 · https://www.thetvdb.com/series/moo/episodes/7255224
36. [referencia-schedule-1.md](referencia-schedule-1.md) (D-0107), §4, §5 y sus fuentes [20]-[33].
