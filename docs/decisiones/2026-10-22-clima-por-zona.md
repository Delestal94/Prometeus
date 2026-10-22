# Clima y temperatura por zona (D-0135) — 2026-10-22

## Decisión
El diseño está en `docs/expansion-distritos/diseno/distritos.md`, sección "Clima y temperatura por zona":
- **Dos capas**: la temperatura de la zona es fija (templada, fría en Nieve, caliente en Volcán) y el clima del
  día sale de la semilla.
- **Un clima por zona y por día**, constante todo el día, elegido por una función pura de la semilla **de la
  empresa** (`CompanySeed.for_day`, corriente `weather`), el día y la zona. No se guarda y no necesita RPC. El
  evento del día que fija clima (ola de calor) gana; los días 1 a 3 no tienen lluvia ni niebla.
- **Un frente compartido para el llano** (Parque Industrial, Centro, Suburbio, Campo, Puerto, Islas): una sola
  tirada con las probabilidades de hoy, y las seis zonas admiten los cuatro perfiles. Montaña, Nieve y Volcán
  tiran por separado.
- **Pronóstico chico**: la línea de la Jefa a la apertura y una línea en el portapapeles; el tablero por zona
  llega con las zonas de altura.
- **El clima no rompe cajas solo**: multiplica riesgos que ya existen. El primer efecto nuevo es el agarre en
  lluvia, como **multiplicador** ×0,75 del agarre base de cada vehículo por `GripZones` (la camioneta, 3,5 →
  2,6), medido con un test de frenado. Es Ampliación de F1 (D-0324): el corte vertical no lo necesita.
- **La jugabilidad lee la zona del vehículo, nunca `WorldMood.active`**; la presentación sigue siendo un perfil
  global hasta que haya zonas de altura (el cruce entre zonas pasa a D-1610).
- **Temperatura por salida** (zona de destino × minutos de viaje en `ColdPack`), y con la ola de calor se toma
  el máximo de las dos tasas, no el producto.
- **Volcán no tiene clima `calor`**: el calor es la temperatura de la zona; su clima variable es `ceniza`.
  En Nieve el perfil de nieve se llama `nevada` (para no confundirlo con el id de la zona).
- **Entrega y Endless no cambian**: el clima sigue siendo cosmético ahí.

## Por qué
- En un mapa continuo, climas independientes por zona dan cortes absurdos a 50 m de distancia; uno solo para todo
  el mapa no deja que Nieve y Volcán tengan el suyo. El frente del llano resuelve las dos cosas con una tirada.
- `world_seed` cambia en cada sesión (D-0246): con esa semilla el mismo día guardado tendría otro clima al
  recargar. La de la empresa no cambia.
- Un número absoluto de agarre con `GripZones` (que se queda con el mínimo) castigaría distinto a cada vehículo.
- Contar minutos por zona y por caja pedía un acumulador nuevo en el host y rompía `ice_needed()`; por salida
  cuesta medio día y se lee de una ("en Volcán el frío dura la mitad").
- `critico-diseno` marcó el error de semilla, el corte del frente con las listas de permitidos, el cruce de 8 s
  que en F1-F2 no se usaría y dos reglas que no tocaban ninguna caja (calor en Volcán, niebla ×1,5 en Montaña):
  todo aplicado.
- Sacarlo de la semilla y el día reusa lo que ya está replicado (semilla, día, posición): cero ancho de banda y
  nada nuevo en el save (`diseno/guardado.md`).
- Un clima que cambia a mitad del día o que rompe cosas por su cuenta es una sorpresa sin decisión; anunciado a
  la apertura, es una decisión de a dónde ir primero y con qué vehículo.
- El agarre es la única palanca real de manejo del motor (`GripZones`, ya usada por ripio y barro), así que la
  lluvia cuesta una línea por vehículo y no un sistema nuevo.

## Qué cambia
- `diseno/distritos.md`: sección nueva; columna "Clima permitido" (el llano con los cuatro perfiles, Nieve con
  `nevada`, Volcán con `ceniza`); tres decisiones.
- D-0324 toma la versión mínima (función, datos en `ZoneDefinition`, agarre, días 1-3, línea de la Jefa).
- D-1610 suma el cruce de presentación entre zonas y el pronóstico por zona en el tablero.
- D-1610, D-1617, D-1715, D-1321, D-1605, D-0738, D-0722 y D-1703 usan estas tablas.
