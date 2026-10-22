# Janim.jl en Windows 11 · sugerencias para el agente

Escrito el 2026-10-21 en el Mac M1 donde se acaba de terminar el port a macOS
(`MACOS.md`), **sin probar nada en Windows**. Son sugerencias, no
instrucciones cerradas: cada punto dice qué espero, dónde mirar y cómo
confirmarlo. Lo que pude comprobar desde aquí (artefactos, cabeceras, código)
lleva la marca «comprobado». Si algo resulta falso, corrígelo en este fichero
y di que lo estaba.

El repo hermano, Janim.py, tiene su propio `WINDOWS.md`. Las dos bibliotecas
comparten los shaders WGSL y la versión mayor de wgpu-native (v24), así que
lo que aprendas en una sirve para la otra. Lee también el `MACOS.md` de este
repo: el port a macOS es el precedente, y la ventana en vivo de Windows se
escribe en el mismo sitio y con la misma forma que la de Cocoa.

## Resultado · 2026-10-21, Windows 11 Home 25H2, Ryzen 7 9700X, Radeon RX 9070 XT, Julia 1.12.7 (juliaup)

**Hechos el §2, el §3, el §4, el §5 y el §6.** Render a fichero, las doce
demos a 720p60 y a 1080p60, la CLI con su daemon bajo Git Bash, la ventana en
vivo con teclas y ratón, y Julia contra Python, comprobados en esta máquina
el 2026-10-21 y el 22 (la ventana, a mano por Alex). Falta la comparación de
frames en Linux y macOS que pide el §0, porque un shader común cambió.

- **§1 · Preparar.** El ID de winget era `Julialang.Juliaup`, no
  `Julia.Julialang` (corregido abajo). juliaup instala la 1.13 por defecto;
  `juliaup add 1.12` y `juliaup default 1.12` dejan la 1.12.7, con la que se
  hizo todo. Git 2.56 con `core.autocrlf=true` sacó `bin/janim` con CRLF,
  como se preveía; el `.gitattributes` nuevo lo evita. DejaVu 2.37 y
  Liberation 2.1.5 instaladas para el usuario, en
  `%LOCALAPPDATA%\Microsoft\Windows\Fonts`.
- **§2 · Instalar y renderizar.** `Pkg.instantiate()` tarda 1:37 (203
  paquetes precompilados; Janim, 25 s). **Lo que no estaba previsto:** el
  primer `julia … 01_how_janim_works.jl` murió con `could not load library
  "…\.julia\artifacts\330a41ac…\lib\wgpu_native.dll" — Acceso denegado`. El
  tarball `WGPU.v24.0.0.1.x86_64-windows.tar.gz` de WGPUNative.jl 0.1.5
  guarda la DLL con modo `-rw-rw-rw-`, sin bit de ejecución; `Tar` de Julia
  en Windows (`extract.jl:109-121`, `chmod` con 0o644) lo traduce a una ACL
  explícita `(R,WA)`, sin ejecución, y `LoadLibrary` falla con error 5. Las
  DLL de BinaryBuilder vienen con 0755 y salen con `(RX,WA)`: de las 57 DLL
  del depot, esta es la única real sin X. El arreglo que documenta el README
  es `icacls <dll> /grant "*S-1-1-0:(RX)"`, una vez por depot. Alternativas:
  reempaquetar el tarball de Windows con 0755 (otro artefacto en
  `Artifacts.toml`) o pedirlo en WGPUNative.jl. Con el permiso, el mp4 sale
  en 7 s (854×480, 114 frames a 30 fps, h264) y se ve bien. Las doce demos
  a 1280×720 y 60 fps salen en 7-13 s cada una (la 12 pide la fuente
  «Fredoka Expanded», no instalada; las 04, 10 y 12 sin su `motion_blur`).
  - **§2.1, confirmado:** `JANIM_HEADLESS=1` funciona: WARP sale como
    «Microsoft Basic Render Driver», `kind = :cpu`, y el mismo mp4 tarda 6 s
    y da otros bytes que la GPU.
  - **§2.2:** ningún pánico.
  - **§2.3:** el ABI cuadra: ni basura en los callbacks ni valores absurdos.
  - **§2.4, falso:** DX12 no da el nombre del vendedor. wgpu-native pone en
    `vendor` la versión del driver («32.0.32015.7029») y deja `description`
    vacía: el slug es `320320157029` (WARP: `100261009711`, la build de
    Windows) y la versión `unknown`, igual que en Janim.py. No rompe nada,
    pero cambia con cada driver; si importa, derivarlo de `vendor_id`.
  - **§2.5, confirmado:** BaseDirs 1.4 (`nt.jl:271`) incluye la carpeta del
    usuario y «DejaVu Sans» se encuentra sin variables.
- **§3 · DX12.** Una cosa se vio MAL, y no por un píxel: FXC no compila
  `effects.wgsl`, que escribía `grille[col] = 1.0` (una componente de `vec3`
  con índice dinámico), y la demo 06 moría al entrar el efecto CRT con
  `X3500: array reference cannot be used as an l-value`. Ahora es un
  `select` con el mismo valor, en las dos bibliotecas. **Ojo:** `_wgsl` lee
  los shaders al precompilar sin `include_dependency`, así que un `.wgsl`
  cambiado solo entra cuando otro `.jl` invalida la caché; la primera prueba
  del arreglo siguió fallando por eso (arreglado el 22, abajo).
- **§4 · Daemon y CLI.** Hecho el 2026-10-22, todo desde Git Bash (Git
  2.56, `uname -s` = `MINGW64_NT-10.0-26200`; ojo, este bash dice
  `$OSTYPE` = `cygwin`, no `msys`: la compuerta `WIN` acepta los dos). Por
  el orden de la lista de abajo:
  1. **Las rutas**, como se preveía: `abs_path` pasa por `cygpath -ma`
     (forma mixta, también para un fichero que no existe; acepta `/c/x`,
     `C:\x` y `C:/x`); la `:escena` de una dirección se separa antes, porque
     cygpath se come los dos puntos (`x.jl:intro` → `x.jlintro`). Bash
     acepta `C:/…` en `[[ -f ]]`, `mkdir -p` y redirecciones, así que
     `janim.cfg`, `--out_dir` y `-o` no necesitan más; `_is_abs` reconoce
     `C:\…` y `C:/…` como absolutas (el aviso de `--out_dir` sale bien).
  2. **`--project`**: MSYS sí convierte `--project=/c/…` (comprobado con
     `Base.active_project()`), pero `janim_root` da la forma mixta igual,
     para no depender de ello.
  3. **`/dev/tcp` funciona**: `_connect3` no cambia.
  4. **`daemon start`** cae en `nohup` y contesta a los 4,4 s. `$!` es el
     pid de bash, no el de Windows (913 frente a WINPID 4440): `kill -0`,
     `wait` y el `kill` del tiempo de espera funcionan sobre él, y ese
     `kill` se lleva al lanzador y al julia real (comprobado); el pidfile lo
     guarda tal cual. **No previsto:** el `julia` del PATH es
     `julialauncher.exe` (winget instala el MSIX de la Store); el lanzador
     lleva en su línea de órdenes el `daemon(port = N)` y arranca el julia
     real como hijo con una línea de órdenes vacía (solo el `.exe`).
  5. **`check` y `finish`**: rama de Windows con una sola llamada a
     PowerShell (≈0,8 s: `Win32_Process` de `julia.exe` y
     `julialauncher.exe`, más `Get-NetTCPConnection -State Listen`), que
     informa del hijo (el que escucha y tiene la memoria) y guarda el
     lanzador como sexto campo para que `finish` lo cierre también, con
     `taskkill /F /T` (no hay TERM). El pid del pidfile se traduce a WINPID
     con `ps -p`. Probado con un huérfano en el 7400 arrancado a mano:
     `check` lo ve y sale 1, `finish` lo cierra y respeta el tuyo.
  6. **`-p`**: `cmd.exe /c start "" "$(cygpath -w ruta)"`, con
     `MSYS2_ARG_CONV_EXCL='*'` delante, igual que el `taskkill /F /T` de
     `finish`: MSYS convierte un `/c` suelto en ruta (`tasklist /FI` llegó
     como `C:/Program Files/Git/FI`) y la variable lo impide. `//c` también
     lo impediría, pero Cygwin, que no convierte nada, se lo pasaría tal cual
     a cmd, que lo ignora y abre un cmd interactivo, y taskkill rechaza
     `//F` (comprobado pasándolos literales desde PowerShell). Como Cygwin
     ignora la variable, el mismo texto sirve en Git Bash, MSYS2 y Cygwin;
     los dos últimos, sin probar aquí (MSYS2 además no hereda el PATH de
     usuario con su `MSYS2_PATH_TYPE=minimal`, así que no encuentra `julia`
     sin `inherit`). WSL no es este port: es un Linux.
  7. **El panel**: sin probar aquí (los lotes no tienen TTY); a probar por
     Alex en Windows Terminal, junto con `preview` cerrada a mano y Ctrl-C.
  8. **El daemon**: ningún cambio salvo uno **no previsto, y el único que
     importa: los espacios.** El protocolo parte la línea por blancos y la
     carpeta de usuario es `C:/Users/Alexander Vazquez`: ninguna orden
     llegaba entera. `_send` (cliente, solo Windows) manda cada espacio de
     un campo como `|`, que ningún nombre Win32 puede contener, y `_serve`
     (daemon, tras `Sys.iswindows()`) los devuelve; `-p` toma la ruta de la
     respuesta hasta el ` (` de la nota. Linux y macOS mandan y reciben la
     línea de antes, con su mismo fallo para rutas con espacios: quitar la
     compuerta es una línea en cada lado, y es decisión de Alex.

  Probado todo por el daemon, en `renders/cli dir/` (con espacio, a
  propósito): `render -ql` (9 s con la compilación de la escena, luego
  menos de 1 s), `-o "03 with spaces.mp4"`, `frame … 60`, `-s --to 40`,
  `x.jl:construct -s --to 10`, `-j 2` (8 s, 140 frames: la granja arranca
  sus julias con `Sys.BINDIR/julia` sin `.exe` y Windows lo encuentra), `-t`
  (ProRes, 46 MB), `-o 'C:\…\abs win.mp4'` con `--out_dir` (avisa y gana la
  absoluta), `states`, `status`, la preview caliente por el socket con tope
  de 3 s, `-p` (abre el reproductor) y `daemon stop` (borra el pidfile).
  `bin/janim` cambia en ramas `((WIN))` y en tres refactors de salida
  idéntica (`_send`, `_is_abs`, `_reply_path`; `check`/`finish` leen un
  sexto campo que en Linux va vacío). **Probado por Alex el 22:** el daemon
  sobrevive a cerrar la ventana de Git Bash que lo arrancó y sigue
  contestando desde una nueva.
- **§5 · La ventana.** Escrita como se preveía: `bindings.jl` gana
  `WGPUSurfaceSourceWindowsHWND`, `_create_surface` la rellena con
  `glfwGetWin32Window` y `GetModuleHandleW`, y `create_window` acepta
  `:win32`. La superficie queda en `BGRA8Unorm` con CopySrc y
  `_framebuffer_size` es `(854, 480)` para una ventana de 854×480. El bucle
  en vivo con `03_portals` a 15 fps presentó 188 frames en 20 s sin
  reconfigurar (los primeros segundos son compilación). **Teclas y ratón:**
  probados a mano por Alex el 2026-10-22: funcionan. Desde el daemon, la
  preview por el socket abre y cierra bien (tope de 3 s); las teclas desde el
  daemon, a probar por Alex.
- **§6 · Julia contra Python.** Hecho con los arneses del `MACOS.md`, a
  640×360 y 10 fps, un proceso por render: las cinco demos dan frames
  **idénticos byte a byte** en DX12 (140, 140, 180, 141 y 220).
- **Lo que no cambió:** `glfw.jl`, `context.jl`, `live.jl`. **Lo común que
  sí cambió:** el `select` del CRT en `effects.wgsl` (§3) y el
  `include_dependency` de los `.wgsl` en `_wgsl` (`pipelines.jl`), que no
  toca ningún frame: editar `effects.wgsl` solo ya recompila Janim (20–25 s,
  comprobado).

## 0 · Reglas de trabajo

- **El objetivo** es que en un Windows 11 funcionen: el render a fichero, la
  CLI `bin/janim` con su daemon y la ventana en vivo, con la GPU de la máquina.
- **Linux y macOS no pueden cambiar.** Todo lo específico de Windows va dentro
  de `Sys.iswindows()`, y en Linux y en macOS el código que corre y los frames
  que salen deben ser los mismos que hoy. Al volver a esas máquinas, se repite
  allí la comparación de frames contra la versión anterior.
- **No hay frames de referencia en el repo.** En DX12 muchos bordes cambiarán
  un píxel respecto a Linux y a Metal, así que una diferencia de bytes no es
  un fallo. Lo que hay que buscar es que algo se vea MAL. Las escenas se
  miran; un exit 0 no dice nada de lo que hay en pantalla.
- **Commits solo con permiso de Alex, y nunca push.** Un commit por arreglo,
  en español, que explique el porqué. Ninguna dependencia nueva sin preguntar.
  Solo texto y SVG en git.
- **El orden que sugiero:**
  1. Instalar y renderizar a fichero desde `julia` (§2): debería funcionar ya.
  2. Probar fórmulas, capas y 3D.
  3. La CLI y el daemon bajo Git Bash (§4): es la parte más larga.
  4. La ventana en vivo (§5): es lo único que falta escribir.
  5. Julia contra Python en la misma máquina (§6).

## 1 · Preparar el Windows

- **Windows 11** (o Windows 10 con DX12). Cualquier GPU con driver WDDM y
  Direct3D 12; sin GPU, DX12 ofrece WARP, el rasterizador por software de
  Microsoft (§2.1).
- **Julia 1.12 con juliaup** (`winget install -e --id Julialang.Juliaup`, y
  luego `juliaup add 1.12` y `juliaup default 1.12`; este fichero decía
  `Julia.Julialang`, que no existe), x86-64. El `Manifest.toml` se generó
  con la 1.12.6.
- **Git for Windows**, por su Git Bash: `bin/janim` es bash y no tiene
  equivalente en PowerShell (§4). Ojo con `core.autocrlf`: si está en `true`
  (el valor por defecto del instalador), `bin/janim` sale con CRLF y bash
  muere con `$'\r': command not found`. Un `.gitattributes` con
  `bin/janim text eol=lf` lo evita; pide permiso, es un fichero nuevo en git.
- **Fuentes:** DejaVu no viene con Windows. Descárgala de
  dejavu-fonts.github.io e instálala «para todos los usuarios»
  (`C:\Windows\Fonts`) o solo para ti (`%LOCALAPPDATA%\Microsoft\Windows\Fonts`).
  FreeTypeAbstraction recorre las dos (§2.5). Algunas demos piden otras
  fuentes, como «Fredoka Expanded»; espera un error con nombre si no están.
- **LaTeX, opcional, solo para `Tex(…; via = :latex)`:** MiKTeX (trae
  `dvisvgm`) o TeX Live, con `latex.exe` y `dvisvgm.exe` en el `PATH` del
  daemon, no solo del terminal. En MiKTeX, pon la instalación de paquetes que
  falten en «siempre», o el primer `Tex` espera un diálogo que nadie ve.
- **ffmpeg, Typst, FreeType, GLFW y wgpu-native** vienen como artefactos de
  Julia. Comprobado en el Mac: `Artifacts.toml` trae wgpu-native v24.0.0.1
  para `x86_64-windows`, y los `Artifacts.toml` de GLFW_jll, FFMPEG_jll y
  Typst_jll del depot tienen entradas `os = "windows"`. No hace falta
  instalar nada de eso a mano.
- **Windows Terminal**: la barra de progreso y el panel de la CLI usan
  secuencias ANSI que el conhost viejo no entiende.

## 2 · Instalar y renderizar a fichero (debería funcionar ya)

```bat
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=. examples\tutorial\c1_01_basics\01_how_janim_works.jl
```

Lo que el código ya resuelve para Windows:

- **El backend.** `src/backend/wgpu/context.jl:242`, `_instance_backends()`,
  elige DX12 en Windows (comprobado). El compilador de shaders queda en
  `WGPUDx12Compiler_Undefined` (`_create_instance`), que en wgpu es FXC
  (`d3dcompiler_47.dll`, viene con Windows); DXC necesitaría `dxcompiler.dll`
  y `dxil.dll`. No lo cambies, y si lo cambias, cámbialo también en Janim.py.
- **La librería nativa.** `src/backend/wgpu/bindings.jl:16` abre
  `wgpu_native.dll` (comprobado) desde el artefacto de `x86_64-windows`.
- **La plataforma de GLFW.** `src/backend/glfw.jl:186` solo decide «no hay
  pantalla» en Linux, `_wayland_env` es solo de Linux, y `gl_platform()` ya
  traduce Win32 a `:win32` (línea 249). GLFW.jl elige `ANY_PLATFORM` fuera de
  Linux y respeta `JULIA_GLFW_PLATFORM=win32`.
- **Las rutas.** `abspath`, `mtime`, `homedir()`, `mktempdir` y la caché de
  LaTeX (`src/text/text.jl:142`, `~/.cache/janim/tex` →
  `C:\Users\<tú>\.cache\janim\tex`) valen en Windows. Las direcciones
  `C:\x.jl:nombre` las corta `_scene_address` en el ÚLTIMO `:` cuyo lado
  izquierdo termina en `.jl`, así que la letra de unidad sobrevive;
  compruébalo.

Lo que espero que falle, por orden de probabilidad:

1. **`JANIM_HEADLESS=1` puede FUNCIONAR aquí**, al contrario que en macOS:
   DX12 enumera WARP («Microsoft Basic Render Driver») y wgpu lo reporta como
   adaptador `:cpu`, que es lo que `_choose_adapter` busca. Si funciona, el
   slug saldrá de `vendor` («Microsoft» → `microsoft`), y los README dejan de
   poder decir que el modo headless es solo de Linux.
2. **Un pánico de wgpu-native ABORTA el proceso de Julia** sin stacktrace. Si
   Julia muere en seco, repite con `JANIM_WGPU_LOG=info` (o `debug`) y mira
   la última llamada.
3. **El ABI de los bindings.** `bindings.jl` se generó midiendo el ABI de C en
   Linux x86_64 (LP64). Windows x64 es LLP64: `long` mide 32 bits. Las
   cabeceras de WebGPU usan tipos de ancho fijo (`uint32_t`, `uint64_t`,
   `size_t`), así que las estructuras deberían cuadrar; el único `Culong` del
   código es el `xid` de X11, que en Windows no se ejecuta. Las convenciones
   de paso difieren (en Win64 una estructura de 16 bytes como
   `WGPUStringView` va por referencia oculta, no en dos registros), pero
   `ccall` y `@cfunction` aplican el ABI de la plataforma: si un callback lee
   basura, sospecha esto y compila un C mínimo con el `wgpu.h` del artefacto
   (`~/.julia/artifacts/<hash>/include`) imprimiendo `sizeof`/`offsetof`.
4. **La identidad del driver** (`driver_slug_wgpu`, `context.jl` hacia la
   línea 572): DX12 da nombres de vendedor («NVIDIA», «Advanced Micro
   Devices, Inc.», «Intel»), así que el slug será `nvidia`,
   `advancedmicrodevicesinc` o `intel`. Que un nombre nuevo no rompa nada en
   la cabecera `# driver:`.
5. **Las fuentes.** FreeTypeAbstraction usa `BaseDirs.fonts()`, que en
   Windows (comprobado en `nt.jl`) es la carpeta `Fonts` del sistema y luego
   `%LOCALAPPDATA%\Microsoft\Windows\Fonts`, sin subcarpetas (la recursión es
   solo para `Sys.isunix() && !Sys.isapple()`). Nada que escribir; comprueba
   que «DejaVu Sans» resuelve a `DejaVuSans.ttf` y no a una `.fon` de mapa de
   bits de `C:\Windows\Fonts` con un nombre de familia parecido.

Cuando el primer mp4 salga bien, prueba en este orden:

- **Fórmulas:** `examples/tutorial/c1_03_groups_and_text/06_tex_transformations.jl`,
  y con LaTeX `…/04_latex.jl`.
- **Capas y efectos:** `examples/gallery/06_effects.jl` y
  `examples/demo/03_portals.jl`.
- **3D:** `examples/tutorial/c2_03_camera/03_camera_3d.jl` y
  `examples/demo/07_text_mask.jl`.
- **Partículas y Bloom:** `examples/demo/04_lorenz_glow.jl`.

Mira el centro de cada Transform, el primer frame y el último:

```bash
ffmpeg -i x.mp4 -vf "select='eq(n,K)'" -vframes 1 fK.png
```

## 3 · Qué puede verse MAL en DX12 (y no solo distinto)

Es la lista del §3 del `MACOS.md`, con lo propio de DX12:

- **Rellenos con agujeros o que desaparecen.** El relleno es
  stencil-then-cover (`shaders/stencil.wgsl` y `cover.wgsl`), con
  `sample_mask` bajo MSAA ×4 y un sesgo de profundidad
  (`depthBiasSlopeScale = 1`) cuya semántica cambia entre APIs.
- **Bordes rectos con muescas o triángulos sueltos.** El umbral de triángulos
  finos (`shaders/inserts/thin_triangle.wgsl`, τ = 2⁻⁹) se midió en RADV y
  lavapipe; en Metal no dio problemas.
- **Precisión:** naga traduce el WGSL a HLSL y FXC lo compila. FXC contrae
  `mul`+`add` en `fma` salvo que el HLSL diga `precise`, y sus `pow`, `exp` y
  `sin` pueden no dar los bits de Vulkan ni de Metal. Es reproducible dentro
  de la ruta; lo que importa es que coincida con Janim.py (§6).
- **Capas con el color lavado:** el compositor trabaja en luz lineal sobre
  `rgba16float` con las conversiones de `shaders/inserts/srgb.wgsl`.
- **Lo que no debería cambiar:** la geometría se calcula en la CPU con
  aritmética de Julia, sin la libm del sistema. En x86-64 no hay FMA
  garantizado, al contrario que en el M1: si un bit difiere respecto a Linux
  en la CPU, sospecha un `muladd` que LLVM fusiona distinto según la CPU.

## 4 · El daemon y la CLI bajo Git Bash

`bin/janim` es «bash puro + /dev/tcp», pensado para Linux y macOS. Bajo Git
Bash (MSYS2) casi todo existe, pero no todo se comporta igual. Pruébalo así:

```bash
bin/janim daemon start
bin/janim render examples/demo/03_portals.jl -ql -p
bin/janim frame examples/demo/03_portals.jl 60 f.png -ql
bin/janim ping
bin/janim check
bin/janim daemon stop
```

Lo que espero, por orden de probabilidad de fallo:

1. **Las rutas que cruzan el socket.** `abs_path` (línea 276) construye
   `$PWD/x.jl`, y en Git Bash `$PWD` es `/c/Users/…`: el daemon, que es un
   Julia de Windows, hará `abspath("/c/Users/…")` → `C:\c\Users\…` y no
   encontrará el fichero. Convierte con `cygpath -m` (forma mixta,
   `C:/Users/…`, que Julia acepta y no lleva barras invertidas que escapar)
   cuando `uname -s` empiece por `MINGW` o `MSYS`. Lo mismo para `-o`, para
   `--out_dir` y para la ruta de `janim.cfg`.
2. **`--project="$root"`.** `janim_root` usa `readlink -f` (existe en Git
   Bash) y da `/c/Users/…`. MSYS convierte automáticamente los argumentos con
   forma `--opción=/ruta` cuando lanza un ejecutable nativo como `julia.exe`;
   compruébalo con `julia --project=/c/… -e 'println(Base.active_project())'`.
   Lo que NO convierte es el texto dentro de `-e "live(\"${scene}\")"`
   (línea 1019, la preview sin daemon): ahí la ruta debe ir ya en forma mixta.
3. **`/dev/tcp`.** El bash de MSYS2 se compila con redirecciones de red, así
   que `exec 3<>/dev/tcp/127.0.0.1/7318` debería funcionar. Compruébalo lo
   primero con un daemon vivo; si no, la CLI entera necesita otro transporte
   (PowerShell o un cliente mínimo en Julia), y eso es una conversación con
   Alex, no un arreglo.
4. **`daemon start`.** No hay `setsid`; cae en la rama de `nohup`, que Git
   Bash sí trae (como en macOS). `kill -0 $pid` funciona sobre un hijo de
   MSYS. El log va a `~/.cache/janim/daemon.log`, que en Git Bash es
   `C:\Users\<tú>\.cache\janim\daemon.log`.
5. **`check` y `finish`.** Usan `ps -eo pid=,rss=,args=` (línea 442) y `ss` o
   `lsof` (línea 410). El `ps` de MSYS no admite `-o`, y ni `ss` ni `lsof`
   existen, así que `_can_see_sockets` será falso y `check` dirá que no puede
   distinguir un daemon vivo de uno muerto. Una rama de Windows podría usar
   `netstat -ano` (PIDs con `LISTENING`) y PowerShell
   (`Get-CimInstance Win32_Process -Filter "Name='julia.exe'"` da la línea de
   comandos, donde está `daemon(port = N)`, y `WorkingSetSize`). `wmic` también
   lo daría, pero Windows 11 lo está retirando.
6. **`-p`.** `open_output` (línea 301) mira `uname -s`: en Git Bash es
   `MINGW64_NT-…`, cae en el caso general, no encuentra ni `xdg-open` ni
   `open` y avisa. Añade un caso `MINGW*|MSYS*)` con
   `cmd.exe /c start "" "$(cygpath -w "$path")"` (o `explorer.exe`).
7. **El panel de la CLI** (`read -rsn2 -t 0.02`, línea 880) funciona en
   mintty y en Windows Terminal con Git Bash; en un pipe no aparece, como
   siempre. `--only-cli` lo salta.
8. **El daemon en sí** (`src/interactive/daemon.jl:492`,
   `listen(IPv4(127, 0, 0, 1), port)`) no usa nada de Unix; Revise funciona
   en Windows. El cortafuegos no pregunta por el loopback.

Una alternativa a medio plazo es un `bin/janim.ps1` que hable el mismo
protocolo de una línea por el socket; antes de escribirlo, haz que Git Bash
funcione: es menos código y sirve de referencia.

## 5 · La ventana en vivo: lo que falta escribir

Hoy `src/backend/wgpu/window.jl` crea la superficie para Wayland, X11 y Cocoa.
En Windows `create_window` dará «the preview surface on the win32 platform is
not supported». Los pasos, calcados de la rama `:cocoa`:

1. **La estructura C.** `bindings.jl` tiene la constante
   `WGPUSType_SurfaceSourceWindowsHWND` (línea 368, comprobado) pero no la
   estructura. Añádela junto a `WGPUSurfaceSourceMetalLayer`:
   `struct WGPUSurfaceSourceWindowsHWND; chain::WGPUChainedStruct; hinstance::Ptr{Cvoid}; hwnd::Ptr{Cvoid}; end`
   (el orden `hinstance`, `hwnd` es el de `webgpu.h`).
2. **Los handles.** `hwnd = ccall((:glfwGetWin32Window, GLFW_jll.libglfw),
   Ptr{Cvoid}, (Ptr{Cvoid},), handle)` y
   `hinstance = ccall((:GetModuleHandleW, "kernel32"), Ptr{Cvoid}, (Ptr{Cvoid},), C_NULL)`
   (en x64 no hay `stdcall` distinto). Una rama `plat === :win32` en
   `_create_surface`, y `create_window` acepta `:win32`.
3. **No hay paso Retina.** GLFW declara el proceso consciente del DPI por
   monitor y, con `GLFW_SCALE_TO_MONITOR` apagado, la ventana nace con el
   tamaño pedido en píxeles: `_framebuffer_size` será `(1280, 720)` y el
   presentador va a 1:1. En una pantalla 4K la ventana se verá pequeña; no es
   un fallo. `_cocoa_sync_scale!` no se llama fuera de `:cocoa`.
4. **El formato y el modo.** `_configure!` lee las capacidades: DX12
   preferirá `BGRA8Unorm` (o su variante sRGB; `_plain_format` maneja las
   dos), Fifo existe y CopySrc suele ofrecerse.
5. **El hilo.** Win32 entrega los mensajes de una ventana al hilo que la
   creó. El playhead va con `@async` en el hilo 1, como la ventana; los
   `Threads.@spawn` del codificador no tocan GLFW. Si la ventana se congela
   al abrirla, mira esto primero.
6. **Bucles modales.** Arrastrar la ventana por el título mete a Windows en
   un bucle modal que detiene `glfwPollEvents` hasta soltar: la preview se
   congela mientras tanto y sigue después. Es normal.
7. **El parche de Wayland** (`_drain_focus!`, `glfw.jl:100`) esconde la
   ventana y bombea antes de destruirla; en Cocoa no estorbó. Si en Windows
   deja la ventana parpadeando o tarda, limítalo a Linux.
8. **Preview desde el daemon.** El daemon arranca con `nohup` desde Git Bash
   y abre la ventana desde su proceso. Si `bin/janim preview x.jl` falla pero
   `julia --project=. -e 'using Janim; live("x.jl")'` funciona, la causa está
   en el §4 (las rutas) o en el proceso en segundo plano.

Prueba con `bin/janim examples/demo/03_portals.jl`: teclas (espacio, `,`/`.`,
←/→, `[`/`]`, Esc), ratón, y abrir y cerrar dos previews seguidas en el mismo
daemon. Al terminar la escena la ventana se queda en el último frame hasta
Esc: no es un cuelgue.

## 6 · Un instrumento sin Linux: Julia contra Python en el mismo Windows

Es el §6 del `MACOS.md`, con los mismos dos arneses (están allí: `tapf.jl` y
`tapf.py`). En Linux (RADV) y en macOS (Metal) las cinco demos `01_multicam`,
`03_portals`, `04_lorenz_glow`, `07_text_mask` y `11_chase_camera` dan frames
idénticos byte a byte en Janim.jl y Janim.py; en Windows, con las dos en DX12,
deberían seguir coincidiendo.

**Lo que aprendimos en macOS.** La 11 difería en los 220 frames porque Python
fusiona mallas consecutivas en un solo `draw_indexed` y Metal interpola el
color iluminado distinto según la llamada que lleva el triángulo; Julia emite
una llamada por malla y no cambió. El arreglo fue del lado de Python
(`_MERGE_MESH_DRAWS`), y si DX12 hace lo mismo, el arreglo vuelve a ser suyo:
está descrito en el `WINDOWS.md` de Janim.py, §8. Si difieren más demos,
sospecha primero las fuentes (§2.5) y después el compilador de shaders (§2).

**Determinismo:** la misma escena en dos procesos de la misma máquina debe
dar los mismos frames. Compruébalo con un par de escenas, y con WARP si el
§2.1 funciona.

## 7 · Lo que no es un problema de Windows

- **El desenfoque de movimiento en vídeo no existe** en ninguna plataforma:
  `Scene` rechaza `motion_blur > 1` y la CLI rechaza `--motion-blur`. Las
  demos 10 y 12 y las lecciones de `c3_05_motion_blur` lo describen y fallan
  igual en Linux y en macOS.
- **El manual dice «una escena por fichero»,** pero `fichero.jl:nombre`
  funciona.
- **Un aviso de `gaussian-kernel-radius-limit`** en escenas con Bloom grande
  es informativo, no un error.

## 8 · WSL2 es un atajo, no el port

La versión de Linux corre tal cual en WSL2 (Ubuntu) con lavapipe
(`JANIM_HEADLESS=1`) y, con WSLg, abre la ventana en Wayland; `bin/janim` y
el daemon funcionan allí sin cambios. La GPU por Vulkan dentro de WSL2
depende del driver `dzn` de Mesa (Vulkan sobre D3D12), experimental. Sirve
para comparar y para desatascarse, no es el objetivo de este fichero: el
objetivo es Windows nativo con DX12.

## 9 · Al terminar

Deja aquí, en este fichero, lo que confirmaste y lo que resultó falso (como
hace el `MACOS.md`, con una sección de resultados al principio), y en la
sección «Known limitations» de los dos README cambia «Linux y macOS» por lo
que de verdad funcione, con la versión de Windows y la GPU en que se probó.
