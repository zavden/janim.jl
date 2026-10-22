# Janim.jl en Linux · confirmar que el port a Windows no lo cambió · sugerencias para el agente

Escrito el 2026-10-22 en el Windows 11 donde se acaba de terminar el port a
Windows (`WINDOWS.md`, apartado «Resultado»), **sin probar nada en Linux**
desde entonces. La regla del port era que Linux y macOS no cambiaran: todo lo
de Windows va tras `Sys.iswindows()` en Julia y tras `((WIN))` en
`bin/janim`, y el código que corre y los frames que salen en Linux deben ser
los mismos que antes. Este fichero dice dónde mirar para confirmarlo, qué
quedó sin probar en Linux (las líneas de instalación del README) y qué
decidir. Lo que pude comprobar desde aquí (el diff, las fuentes) lleva la
marca «comprobado». Si algo resulta falso, corrígelo en este fichero y di
que lo estaba.

El repo hermano, Janim.py, tiene su propio `LINUX.md`. Las dos bibliotecas
comparten los shaders WGSL, y el único shader común que cambió es el mismo en
las dos (§2). Los arneses de comparación están en el `MACOS.md` de este
repo, §6.

## 0 · Reglas de trabajo

- **El objetivo** es confirmar que en Linux nada cambió: ni el código que
  corre ni los frames. No es un port: si todo coincide, el trabajo es corto.
- **El antes** es el commit `0c63cf3` («WINDOWS.md: sugerencias para portar
  Janim.jl a Windows 11»), el último `main` anterior al port; **el después**
  es `main`. Los 12 commits entre los dos: `git log --oneline 0c63cf3..main`.
- **Windows y macOS no pueden cambiar** desde aquí: no hay máquina donde
  probarlos. Si algo de Linux hay que arreglar, va tras una compuerta de
  Linux, o fuera de toda compuerta solo si es idéntico en los tres.
- **Commits solo con permiso de Alex, y nunca push.** Un commit por arreglo,
  en español, que explique el porqué. Ninguna dependencia nueva sin preguntar.
  Solo texto y SVG en git.
- **No hay frames de referencia en el repo, pero aquí sí hay un antes:** el
  mismo Linux, la misma GPU, el commit `0c63cf3`. La comparación es byte a
  byte (§2), no a ojo.
- **El orden que sugiero:** instalar desde cero con el README (§1), comparar
  frames antes y después (§2), repasar el resto del código común (§3), la CLI
  con su daemon y la ventana (§4), y anotar tiempos (§5).

## 1 · Instalar desde cero: las líneas de Linux del README no se han probado

El README (`### Linux`) da juliaup por `curl`, `dnf` para Fedora y `apt` para
Debian/Ubuntu, escritos sin una máquina Linux delante: los nombres de paquete,
sobre todo los de TeX Live (`texlive-standalone`, `texlive-preview`,
`texlive-dvisvgm`), pueden no existir con ese nombre en la distribución que
tengas. Sigue el README tal cual en un clon limpio, corrige las líneas que
fallen (en los dos idiomas) y pasa el apartado «Check it / Comprobar» que
viene tras las plataformas: `gpu_info()` debe decir `backend = "vulkan"`, el
render de la primera lección debe salir, y la CLI con su daemon también.

`Pkg.instantiate()` precompila Janim con el `include_dependency` nuevo (§3):
si la precompilación falla, es lo primero que mirar.

## 2 · Frames: antes y después, byte a byte

Lo único común que puede mover un píxel es
`src/backend/wgpu/shaders/effects.wgsl`, en `fs_crt`: `grille[col] = 1.0`
(una escritura por índice dinámico, que el compilador de DX12 rechaza) pasó a
un `select` con el mismo valor:

```wgsl
let grille = select(vec3<f32>(1.0 - mask_depth * intensity), vec3<f32>(1.0),
                    vec3<bool>(col == 0, col == 1, col == 2));
```

Lo demás común (§3) no toca ningún frame. Aun así compara más de una demo:
el arnés es barato.

Usa `tapf.jl` del `MACOS.md`, §6 (hashes SHA-256 por frame, 640×360 a 10 fps,
un render por proceso), guardado fuera del repo, con dos clones o un
`git worktree add ../janim_jl-antes 0c63cf3` (cada uno con su propio
`Pkg.instantiate()`; la caché de precompilación es por ruta, no se mezclan).
Para cada demo, una lista de hashes con cada checkout, y compáralas frame a
frame:

- **`06_broadcast`**: es la del CRT, la única con un motivo para cambiar.
  Debe dar la misma lista. Si no, mira el shader: el `select` tiene que dar
  exactamente `1.0` en la franja `col` y `1.0 - mask_depth * intensity` en
  las otras dos.
- **`01_multicam`, `03_portals`, `04_lorenz_glow`, `07_text_mask`,
  `11_chase_camera`**: las cinco que en Linux dan lo mismo en Julia y en
  Python; sirven de control (no tocan el CRT) y, de paso, confirman que las
  dos bibliotecas siguen coincidiendo entre sí tras el port (en Windows, con
  DX12, las cinco siguieron coincidiendo byte a byte).

Una diferencia aquí es un fallo del port, no del driver: misma máquina, mismo
driver, un proceso por render.

## 3 · El resto del código común, fichero por fichero

Todo esto está comprobado en el diff (`git diff 0c63cf3..main -- src bin`);
lo que hace falta en Linux es que corra.

| fichero | cambio | qué comprobar en Linux |
|---|---|---|
| `src/backend/wgpu/shaders/effects.wgsl` | el `select` del CRT | §2 |
| `src/backend/wgpu/pipelines.jl`, `_wgsl` | `include_dependency` del fichero y de cada insert: las constantes `*_WGSL` cocinan los shaders en la caché de precompilación, y sin esto un `.wgsl` editado seguía viejo hasta que algún `.jl` cambiaba | `Pkg.instantiate()` precompila; añadir un comentario a `effects.wgsl` y hacer `using Janim` recompila Janim (en Windows, 20–25 s); los frames no cambian (§2) |
| `src/interactive/daemon.jl`, `_serve` | tras el `split`, `Sys.iswindows() && (parts = [replace(p, '\|' => ' ') for p in parts])`: en Windows el cliente manda los espacios de una ruta como `\|`; `Sys.iswindows()` es constante al compilar, así que en Linux la línea no existe | el daemon contesta igual (§4) |
| `src/backend/wgpu/bindings.jl` | `struct WGPUSurfaceSourceWindowsHWND`, nuevo, tras `WGPUSurfaceSourceMetalLayer` | que cargue |
| `src/backend/wgpu/window.jl` | `platform` admite `:win32`; `create_window` lo acepta; `_create_surface` gana un `elseif plat === :win32` con dos `ccall` (`glfwGetWin32Window` en libglfw y `GetModuleHandleW` en `kernel32`) que no existen en Linux. Julia resuelve el símbolo de un `ccall` la primera vez que esa llamada se ejecuta, no al compilar la función, así que la rama debería ser inerte mientras `gl_platform()` sea `:wayland` o `:x11` | **lo primero que puede fallar en Linux:** abre la ventana en vivo en Wayland y en X11. Si Julia se queja de `glfwGetWin32Window` o de `kernel32` al abrirla, envuelve ese `elseif` en `@static if Sys.iswindows()` (la rama de Cocoa está igual de desprotegida y en Linux nunca molestó, así que no lo espero) |
| `bin/janim` | `WIN` sale de `$OSTYPE` (`linux-gnu` → 0); `_send` (en Linux, `echo "$*" >&3`, como antes), `_is_abs` (en Linux, solo `/*`), `_reply_path` (el campo 2 de la primera línea, como el `awk` de antes); `check` y `finish` leen un sexto campo que en Linux va vacío; `janim_root`, `abs_path`, `_can_see_sockets` y `_classify_daemons` empiezan con un `((WIN)) && …` que en Linux no hace nada; `open_output` gana un caso `MINGW*\|MSYS*\|CYGWIN*`; el `finish` de Linux (TERM, un segundo, KILL) está dentro de un `else` | §4 entera |
| `.gitattributes` | `bin/janim text eol=lf` | nada |
| `README*.md`, `WINDOWS.md` | documentación; las líneas de Linux (§1) | §1 |

Lo que no cambió: `glfw.jl`, `context.jl`, `live.jl`, `scene.jl`, `video.jl`
y todo lo demás.

## 4 · La CLI, el daemon y la ventana

Los tres refactors de `bin/janim` (`_send`, `_is_abs`, `_reply_path`) son de
salida idéntica en Linux, pero son los únicos cambios de ese fichero que
Linux ejecuta, así que pásalo entero, con el daemon arrancado por `setsid`
(la rama de Linux; macOS y Windows van por `nohup`):

```bash
bin/janim daemon start
bin/janim ping; bin/janim daemon status
bin/janim render examples/demo/03_portals.jl -ql -p                       # xdg-open al terminar (_reply_path)
bin/janim render examples/demo/03_portals.jl -qs -o out.mp4 --out_dir /tmp/j   # -o relativa: se une
bin/janim render examples/demo/03_portals.jl -qs -o /tmp/abs.mp4 --out_dir /tmp/j   # absoluta: WARN y gana (_is_abs)
bin/janim frame  examples/demo/03_portals.jl 60 f.png -ql --out_dir /tmp/j
bin/janim render examples/demo/03_portals.jl -s --to 40 -ql --no-tui
bin/janim render examples/demo/03_portals.jl:construct -s --to 10 -qs --no-tui
bin/janim render examples/demo/03_portals.jl -qs -j 2 -o /tmp/farm.mp4
bin/janim render examples/demo/03_portals.jl -qs -t -o /tmp/alpha.mov
bin/janim states examples/demo/03_portals.jl
bin/janim examples/demo/03_portals.jl          # la ventana en caliente: teclas, Esc; otra vez, y Ctrl-C
bin/janim render examples/demo/03_portals.jl   # el panel: ENTER, y otra vez con Ctrl+S (janim.cfg)
bin/janim check
bin/janim daemon stop
```

Para `check` y `finish`, arranca a mano un huérfano en otro puerto
(`nohup julia --project=. -e 'using Janim; Janim.daemon(port = 7400)' &`):
`check` debe listarlo como `orphan … listening` y salir 1, `finish` cerrarlo
y respetar el tuyo, y la cuenta de «closed N orphan daemon(s)» decir 1.

La ventana, en Wayland y en X11 si la máquina tiene los dos. Y la cold
preview sin daemon (`bin/janim preview x.jl` con el daemon parado) sigue
pasando la ruta dentro de `-e "live(\"…\")"`, sin cambios.

**Una decisión de Alex, no tuya:** el protocolo del daemon parte la línea
por blancos, y una ruta con espacios falla en Linux como fallaba en Windows.
En Windows el cliente manda cada espacio como `|` y `_serve` lo devuelve,
los dos tras su compuerta. Quitar las compuertas (una línea en `_send`, otra
en `_serve`) lo arreglaría en Linux y macOS también, a cambio de que un `|`
en una ruta (legal en Unix, no en Windows) dejara de funcionar. Si Alex lo
pide, pruébalo con `mkdir "/tmp/con espacio"` y una escena dentro.

## 5 · Tiempos, para comparar con Windows

En Windows (Ryzen 7 9700X, Radeon RX 9070 XT, DX12, driver 32.0.32015.7029),
un render cada vez, tiempo de reloj del proceso entero (Julia arranca en
4–5 s; Python, ~1 s), medido el 2026-10-21 con `main` en `2a4a530`, a través
de un lanzador que hace `include` del demo y llama a `Scene(construct;
output, fps, resolution)` (así que la 04, 10 y 12 van sin su `motion_blur`
y la 06 sin `encoder_threads = 1`):

| demo | frames | 1080p60 Julia | 1080p60 Python | 720p60 Julia | 720p60 Python |
|---|---:|---:|---:|---:|---:|
| 01_multicam | 840 | 10 s | 7 s | 7 s | 4 s |
| 02_pendulum_glow | 1356 | 18 s | 12 s | 13 s | 9 s |
| 03_portals | 840 | 13 s | 8 s | 10 s | 7 s |
| 04_lorenz_glow | 1080 | 16 s | 61 s | 11 s | 57 s |
| 05_rack_focus | 756 | 11 s | 6 s | 7 s | 3 s |
| 06_broadcast | 1188 | 13 s | 8 s | 9 s | 5 s |
| 07_text_mask | 846 | 12 s | 51 s | 8 s | 54 s |
| 08_light_vs_pigment | 708 | 10 s | 5 s | 8 s | 4 s |
| 09_reflection | 768 | 11 s | 6 s | 9 s | 4 s |
| 10_motion_blur | 540 | 9 s | 4 s | 7 s | 2 s |
| 11_chase_camera | 1320 | 15 s | 12 s | 11 s | 8 s |
| 12_motion_blur | — | falla | falla | falla | falla |

La 12 pide la fuente «Fredoka Expanded», que no estaba instalada. Para
repetirlo aquí, en el mismo orden y nunca dos a la vez, el lanzador:

```julia
# render-demo.jl — julia --project=<Janim.jl> render-demo.jl DEMO.jl OUT.mp4 W H FPS
using Janim
path, out, w, h, fps = ARGS[1], ARGS[2], parse(Int, ARGS[3]), parse(Int, ARGS[4]), parse(Int, ARGS[5])
include(abspath(path))
Scene(construct; output = out, fps = fps, resolution = (w, h))
```

```bash
time julia --project=. render-demo.jl examples/demo/01_multicam.jl /tmp/01.mp4 1920 1080 60
```

Anota la GPU, el driver de Mesa y los tiempos al principio de este fichero,
junto con el resultado del §2.

## 6 · Lo que no es un problema de Linux

- `12_motion_blur` falla por la fuente «Fredoka Expanded»; Alex dijo que se
  ignore, como el desenfoque de movimiento (`04`, `10`, `12`).
- Todo lo que está tras `Sys.iswindows()` y `((WIN))`: no se puede probar
  aquí y no hay que tocarlo.

## 7 · Al terminar

Deja aquí, al principio de este fichero, una sección «Resultado» con la
distribución, la GPU, el driver, lo que coincidió y lo que no (como hacen
`MACOS.md` y `WINDOWS.md`). Si las líneas de Linux del README cambiaron, di
cuáles. Si todo coincide, el port está cerrado en las tres plataformas y Alex
decide el push.
