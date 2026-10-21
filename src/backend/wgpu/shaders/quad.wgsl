// quad.wgsl — the compositor's ten fragments and its two vertices, one
// module: COMB, BLUR, COPY, SATURATE, MASK, BRIGHT, ADD2, DECODE, FINAL and
// ZOOM, plus WINDOW's vertex and fragment. The parameters come from P (quad_common.wgsl), field by field:
//
//   comb     i0.x mode · f0.x opacity              mask     i0.xyz use_luma, invert, hard
//   blur     f0.xy step_uv · i0.x radius · w       bright   f0.x threshold
//   add2     f0.x k                                 final    f0 background · i0.x premult_out
//   zoom     f0.xy center_point · f0.z strength    window   f0 dst (vertex) · f1 src (fragment)
//   copy, saturate, decode   —
//
// SATURATE is `min(tex, 1)`, the Bloom's first pyramid step: ADD2 over a
// cleared halo, `min(0 + 1·B, 1)`, is `min(B, 1)` to the bit, so the clear
// pass is not needed.

// #INSERT quad_common.wgsl
// #INSERT srgb.wgsl

@fragment
fn fs_comb(in: QuadOut) -> @location(0) vec4<f32> {
    let b = sample_a(in.uv);                        // accumulated (premultiplied)
    let s = sample_b(in.uv) * P.f0.x;               // layer × opacity (opacity scales premult, AE)
    let mode = P.i0.x;
    if (mode == 1) {                                // add == plus: premult sum
        return min(b + s, vec4<f32>(1.0));
    }
    var Cb = vec3<f32>(0.0);
    if (b.a > 0.0) {
        Cb = b.rgb / b.a;
    }
    var Cs = vec3<f32>(0.0);
    if (s.a > 0.0) {
        Cs = s.rgb / s.a;
    }
    var B: vec3<f32>;
    if (mode == 2) {
        B = Cb * Cs;
    } else if (mode == 3) {
        B = Cb + Cs - Cb * Cs;
    } else if (mode == 4) {
        B = mix(2.0 * Cb * Cs,
                1.0 - 2.0 * (1.0 - Cb) * (1.0 - Cs),
                step(vec3<f32>(0.5), Cb));
    } else {
        B = Cs;
    }
    // only the COMPLEMENT factors cap, so an alpha above 1 never makes a
    // factor negative
    let sa = min(s.a, 1.0);
    let ba = min(b.a, 1.0);
    let rgb = (1.0 - sa) * b.rgb + (1.0 - ba) * s.rgb + s.a * b.a * B;
    let a = min(s.a + b.a * (1.0 - sa), 1.0);
    return vec4<f32>(rgb, a);
}

@fragment
fn fs_blur(in: QuadOut) -> @location(0) vec4<f32> {
    let step_uv = P.f0.xy;                          // (1/W, 0) horizontal · (0, 1/H) vertical
    let radius = P.i0.x;
    var color = P.w[0][0] * sample_a(in.uv);
    for (var i: i32 = 1; i <= radius; i = i + 1) {
        let w = P.w[i >> 2][i & 3];
        color = color + w * sample_a(in.uv + f32(i) * step_uv);
        color = color + w * sample_a(in.uv - f32(i) * step_uv);
    }
    return color;
}

@fragment
fn fs_copy(in: QuadOut) -> @location(0) vec4<f32> {
    return sample_a(in.uv);
}

@fragment
fn fs_saturate(in: QuadOut) -> @location(0) vec4<f32> {
    return min(sample_a(in.uv), vec4<f32>(1.0));
}

@fragment
fn fs_mask(in: QuadOut) -> @location(0) vec4<f32> {
    let c = sample_a(in.uv);                        // layer (premultiplied)
    let mpx = sample_b(in.uv);                      // mask (premultiplied)
    // luma over premult = alpha·luma(straight): black counts as transparent
    var m = mpx.a;
    if (P.i0.x == 1) {
        m = dot(mpx.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    }
    if (P.i0.y == 1) {
        m = 1.0 - m;
    }
    if (P.i0.z == 1) {
        m = step(0.5, m);
    }
    return c * m;                                   // premult × coverage
}

@fragment
fn fs_bright(in: QuadOut) -> @location(0) vec4<f32> {
    // threshold on the STRAIGHT colour, excess re-premultiplied
    let c = sample_a(in.uv);
    var straight = vec3<f32>(0.0);
    if (c.a > 0.0) {
        straight = c.rgb / c.a;
    }
    let excess = max(straight - P.f0.x, vec3<f32>(0.0)) * c.a;
    return vec4<f32>(excess, max(excess.r, max(excess.g, excess.b)));
}

@fragment
fn fs_add2(in: QuadOut) -> @location(0) vec4<f32> {
    return min(sample_a(in.uv) + P.f0.x * sample_b(in.uv), vec4<f32>(1.0));
}

@fragment
fn fs_decode(in: QuadOut) -> @location(0) vec4<f32> {
    // the entry border: premultiplied sRGB into premultiplied linear; the
    // encoding rides on the straight colour, alpha gets no gamma
    let c = sample_a(in.uv);
    var straight = vec3<f32>(0.0);
    if (c.a > 0.0) {
        straight = clamp(c.rgb / c.a, vec3<f32>(0.0), vec3<f32>(1.0));
    }
    return vec4<f32>(srgb_to_linear(straight) * c.a, c.a);
}

@fragment
fn fs_final(in: QuadOut) -> @location(0) vec4<f32> {
    // the exit border: the over with the DECODED background in linear,
    // inside the shader, then the single OETF; premult_out picks the
    // convention (encoded straight × α) or straight alpha
    let s = sample_a(in.uv);
    let background = P.f0;
    let sa = min(s.a, 1.0);                         // the cap, where it is consumed
    let premult = s.rgb + (1.0 - sa) * background.rgb;
    let alpha = sa + background.a * (1.0 - sa);
    var straight = vec3<f32>(0.0);
    if (alpha > 0.0) {
        straight = premult / alpha;
    }
    let enc = linear_to_srgb(clamp(straight, vec3<f32>(0.0), vec3<f32>(1.0)));
    if (P.i0.x == 1) {
        return vec4<f32>(enc * alpha, alpha);
    }
    return vec4<f32>(enc, alpha);
}

@fragment
fn fs_zoom(in: QuadOut) -> @location(0) vec4<f32> {
    var color = vec4<f32>(0.0);
    let N: i32 = 32;
    for (var i: i32 = 0; i < N; i = i + 1) {
        let t = P.f0.z * f32(i) / f32(N);
        color = color + sample_a(mix(in.uv, P.f0.xy, t));
    }
    return color / f32(N);
}

// The window: the unit quad placed at `dst` (NDC) by the vertex — not
// by the viewport, whose integer coordinates would make an animated window
// jump pixel by pixel — and the fragment samples the `src` crop of the layer
// LINEAR (the bind group carries the linear sampler). Pixels outside the
// quad keep the pass's transparent clear. `dst` is the rect of the video
// route (`_window_dst(…; flip_y = true)`) and y is negated here as in
// vs_quad: the same memory rows, the same uv bits.
@vertex
fn vs_window(@builtin(vertex_index) vertex_index: u32) -> QuadOut {
    let tc = quad_corner(vertex_index);
    let dst = P.f0;                                 // (x0, y0, x1, y1) in NDC
    let p = mix(dst.xy, dst.zw, tc);
    var out: QuadOut;
    out.position = vec4<f32>(p.x, -p.y, 0.0, 1.0);
    out.uv = tc;
    return out;
}

@fragment
fn fs_window(in: QuadOut) -> @location(0) vec4<f32> {
    let src = P.f1;                                 // (u0, v0, u1, v1) in uv
    return sample_a(mix(src.xy, src.zw, in.uv));
}
