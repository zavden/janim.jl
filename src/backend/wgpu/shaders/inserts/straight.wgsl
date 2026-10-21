// inserts/straight.wgsl — the un-premultiply / re-premultiply boilerplate
// every colour effect needs, and Rec.601 luma. The division is guarded
// against alpha = 0.

fn unpremult(c: vec4<f32>) -> vec3<f32> {
    if (c.a > 0.0) {
        return c.rgb / c.a;
    }
    return vec3<f32>(0.0);
}

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}
