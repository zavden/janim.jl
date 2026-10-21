// inserts/noise.wgsl — the deterministic noise, the WGSL twin of Julia's
// `_noise_hash`: Wellons' lowbias32 over (pixel, frame, seed), 24 significant
// bits, so the GPU returns THE SAME Float32 the CPU does.
//
// Two things WGSL has to say that GLSL gets for free: a seed is an i32 and
// NEGATIVE half of the time (`_noise_seed` reinterprets a hash), and GLSL's
// `uint(seed)` is a reinterpretation — here it is `bitcast<u32>`, never
// `u32()`, whose result is not promised for negative input; and the
// `seed + 1/2/3` the effects add are summed in u32 through `seed_plus`, which
// is what GLSL's int sum followed by uint() amounts to. The pixel is
// `@builtin(position).xy`: `r + 0.5` for memory row r (quad_common.wgsl).

fn janim_hash32(x_in: u32) -> u32 {
    var x = x_in;
    x = x ^ (x >> 16u);
    x = x * 0x7feb352du;
    x = x ^ (x >> 15u);
    x = x * 0x846ca68bu;
    x = x ^ (x >> 16u);
    return x;
}

fn janim_noise(px: i32, py: i32, frame: i32, seed: i32) -> f32 {
    var h = janim_hash32(bitcast<u32>(seed) ^ 0x9e3779b9u);
    h = janim_hash32(bitcast<u32>(px) + h);
    h = janim_hash32(bitcast<u32>(py) + h);
    h = janim_hash32(bitcast<u32>(frame) + h);
    return f32(h >> 8u) * (1.0 / 16777216.0);
}

fn janim_noise_px(position: vec2<f32>, frame: i32, seed: i32) -> f32 {
    return janim_noise(i32(position.x), i32(position.y), frame, seed);
}

// The noise in STEPS — what to multiply a colour by (see _noise_steps).
fn janim_noise_steps(position: vec2<f32>, frame: i32, seed: i32, levels: i32) -> f32 {
    let L = f32(max(levels, 1));
    return floor(janim_noise_px(position, frame, seed) * L) / L;
}

fn janim_frame_step(frame: i32, every: i32) -> i32 {
    return frame / max(every, 1);
}

// `seed + k` in int, then `uint()`: the sum modulo 2^32
fn seed_plus(seed: i32, k: u32) -> i32 {
    return bitcast<i32>(bitcast<u32>(seed) + k);
}
