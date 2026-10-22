# Janim.jl

[English](README.md) · **Español**

Janim es un paquete de Julia para animación matemática que habla el
vocabulario narrado de Manim —`Circle`, `Transform`, `play!`, `next_to!`,
`TextMobject`, `Tex`— sobre un motor propio:

- **Render determinista.** El mismo código da los mismos frames en cada
  ejecución: el reloj es fijo y nada lee la hora del sistema. Eso es lo que
  hace exactas las previsualizaciones, la caché de frames y el render por
  segmentos en paralelo.
- **WebGPU.** El render pasa por wgpu-native, sobre Vulkan (Linux: la GPU o
  la CPU con lavapipe), Metal (macOS) o DX12 (Windows: la GPU o la CPU con
  WARP), sin ventana y sin pantalla.
- **Un compositor por capas** que Manim no tiene: modos de fusión, máscaras de
  verdad con difuminado, desenfoque, bloom, profundidad de campo, efectos de
  editor y una cámara por capa (lupas, imagen dentro de imagen, varias vistas
  3D de un mismo mundo).
- **Texto y fórmulas sin LaTeX**: `Tex("x^2")` se compone en una fracción de
  milisegundo con MathTeXEngine; `via = :latex` y `via = :typst` quedan para
  lo que no cubre.
- **3D** con cámara de cuaterniones, superficies con normales analíticas y
  test de profundidad.
- **Julia dentro de la escena**: integradores de SciML en los updaters,
  animación por gradiente (ForwardDiff) y una granja de procesos para los
  renders largos.
- **Para la terminal y para agentes**: una CLI en bash puro sobre un daemon
  TCP caliente (un frame en milisegundos), `render_frame`/`describe` sin
  ventana, y `llms.txt`.
- **Una ventana en vivo** con Revise: editas el fichero y ves el cambio,
  pausas, avanzas frame a frame, recorres la línea de tiempo.

## Requisitos

- **Linux** con un driver de Vulkan (Mesa RADV, lavapipe u otro), **macOS en
  Apple Silicon**, donde Janim dibuja con Metal (probado en macOS 26.6, Apple
  M1), o **Windows 11**, donde dibuja con DX12 (probado en Windows 11 25H2,
  AMD Radeon RX 9070 XT) y la línea de órdenes corre desde Git Bash (las
  notas del port están en [`WINDOWS.md`](WINDOWS.md)).
- **Julia 1.11 o posterior** (desarrollado con la 1.12).
- Las fuentes que pidan tus escenas. Los ejemplos usan DejaVu Sans.
- Opcional: **`latex` y `dvisvgm`** en el `PATH`, solo para
  `Tex(…; via = :latex)`.

`ffmpeg`, Typst, FreeType y la biblioteca de WebGPU vienen con las
dependencias de Julia.

## Instalación

```bash
git clone https://github.com/<usuario>/Janim.jl.git
cd Janim.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

`Pkg.instantiate()` instala las versiones exactas que registra
`Manifest.toml`, binarios incluidos. Janim todavía no está en el registro
General; para usarlo desde otro entorno, `] dev ruta/a/Janim.jl`. Antes, cada
plataforma necesita sus paquetes.

### Linux

Julia con [juliaup](https://github.com/JuliaLang/juliaup)
(`curl -fsSL https://install.julialang.org | sh`) o de la distribución; los
drivers Vulkan de Mesa y las fuentes DejaVu; y, para `via = :latex`, LaTeX
con la clase `standalone` y `dvisvgm`:

```bash
# Fedora
sudo dnf install mesa-vulkan-drivers dejavu-sans-fonts \
  texlive-latex texlive-standalone texlive-preview texlive-amsmath texlive-amsfonts texlive-xcolor texlive-dvisvgm
# Debian, Ubuntu
sudo apt install mesa-vulkan-drivers fonts-dejavu texlive-latex-extra dvisvgm
```

### macOS

```bash
curl -fsSL https://install.julialang.org | sh      # juliaup
brew install --cask font-dejavu                     # la fuente de los ejemplos, en ~/Library/Fonts
```

`via = :latex` necesita MacTeX o BasicTeX más `dvisvgm`
(`sudo tlmgr install dvisvgm` si falta); los dos quedan en
`/Library/TeX/texbin`, que debe estar en el `PATH`.

### Windows

En PowerShell. Julia viene con juliaup desde winget; Git for Windows trae
Git Bash, desde donde corre `bin/janim`; MiKTeX, que trae `dvisvgm`, es
opcional.

```powershell
winget install -e --id Julialang.Juliaup
winget install -e --id Git.Git
winget install -e --id MiKTeX.MiKTeX      # opcional: Tex(…; via = :latex)
```

Abre un terminal nuevo para que cargue el `PATH`, haz `juliaup add 1.12` y
`juliaup default 1.12` (el `Manifest.toml` se hizo con la 1.12) y ejecuta el
`Pkg.instantiate()` de arriba. Queda un paso más: la biblioteca de WebGPU
viene en un artefacto cuyo tarball de Windows no trae el bit de ejecución, y
`Tar` de Julia lo convierte en un fichero que Windows se niega a cargar
(`could not load library … Acceso denegado`). Concede el permiso una vez por
depot:

```powershell
Get-ChildItem "$env:USERPROFILE\.julia\artifacts" -Recurse -Filter wgpu_native.dll |
  ForEach-Object { icacls $_.FullName /grant "*S-1-1-0:(RX)" }
```

Fuentes: descarga [DejaVu](https://github.com/dejavu-fonts/dejavu-fonts/releases),
selecciona los `.ttf`, clic derecho, *Instalar*. Van a
`%LOCALAPPDATA%\Microsoft\Windows\Fonts`, donde Janim las encuentra. Si
instalaste MiKTeX, abre MiKTeX Console y pon la instalación de paquetes que
falten en *Always* (o ejecuta
`initexmf --set-config-value=[MPM]AutoInstall=1`).

La línea de órdenes es el mismo `bin/janim` que en Linux y macOS, desde
**Git Bash** (el terminal que instala Git for Windows). Desde el clon,
`bin/janim daemon start`, y luego `bin/janim render escena.jl -qm`,
`bin/janim escena.jl` para la ventana en vivo, `bin/janim check` y el resto
como abajo; las rutas pueden llevar espacios y escribirse `C:\…`, `C:/…` o
`/c/…`. Desde PowerShell, sin daemon, `julia --project=. escena.jl`
renderiza y `julia --project=. -e 'using Janim; live(\"escena.jl\")'` abre
la ventana en vivo (PowerShell quiere las comillas interiores escapadas así).

## Una escena mínima

```julia
using Janim

function construct(scene)
    c = Circle(radius = 1.0)
    set_fill!(c; color = YELLOW, opacity = 1.0)
    play!(scene, FadeIn(c; shift = 0.5 * UP); run_time = 0.8)
    play!(scene, Transform(c, Square()); run_time = 1.2)
    wait!(scene, 0.5)
end

if abspath(PROGRAM_FILE) == @__FILE__
    Scene(construct; output = "hello.mp4", fps = 30, resolution = (1280, 720))
end
```

Guárdala como `hello.jl` y renderízala con Julia a secas:

```bash
julia --project=. hello.jl
```

`construct(scene)` es un contrato, no una convención: el daemon, la granja de
render y la ventana en vivo buscan ese nombre en tu fichero.

## La línea de órdenes

`bin/janim` nunca arranca Julia: habla con un daemon que se mantiene
caliente, así que un frame cuesta milisegundos en vez de un arranque de Julia.

```bash
bin/janim daemon start                    # una vez por sesión
bin/janim render hello.jl -ql             # el vídeo, junto a la escena
bin/janim hello.jl                        # la ventana en vivo; Esc o q para salir
bin/janim frame hello.jl 20 f.png -ql     # un solo frame
bin/janim render hello.jl -s              # el último frame, en png
bin/janim daemon stop
```

Un fichero puede tener varias funciones de escena: nombra la que quieres
después de `:` (`bin/janim render escenas.jl:intro -ql`). `bin/janim --help`
muestra el resto de la línea de órdenes.

La opción de calidad fija a la vez la resolución y los fps:

| opción | resolución | fps |
|---|---|---|
| `-qs` | 640×360 | 10 |
| `-ql` | 854×480 | 15 |
| `-qm` | 1280×720 | 30 (por defecto) |
| `-qh` | 1920×1080 | 60 |
| `-qq` | 2560×1440 | 60 |
| `-qk` | 3840×2160 | 60 |

Por defecto se renderiza en la GPU. Con `JANIM_HEADLESS=1` (para el daemon o
para una ejecución de `julia`) se renderiza en la CPU: lavapipe en Linux, WARP
en Windows (macOS no tiene adaptador de CPU).

## Ejemplos

| carpeta | contenido |
|---|---|
| [`examples/tutorial/`](examples/tutorial/README.md) | el curso: fundamentos, a fondo, lo que solo hace Janim y la referencia |
| [`examples/gallery/`](examples/gallery/README.md) | clásicos de Manim y la galería de efectos |
| [`examples/scenes/`](examples/scenes/README.md) | escenas completas: máscaras, fórmulas, 2D y 3D, el compositor |
| [`examples/demo/`](examples/demo/README.md) | demostraciones de capas, cámaras y efectos |

```bash
bin/janim render examples/demo/03_portals.jl -ql
```

Cada lección se explica en los comentarios de su cabecera. El código y sus
comentarios están en inglés, salvo los de las demos; el texto en pantalla de
muchos ejemplos está en español.

## Documentación

- [`docs/src/`](docs/src/index.md): el manual y la referencia de la API (en
  inglés). Se construye con
  `julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'`
  y luego `julia --project=docs docs/make.jl`.
- [`llms.txt`](llms.txt): toda la API en un solo fichero.

## Limitaciones conocidas

- **Windows es nuevo.** El render, la línea de órdenes con su daemon (desde
  Git Bash) y la ventana en vivo funcionan con DX12, comprobado en una sola
  máquina. Los frames son reproducibles dentro de cada ruta (RADV, lavapipe,
  Metal, DX12 o WARP), y las rutas pueden diferir entre sí en un píxel en
  algunos bordes.
- **No hay desenfoque de movimiento en el vídeo.** `Scene` rechaza
  `motion_blur > 1`, y por tanto también la opción `--motion-blur` de la CLI.
  Lo que existe es `render_frame_motion`, que promedia varias exposiciones en
  un solo frame fijo. Las lecciones de
  `examples/tutorial/c3_05_motion_blur/` y las demos `04_lorenz_glow.jl`,
  `10_motion_blur.jl` y `12_motion_blur.jl` todavía describen la versión en
  vídeo; se revisarán.

## Licencia

MIT, ver [`LICENSE`](LICENSE). Janim sigue a ManimGL y a Manim Community y
porta partes de ellos, y del paquete `isosurfaces`, todos con licencia MIT:
sus avisos están en [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
