# Narrativa de la empresa: quién manda, por qué empezamos, cómo hablan los mensajes (D-0121)

> Última actualización: 2026-10-22
> Cómo suena el modo Empresa. **No reemplaza** a [`docs/narrativa.md`](../../narrativa.md) (S-601): la
> extiende. Si algo de acá lo contradice, gana `docs/narrativa.md`. Sin personajes nuevos, sin caras,
> sin voces grabadas (`docs/decisiones/2026-10-04-expansion-decisiones-delegadas.md`, fila 8): todo es
> texto con clave de traducción. Decisión: [`2026-10-22-narrativa-empresa`](../../decisiones/2026-10-22-narrativa-empresa.md).

## 1. Quién manda en el modo Empresa

**Sigue mandando la Jefa, Marta Bermúdez**: sin cara, solo por la radio del depósito y por notas en la
pizarra y en las cajas. El **Jefe del depósito** sigue siendo el encargado visible (chaleco, mate) y no
habla por radio.

Lo que cambia es el vínculo: antes la tripulación hacía el trabajo sucio de la Jefa con su camión; ahora
**la Jefa les abre una sucursal: un galpón propio** y les dice "esto lo llevan ustedes". Sigue en otra
cosa, sigue minimizando los desastres, pero ahora también delega plata y llaves.

Por qué no un jefe nuevo ni la tripulación sola: (a) no contradice el canon y no hay que reescribir
nada ya hecho (S-603, el Jefe del diario); (b) una Jefa que nunca se ve no necesita modelo ni animación
(arte es el cuello de botella); (c) "la Jefa manda, el Jefe carga con las consecuencias" funciona igual
con más galpones; (d) evita el tema "mi jefe el capo", que remitiría a lo criminal (§6).

| Quién | Habla por | En el modo Empresa |
|---|---|---|
| La Jefa | Radio y notas | Apertura, hitos, pedidos grandes, cierre del día. Seca, práctica, minimiza. Pocas frases por día |
| El Jefe del depósito | Burbuja o cartel, nunca radio | Avisos del galpón: falta stock, camión del proveedor, llegó la hora. Cansado, simpático |
| Clientes | Notas en pedidos y reclamos | Su manía, en voz propia (ver §3) |
| Los empleados NPC | Murmullos (`SynthAudio`) y ícono | Sin líneas de diálogo |

## 2. Por qué empezamos

**Premisa corta:** la Jefa heredó un galpón vacío en el Parque Industrial (de una tía; ella no da
detalles) y llegaron más pedidos de los que caben en un camión. Les presta el galpón con
un alquiler y una frase: *"Hasta fin de mes. Después vemos."* Siempre es "hasta fin de mes".

**Por qué crece a distritos:** porque los clientes excéntricos del pueblo tienen parientes. El del
puerto conoce a uno que vive "del otro lado del agua", la anticuaria sabe de una cabaña en la montaña y
el de los fuegos artificiales jura que el volcán "tiene buen eco". Cada distrito nuevo es *alguien más a
quien nadie le entrega*, no un enemigo ni una zona de conquista. El tono no cambia: agua (lancha),
montaña (4x4), volcán son nuevas excusas para que la caja se queje. El lema sigue siendo "entregamos
(casi) todo"; el "casi" crece con el mapa.

## 3. Tono de los mensajes

Reglas heredadas de `docs/narrativa.md`: voseo rioplatense, frases cortas, **un solo chiste por texto**,
la culpa es de la situación, nunca cruel, nada humilla al jugador, animales indignados y no lastimados.

Los **números (plata, cantidades, horas) van por parámetro `%s/%d`**, nunca pegados al chiste: el chiste
va en una frase y el dato en otra.

| Tipo | Quién habla | Largo máx. | En voz correcta | En voz incorrecta |
|---|---|---|---|---|
| Pedido entrante | El cliente (nota breve) | 80 car. + datos | "Pedido nuevo de Norma: una gallina. Trátenla bien, tiene carácter." / "Torta de tres pisos. Cuatro, si Dios quiere." | "Pedido nuevo: 1x gallina, plazo 14:00." (sin voz, aceptable solo como línea de tablero) |
| Aviso de vencimiento | El Jefe del depósito | 60 car. | "Jefe: a la torta le quedan dos horas y ninguna paciencia." / "Se acerca la hora. La torta ya está nerviosa." | "¡Pedido atrasado por su culpa!" (culpa al jugador) |
| Reclamo | El cliente de la caja; exagerado y formal | 90 car. | "Era un regalo... ERA." / "Voy a llamar a la empresa. Ah, ya estoy llamando." | "Son unos inútiles." (insulto) |
| Felicitación | Cliente; cálido, con la manía | 70 car. | "Llegó fresca. Iba a decir: llegó." / "Le habló y todo. Gracias." | "Por fin, no era tan difícil." (sarcasmo) |
| Cierre del día | La Jefa por radio o nota | 2 frases, 100 car. | "Cerramos. Los números están ahí, no los miro, pero están." / "Hoy se entregó casi todo. Es un récord del casi." | "Perdiste plata." (reto) |
| Quiebra / mal día | La Jefa; minimiza, nunca grita | 100 car. | "Mal mes. Hay peores. No me acuerdo cuáles." / "Hoy entran menos pedidos. Mañana vemos." | "Cerraste en rojo, mal manejado." (culpa) |

**Los 10 clientes sin clientes nuevos (D-0122 pospuesta):** los clientes de `docs/narrativa.md` siguen
siendo los únicos con nombre. Un pedido de un distrito toma el cliente de su producto (la manía va con el
contenido: gallina = Norma, torta = Ramiro). Cuando el pedido no tiene cliente con nombre, se usa una
**voz genérica por distrito** (una frase de respaldo con la manía del lugar, sin nombre ni historia ni
retrato):

| Distrito | Voz genérica (respaldo) |
|---|---|
| Pueblo / Parque Industrial | Vecino práctico: "Es para hoy, si se puede." |
| Agua / islas | Isleño pegado a la radio: "Si no llega por agua, llega por el cielo." |
| Montaña | Cabañero con frío: "Que no se enfríe, que ya hay bastante frío acá." |
| Volcán | Vecino tranquilo ante lo peor: "Está humeando como siempre. Normal." |

Sin memoria entre pedidos, sin cadenas ni VIP: eso es posterior al lanzamiento.

## 4. Reglas para textos nuevos

1. **Todo texto con voz va a `strings_*.csv` con clave**, nunca en el código. UI en `strings_ui.csv`, voces de
   mundo en `strings_world.csv`. Español e inglés a la vez.
2. Prefijos: `UI_` para pantallas y tableros; `WORLD_` para voces (cliente, Jefa, Jefe). Las líneas de
   respaldo por distrito: `WORLD_COMPANY_<DISTRITO>_<TIPO>_<n>`. Un chiste por clave.
3. Dato variable por `%s/%d`, nunca concatenado. La frase tiene que funcionar con cualquier número.
4. Una variante, como mínimo, por tipo y tres si se repite mucho (pedido, reclamo) para que no cansen.
5. Antes de entregar, releé la tabla Sí/No de `docs/narrativa.md`. El agente `localizador` revisa glosario
   y textos que no entran.

## 5. Qué ya existe en el código y qué queda fuera de tono

Estado a 2026-10-22. "Neutro" = es un dato de tablero, no necesita voz. "Fuera de tono" = tiene que
reescribirse cuando se haga la pasada de voz.

| Archivo | Clave | Texto actual | Estado |
|---|---|---|---|
| `scripts/gameplay/business/order_notice.gd` | `UI_ORDER_NOTICE_ONE`, `_NO_ADDRESS`, `_MANY` | "Pedido nuevo: %s — %s %d" / "%d pedidos nuevos" | Fuera de tono: aviso de pedido entrante sin cliente ni manía |
| `scripts/gameplay/business/bankruptcy.gd` | `UI_COMPANY_BANKRUPT_WARNING` | "Cerraste en rojo: hoy llegan menos pedidos (%d %%)." | Fuera de tono: culpa al jugador; debería ser la Jefa minimizando |
| `scripts/gameplay/business/day_summary.gd` y `UI_COMPANY_DAY_CUT*` | `UI_COMPANY_DAY_CUT`, `UI_COMPANY_DAY_CUT_PARTIAL` | "Día %d interrumpido a las %s: ingresos $%d, gastos $%d…" | Fuera de tono si es lo único que ve el jugador al cierre; los números quedan, hace falta una frase de la Jefa encima |
| `scripts/gameplay/business/order_board.gd` | `UI_ORDER_BOARD_LATE`, `_FAILED`, `_CANCELLED` | "Atrasado" / "Fallido" / "Cancelado" | Neutro como etiqueta de estado (no apunta a nadie); mantener |
| `scripts/gameplay/business/order_board.gd` | `UI_ORDER_BOARD_OPEN/_PACKED/_OUT/_DELIVERED/_EMPTY/_TITLE/_MORE/_ITEM` | Etiquetas de estado | Neutro |
| `scripts/gameplay/business/stock_alert.gd` | `UI_STOCK_SHORT`, `_SHORT_COMING`, `_EMPTY`, `_COVERED` | Avisos de stock | Pendiente de verificar (`TODO(verificar)`): son del Jefe del depósito, revisar que no regañen |
| `scripts/gameplay/business/delivery_note.gd` | sin clave propia | arma líneas de recibo; no tiene texto con voz | Sin texto de voz todavía: la nota de entrega puede llevar la firma de la Jefa |
| Presencia (Discord/Steam) | `UI_COMPANY_PRESENCE`, `_UNNAMED` | "Empresa %s — día %d" | Neutro |
| Modo Entrega actual | `WORLD_REACTION_*`, `WORLD_COMPLAINT_*` | Reclamos con los 10 clientes | Canon; se reutilizan tal cual para los reclamos del modo Empresa |

## 6. Qué NO

- **Nada criminal ni de narcomenudeo.** Ni "mercadería sucia", ni capos, ni sobornos, ni mercado negro, ni
  policía que persigue. El referente es [`referencia-schedule-1.md`](referencia-schedule-1.md), y la
  narrativa no remite a eso: acá el "negocio" es repartir tortas y gallinas. Si un texto da risa
  por parecerse a lo ilegal, se descarta. Los productos prohibidos tampoco se insinúan.
- **Nadie humilla al jugador.** Ni la Jefa ni el Jefe ni los clientes; la culpa es del bache, de la gallina.
- **Ningún animal lastimado.** Salen indignados.
- **Sin personajes nuevos con nombre**, sin rival NPC (D-0125 recortada) ni clientes con historia (D-0122
  pospuesta). Si aparece una camioneta rival, queda de decorado varado en la banquina, como hoy.
- **Sin voz grabada**: solo texto y murmullos.
