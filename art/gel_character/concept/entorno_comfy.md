# Entorno local de generación S-311.6

Instalado con autorización del usuario el 2026-09-30; no forma parte del juego
ni se versionan modelos, dependencias o logs en este repositorio.

- GPU comprobada: AMD Radeon RX 7800 XT, 16 GB VRAM; RAM del equipo: 32 GB.
- ComfyUI 0.38.0: `D:/Programas/ComfyUI`, commit
  `b65d1ffaca35fcda5889e120dcd0c8520553c7b2`.
- Python 3.13.15: entorno `D:/Programas/comfy-venv`.
- PyTorch `2.13.0+rocm10.0.0`, dispositivo AMD `gfx1101`.
- Modelos oficiales de [Comfy-Org](https://huggingface.co/Comfy-Org/z_image_turbo):
  `diffusion_models/z_image_turbo_int8_convrot.safetensors`,
  `text_encoders/qwen_3_4b_fp8_mixed.safetensors`, `vae/ae.safetensors`.
- Instalación basada en la [guía oficial AMD para Windows](https://docs.comfy.org/installation/manual_install).
- Servicio ligado solamente a `127.0.0.1:8188`, sin exposición a la red.

Arranque desde `D:/Programas/ComfyUI`:

```powershell
D:/Programas/comfy-venv/Scripts/python.exe main.py --listen 127.0.0.1 --port 8188 --disable-auto-launch --highvram --disable-pinned-memory --disable-async-offload
```

Generación desde la raíz del repositorio: comandos y prompts completos en
`prompts_comfy.md`; workflow compartido en `art/tools/comfy_generate.py`.
La descripción histórica de `.claude/agents/artista-conceptual.md` menciona una
RTX 4060 Ti, pero esa no es la GPU comprobada en esta máquina. No se necesita
instalar nodos personalizados ni utilizar servicios pagos.

El arranque por defecto reservó unos 12 GB de RAM fijada y se interrumpió durante
la primera generación. Un intento HIGH_VRAM fue detenido a pedido del usuario
porque estaba jugando. Se probó también LOW_VRAM con reserva de 12 GB,
texto/VAE en CPU y prioridad baja. Al cerrar el juego, el usuario autorizó
volver a GPU completa; el comando anterior es el perfil final. No cambian
los ocho pasos ni el sampler. Para coexistir con juegos hay que escoger el perfil
de baja VRAM o pausar: `reserve-vram` guía la carga, no limita la potencia de cálculo.
