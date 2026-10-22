# Janim.jl en macOS (Apple Silicon) · sugerencias para el agente

Escrito el 2026-10-21 en la máquina Linux de desarrollo (RADV, Fedora), **sin
probar nada en un Mac**. Son sugerencias, no instrucciones cerradas: cada punto
dice qué espero, dónde mirar y cómo confirmarlo. Si una resulta falsa,
corrígela aquí mismo y di que lo estaba.

El repo hermano, Janim.py, tiene su propio `MACOS.md`. Las dos bibliotecas
comparten los shaders WGSL y la versión mayor de wgpu-native (v24), así que lo
que aprendas en una sirve para la otra. Si tienes los dos clones, lee también
ese fichero.

## Resultado · 2026-10-21, macOS 26.6.2, Apple M1, Julia 1.12.6 (juliaup)

**El port está terminado.** Render a fichero, CLI con daemon y ventana en
vivo con teclas y ratón, verificados por Alex el 2026-10-21 en este M1, en
las dos bibliotecas; las siete primeras demos renderizadas a 1080p60 en las
dos.

Probado en el Mac, sección por sección. Lo previsto se cumplió casi entero;
lo que resultó distinto está marcado.

- **§1 · Preparar.** Confirmado. `brew install --cask font-dejavu` deja las
  DejaVu en `~/Library/Fonts`; `Pkg.instantiate()` descarga el artefacto de
  wgpu-native para `aarch64-apple-darwin` y el resto, y la precompilación
  de Janim tarda unos 30 s. LaTeX y `dvisvgm` de MacTeX en
  `/Library/TeX/texbin` llegan al daemon por el `PATH` sin más.
- **§2 · Render a fichero.** Funciona sin tocar código. El adaptador es
  «Apple M1 · integrated · metal», con `vendor` y `description` vacíos (slug
  `apple`, versión `unknown`, y la cabecera `# driver:` lo dice así).
  `JANIM_HEADLESS=1` da el error con la lista de adaptadores, como se
  esperaba. Ni pánicos ni valores absurdos: el ABI de los bindings cuadra
  en arm64, callbacks con `WGPUStringView` por valor incluidos. Vistos a
  ojo y correctos: `c1_01/01`, `c1_03/04_latex`, `c2_03/03_camera_3d`,
  `demo/03_portals`.
- **§3 · Metal.** Nada se vio MAL en lo probado, y el §6 lo confirma de otra
  manera: píxel a píxel igual que Python en las cinco demos.
- **§4 · Daemon y CLI.** Confirmado: `daemon start` (2,4 s en caliente con
  `nohup`), `render`, `frame`, `ping`, `status`, `check` (informa «yours»
  con `lsof`), `preview` y `stop`. No probado: un daemon huérfano.
- **§5 · La ventana en vivo.** Escrita y probada. `bindings.jl` gana la
  `struct WGPUSurfaceSourceMetalLayer`; `window.jl` gana `_cocoa_metal_layer!`
  y `_cocoa_sync_scale!`, con el runtime de Objective-C por `ccall`
  (`/usr/lib/libobjc.A.dylib`) y `create_window` acepta `:cocoa`. Hubo que
  hacer `dlopen` de QuartzCore (GLFW enlaza Cocoa y AppKit, no QuartzCore).
  La superficie prefiere `BGRA8UnormSrgb` (se usa `BGRA8Unorm`), ofrece
  Fifo y CopySrc. **Retina:** wgpu-native pone `drawableSize` al tamaño del
  framebuffer (2560×1440 sobre 1280×720 puntos), y `contentsScale =
  backingScaleFactor` (2.0) se pone al crear y al reconfigurar, como hace
  GLFW con sus surfaces de Vulkan; en Janim.py, con la misma capa, se midió
  que cada píxel del frame ocupa exactamente un bloque 2×2 del swapchain.
  Dos sesiones de 3 s seguidas (~27 fps) abren y cierran limpias; el
  drenaje de foco de Wayland no estorba (sin agotar el tope); el playhead
  con `@async` va bien en el hilo 1. Desde el daemon, dos previews seguidas
  en el mismo daemon: la ventana se abre desde el proceso con `nohup`,
  reproduce los 420 frames y cierra con Esc («OK preview closed»). **Teclas
  y ratón:** probados a mano por Alex, incluido el movimiento de cámara:
  funcionan. Sin probar: el cierre por Ctrl-C en el cliente del daemon.
- **§6 · Julia contra Python.** Hecho. Cuatro demos idénticas byte a byte a
  la primera; `11_chase_camera` difería en los 220 frames y la causa estaba
  en Python: fusiona mallas consecutivas en un solo `draw_indexed` y en
  Metal la interpolación del color iluminado depende de la llamada que lleva
  el triángulo. Arreglado en Janim.py (una llamada por malla en Metal, como
  aquí); Janim.jl no necesitó cambios. Con eso, las cinco demos coinciden
  (140, 140, 180, 141 y 220 frames). Los detalles están en el `MACOS.md` de
  Janim.py, §7.
- **Lo que resultó falso:** el pánico, el ABI y las tres causas sugeridas
  para una discrepancia (fuentes, libm, numpy) no fueron el problema.
- **Lo que no cambió:** `glfw.jl`, `context.jl`, `live.jl`, `bin/janim`.

## Resultado · 2026-10-22, revisión tras el port a Windows (macOS 26.6.2, Apple M1, Julia 1.12.6)

**Nada cambió en el Mac.** Revisado con un clon limpio de `main` (`a17ef2e`)
frente al último `main` anterior al port a Windows (`0c63cf3`), con el guion
del `LINUX.md`, en esta sesión:

- **Instalación desde cero**: `Pkg.instantiate()` y la precompilación de
  Janim con el `include_dependency` nuevo (30 s); `gpu_info()` dice «Apple
  M1 · metal · integrated»; el render frío de `c1_01/01_how_janim_works.jl`
  desde `julia --project=.` sale.
- **Frames antes y después, byte a byte** (`tapf.jl` del §6, 640×360 a
  10 fps): `01_multicam` (140), `03_portals` (140), `04_lorenz_glow` (180),
  `06_broadcast` (198, la del CRT con el `select`), `07_text_mask` (141) y
  `11_chase_camera` (220) dan la misma lista de hashes con los dos checkouts.
  Las cinco de referencia siguen idénticas entre Julia y Python.
- **CLI y daemon**, la pasada entera del `LINUX.md` §4 salvo `-p` y la
  ventana desde la CLI (abren algo que solo Alex cierra): `daemon start`
  (`nohup`), `ping`, `status`, `render -qs`, `-o` relativa con `--out_dir`
  (se unen), `-o` absoluta con `--out_dir` (el WARN de `_is_abs`, y gana la
  absoluta), `frame … --out_dir`, `-s --to 40 --no-tui`, la dirección
  `fichero.jl:construct`, `-j 2` (140 frames, 2 procesos; el mismo contenido
  que el render de un proceso, a 45 dB de PSNR por la codificación por
  segmentos, exactamente igual que en Python), `-t` (ProRes 4444,
  `yuva444p12le`), `states`, y `check`/`finish` con un daemon huérfano
  arrancado a mano en el puerto 7400: `check` lo lista como «orphan …
  listening» y sale 1, `finish` lo cierra («closed 1 orphan daemon(s)») y
  respeta el tuyo, y `daemon stop` no deja procesos.
- **Ventana en vivo** en proceso (`setup_live` más dos sesiones de
  `live(…; max_seconds = 3.0)`): Cocoa, `CAMetalLayer`, `contentsScale`
  2.0, `drawableSize` 2560×1440 sobre 1280×720 puntos, 82 presentaciones
  por sesión, sin reconfiguraciones, cierra limpia. `JANIM_HEADLESS=1`
  sigue dando el error con la lista de adaptadores.
- **Las 12 demos a 1080p60** (`bin/janim render … -qh --only-cli` con el
  daemon), una cada vez: 11 salen; `12_motion_blur` falla por la fuente
  «Fredoka Expanded», como en Windows. Las de `01` a `07` son idénticas
  fotograma a fotograma a las renderizadas el 2026-10-21, antes del port a
  Windows.

**Julia contra Python en los mp4 a 1080p60** (decodificados y comparados
fotograma a fotograma): `01`, `03`, `04`, `07` y `10` idénticos.
`11_chase_camera` difiere en 28 fotogramas (972–1000, a 54–58 dB) con
fotogramas crudos idénticos: el arnés a 1920×1080/60 da 1320 hashes iguales,
y `frame 972` y `frame 990` por las dos CLIs dan los mismos píxeles. La causa
es el codificador: Janim.jl escribe con el ffmpeg de FFMPEG_jll (x264 core
164) y Janim.py con el del `PATH` (Homebrew ffmpeg 9.0.1, x264 core 165).
Para comparar las dos bibliotecas valen los arneses, no los mp4. `02`, `05`,
`06`, `08` y `09` difieren en todos los fotogramas, como en Linux: en `08` y
`09` el texto del demo nombra el lenguaje; en `02`, `05` y `06` lo visible a
ojo es el espaciado del `Tex` (Janim.jl separa los glifos; Python los compone
con el kerning de LaTeX). Si no es intencionado, es cosa de `Tex` en Janim.jl,
no del port.

**Tiempos a 1080p60**, reloj del proceso `bin/janim render` entero, un
render cada vez (Julia a través del daemon caliente, con los ajustes de cada
fichero); los de Windows son los del `LINUX.md`, §5 (Ryzen 7 9700X, Radeon
RX 9070 XT, DX12, Julia en frío con el lanzador):

| demo | frames | Mac Julia | Mac Python | Windows Julia | Windows Python |
|---|---:|---:|---:|---:|---:|
| 01_multicam | 840 | 9 s | 10 s | 10 s | 7 s |
| 02_pendulum_glow | 1356 | 82 s | 73 s | 18 s | 12 s |
| 03_portals | 840 | 16 s | 16 s | 13 s | 8 s |
| 04_lorenz_glow | 1080 | 163 s | 168 s | 16 s | 61 s |
| 05_rack_focus | 756 | 54 s | 54 s | 11 s | 6 s |
| 06_broadcast | 1188 | 11 s | 17 s | 13 s | 8 s |
| 07_text_mask | 846 | 38 s | 78 s | 12 s | 51 s |
| 08_light_vs_pigment | 708 | 40 s | 38 s | 10 s | 5 s |
| 09_reflection | 768 | 58 s | 59 s | 11 s | 6 s |
| 10_motion_blur | 540 | 6 s | 10 s | 9 s | 4 s |
| 11_chase_camera | 1320 | 15 s | 24 s | 15 s | 12 s |
| 12_motion_blur | — | falla | falla | falla | falla |
| total 01–11 | 10 242 | 492 s | 547 s | 138 s | 180 s |

En las demos pesadas de GPU (`02`, `04`, `05`, `08`, `09`) Julia y Python
tardan lo mismo en el M1: el límite es la GPU integrada, de 5 a 10 veces más
lenta que la RX 9070 XT.

## 0 · Reglas de trabajo

- **El objetivo** es que en un M1 funcionen: el render a fichero, la CLI
  `bin/janim` con su daemon y la ventana en vivo.
- **Linux no puede cambiar.** Todo lo específico de macOS va dentro de
  `Sys.isapple()`, y en Linux el código que corre y los frames que salen
  deben ser los mismos que hoy. Al volver a la máquina Linux, se repite allí
  la comparación de frames contra la versión anterior.
- **No hay frames de referencia en el repo.** En Metal muchos bordes cambiarán
  un píxel respecto a Linux, así que una diferencia de bytes no es un fallo.
  Lo que hay que buscar es que algo se vea MAL. Las escenas se miran; un exit 0
  no dice nada de lo que hay en pantalla.
- **Commits solo con permiso de Alex, y nunca push.** Un commit por arreglo,
  en español, que explique el porqué. Ninguna dependencia nueva sin preguntar.
  Solo texto y SVG en git.
- **El orden que sugiero:**
  1. Instalar.
  2. Renderizar a fichero una escena simple.
  3. Probar fórmulas, capas y 3D.
  4. Probar la CLI y el daemon.
  5. Dejar la ventana en vivo para el final: es lo único que falta escribir.

## 1 · Preparar el Mac

- **macOS 14 o posterior.** Janim.py lo exige por su wheel de numpy; Julia no.
- **Julia 1.12 con juliaup**, nativo arm64. El `Manifest.toml` se generó con
  la 1.12.6.
- **Fuentes:** `brew install --cask font-dejavu`. Los ejemplos piden DejaVu
  Sans, y una familia o un peso que falta es un ERROR a propósito, no un
  sustituto silencioso. Algunas demos piden otras fuentes, como
  «Fredoka Expanded»; espera un error con nombre si no están instaladas.
- **LaTeX, opcional, solo para `Tex(…; via = :latex)`:** MacTeX o BasicTeX,
  más `dvisvgm`. Los dos quedan en `/Library/TeX/texbin`. Comprueba que esa
  carpeta está en el `PATH` del proceso, incluido el del daemon, y no solo en
  el de la terminal.
- **ffmpeg, Typst, FreeType, GLFW y wgpu-native** vienen como artefactos de
  Julia, con versión para `aarch64-apple-darwin`. No hace falta Homebrew para
  ellos.

## 2 · Instalar y renderizar a fichero (debería funcionar ya)

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. examples/tutorial/c1_01_basics/01_how_janim_works.jl
```

Lo que el código ya resuelve para macOS:

- **El backend.** `src/backend/wgpu/context.jl:242`, `_instance_backends()`,
  elige Metal en macOS, DX12 en Windows y Vulkan en Linux.
- **La librería nativa.** `Artifacts.toml` trae wgpu-native v24.0.0.1 para
  macOS aarch64, y `src/backend/wgpu/bindings.jl:16-17` abre
  `libwgpu_native.dylib`. Se descarga con `Pkg.instantiate()` y se abre la
  primera vez que se usa.
- **La plataforma de GLFW.** `src/backend/glfw.jl:186` solo decide «no hay
  pantalla» en Linux, y `glfw.jl:250` ya traduce Cocoa a `:cocoa`.
- **La CLI.** `bin/janim` ya pasó una vez por este M1 con el bash 3.2 de
  Apple. Usa:
  - `readlink -f` (`:270`), que necesita macOS 12.3 o posterior;
  - `open` en vez de `xdg-open` (`:301-316`);
  - `nohup` cuando no hay `setsid` (`:336-350`);
  - `lsof` cuando no hay `ss` (`:405-422`).

Lo que espero que falle, por orden de probabilidad:

1. **`JANIM_HEADLESS=1` no funciona en macOS.** Pide el adaptador de CPU de
   Mesa (lavapipe), que en macOS no existe. Sin esa variable se elige la GPU
   integrada del M1: `_choose_adapter` en `context.jl`, debajo de la línea
   280. El error con la lista de adaptadores es el comportamiento correcto.
2. **Un pánico de wgpu-native ABORTA el proceso de Julia** sin stacktrace de
   Julia.
   - Las funciones de wgpu-native que abortan quedaron fuera de los bindings,
     pero Metal tiene aserciones propias que en Vulkan nunca saltaron.
   - Si Julia muere en seco, repite con `JANIM_WGPU_LOG=info` (o `debug`) y
     mira la última llamada.
3. **El ABI de los bindings.** `bindings.jl` se generó midiendo el ABI de C
   en Linux x86_64.
   - macOS arm64 también es LP64, así que espero que todo cuadre.
   - Si salen errores absurdos (campos con basura, estados imposibles),
     compila un C mínimo con el `wgpu.h` del artefacto
     (`~/.julia/artifacts/<hash>/include`) e imprime
     `sizeof`/`offsetof` de las estructuras sospechosas.
   - Los callbacks reciben `WGPUStringView` por valor: en arm64 eso va en
     registros. Si un callback lee basura, sospecha esto.
4. **El slug del driver** (hacia `context.jl:572`) solo da nombre a la
   cabecera `# driver:`. Que un nombre nuevo de Metal no rompa nada al
   renderizar.

Cuando el primer mp4 salga bien, prueba en este orden:

- **Fórmulas:** `examples/tutorial/c1_03_groups_and_text/06_tex_transformations.jl`,
  y con LaTeX `…/04_latex.jl`.
- **Capas y efectos:** `examples/gallery/06_effects.jl` y
  `examples/demo/03_portals.jl`.
- **3D:** `examples/tutorial/c2_03_camera/03_camera_3d.jl` y
  `examples/demo/07_text_mask.jl`.
- **Partículas y Bloom:** `examples/demo/04_lorenz_glow.jl`. Su pie usa
  `motion_blur = 4`, que el motor rechaza en todas las plataformas: quítalo
  para probar, o usa la escena desde el arnés del §6.

Mira el centro de cada Transform, el primer frame y el último:

```bash
ffmpeg -i x.mp4 -vf "select='eq(n,K)'" -vframes 1 fK.png
```

## 3 · Qué puede verse MAL en Metal (y no solo distinto)

- **Rellenos con agujeros o que desaparecen.** El relleno es
  stencil-then-cover (`shaders/stencil.wgsl` y `cover.wgsl`).
  - La curva se recorta con `sample_mask` bajo MSAA ×4.
  - La pasada de cobertura usa un sesgo de profundidad
    (`depthBiasSlopeScale = 1`), y la semántica del sesgo cambia entre APIs.
- **Bordes rectos con muescas o triángulos sueltos.** Los triángulos finos del
  relleno se descartan con un umbral en píxeles de ventana
  (`shaders/inserts/thin_triangle.wgsl`, τ = 2⁻⁹). Se midió en RADV y en
  lavapipe, no en Metal.
- **Trazos de grosor raro:** los `smoothstep` de `shaders/stroke.wgsl`.
- **Capas con el color lavado o cambiado:** el compositor trabaja en luz
  lineal sobre texturas `rgba16float`, y las conversiones sRGB están en
  `shaders/inserts/srgb.wgsl`.
- **Precisión:** naga traduce el WGSL a MSL, y las funciones trascendentes de
  Metal (`pow`, `exp`, `sin`) pueden no dar los mismos bits que Vulkan.
- **Lo que no debería cambiar:** la geometría se calcula en la CPU con
  aritmética de Julia, sin la libm del sistema. Si difiere en el último bit,
  sospecha un `muladd`: el M1 siempre tiene FMA, y LLVM puede fusionar
  distinto según la arquitectura.

## 4 · El daemon y la CLI

```bash
bin/janim daemon start
bin/janim render examples/demo/03_portals.jl -ql -p     # -p abre con `open`
bin/janim frame examples/demo/03_portals.jl 60 f.png -ql
bin/janim ping
bin/janim daemon stop
```

- **El arranque deja su log** en `~/.cache/janim/daemon.log`. Si el daemon
  muere al arrancar, la CLI imprime el final del log.
- **El daemon escucha en `127.0.0.1:7318`.** `JANIM_PORT` lo cambia.
- **`bin/janim check`** usa `ps` y `lsof`. Compruébalo con un daemon vivo y
  con uno huérfano.

## 5 · La ventana en vivo: lo que falta escribir

Hoy `src/backend/wgpu/window.jl:105-116` solo crea la superficie para Wayland
y X11. En macOS da el error «the preview surface on the cocoa platform is not
supported». Los pasos que sugiero:

1. **La estructura C.** `bindings.jl` ya tiene la constante
   `WGPUSType_SurfaceSourceMetalLayer` (línea 367), pero no la estructura.
   Añádela junto a `WGPUSurfaceSourceXlibWindow` (línea ~943), con la misma
   forma:
   `struct WGPUSurfaceSourceMetalLayer; chain::WGPUChainedStruct; layer::Ptr{Cvoid}; end`.
2. **La CAMetalLayer**, con el runtime de Objective-C por `ccall`. Es la
   receta del ejemplo de wgpu-native:
   - `ns_window = glfwGetCocoaWindow(handle)` (de `GLFW_jll.libglfw`);
   - `view = [ns_window contentView]`;
   - `layer = [CAMetalLayer layer]`;
   - `[view setWantsLayer:YES]` y `[view setLayer:layer]`.

   En Julia: `ccall((:objc_getClass, "libobjc"), …)`, `sel_registerName` y
   `objc_msgSend`, con la firma de cada mensaje. En arm64 no hay variantes
   `_fpret`/`_stret`. Antes de pedir `CAMetalLayer`, carga QuartzCore con
   `Libdl.dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore")`,
   o la clase no existirá. La referencia en Python es la rama `darwin` de
   `get_surface_id_from_info` en `wgpu/backends/wgpu_native/_helpers.py`
   (wgpu-py 0.21.0).
3. **Retina.** El presentador ya se configura con `_framebuffer_size` (píxeles
   físicos, `window.jl:229`, `:381`, `:400`): en Retina es el doble que la
   ventana. Pon también `[layer setContentsScale: [ns_window backingScaleFactor]]`,
   o la imagen saldrá borrosa o en un cuarto de la ventana. En la era OpenGL,
   este error dio una ventana negra en este mismo M1.
4. **El formato y el modo.** `window.jl:164-191` lee las capacidades de la
   superficie: en Metal el formato preferido será `bgra8unorm`, que ya se
   maneja, y el modo Fifo existe.
5. **El hilo principal.** Cocoa exige que ventanas y eventos vivan en el hilo
   principal.
   - La preview avanza con `@async` (`src/interactive/live.jl:273`), que corre
     en el hilo 1 y debería valer.
   - Los `Threads.@spawn` del codificador (`backend/video_impl.jl`,
     `wgpu/pipeline.jl:136`) no tocan GLFW.
   - Si la ventana se congela o el proceso muere al abrirla, mira primero si
     alguna llamada a GLFW ocurre fuera del hilo 1.
6. **El parche de Wayland.** `close_context` (`glfw.jl:63-160`) esconde la
   ventana y bombea eventos antes de destruirla, para el temporizador de
   repetición de teclas de GLFW en Wayland. Si en macOS estorba (retrasos al
   cerrar, eventos raros), limítalo a Linux.
7. **El ratón en Retina.** El cursor llega en coordenadas lógicas y el
   framebuffer está en físicas. Si orbitar o arrastrar va al doble o a la
   mitad de velocidad, la mezcla está en `src/interactive/controls.jl`.
8. **Preview desde el daemon.** El daemon arranca con `nohup` y abre la
   ventana desde su proceso. Si `bin/janim preview x.jl` falla pero
   `julia --project=. -e 'using Janim; live("x.jl")'` funciona, la causa es el
   proceso en segundo plano. Prueba a arrancar el daemon en primer plano para
   aislarlo.

Prueba con `bin/janim examples/demo/03_portals.jl`: teclas (espacio, `,`/`.`,
←/→, `[`/`]`, Esc), ratón, redimensionado si aplica, y abrir y cerrar dos
previews seguidas en el mismo daemon.

## 6 · Un instrumento sin Linux: Julia contra Python en el mismo Mac

En Linux (RADV, 640×360 a 10 fps) estas cinco demos dan **frames idénticos
byte a byte** en Janim.jl y en Janim.py, medido el 2026-10-21:

| demo | frames |
|---|---|
| `01_multicam` | 140 |
| `03_portals` | 140 |
| `04_lorenz_glow` | 180 |
| `07_text_mask` | 141 |
| `11_chase_camera` | 220 |

Las otras ya difieren en Linux: la 08 por su texto en pantalla, y las 02, 05,
06 y 09 por causas no investigadas. No las uses para esto. Las dos bibliotecas
compilan el mismo WGSL con wgpu-native v24, así que en el Mac deberían seguir
coincidiendo entre sí.

- **Si coinciden** y se ven bien, es una prueba fuerte de que la ruta de
  Metal es correcta en las dos.
- **Si no coinciden en el Mac** pero sí en Linux, la diferencia está en lo que
  cada una hace distinto en macOS: el código nuevo de plataforma, o las
  fuentes. Python debe buscar fuentes en las mismas carpetas y en el mismo
  orden que FreeTypeAbstraction (ver su `MACOS.md`).

Guarda estos dos arneses fuera del repo. El de Julia:

```julia
# tapf.jl — julia --project=<Janim.jl> tapf.jl ESCENA.jl SALIDA.json
using Janim, SHA
path, out = ARGS
m = Module(:scene); Core.eval(m, :(include(x) = Base.include($m, x)))
include_string(m, read(path, String), path)
taps = String[]; lk = ReentrantLock()
Janim._FRAME_TAP[] = (k, b) -> lock(lk) do; push!(taps, bytes2hex(sha256(b))); end
Base.invokelatest(Janim.Scene, Base.invokelatest(getfield, m, :construct);
    output = joinpath(mktempdir(), "x.mp4"), fps = 10, resolution = (640, 360), progress = false)
write(out, "[" * join(repr.(taps), ", ") * "]")
```

El de Python, con el venv de Janim.py. Las clases son `Multicam`, `Portals`,
`LorenzGlow`, `TextMask` y `ChaseCamera`:

```python
# tapf.py — <Janim.py>/.venv/bin/python tapf.py <Janim.py> ESCENA.py Clase SALIDA.json
import hashlib, importlib.util, json, sys, tempfile
from pathlib import Path
root, path, cls, out = sys.argv[1], Path(sys.argv[2]), sys.argv[3], sys.argv[4]
sys.path.insert(0, root)
spec = importlib.util.spec_from_file_location("scene_under_test", path)
mod = importlib.util.module_from_spec(spec); sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
taps = []
scene = getattr(mod, cls)(output=str(Path(tempfile.mkdtemp()) / "x.mp4"), fps=10,
    resolution=(640, 360), progress=False,
    frame_tap=lambda i, px: taps.append(hashlib.sha256(bytes(px)).hexdigest()))
scene.run()
Path(out).write_text(json.dumps(taps))
```

**Compara las listas frame a frame.** Cada lista se calcula en su propio
proceso, nunca dos renders en uno.

**Determinismo:** la misma escena en dos procesos del Mac debe dar los mismos
frames. Es la propiedad central de Janim y no debería depender de la GPU.
Compruébalo con un par de escenas.

**Otra referencia posible:** Alex puede renderizar PNGs de fotogramas clave en
Linux y pasártelos. No van al repo. Ahí la comparación es a ojo o con una
tolerancia medida, nunca bytes.

## 7 · Lo que no es un problema del Mac

- **El desenfoque de movimiento en vídeo no existe** en ninguna plataforma.
  `Scene` rechaza `motion_blur > 1` y la CLI rechaza `--motion-blur`. Las
  demos 10 y 12 y las lecciones de `c3_05_motion_blur` lo describen y fallan
  igual en Linux.
- **El manual dice «una escena por fichero»,** pero `fichero.jl:nombre`
  funciona.
- **Un aviso de `gaussian-kernel-radius-limit`** en escenas con Bloom grande
  es informativo, no un error.

## 8 · Al terminar

Deja aquí, en este fichero, lo que confirmaste y lo que resultó falso, y en la
sección correspondiente del README cambia «Linux only» por lo que de verdad
funcione, con la versión de macOS y el chip en que se probó.
