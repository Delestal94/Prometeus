# Jugabilidad de paquetes, caos y rescate — especificación propuesta

> 2026-09-27. Dirección acordada: diseñar primero e implementar después;
> impulsar velocidad mediante plazos y recompensas; priorizar la reparación
> convincente y dar una interacción cómica ante un arreglo fallido. Las reglas
> detalladas y cifras de este documento son una propuesta para revisar.

## Experiencia buscada

Cada entrega debe alternar tres momentos: preparar la carga, sobrevivir a varios
tramos rápidos y resolver las consecuencias antes de entregar. El conductor tiene
motivos claros para acelerar; los pasajeros tienen decisiones y acciones físicas
durante el trayecto. Un golpe crea trabajo para el equipo. Un error aislado no
termina la partida ni deja a un pasajero sin nada que hacer.

El juego debe permitir una entrega improvisada y graciosa: una caja encintada,
un jarrón pegado de forma cuestionable o una gallina sustituida por un juguete
pueden llegar a la puerta. El cliente y el puntaje distinguen esa entrega de una
intacta. La improvisación salva la ronda, pero nunca es un camino más fácil hacia
la máxima recompensa.

## Bucle de una entrega

1. **Depósito (15–30 s):** leer contenido, elegir quién atiende cada caja y tomar
   un kit básico. Se puede gastar dinero en más consumibles o protección.
2. **Salida segura (~100 m):** aprender la regla de la carga y ubicar el paquete
   en manos, regazo, soporte o estante. Cada opción cambia el riesgo y las tareas.
3. **Tramos de presión:** el navegador avisa de un plazo o ventana de velocidad
   antes de una zona difícil. El conductor decide línea, velocidad y si avisa al
   equipo. Los pasajeros equilibran, sujetan y atienden su regla particular.
4. **Crisis:** una sacudida puede desplazar, abrir, agrietar, derramar o soltar
   contenido. Primero se evita el daño siguiente; después se repara. Algunas
   acciones caben en el asiento; otras requieren que el vehículo esté detenido.
5. **Entrega:** el cliente inspecciona pistas visibles y reacciona según el
   contenido real. El resultado muestra calidad, reparación, sustitución,
   tiempo y acciones de rescate.

## Estados del paquete

Separar el estado del **contenido** del estado del **embalaje** y de la **trampa**.
La barra actual de `ITrapBehavior` mezcla riesgo, tiempo y daño: no debe usarse
como único dato para decidir si algo puede repararse o entregarse.

| Estado | Qué significa | Qué puede hacer el equipo |
| --- | --- | --- |
| Intacto | Contenido y caja en orden. | Protegerlo; cobrar máximo. |
| Comprometido | Caja abierta, sujeción floja, inclinación o agitación alta. | Acción preventiva inmediata; todavía no hay pérdida permanente. |
| Dañado | Parte del contenido sufrió daño o salió de su lugar. | Reparar, rearmar, contener o sustituir según el contenido. |
| Crítico | Está a punto de escapar, desparramarse o romperse más. | Rescate urgente con señal visible y sonido; hay una ventana de reacción. |
| Rescatado | Se estabilizó tras un accidente. | Entregar con descuento o seguir reparando si queda tiempo. |
| Perdido | El contenido no existe, quedó fuera de alcance o acabó un plazo de rescate. | Entregar la caja vacía para cerrar el pedido o seguir hacia otros pedidos. |

Una reparación **nunca borra el historial de daño**. La integridad física puede
mejorar hasta un tope por tipo de arreglo, pero la puntuación conserva el daño
máximo sufrido, las piezas sustituidas y el tiempo invertido. Distinguir así
`calidad_actual`, `mejor_calidad_posible`, `embalaje`, `contenido_presente`,
`reparaciones` y `sustitucion`. Una caja totalmente destruida puede tener contenido
rescatable. Una caja entera puede ocultar contenido perdido.

**Calidad de entrega** se calcula con cuatro comprobaciones visibles para el
jugador: contenido correcto y presente, función conservada, embalaje cerrado y
apariencia suficiente. La reparación es convincente si cumple las cuatro;
un sustituto deliberado falla la primera. El HUD muestra cuál falta y qué
acción puede corregirla. La inspección del cliente no usa una tirada aleatoria:
el mismo estado siempre produce la misma categoría de respuesta. El daño
anterior reduce puntos incluso si el arreglo queda convincente.

La partida no termina cuando todas las barras llegan a cero. Se sigue hasta
completar la ruta o decidir cerrarla desde una parada segura. Las cajas
recuperables mantienen viva la posibilidad de completar la entrega. Una carga
irrecuperable se liquida en resultados, sin corte brusco de la sesión.

## Cómo se juega sentado atrás

Cada asiento tiene un **área de trabajo** al alcance. El pasajero puede mirar,
tomar la caja en el regazo, devolverla a su soporte, usar una mano para sujetarla
o abrir el kit. El regazo permite reaccionar mejor a un golpe, pero ocupa las
manos y transmite más las curvas. El soporte libera las manos para reparar,
pero necesita una cincha; una caja suelta se desliza y puede golpear otra.

El minijuego común es **anticipar y compensar**. Un indicador muestra hacia
dónde empuja la inercia y da una breve señal antes de un bache anunciado por el
camino. El jugador mueve stick o mouse en sentido opuesto y mantiene presión
para centrar una zona móvil. El input tiene tres zonas: corrección adecuada,
insuficiente y exceso. No se premia machacar un botón: sobrecorregir la caja
también la desplaza. En línea recta estable el medidor se calma, para que
existan pausas reales. En curva rápida, frenada o salto, la zona segura se
estrecha durante unos segundos. Un acierto reduce desplazamiento y daño; un
fallo primero afloja el agarre y solo después provoca golpe o caída. Soltar
para usar una herramienta es una elección consciente y visible.

Esto convive con la regla de cada contenido. El jugador debe elegir entre
dedicar la mano a sujetar, ejecutar la acción de su trampa o pedir ayuda.
Los dos sistemas no deben exigir inputs incompatibles al mismo tiempo sin
aviso ni alternativa: la dificultad nace de priorizar y coordinar. Una ayuda
de otro pasajero tiene valor claro (sostener mientras el dueño encinta, pasar
un objeto, recuperar algo del piso).

**Reglas de comodidad y lectura:** el peligro se ve en la caja y en el medidor,
no solo en una vibración de cámara. La cámara de primera persona sacude menos
que el objeto. Las acciones y señales deben ser legibles en gamepad, sin
depender del color. La vista hacia la zona de trabajo debe poder recuperarse
con un botón.

## Presión para conducir rápido

El bono de rapidez actual es pequeño y no exige acelerar: cada ruta tendrá
dos o tres **plazos de entrega** avisados con antelación (cliente que sale de
casa, evento que empieza, comercio por cerrar). Llegar a tiempo da dinero y
mérito; fallar un plazo reduce la paga sin arruinar carga. El calendario de
plazos se ajusta al largo real de la ruta y las paradas previstas. Obtener la
mejor recompensa exige manejar rápido en varios tramos, pero siempre se puede
elegir ir más lento y salvar paquetes. Un plazo jamás obliga a cruzar un
peligro físico a una velocidad exacta.

Cada plazo se calcula sobre la ruta generada, no sobre un temporizador fijo.
Un recorrido competente y rápido debe poder cobrar todos los bonos incluso
si hace una parada breve de rescate. Una conducción cuidadosa debería cobrar
al menos el pago base y perder algunos bonos. Medir estos dos casos con el
simulador de ruta antes de fijar segundos; si la mejor estrategia resulta ser
frenar siempre o acelerar siempre sin usar pasajeros, ajustar plazos y
sacudidas, no multiplicar daño de forma general.

La velocidad constante por sí sola no debe causar daño. El peligro surge de
aceleración, frenada, curva, bache y colisión **medidos en el punto real de cada
caja**. Un conductor hábil puede sostener velocidad alta con una buena línea;
un pasajero hábil puede salvar una maniobra agresiva. Los tramos peligrosos
deben anunciarse con señales visibles y un intervalo de reacción. Tras una
secuencia intensa debe haber espacio para estabilizar o reparar.

Objetivo inicial para playtesting: en una ruta de 2–5 minutos, 2–4 crisis
significativas para un grupo que persigue bonificaciones; 0–1 para un grupo que
renuncia deliberadamente a velocidad y maneja bien. No debe ocurrir que un
único choque moderado lleve varias cajas de intactas a perdidas. Revisar
`bench_route_shocks`: hoy badén, ripio y loma casi no amenazan una caja frágil,
mientras un choque con tren puede generar un impulso extremo. Capar daño por
evento y reforzar amenazas normales antes de subir daño global.

## Correr con la caja (N-115)

Decisión del usuario (2026-09-29): se puede correr con una caja en brazos, es una apuesta. Llegás antes a una caja
caída (los 30 s del rescate) o al pedido, pero la caja lo paga. Lo decide el dueño del jugador (movimiento del cliente,
como el resto a pie) y lo aplica el host.

- **Velocidad**: 3,6 m/s caminando, 6 corriendo, 5 corriendo con caja, 4,2 (trote) con la caja de Peso Creciente.
- **Cada paso sacude la caja** (un paso cada 2 m): el cliente avisa al host y el host llama al camino de daño de
  siempre (`package_run_shake.gd` -> `ITrapBehavior.on_carried_step()`), escalado por el relleno y la cinta.
  Cada trampa lo siente a su manera: Frágil pierde integridad (1,4 por paso, la que más), Equilibrio se inclina
  (2,5 grados por paso, bajan al parar), Líquido derrama (1,6 por paso), Ruidoso se agita (3,5), Explosivo acorta
  la mecha (0,12 s), Hostil se enoja (1,2). Peso Creciente no recibe daño por paso: lo que paga es la velocidad.
- **Tropezón**: en cada paso con caja el host tira un dado que depende solo de la semilla de la sesión, del jugador
  y del número de paso (el mismo en todos los pares). Probabilidad: 0,8 % por paso más hasta 14 % según lo mala que
  sea la situación que informa el dueño: giro brusco de la vista, pendiente de más de 9 grados, ripio (1) o banquina
  (0,25) del tramo (`Route.ground_roughness()`), y chocar con algo. Al tropezar la caja sale de las manos con un
  empujón y un golpe fuerte (6 m/s de cambio de velocidad, como un `drop_carried()` con impacto), y no se puede
  volver a correr por 1,5 s.
- **Se ve venir**: la caja rebota en los brazos con cada paso (la malla, no el cuerpo), cruje cada dos pasos y la
  primera vez sale el consejo "Correr con la caja la sacude".
- **Solo, 2 y 5 jugadores**: no depende de nadie más. Sin semilla de sesión (jugando solo) el dado usa una semilla
  propia del jugador.

## Kit y reparación común

Cada equipo empieza con suficientes recursos para **un rescate simple por caja**.
Comprar mejoras amplía posibilidades o reduce tiempo; nunca es requisito para
tener una salida. Los consumibles viven físicamente en un cajón de la camioneta
y tienen contador compartido. Reparar en movimiento es posible solo para tareas
cortas y con alguien sosteniendo la caja. Una reparación compleja exige bajar
la velocidad o detenerse. Esa parada cuesta el plazo de entrega: es una
decisión del equipo, no una pantalla de menú.

| Herramienta | Sirve para | Límite y minijuego |
| --- | --- | --- |
| Cinta | Cerrar caja, fijar tapa, sujetar fuga pequeña, improvisar cincha. | Trazar y mantener la cinta sobre bordes que se mueven; no recompone contenido. |
| Pegamento | Unir piezas grandes de objetos sólidos. | Ordenar piezas y sostenerlas unos segundos sin una sacudida fuerte; quedan grietas. |
| Relleno | Inmovilizar contenido dentro de la caja. | Repartir material alrededor del objeto; reduce golpes futuros, no recupera calidad. |
| Trapo/absorbente | Contener líquido y limpiar el piso. | Presionar en la fuga y cambiar el trapo cuando se satura; no devuelve líquido perdido. |
| Cincha | Fijar caja a soporte o regazo. | Tensar hasta zona segura; demasiado floja se suelta y demasiado fuerte daña lo frágil. |
| Kit de sustitución | Reemplazo humorístico de un contenido concreto. | Encontrar el sustituto, meterlo en la caja y cerrar; la etiqueta y resultado registran el cambio. |

La cinta y el pegamento son **acciones**, no botones que suman salud. Una caja
reparada sigue siendo vulnerable: el arreglo puede aflojarse con un golpe fuerte
y exigir mantenimiento. Evitar acciones de varios segundos sin información:
si el vehículo se mueve, mostrar progreso, tensión y causa de interrupción.

## Contenidos y rescates específicos

| Contenido / trampa actual | Crisis durante el viaje | Prevención activa | Rescate tras el daño | Resultado máximo tras rescate |
| --- | --- | --- | --- | --- |
| Jarrón / Frágil | Grieta, luego piezas separadas. | Sujetar en curvas y rellenar huecos. | Reunir piezas grandes, pegarlas y encintar la caja. Si hay demasiadas piezas, entregar fragmentos acolchados. | «Reparado», nunca intacto. |
| Torta / Equilibrio | Pisos corridos, cobertura caída, derrumbe. | Contrapesar con stick y sostener base. | Reapilar pisos y fijar con palillos o cinta; decorado torcido queda visible. | «Rearmada». |
| Gallina / Ruidoso | Agitación, tapa abierta, fuga al interior. | Calmar en ritmo y asegurar respiradero sin taparlo. | Perseguirla dentro del vehículo y devolverla; si se escapa fuera, usar juguete de gallina. | Real recapturada: «estresada»; juguete: «sustituida». |
| Líquido | Tapa floja, charco y pérdida gradual. | Fregar el charco alternando A y D y sujetar tapa. | Sellar, absorber y trasvasar lo recuperable si hay recipiente. | «Contenido parcial». |
| Peso creciente | La caja se desplaza y bloquea trabajo/salida. | Resolver secuencia y asegurar soporte. | Dos personas levantan y reubican; completar puzzle reduce masa. | «Controlado», con marca por golpes sufridos. |
| Explosivo | Cuenta atrás, sacudidas aceleran el riesgo. | Pedirle el código al conductor (lo ve en el tablero) y tocarlo, mientras otro lo inmoviliza. | Antes del cero: retirar módulo de emergencia o usar consumible limitado. Después: caja inutilizada y consecuencia cómica, sin borrar toda la ronda. | «Desactivado a tiempo» o «neutralizado tarde». |
| Hostil | Ataque, rotura de jaula, criatura suelta. | Leer señal «calmar/no tocar» y cerrar pestillo. | Contenerla entre dos jugadores o atraerla de vuelta; reparar jaula. | «Reenjaulado». |

La sustitución de la gallina debe ser explícita para los jugadores. El juguete
produce un sonido obviamente distinto y el cliente lo descubre en la puerta.
El humor está en la decisión desesperada y su consecuencia, no en un castigo
aleatorio sin pistas. No tratar a una criatura viva como un objeto que se
arregla con cinta o pegamento.

### Qué cuenta como reparación convincente

| Contenido | Comprobación concreta en la puerta |
| --- | --- |
| Jarrón | Están las piezas principales, se sostiene solo y no pierde agua en una breve prueba. Las grietas pueden verse. |
| Torta | Conserva los pisos, queda en pie y tiene cobertura sobre la zona dañada. Una inclinación leve es aceptable. |
| Gallina | Es la gallina original, está dentro de la caja ventilada y responde. El juguete nunca cumple. |
| Líquido | Queda una cantidad mínima marcada en el envase, la tapa no gotea y la etiqueta coincide. |
| Peso creciente | El contenido está completo, se puede retirar sin peligro y la caja no bloquea la puerta. |
| Explosivo | Está desactivado y cerrado; la explosión ya ocurrida no se puede reparar para cobrar íntegro. |
| Hostil | La criatura está dentro, el cierre aguanta y no ataca al cliente al recibirla. |

Cuando un contenido ya no puede cumplir esta prueba, la interfaz lo indica y
ofrece la mejor salida restante. El equipo puede intentar presentarlo igual,
pero no pierde tiempo buscando una reparación imposible por falta de información.

## Inspección e interacción con el cliente

La puerta tiene una secuencia breve, sin diálogo largo que frene al grupo:
entregar, inspección de 2–4 segundos, reacción y resultado. Se puede mostrar
la caja reparada antes de soltarla. El cliente comenta una pista concreta:
la grieta visible, la torta inclinada, el goteo o el cacareo de plástico.

| Estado en la puerta | Reacción | Pago |
| --- | --- | --- |
| Intacto | Recibe y agradece. | Completo. |
| Reparado convincente | Nota el percance, ve que el pedido funciona y lo acepta. | Alto, con descuento por daño. |
| Reparado poco convincente | Interacción cómica específica; el equipo puede explicar, mostrar el arreglo o admitir el desastre. | Bajo, según contenido restante; no depende de azar. |
| Sustituido | Descubrimiento y remate cómico específico. | Mínimo o cero por el pedido, con posible mérito por improvisación. |
| Perdido/no entregado | Reclamo breve. | Cero y penalidad de pedido. |

Las opciones de respuesta alteran la escena y el mérito social, no convierten
por azar un objeto falso en intacto. Ejemplo de gallina: el jugador presenta
el juguete; el cliente lo aprieta, suena un chillido de goma y pregunta por qué
su gallina tiene pilas. El jugador puede admitir la fuga o intentar una excusa;
ambas ramas son cortas y distintas, y el pago sigue reflejando el sustituto.
Ejemplo de jarrón: el cliente lo gira, ve una línea de pegamento y pregunta si
esa era parte del diseño. Si las piezas sostienen agua y el arreglo está limpio,
acepta con descuento. Si gotea, llega el remate cómico y una paga menor.
La torta puede deslizarse al abrir la tapa; el cliente pregunta por el piso
que quedó abajo. Un líquido que pierde una gota mancha el recibo. La caja de
peso creciente casi se lleva la puerta. La de hostil gruñe durante la firma.
Estas reacciones se disparan por estados observables; no requieren escenas
largas ni actuaciones únicas para cada combinación de daños.

## Reglas de justicia y dificultad

- **Aviso antes de la consecuencia:** peligro de ruta visible; la caja indica
  cuándo el agarre está por soltarse; el contenido da una señal antes de perderse.
- **Ventana de rescate:** una fuga o rotura deja 8–15 s para estabilizar antes
  de volverse pérdida definitiva, salvo eventos excepcionales muy anunciados.
- **Daño por etapas:** un impacto moderado cambia una etapa como máximo. Los
  impulsos físicos anómalos se limitan para puntuar; el objeto sigue pudiendo
  volar y generar caos visual.
- **Evitar espirales imposibles:** después de un golpe fuerte hay un breve
  período de inmunidad al mismo origen de daño; cada crisis importante deja una
  salida jugable y no encadena cuatro alarmas nuevas al instante.
- **Composición de pedidos:** no asignar simultáneamente más tareas continuas
  que jugadores disponibles puedan atender. Las pausas entre crisis crecen si
  hay menos jugadores.
- **Juego solo:** conducir con una mano en el control principal. Las trampas
  reciben ayuda pasiva básica cuando la caja está bien montada; el conductor
  puede parar y reparar sin que un temporizador irreversible siga corriendo.
  El puntaje máximo solo se ajusta a lo que una persona puede ejecutar.
- **Caída de un jugador:** su caja queda asegurada temporalmente y otro jugador
  puede reasignarse; desconectarse nunca causa pérdida instantánea.
- **Sin abuso de reparación:** no hay curación infinita, los recursos son finitos,
  el tiempo corre y la calidad máxima baja tras cada accidente real.

## Puntuación y feedback

Puntuar por pedido: intacto > reparado convincente > reparado poco convincente
> sustituto > caja vacía/no entregada. La velocidad suma por plazos logrados;
rescatar una crisis aporta mérito y una recompensa pequeña. Una sustitución
evita perderlo todo, pero no supera una reparación auténtica. La pantalla de resultados debe contar
la historia: «Jarrón pegado en marcha», «Gallina sustituida por juguete»,
«Recuperada del piso», además de puntos y descuento. El HUD muestra calidad
actual, siguiente amenaza, herramienta sugerida y quién puede ayudar. El
conductor ve una versión mínima: iconos de carga, urgencia y pedidos de freno.

## Integración con el proyecto actual

1. `DeliveryPackage` necesita estado persistente de embalaje/contenido y
   eventos de rescate, separados de `trap_behavior.integrity`. Hoy
   `mark_lost()` y `spill_contents()` llevan directo a `RUINED`.
2. `RunManager._on_package_ruined()` termina la partida si toda la carga a
   bordo está arruinada. Cambiarlo cuando el nuevo estado de rescate exista,
   no antes, para que las pruebas de partida mantengan un significado claro.
3. `FragileTrapBehavior` hoy no recibe defensa activa del pasajero. El sistema
   común de sujeción debe protegerlo y darle una tarea durante la ruta.
4. `BalanceTrapBehavior` permite corregir manteniendo un botón. La corrección
   direccional del minijuego debe entrar por la misma ruta host autoritativa
   de `submit_tender_input`, sin permitir que el cliente decida su integridad.
5. `PackageContent` hoy define presentación y textos; ampliar datos de piezas,
   reparaciones permitidas y sustitutos sin poner reglas de reparación en la
   escena visual. Sincronizar acciones, consumibles y calidad con el host.
6. El trabajo de paquetes, jugador e interfaz pertenece al dominio de Slatex;
   la presión de velocidad y los tramos, al de Nacho; `RunManager`, eventos y
   nivel son zona compartida. Registrar los contratos antes de cambiar ambos.

## Orden de construcción y criterios de aceptación

**Corte vertical 1: jarrón.** Caja en regazo y soporte, minijuego de sujeción,
grieta por golpe, cinta, pegamento, entrega reparada y resultado distinto.
Probar en solitario y con conductor + pasajero. Un golpe moderado debe dejar
al menos una acción útil; la caja no se destruye durante una animación de
recuperación por el mismo impacto.

**Corte vertical 2: ritmo de ruta.** Dos plazos y tramos con
sacudidas normales medibles. Un equipo que busca la mejor paga debe acelerar
en varias ocasiones; uno que prioriza seguridad aún debe poder terminar.
Medir el número de crisis, el tiempo disponible para reaccionar y el daño por
evento en muchas semillas.

**Corte vertical 3: gallina y sustitución.** Fuga dentro del vehículo,
recaptura, juguete sustituto, reacción del cliente y resultado. Probar que
ningún cliente ve una gallina real mientras el host ya registró el juguete.

**Expansión:** torta, líquido y resto de trampas; ayuda entre pasajeros;
herramientas adicionales; UI y audio. Cada tipo debe tener una acción útil
antes y después de una crisis, un límite claro para su reparación y un
resultado visible en la puerta. Probar pérdida total, desconexión, entrega
durante una reparación y consumo simultáneo del último recurso en red.

## Decisiones cerradas en esta conversación

1. Se cierra el diseño completo antes de implementar.
2. La velocidad surge de plazos y recompensas, sin puertas que exijan una
   velocidad arbitraria.
3. El primer objetivo tras un accidente es reparar de forma convincente. Si
   no se logra, la entrega genera una interacción cómica con el cliente.

