# Third-party notices

Janim.jl is released under the MIT License (see `LICENSE`). Parts of it are
ported from, or follow closely, the projects below. All of them are
distributed under the MIT License; their copyright notices are reproduced
here, and the MIT permission notice that applies to each of them is the one
at the end of this file.

| Project | What Janim takes from it | Copyright |
|---|---|---|
| [ManimGL](https://github.com/3b1b/manim) | the API and behaviour Janim follows (mobjects, animations, rate functions, paths, layout, the camera frame); the structure of the stroke, fill and surface shaders | Copyright (c) 2020-2023 3Blue1Brown LLC |
| [Manim Community](https://github.com/ManimCommunity/manim) | the colour catalogues in `src/core/palette_catalogs.jl` and the CE palette; the CE spellings of several names | Copyright (c) 2018 3Blue1Brown LLC; Copyright (c) 2024, the Manim Community Developers |
| [isosurfaces](https://github.com/jared-hughes/isosurfaces) | the quadtree isoline tracer of `ImplicitFunction` in `src/core/implicit.jl` | Copyright (c) 2024 Jared Hughes |

Janim also depends on Julia packages (MathTeXEngine, Colors, GeometryBasics,
OrdinaryDiffEqTsit5, ForwardDiff, VideoIO, GLFW and others) and on
wgpu-native, which are installed by the package manager under their own
licenses and are not redistributed here.

## MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
