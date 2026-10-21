# demo/ — cosas que Janim hace y Manim no puede

Doce escenas cortas (9–23 s, 1280×720) para una demostración: cada una vive
sobre UNA capacidad que ni ManimCE ni ManimGL tienen — el compositor por
capas y todo lo que cuelga de él (máscaras, modos de fusión, efectos, una
cámara por capa) más la física SciML dentro de un updater y una nube de un
millón de partículas.

Los comentarios van en **español**; los identificadores son la API de Janim y
siguen en inglés. **Los textos que se dibujan en pantalla van en inglés**
(rótulos, pies, títulos): es material de demostración, no de estudio.

## Cómo renderizarlas

Desde la raíz del repositorio, cada fichero es una escena completa con su pie:

```bash
julia --project=. examples/demo/03_portals.jl
```

o por el CLI, con el daemon caliente (un frame en ~17 ms, el vídeo entero
sin pagar el arranque de Julia):

```bash
bin/janim render examples/demo/03_portals.jl -qm
bin/janim frame  examples/demo/03_portals.jl 90 f.png -qm
bin/janim preview examples/demo/09_reflection.jl      # la ventana viva
```

**Tres demos no se renderizan: 04, 10 y 12.** Llevan motion blur dentro del
bucle de render en su pie (`motion_blur = 4` en la 04, `motion_blur = 8` en
la 10 y la 12), y el motor no lo admite: `Scene` con `motion_blur > 1` lanza
un error. Se conservan como están, con ese pie, para ver cómo se escribiría;
para obtener un fotograma borroso suelto el motor ofrece `render_frame_motion`,
que promedia sub-fotogramas en la CPU. Quitando `motion_blur` del pie, la 04
se renderiza como exposición simple.

Un aviso que puede salir UNA vez por proceso y no es un error:
`gaussian-kernel-radius-limit`. El kernel del compositor calcula entero hasta
σ = 21 px, y un `Bloom` a 720p pide más en su nivel más ancho (σ, 2σ, 4σ). El
halo sale algo más estrecho de lo pedido y el motor lo DICE en vez de
callarse.

## El índice

| # | fichero | lo que solo Janim puede hacer | dur. |
|---|---|---|---|
| 01 | `01_multicam.jl` | **una cámara por capa**: cuatro vistas del MISMO mundo 3D, cada una con su z-buffer, los updaters corriendo una sola vez. `examples/scenes/11_multicam_views.jl` tal cual. | 14 s |
| 02 | `02_pendulum_glow.jl` | **física SciML en un updater + capa aditiva con Bloom + máscara animada**: el doble péndulo de `examples/scenes/03_field_and_chaos.jl`, sin las líneas de campo y con la rejilla entera; la estela se une con `set_points_smoothly!`, la masa lleva un `GlowDot` detrás (halo redondo por fragmento) y el foco que sigue a la punta es un `crop` con `feather`. | 23 s |
| 03 | `03_portals.jl` | **multicámara con máscaras, en 2D**: una roseta en el centro (la cámara de la escena) y dos lupas ×3 IGUALES a los lados —un círculo y una estrella que GIRA sobre sí misma—, cada una con una cámara que persigue a su punto (updater sobre el `CameraFrame`); la forma del portal es solo la máscara (`window` + `crop`), y por eso puede girar con la imagen quieta. | 14 s |
| 04 | `04_lorenz_glow.jl` | **10⁶ partículas `GlowDots` + `:add` + Bloom** (y, en el pie, motion blur: ver arriba). Es `examples/scenes/10_lorenz_glow.jl` con ese pie. | 14 s |
| 05 | `05_rack_focus.jl` | **profundidad de campo por capa** (`Dof`): cinco fórmulas a cinco profundidades, el foco viaja de la más cercana a la más lejana escribiendo un número; paralaje de propina. | 13 s |
| 06 | `06_broadcast.jl` | **los efectos de editor** (`Glitch`, `CRT` con `roll`, `VHS`, `ColorAdjust`) sobre una fórmula que sigue morfando debajo; cada dial vuelve a un cero que es un no-op exacto. | 20 s |
| 07 | `07_text_mask.jl` | **texto como máscara de un render 3D con luz**: «JANIM» recortando un mar de olas visto por su propia cámara, y el vuelo de cabecera a través de la «I». | 13 s |
| 08 | `08_light_vs_pigment.jl` | **modos de fusión en luz lineal**: R+G+B = blanco con `:add`, C×M×Y = negro con `:multiply`, cada disco en su capa, los de luz en una precomposición con Bloom. | 12 s |
| 09 | `09_reflection.jl` | **un reflejo de verdad**: copia volteada en una capa con `Wave` (fase animada), `Blur`, `opacity` y una `Mask` con `feather` que la apaga con la distancia; luna y estrellas con Bloom, `Vignette` de ajuste. | 13 s |
| 10 | `10_motion_blur.jl` | **motion blur** (`motion_blur = 8, shutter = 0.5`) tal como se escribiría: el estado avanza entre sub-exposiciones, así que la rueda, las órbitas y el barrido de cámara se emborronan por su trayectoria real. No se renderiza: ver arriba. | 9 s |
| 11 | `11_chase_camera.jl` | **persecución y minimapa**: un cometa por un nudo trébol con la principal orbitando, una cámara de PERSECUCIÓN por updater (lo que en CE pide un `ZoomedScene`) y un minimapa cenital en ventana cuadrada; el HUD con `fix_in_frame!` no derrapa. `examples/scenes/12_chase_camera.jl` con diez segundos más de vuelo. | 22 s |
| 12 | `12_motion_blur.jl` | **motion blur**, la variante con el título «Welcome to JANIM» (`motion_blur = 8, shutter = 0.5`). No se renderiza: ver arriba. | — |

## Lo que cuesta verlas bien (y por qué está así)

- **Un disco por capa** (08). Dentro de una misma capa los mobjects se tapan;
  el modo de fusión actúa entre la capa entera y lo de debajo. Si los tres
  discos fueran una sola capa, `:add` no sumaría nada.
- **La máscara no se dibuja; el aro sí** (03, 07). La forma que recorta va
  rellena de blanco y no entra en ninguna capa de contenido; el borde visible
  es OTRO mobject con solo stroke, en una capa por encima.
- **El centro de la caja de una estrella no es su centro** (03). `rotate!`
  gira sobre `get_center` (la caja), que en una estrella de cinco puntas está
  0.2 u por encima del centro real: la estrella orbitaba en vez de girar.
  Colocarla y girarla por `get_real_center_of_mass` (el centroide exacto,
  solo de Janim) lo arregla. Y como `window =` coloca la imagen en la CAJA
  del mobject, una estrella que gira haría bailar la imagen ±0.2 u: la
  ventana de esa capa es un cuadrado fijo que no se dibuja, y la estrella es
  solo la máscara.
- **Una cola del color del trazo no se ve** (03). La `TracingTail` amarilla
  sobre la roseta con degradado desaparecía al pasar por el lóbulo amarillo;
  blanca y más gruesa se lee en las tres vistas.
- **Dos animaciones sobre un mismo mobject se pisan** (07). Cada una escribe
  el estado entero, así que un `FadeOut` y un `animate` a la vez sobre el aro
  dejaban al aro quieto. Un solo `animate` con dos operaciones
  (`(blowup!, 90.0), dim!`) hace las dos cosas.
- **σ tiene un techo honesto**: 0.23 unidades a 720p (21 px). El `Dof` de 05
  pone `max_sigma = 0.23` por eso; pedir 3.0 solo produce el aviso de arriba
  y un blur recortado.
- **Un Bloom recortado hace halos CUADRADOS** (02). El nivel 4σ de la
  pirámide con `sigma = 0.16` pedía 58 px y el kernel lo cortaba a ±63: una
  gaussiana truncada es casi una caja, y una caja separable H+V alrededor de
  un punto brillante es un cuadrado. Sobre un trazo largo no se nota; sobre
  la masa sí. Arreglo doble: `sigma = 0.055` (los tres niveles caben) y un
  `GlowDot` detrás de la masa, que es un halo redondo por fragmento y no
  depende del kernel.
- **El estado inicial ya dibujado** (02). Varilla, masas y foco se colocan en
  la posición del estado inicial ANTES de arrancar el integrador: nada nace en
  el origen para saltar un frame después.
