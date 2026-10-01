# Animaciones del personaje definitivo: Mixamo, rig y ragdoll (investigación)

**Fecha:** 2026-10-01 · **De:** Nacho (con Claude) · **Para:** Slatex

No cambia código. Es la investigación de cómo animar el personaje definitivo (que hacés vos) sin
problemas de derechos y para que funcione con un ragdoll de verdad. Hay **una decisión pendiente**
(abajo, "Qué tiene que hacer Slatex").

## Mixamo: qué se puede y qué no

- **Gratis y sin regalías** para juegos comerciales (solo pide cuenta de Adobe). Las animaciones pueden
  ir dentro del juego exportado.
- **No se pueden redistribuir los archivos crudos** (FBX de personaje o animación) como pack,
  plantilla o asset suelto.
- **El repo es público.** Commitear los FBX de Mixamo (o las animaciones convertidas a `.res`/`.anim`)
  deja esos archivos descargables por cualquiera: eso se parece demasiado a redistribuir. Opciones:
  1. **Repo privado aparte** con los assets de Mixamo, como submódulo en
     `do-not-drop/assets/animations/mixamo/`; el público no los trae y la build/CI los baja con token
     (recomendado).
  2. Hacer privado el repo principal.
- **No hay API oficial.** Los scripts de descarga masiva de GitHub usan endpoints internos sin
  documentar (se rompen y son zona gris con los términos). No traer el catálogo entero: bajar a mano
  una **lista curada de ~20–40 clips** (caminar, correr, idle, levantar/cargar caja, tropezar,
  levantarse del piso, festejos, gestos de cada trampa).

## Alternativas sin restricciones

- **Quaternius** (Universal Animation Library) y **Kenney**: CC0, se pueden commitear al repo público.
- **CMU Motion Capture Database**: uso libre incluido comercial (BVH; hay que limpiar y retargetear).
- **Video propio + mocap** (Rokoko Video, DeepMotion, Move.ai) para gestos únicos del juego: el
  movimiento es tuyo, pero revisar los términos del plan (algunos piden plan pago para uso comercial o
  exportar sin marca). Cascadeur: la versión gratis limita exportación; para vender puede hacer falta
  Indie. Verificar estas licencias antes de usar.
- Evitar generadores texto→movimiento por IA: suelen entrenarse con datos no comerciales (AMASS,
  HumanML3D).

Consejos si se filma: cámara fija a la altura de la cintura con el cuerpo entero, buena luz, fondo
liso, ropa ajustada, gestos exagerados, empezar y terminar en pose neutra, clips de 2–5 s. El mocap
por video da ~70–80 %: después hay que limpiar temblor, pies que patinan y manos.

## Estado actual del personaje (para el definitivo)

- `assets/models/characters/sm_char_player_*.glb` no tienen esqueleto humanoide.
- `modules/ragdoll/player_ragdoll.gd` arma cuerpos rígidos sueltos en runtime porque no hay rig; es
  solo visual. El comentario en `scripts/gameplay/player/player.gd` (`_activate_ragdoll`) ya dice
  que un ragdoll real necesita un esqueleto físico.

## Cómo encaja Mixamo con un ragdoll

1. **Rig humanoide estándar** en el personaje definitivo: auto-rigger de Mixamo (gratis, subís el
   modelo) o Rigify en Blender. Proporciones muy redondeadas pueden pedir retocar pesos.
2. **Retarget en Godot 4** con `BoneMap` + `SkeletonProfileHumanoid` (nativo). Addons que lo
   automatizan (revisar licencia antes): MixaBridge, Mixamo Animation Batcher,
   Godot-Mixamo-Animation-Retargeter. O un importador propio en `modules/` (regla de módulos
   portables).
3. **Ragdoll real** con `PhysicalBoneSimulator3D` (Godot 4.3+) sobre el mismo esqueleto:
   - completo al salir volando (reemplaza `player_ragdoll.gd`);
   - parcial/"activo" mezclando animación y física con `influence` (tambalearse con Equilibrio,
     brazos que reaccionan a un golpe).
   - Sigue siendo **solo visual**: el `CharacterBody3D` es la autoridad de red; no se sincronizan
     huesos.
4. **Levantarse**: mezclar la última pose del ragdoll con el clip "levantarse del piso".

Para el modelo nuevo conviene que el rig salga con nombres humanoides estándar (los de Mixamo o
mapeables a `SkeletonProfileHumanoid`) para que cualquier fuente de animación sirva sin rehacerlo.

## Qué tiene que hacer Slatex

- **Decidir** dónde viven los assets de Mixamo: repo privado aparte (recomendado) o repo principal
  privado.
- Riggear el personaje definitivo con esqueleto humanoide estándar.
- Cuando esté el rig, Nacho puede sumar las tareas de retarget, importador y ragdoll físico
  (`animador`, `constructor-jugador`, y `auditor-red` para revisar que no desincronice).

Fuentes: Mixamo FAQ (helpx.adobe.com/creative-cloud/faq/mixamo-faq.html); comunidad de Adobe sobre
la API de Mixamo; repos github.com/uzairdeveloper223/mixabridge y
github.com/RaidTheory/Godot-Mixamo-Animation-Retargeter; Godot Asset Library #5079.
