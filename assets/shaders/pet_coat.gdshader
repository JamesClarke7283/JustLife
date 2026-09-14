shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Original JustLife pet coat. The authored pet models carry flat placeholder
// materials named Fur and Fur_Mark; the game overrides both with this shader
// and blends two natural colours along the pet's own height. Countershading
// (darker back, lighter belly) and the marking zones therefore come from one
// continuous gradient instead of two flat colours meeting at a hard edge.

uniform vec3 primary_color : source_color = vec3(0.42, 0.30, 0.20);
uniform vec3 secondary_color : source_color = vec3(0.93, 0.90, 0.84);
// How far the coat mixes toward the second colour. 0 gives a solid coat;
// 1 gives the full natural gradient.
uniform float gradient_blend : hint_range(0.0, 1.0) = 0.6;
// The marking zones (muzzle, chest, paws, tail tip) are held at or above this
// much of the second colour, so they stay readable through the gradient.
uniform float marking_bias : hint_range(0.0, 1.0) = 0.0;
// The softness of the band where the two colours meet.
uniform float softness : hint_range(0.02, 1.0) = 0.55;
uniform float coat_roughness : hint_range(0.0, 1.0) = 0.88;
// The pet's standing base height and full height in world metres, so the
// gradient is stable across the cat and the dog and follows the pet as it
// moves and turns.
uniform float base_y = 0.16;
uniform float coat_height = 0.3;

varying float world_y;

void vertex() {
    world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
    // 0 at the pet's feet, 1 at the top of its head.
    float height_fraction = clamp((world_y - base_y) / max(coat_height, 0.001), 0.0, 1.0);
    float lower = 0.5 - softness * 0.5;
    float upper = 0.5 + softness * 0.5;
    // Natural countershading: the coat sits at full base colour along the back
    // and blends toward the second colour low on the body, so a dark base with
    // a pale second colour reads as a dark back over a lighter belly.
    float belly = 1.0 - smoothstep(lower, upper, height_fraction);
    // The marking zones (muzzle, chest, paws, tail tip) never fall below their
    // own bias, so a bicolour or tuxedo pet keeps readable markings even when
    // the gradient itself is light.
    float mix_amount = max(belly * gradient_blend, marking_bias);
    ALBEDO = mix(primary_color, secondary_color, clamp(mix_amount, 0.0, 1.0));
    ROUGHNESS = coat_roughness;
    SPECULAR = 0.22;
}
