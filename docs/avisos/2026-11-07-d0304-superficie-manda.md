# D-0304: el agarre y las pisadas siguen a la superficie dibujada

- **Qué cambió:**
  - `modules/route_gen/` (zona compartida, solo agrega): `GripArea`, un `Area3D` que baja el agarre por `GripZones` en la huella
    que se le da con `add_box()`. `GripZones` y `GravelSegment` no cambian.
  - `scripts/gameplay/player/player_sprint.gd` (Slatex): `ground_roughness()` sigue preguntando a la ruta; sin ruta (la empresa)
    lee del piso la meta `ground_roughness` (nuevo `roughness_of()`). En una entrega nada cambia.
  - `scripts/gameplay/player/gel/gel_player_audio.gd` no se tocó: `StreetSurface` pone en la calzada la meta `gel_audio_surface`
    que ya leía. En las calles de la empresa las pisadas ahora suenan a ripio y a tierra.
  - `rail_crossing_segment.gd`: `CrossingStopLine` pasa a `CrossingStopLineNear` y `CrossingStopLineFar` (nadie los buscaba).
  - `.github/workflows/tests.yml`: paso nuevo en `runtime-audit`, *Compile the street shader*.
- **Qué tiene que hacer Slatex:** nada para lo que hay. Un piso nuevo que quiera sonar o hacer tropezar distinto en la empresa
  puede poner esas dos metas en su `StaticBody3D`.
