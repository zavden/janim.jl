// effects.wgsl — the eleven editor effects as one module: GLITCH, CRT, VHS,
// COLOR, PIXELATE, VIGNETTE, GRAIN, CHROMA, SHARPEN, WAVE and EDGE, each a
// fragment over the shared quad. Where WGSL differs from the usual shader
// idioms it is written where it matters: `mod(x, 3)` as `x − 3·floor(x/3)`,
// the grille's dynamic index on a `var`, the pixel from `position`,
// `bitcast<u32>` of the seed and its `+1/+2/+3` in u32 (noise.wgsl), every
// sample through `textureSampleLevel` because CRT and VHS return before they
// sample. The parameters come from P (quad_common.wgsl):
//
//   glitch    i0 frame, seed, rate, slices · f0.x intensity · f0.y shift_x · f0.zw block_uv
//   crt       f0 intensity, scanlines, scan_depth, mask_depth · f1 curvature, vignette, roll, out_height
//   vhs       i0.xyz frame, seed, rate · f0 intensity, jitter_x, chroma_x, noise_amt · f1.x head_switch
//   color     f0 brightness, contrast, saturation, hue
//   pixelate  f0.xy cell                             vignette  f0.xyz amount, radius, feather
//   grain     i0 frame, seed, rate, levels · f0.x amount
//   chroma    f0.xy amount                           sharpen   f0.x amount (tex_a Src, tex_b Blurred)
//   wave      f0.xy amp · f0.z k · f0.w phase · f1.xy dir
//   edge      f0.xy step_uv · f0.z amount · i0.x use_color · f1.xyz edge_color
//
// The compositor works in PREMULTIPLIED colour: a channel taken from another
// place arrives multiplied by ITS alpha, so the colour effects unpremultiply
// first and premultiply back (straight.wgsl), or the edges grow dark fringes.

// #INSERT quad_common.wgsl
// #INSERT noise.wgsl
// #INSERT straight.wgsl

const TAU: f32 = 6.28318530718;

// ── Glitch ───────────────────────────────────────────────────────────────

@fragment
fn fs_glitch(in: QuadOut) -> @location(0) vec4<f32> {
    let frame = P.i0.x;
    let seed = P.i0.y;
    let rate = P.i0.z;
    let slices = P.i0.w;
    let intensity = P.f0.x;
    let shift_x = P.f0.y;
    let block_uv = P.f0.zw;
    let t = janim_frame_step(frame, rate);          // held for `rate` frames

    // (1) horizontal bands: a fraction of them slide sideways
    let band = i32(floor(in.uv.y * f32(slices)));
    var off = 0.0;
    if (janim_noise(band, 0, t, seed) < intensity) {
        off = (janim_noise(band, 1, t, seed) * 2.0 - 1.0) * 0.08 * intensity;
    }

    // (2) blocks: a few cells jump harder than their band
    let cell = vec2<i32>(floor(in.uv / block_uv));
    if (janim_noise(cell.x, cell.y, t, seed_plus(seed, 1u)) < 0.06 * intensity) {
        off = off + (janim_noise(cell.x, cell.y, t, seed_plus(seed, 2u)) * 2.0 - 1.0) * 0.15 * intensity;
    }

    // fract, not the sampler's wrap: the wrap belongs to the effect
    let x = fract(in.uv.x + off);

    // (3) RGB separation, on STRAIGHT colour
    let d = shift_x * intensity;
    let cr = sample_a(vec2<f32>(fract(x + d), in.uv.y));
    let cc = sample_a(vec2<f32>(x, in.uv.y));
    let cb = sample_a(vec2<f32>(fract(x - d), in.uv.y));
    let a = max(max(cr.a, cc.a), cb.a);             // channels may leave the silhouette
    let straight = vec3<f32>(unpremult(cr).r, unpremult(cc).g, unpremult(cb).b);
    return vec4<f32>(straight * a, a);              // back to premultiplied
}

// ── CRT and VHS ──────────────────────────────────────────────────────────

@fragment
fn fs_crt(in: QuadOut) -> @location(0) vec4<f32> {
    let intensity = P.f0.x;
    let scanlines = P.f0.y;
    let scan_depth = P.f0.z;
    let mask_depth = P.f0.w;
    let curvature = P.f1.x;
    let vignette = P.f1.y;
    let roll = P.f1.z;
    let out_height = P.f1.w;

    var p = in.uv;
    p.y = fract(p.y + roll);                        // the picture rolls

    // barrel: push points away from the centre by k·r²
    let c = p - vec2<f32>(0.5);
    p = 0.5 + c * (1.0 + curvature * intensity * dot(c, c) * 4.0);
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) {
        return vec4<f32>(0.0);                      // outside the tube
    }
    let s = sample_a(p);

    // scanlines: exactly `scanlines` minima across the height; below ~3
    // pixels per line the pattern fades out instead of aliasing
    let ppl = out_height / max(scanlines, 1.0);
    let scan_ok = smoothstep(1.5, 3.0, ppl);
    let scan = 1.0 - scan_depth * intensity * scan_ok
                   * 0.5 * (1.0 - cos(TAU * p.y * scanlines));

    // aperture grille: a 3-pixel RGB stripe (`mod`, written out)
    let fx = in.position.x;
    let col = i32(fx - 3.0 * floor(fx / 3.0));
    var grille = vec3<f32>(1.0 - mask_depth * intensity);
    grille[col] = 1.0;

    // vignette: 0 at the centre, 1 at the corner (dot(c,c) peaks at ½)
    let vig = 1.0 - vignette * intensity * clamp(dot(c, c) * 2.0, 0.0, 1.0);

    // the dark sync bar at the seam of the roll
    var seam = 1.0;
    if (fract(in.uv.y + roll) < 0.02 && roll != 0.0) {
        seam = 0.25;
    }

    // premultiplied: scaling rgb without alpha darkens WITHOUT changing cover
    return vec4<f32>(s.rgb * (scan * vig * seam) * grille, s.a);
}

@fragment
fn fs_vhs(in: QuadOut) -> @location(0) vec4<f32> {
    let frame = P.i0.x;
    let seed = P.i0.y;
    let rate = P.i0.z;
    let intensity = P.f0.x;
    let jitter_x = P.f0.y;
    let chroma_x = P.f0.z;
    let noise_amt = P.f0.w;
    let head_switch = P.f1.x;
    let t = janim_frame_step(frame, rate);
    let row = i32(in.position.y);

    // (1) the tape wanders line by line
    var j = (janim_noise(0, row, t, seed) * 2.0 - 1.0) * jitter_x * intensity;

    // (2) head switching: the bottom band tears, worse towards the edge
    if (in.uv.y < head_switch) {
        let k = 1.0 - in.uv.y / max(head_switch, 1e-5);
        j = j + (janim_noise(1, row, t, seed) * 2.0 - 1.0) * 0.12 * k * intensity;
    }
    let x = fract(in.uv.x + j);
    let c0 = sample_a(vec2<f32>(x, in.uv.y));

    // When nothing displaces or recolours THIS pixel, the identity BY
    // CONSTRUCTION — the zero dials stay exact no-ops
    if (j == 0.0 && chroma_x == 0.0 && noise_amt * intensity == 0.0) {
        return c0;
    }

    // (3) chroma bleed: the neighbours' COLOUR, my own LUMA
    let base = unpremult(c0);
    var acc = vec3<f32>(0.0);
    var wsum = 0.0;
    for (var i: i32 = -4; i <= 4; i = i + 1) {
        let w = 1.0 - abs(f32(i)) / 5.0;
        acc = acc + unpremult(sample_a(vec2<f32>(fract(x + f32(i) * chroma_x), in.uv.y))) * w;
        wsum = wsum + w;
    }
    let smeared = acc / wsum;
    var straight = clamp(smeared - luma(smeared) + luma(base), vec3<f32>(0.0), vec3<f32>(1.0));

    // (4) tape noise, in exact steps; `t`, not `frame`: `rate` is ONE dial
    straight = straight * (1.0 - noise_amt * intensity * janim_noise_steps(in.position.xy, t, seed_plus(seed, 3u), 8));

    return vec4<f32>(straight * c0.a, c0.a);
}

// ── the cheap family ─────────────────────────────────────────────────────

// Rotation about the grey axis (1,1,1)/√3 — Rodrigues: grey is a fixed point
fn hue_rotate(c: vec3<f32>, a: f32) -> vec3<f32> {
    let k = vec3<f32>(0.5773502691896258);
    let ca = cos(a);
    let sa = sin(a);
    return c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca);
}

@fragment
fn fs_color(in: QuadOut) -> @location(0) vec4<f32> {
    let src = sample_a(in.uv);
    var c = unpremult(src);
    c = c * P.f0.x;                                 // brightness
    c = (c - 0.5) * P.f0.y + 0.5;                   // contrast: 0.5 is the fixed point
    c = mix(vec3<f32>(luma(c)), c, P.f0.z);         // saturation 0 → exact luma
    if (P.f0.w != 0.0) {
        c = hue_rotate(c, P.f0.w);
    }
    c = clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
    return vec4<f32>(c * src.a, src.a);
}

@fragment
fn fs_pixelate(in: QuadOut) -> @location(0) vec4<f32> {
    let cell = P.f0.xy;
    return sample_a((floor(in.uv / cell) + 0.5) * cell);
}

@fragment
fn fs_vignette(in: QuadOut) -> @location(0) vec4<f32> {
    let s = sample_a(in.uv);
    let r = length(in.uv - vec2<f32>(0.5)) * 1.4142135624;   // 0 centre, 1 corner
    let k = 1.0 - P.f0.x * smoothstep(P.f0.y, P.f0.y + max(P.f0.z, 1e-4), r);
    return vec4<f32>(s.rgb * k, s.a);               // premultiplied: scale rgb only
}

@fragment
fn fs_grain(in: QuadOut) -> @location(0) vec4<f32> {
    let s = sample_a(in.uv);
    let n = janim_noise_steps(in.position.xy, janim_frame_step(P.i0.x, P.i0.z), P.i0.y, P.i0.w);
    return vec4<f32>(s.rgb * (1.0 - P.f0.x * n), s.a);
}

@fragment
fn fs_chroma(in: QuadOut) -> @location(0) vec4<f32> {
    let d = (in.uv - vec2<f32>(0.5)) * P.f0.xy;     // radial, zero at the centre
    let cr = sample_a(in.uv + d);
    let cc = sample_a(in.uv);
    let cb = sample_a(in.uv - d);
    let a = max(max(cr.a, cc.a), cb.a);
    // straight colour before mixing channels, or the edges grow dark fringes
    let c = vec3<f32>(unpremult(cr).r, unpremult(cc).g, unpremult(cb).b);
    return vec4<f32>(c * a, a);
}

@fragment
fn fs_sharpen(in: QuadOut) -> @location(0) vec4<f32> {
    let s = sample_a(in.uv);                        // Src
    let b = sample_b(in.uv);                        // Blurred
    let o = s + P.f0.x * (s - b);
    // premultiplied stays valid: rgb never exceeds its own alpha
    return vec4<f32>(clamp(o.rgb, vec3<f32>(0.0), vec3<f32>(max(o.a, 0.0))), clamp(o.a, 0.0, 1.0));
}

@fragment
fn fs_wave(in: QuadOut) -> @location(0) vec4<f32> {
    let s = sin(dot(in.uv, P.f1.xy) * P.f0.z + P.f0.w);
    return sample_a(clamp(in.uv + P.f0.xy * s, vec2<f32>(0.0), vec2<f32>(1.0)));
}

fn lum_at(p: vec2<f32>) -> f32 {
    let c = sample_a(p);
    return luma(unpremult(c)) * c.a;
}

@fragment
fn fs_edge(in: QuadOut) -> @location(0) vec4<f32> {
    let st = P.f0.xy;
    let tl = lum_at(in.uv + st * vec2<f32>(-1.0, 1.0));
    let t = lum_at(in.uv + st * vec2<f32>(0.0, 1.0));
    let tr = lum_at(in.uv + st * vec2<f32>(1.0, 1.0));
    let l = lum_at(in.uv + st * vec2<f32>(-1.0, 0.0));
    let r = lum_at(in.uv + st * vec2<f32>(1.0, 0.0));
    let bl = lum_at(in.uv + st * vec2<f32>(-1.0, -1.0));
    let b = lum_at(in.uv + st * vec2<f32>(0.0, -1.0));
    let br = lum_at(in.uv + st * vec2<f32>(1.0, -1.0));
    let gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
    let gy = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);
    let g = clamp(sqrt(gx * gx + gy * gy) * P.f0.z, 0.0, 1.0);
    if (P.i0.x == 1) {
        return vec4<f32>(P.f1.xyz * g, g);
    }
    let s = sample_a(in.uv);
    return vec4<f32>(s.rgb * g, s.a * g);
}
