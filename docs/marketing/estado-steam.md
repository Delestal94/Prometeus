# Estado de Steam — Take My Package

> Rutina mensual de lanzamiento, **2026-10-01** (rama `rutina/lanzamiento-2026-10`). Lo arma
> `estratega-steam`; se reescribe cada mes. Fuentes del código: `origin/main` a `061f1d7`.
> Vara: qué hacen los indies de 1-2 personas que venden, no las campañas de estudio grande.
>
> **Red:** GitHub y la búsqueda web respondieron. `partner.steamgames.com`, `godotengine.org`,
> `codeberg.org`, `godotsteam.com` y `store.godotengine.org` están **bloqueados por el proxy** de
> esta sesión: los datos de Steamworks salen de resultados de búsqueda que citan la documentación
> oficial y de guías de terceros, marcados "(verificar)". Antes de subir nada a Steamworks, mirarlos
> en la página oficial.

## 0. Resumen en cinco líneas

1. **Bloqueante n.º 1: no hay AppID propio** (`do-not-drop/steam_appid.txt:1` = `480`, Spacewar;
   N-901 ⏸). Sin él no hay página, ni logros, ni nube, ni prueba real de invitaciones (N-215), y el
   Steam Direct tiene una **espera de 30 días** desde el pago hasta poder lanzar.
2. Lobby de amigos e invitaciones por la lista de amigos: **hechos en código, nunca probados con
   un AppID real**. Falta el botón "Invitar amigos" dentro del juego y la presencia enriquecida.
3. Logros y nube: **cero código** (S-907 ⏸). Mando: **casi completo** (falta pulsar-para-hablar en
   el mando). Steam Deck: sin probar en hardware. Remote Play Together: **no aplica** sin pantalla
   compartida local; no prometerlo.
4. Cápsulas: **ninguna existe** y la lista de tamaños de S-903 está vieja. Capturas: 5 escenas en
   1920×1080 (dos tandas), pero muestran las caras anteriores a N-506. Tráiler: guion sí, video no.
5. **Choque de calendario**: el Early Access del 2027-01-22 cae **antes** del Next Fest de febrero
   2027 (22-feb a 1-mar). Decisión del usuario (§2.3).

---

## 1. Features de Steam que un coop necesita

| Feature | Estado | Evidencia | Falta | Dueño probable · costo |
|---|---|---|---|---|
| **Lobby e invitaciones** | Hecho en código, sin probar con AppID real | Lobby solo de amigos: `modules/net_session/net_session.gd:380` (`createLobby`, tipo 1 = amigos), hasta 8: `scripts/core/network_manager.gd:14`. Aceptar invitación o "Unirse a la partida" desde la lista de amigos: `net_session.gd:369-370` y `:437` (`join_requested`). Arrancar el juego desde una invitación: `net_session.gd:151` (`+connect_lobby`) y `scripts/ui/main_menu.gd:150-153`, `:557`. Init: `net_session.gd:305` (`steamInitEx`). | (a) Botón "Invitar amigos" en el depósito/menú (`activateGameOverlayInviteDialog`): no aparece en `scripts/` ni `modules/`. (b) Presencia enriquecida (`setRichPresence`, "Repartiendo · 3/8"): no existe. (c) Probar con AppID propio entre dos PCs (N-901, N-215). | `constructor-red` + `auditor-red` · chico (a, b: medio día); (c) manual con un amigo |
| **Voz** (el plan la mete en el MVP, N-212) | Parcial | Captura y envío: `modules/net_session/steam_voice.gd:86`, `:127`, `:132`. Apagada por defecto: `scripts/core/proximity_voice.gd:22-23`. | Reproducción espacial (N-212.2) y prueba con Steam real. `voice_talk` **no tiene botón de mando** (`do-not-drop/project.godot:166`) y pulsar-para-hablar es el valor por defecto. | `constructor-red` (N-212.2) · grande; mando: `constructor-ui` · chico |
| **Logros** | No existe | Ninguna llamada `setAchievement`/`storeStats` en `scripts/` ni `modules/`. Diseño y sistema local pendientes en S-907 (`docs/tareas-nacho.md:3253-3259`). | Los 15 logros, el sistema local con aviso y el puente a Steam (necesita AppID). | `constructor-progresion` (local) + `constructor-red` (puente) · medio |
| **Guardado en la nube** | No configurado (no necesita código) | Todo vive en `user://`: `scripts/core/unlock_manager.gd:9`, `scripts/core/crew_progression.gd:6`, `scripts/core/run_manager.gd:119`, `scripts/core/game_settings.gd:13`, `scripts/gameplay/depot/depot_campaign_board.gd:21-22`. Sin `use_custom_user_dir` en `project.godot` (carpeta `app_userdata/Take My Package`). | Configurar Steam Auto-Cloud en Steamworks con esas rutas (Windows y Linux), **excluyendo** `user://telemetry/` y `user://trailer_still.png`. Decidir si `depot_photos/` sube. | `constructor-red` (documentar rutas) + usuario en Steamworks · chico, después de N-901 |
| **Soporte de mando** | Casi completo | 32 de 35 acciones con evento de mando en `project.godot` (sección `[input]`, línea 48 en adelante); sin mando: `voice_talk` (`:166`), `dev_camera_toggle` (`:219`, de desarrollo) y `toggle_net_stats` (`:248`, de desarrollo). Foco del menú para mando: `scripts/ui/main_menu.gd:201-203`; anillo de foco: `scripts/ui/ui_theme.gd:298`. Ayudas con texto de mando (`HUD_PAD_*`): `scripts/ui/hud/hud_prompts.gd:55-65`. | Botón de mando para `voice_talk`. Ícono de botón según el mando (Xbox/PlayStation/Deck) en vez de texto: no hay. | `constructor-ui` · chico (voz), medio (íconos) |
| **Steam Deck** | Sin probar en hardware | HUD y menú revisados en 16:10 (`docs/tareas-nacho.md:1166`); export Linux en `tools/export/export_presets.cfg:41-50` y GodotSteam trae `linux64`. | (a) Prueba real en un Deck (o Proton). (b) Escribir el apodo (`scripts/ui/cosmetics_panel.gd:39`) y la IP (`scripts/ui/main_menu.gd:102`) sin teclado: no se llama al teclado en pantalla de Steam (`showFloatingGamepadTextInput` no aparece). (c) Rendimiento a 1280×800 en GL Compatibility. | `constructor-ui` (b) · chico; `perfilador-rendimiento` + usuario con Deck (a, c) |
| **Remote Play Together** | **No aplica** | El juego no tiene juego local en la misma pantalla (búsqueda de pantalla dividida / dispositivos por jugador en `scripts/`: sin resultados). Remote Play Together transmite la pantalla del host: los invitados verían solo la cámara del host, en un juego en primera persona donde cada uno tiene su rol. | Nada en código. **No marcarlo en Steamworks ni prometerlo en la página.** Remote Play común (jugar tu copia en otro dispositivo) funciona sin trabajo. | — |
| **Declaración de contenido IA** | Base lista, con un hueco | `art/ai-registro.md` (44 líneas). Contenido **pregenerado** que queda en el juego: fondo del menú y splash (`:13-14`), ícono de la app (`:15`), íconos de trampas (`:16-20`), íconos de acción (`:21`), **logo** (`:22`, ChatGPT imagegen; va encima de todas las cápsulas), 10 texturas de detalle (`:23`), fondo de resultados (`:29`). Lo de `art/gel_character/` es concepto, no va al juego. **Generado en vivo: nada.** | `mus_ingame_loop.ogg` sin origen ni licencia (N-911 ⏸, `docs/tareas-nacho.md:338-348`): **bloquea** la declaración. | Usuario (N-911.1) |

### Borrador de la declaración (para el cuestionario de contenido de Steamworks)

> Pregenerado: parte del arte 2D (fondos del menú, de la pantalla de resultados y de arranque, el
> ícono, los íconos del HUD, el logotipo y las texturas de detalle del terreno) se generó con
> herramientas de IA de imagen (Z-Image Turbo en local y ChatGPT) y después lo editamos nosotros.
> Los modelos 3D, las animaciones, el código, los sonidos y la música se hicieron sin IA generativa.
> El juego no genera contenido con IA mientras se juega.

La frase de la música **solo vale si N-911 se resuelve por la opción (b)** (pista compuesta con
`tools/audio/compose_music.py`) o si el origen documentado no es IA. Si cambia el registro, se
actualiza este párrafo.

---

## 2. Calendario hacia atrás

Fecha objetivo del plan: **Early Access 2027-01-22** (`docs/plan-desarrollo.md:294`). Hitos del plan:
contenido cerrado 2026-10-30, página publicada 2026-11-27, demo 2026-12-18 (`:291-293`).

### 2.1 Plazos de Steam que fijan el calendario

| Regla | Fuente |
|---|---|
| La página "Próximamente" tiene que estar visible **al menos 2 semanas** antes del lanzamiento. | Steamworks, "Coming Soon" (`partner.steamgames.com/doc/store/coming_soon`, vía búsqueda 2026-10-01; verificar) |
| La revisión de la página tarda 3-5 días hábiles; enviarla **7 días** antes de cuando se quiere pública. La página se revisa antes que la build. | Steamworks, "Release Process" (`partner.steamgames.com/doc/store/releasing`, vía búsqueda; verificar) |
| **30 días** entre el pago del Steam Direct (USD 100) y poder lanzar; no se acorta. | Guías de terceros que citan `partner.steamgames.com/steamdirect` (datahumble.com, thegamemarketer.com, 2026; verificar) |
| Next Fest octubre 2026: 19 al 26-oct. | steampageanalyzer.com (2026; verificar) |
| Next Fest febrero 2027: **22-feb a 1-mar**; inscripción hasta **10-ene**; todo enviado a revisión el **8-feb**; vista previa de prensa desde el 11-feb. | Steamworks, `doc/marketing/upcoming_events/nextfest/feb_2027` (vía búsqueda 2026-10-01; verificar) |
| Next Fest es para juegos **sin lanzar**: un juego ya en Early Access no entra. | Regla conocida del evento; la página oficial no se pudo abrir (proxy). **Verificar antes de decidir.** |

### 2.2 Calendario A — el del plan (Early Access 2027-01-22, sin Next Fest)

| Fecha | Hito | Qué tiene que estar listo en el juego / la cuenta |
|---|---|---|
| **2026-10-16** | Pagar Steam Direct, AppID propio (N-901) | Cuenta de Steamworks, datos fiscales y de identidad. AppID en `steam_appid.txt` y `network_manager.gd`. Prueba de invitaciones con dos PCs (N-215). Es el primer paso porque destraba logros, nube y la prueba real. |
| 2026-10-30 | Contenido cerrado | Sin tareas A abiertas (hoy hay varias, ver §6). Voz N-212.2 adentro o fuera de la página. |
| 2026-11-13 | Material de tienda listo | Cápsulas (§3.1), 6-8 capturas nuevas con las caras de N-506, tráiler grabado, textos (S-901), declaración de IA (N-911 resuelta), precio fijado. |
| 2026-11-20 | Página enviada a revisión | 7 días antes de publicarla. |
| **2026-11-27** | Página "Próximamente" publicada | Desde acá juntamos wishlists. |
| 2026-12-18 | Demo publicada | Una entrega y el depósito, rama propia de Steam (N-210). Con mando completo y el botón de invitar. |
| 2027-01-08 | Build de Early Access enviada a revisión | Build casi final en la rama por defecto, con logros y nube configurados. |
| **2027-01-22** | **Early Access** | 1 vehículo, 1 set de tramos, 7 trampas (N-117), precio definido. |

Wishlists posibles con este calendario: 8 semanas de página, sin festival.

### 2.3 Calendario B — propuesto: Next Fest de febrero y Early Access en marzo (**decide el usuario**)

Igual que A hasta la demo; después:

| Fecha | Hito |
|---|---|
| 2027-01-10 | Inscripción al Next Fest de febrero (con la página y la demo ya publicadas). |
| 2027-02-08 | Demo y materiales del festival enviados a revisión. |
| 2027-02-22 → 03-01 | Next Fest: demo jugable, transmisión en vivo con amigos jugando de a 8. |
| 2027-02-26 | Build de Early Access enviada a revisión. |
| **2027-03-12 (vie)** | **Early Access**, dos semanas después del festival. |

**Recomendación: B.** Un estudio de 1-2 personas sin presupuesto de publicidad no tiene otra vitrina
gratis comparable al Next Fest, y un coop de hasta 8 se presta a la demo de festival (la gente
la juega con amigos y la transmite). Con B la página junta 15 semanas de wishlists en lugar de 8. El
costo es correr el Early Access siete semanas. No doy una cifra de wishlists esperada porque no
tengo una fuente para este caso.

---

## 3. Cápsulas, capturas y tráiler

### 3.1 Cápsulas: no existe ninguna

Hay logo: `do-not-drop/assets/ui/logo/tx_ui_logo_wordmark_2048.png` (2048×1024) y
`tx_ui_logo_stacked_2048.png` (2048×2048), ambos con transparencia. No hay ninguna cápsula en el repo
(búsqueda de `*capsule*`/`*capsula*`: nada; `assets/store/` no existe).

**La lista de S-903 (`docs/tareas-nacho.md:3233`) tiene tamaños viejos** (460×215, 616×353, 231×87).
Steam dejó de aceptar los tamaños viejos en agosto de 2024. Los tamaños actuales (resultados de
búsqueda que citan `partner.steamgames.com/doc/store/assets/standard`, 2026-10-01; **verificar con las
plantillas oficiales**):

| Cápsula | Tamaño | Logo |
|---|---|---|
| Header (encabezado; la que más se ve) | 920×430 | wordmark |
| Small (búsquedas, listas; Steam la achica hasta ~120×45) | 462×174 | wordmark, grande, casi sin fondo |
| Main (carrusel de la portada, mails de wishlist) | 1232×706 | wordmark |
| Vertical (páginas de ofertas) | 748×896 | stacked |
| Fondo de página (opcional) | 1438×810 | sin logo |
| Biblioteca: capsule | 600×900 | stacked |
| Biblioteca: header | 920×430 | wordmark |
| Biblioteca: hero | 3840×1240 | **sin texto**; lo importante en el centro (860×380) |
| Biblioteca: logo | 1280 de ancho y/o 720 de alto, transparente | el logo solo |

Regla para el pedido a `artista-conceptual`: la IA dibuja solo la escena (camión del reparto con la
puerta trasera abierta, cajas en el aire, cuadrilla agarrándolas); **el logo real se pone encima** y
nunca se le pide texto a la IA. En las cápsulas no va otro texto que el título. Cada cápsula
generada se anota en `art/ai-registro.md`.

### 3.2 Capturas: 5 escenas, hay que rehacerlas

`art/marketing/capturas/` tiene 10 PNG de 1920×1080: las mismas 5 escenas (salida del depósito,
curva del bosque, cruce de tren, puente con lluvia, casa de noche) en dos tandas, 2026-09-25 (solo
paisaje y camión, N-905) y 2026-09-30 (con cuadrilla, cajas y percances, N-316). La de 09-30 ya
muestra el juego (la cuadrilla bajando una caja por la rampa mientras otra sale volando).

Faltan:
- **Caras nuevas**: N-506 (#151, 2026-10-01) cambió caras y personaje; las 10 capturas tienen las caras
  anteriores. La página no puede mostrar otro personaje que el del juego.
- **Lo que vende el juego y no se ve**: el interior de la caja de carga con varias trampas a la vez,
  la cuadrilla de 8, el depósito rediseñado (N-319), el barro con la cuadrilla empujando (N-108), los
  animales que van por la carga (N-109), el diario del día siguiente (N-606).
- De noche el camión queda casi negro y el puente no se lee como puente (nota de N-905,
  `docs/tareas-nacho.md:1794-1795`).

Pedido para `revisor-visual` (con `tests/render_store_shots.gd` / `trailer_shot.tscn`), 7 capturas:

| # | Escena | `--mood=` | Cámara | Momento |
|---|---|---|---|---|
| 1 | Caja de carga, 3-4 pasajeros, cajas Frágil, Equilibrio y Ruidosa | tarde | primera persona de un pasajero, mirando a la mampara | el camión toma una curva y la torre de Equilibrio se inclina |
| 2 | Depósito (N-319) con 8 jugadores de colores | día | plano general alto desde la pizarra de pedidos | cargando, uno sube una caja a la rampa |
| 3 | Barro (N-108) | lluvia | tercera persona baja, detrás | la cuadrilla empuja el camión atascado |
| 4 | Curva del bosque (rehacer la de 09-30 con caras nuevas) | otoño | la misma | caja en el aire |
| 5 | Animal yendo por la carga (N-109) | día | desde la puerta trasera | la gaviota agarra una caja |
| 6 | Llegada a la casa | atardecer (no noche) | tercera persona | el vecino abre y se agarra la cabeza ante la caja arruinada |
| 7 | Cabina | día | sobre el hombro del conductor | conductor tranquilo; por el espejo se ve el caos de atrás |

Sin HUD salvo en una (la 1 puede llevar el aviso de la trampa: muestra la mecánica).

### 3.3 Tráiler

Guion de 75 s en `docs/marketing/trailer.md` (N-903) y cámara con rieles (N-902). **No hay video
grabado** (ningún `.mp4`/`.webm`/`.ogv` en el repo). Ajustes que pide el estado de hoy, para la próxima
pasada del guion: sumar un plano de barro con la cuadrilla empujando (N-108) y uno del depósito con 8
jugadores; si la voz (N-212.2) no está para la grabación, que el guion no la muestre.

---

## 4. Qué cambió desde el mes pasado

`git log origin/main --since="1 month ago"`: **423 commits** (el repo empieza el 2026-09-20, así que
es toda su historia; el clon venía superficial y se profundizó con `--shallow-since=2026-09-01`).
Por tipo: 139 `feat`, 64 `docs`, 57 `fix`, 27 `refactor`, 27 `chore`, 18 `test`, 11 `ci`, 5 `perf`, 4 `art`.

Por área, lo que importa para la tienda:
- **Red y 8 jugadores**: validación de RPC y reconexión (N-221), cuadrilla de 8 con colores, nombres y
  séptima bahía de carga (N-226, N-228.3-.8), presupuesto de ancho de banda para 8 (N-228.5), el que entra
  a mitad de partida aparece sentado (N-228.7), sala LAN por código (S-207), voz de Steam con captura y envío
  (N-212, parcial). Sin cambios en lobby/invitación de Steam desde la primera versión.
- **Mecánicas** (M6/M7): barro con empuje (N-108), animales que van por la carga (N-109), furgoneta clásica
  con caja manual (N-114), correr (N-115), estacionamiento como meta (N-116), cada trampa con su acción
  (N-117), rescate de cajas caídas (N-213), fallas del camión (N-214), radio (N-406), parabrisas con barro (N-113).
- **Contenido y UI**: diario del día siguiente y apodo (N-606), pantalla de personaje y caras nuevas
  (N-506), depósito rediseñado (N-319), ilustración de resultados (S-307), textos traducibles (N-805).
- **Arte técnico**: texturas comprimidas (N-314), atlas de cajas (N-315), noche legible (N-317), grúa del
  barro (N-321), capturas de tienda con cuadrilla (N-316).
- **Calidad e infraestructura**: refactors con referencias tipadas y división por responsabilidad
  (N-224, N-225), CI en 4 runners y pre-push por tests afectados, exportación de builds por tag (N-210).

Para la página: hoy el juego tiene bastante más de lo que muestran las capturas. Lo que más pesa (8
jugadores, barro, animales, depósito) no aparece en ninguna imagen.

---

## 5. Versiones de dependencias

| Dónde | Godot | Evidencia |
|---|---|---|
| CI | 4.7.2 | `.github/workflows/tests.yml:19` |
| Hook de arranque de la nube | 4.7.2 | `.claude/hooks/session-start.sh:16`; también `.claude/hooks/lib.sh:30,33` |
| `tools/run-tests.sh` | 4.7.2 | `tools/run-tests.sh:36,40` |
| PC | 4.7.2 | `tools/pc/rutina-pc.ps1:12` |

**Último estable de Godot: 4.7.2-stable (2026-08-18).** Antes: 4.7.1 (2026-07-14), 4.7 (2026-06-18); no
hay 4.8 estable (github.com/godotengine/godot/releases, consultado 2026-10-01; `godotengine.org`
bloqueado por el proxy). **Estamos al día; no hay parche nuevo.**

**GodotSteam:** el instalado es **4.22.1** (`do-not-drop/addons/godotsteam/plugin.cfg:6`), GDExtension
con `compatibility_minimum = "4.4"` (`godotsteam.gdextension:3`), así que carga en 4.7. En GitHub el
último release es **v4.22.1** ("Godot 4.x - Steamworks 1.65", 2026-09-04), el mismo que tenemos. Ese repo
**quedó archivado el 2026-09-04** y el proyecto se mudó a Codeberg (`codeberg.org/godotsteam/godotsteam`),
que el proxy bloquea: **no pude confirmar si hay algo más nuevo que 4.22.1 en Codeberg.** La búsqueda web
no muestra ningún 4.23. Próxima rutina: revisar Codeberg desde la PC; el `readme.md` del addon ya apunta
a Codeberg (`addons/godotsteam/readme.md:29`).

---

## 6. Riesgos que ve la tienda

- **Contenido cerrado el 2026-10-30 con tareas A abiertas**: N-319, N-212, N-115, N-606, N-217, N-218,
  N-215 y otras (`docs/tareas-nacho.md`). Si se corre, se corre todo (regla del plan, `:286-287`).
- **Voz en la página**: no ponerla como característica hasta que N-212.2 esté y se haya probado por
  Steam con gente.
- **"Hasta 8 jugadores" en la página**: el código lo soporta (`network_manager.gd:14`, N-228) pero nunca
  se probó con 8 personas reales por Steam. Probarlo antes de que la página lo diga.
- **Idiomas**: hoy hay español e inglés (`project.godot:256`). La fase 7b de N-211
  (`docs/tareas-nacho.md:1162-1165`, textos de `core/` y `.tres`) está abierta: hasta cerrarla, sumar
  otro idioma deja textos sin traducir.
