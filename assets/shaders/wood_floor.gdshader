shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Original meter-scaled boards. World coordinates keep adjacent cut slabs and
// stair apertures on the same layout, regardless of each BoxMesh's size/UVs.
uniform vec4 wood_color : source_color = vec4(0.811765, 0.662745, 0.494118, 1.0);
varying vec2 floor_position;
varying float top_face;

void vertex() {
    floor_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    top_face = max(NORMAL.y, 0.0);
}

float board_hash(vec2 board) {
    return fract(sin(dot(board, vec2(127.1, 311.7))) * 43758.5453);
}

// Pixel-area coverage for a thin seam; distant views average it instead of
// turning subpixel lines into dark, flickering bands.
float seam_coverage(float distance_to_seam, float half_width, float pixel_width) {
    float radius = max(pixel_width * 0.5, 0.00001);
    return clamp((min(distance_to_seam + radius, half_width)
        - max(distance_to_seam - radius, -half_width)) / (2.0 * radius), 0.0, 1.0);
}

void fragment() {
    vec2 position = floor_position + vec2(5.99, 4.95);
    float row = floor(position.x / 0.30);
    float length_position = position.y + mod(row, 2.0) * 0.83;
    float column = floor(length_position / 1.66);
    vec2 within_board = vec2(mod(position.x, 0.30), mod(length_position, 1.66));
    vec2 footprint = max(fwidth(floor_position), vec2(0.00001));
    float long_seam = seam_coverage(min(within_board.x, 0.30 - within_board.x), 0.0035, footprint.x);
    float end_seam = seam_coverage(min(within_board.y, 1.66 - within_board.y), 0.004, footprint.y);
    float seam = 1.0 - (1.0 - long_seam) * (1.0 - end_seam);
    float seed = board_hash(vec2(row, column));
    float tone = 1.0 + (seed - 0.5) * 0.12;

    // Restrained, uneven fibres along each board; no bitmap/reference artwork.
    float bend = sin(within_board.y * 2.7 + seed * 6.28318) * 1.35
        + sin(within_board.y * 7.1 + seed * 13.0) * 0.17;
    float coarse = sin(within_board.x * 91.0 + bend);
    float fine = sin(within_board.x * 463.0 + bend * 1.9);
    float grain_visibility = 1.0 - smoothstep(0.012, 0.055, max(footprint.x, footprint.y));
    float grain = (coarse * 0.018 + fine * 0.022) * grain_visibility;
    float wood = (tone + grain) * (1.0 - seam * 0.48);
    ALBEDO = wood_color.rgb * mix(1.0, wood, top_face);
    ROUGHNESS = mix(0.80, clamp(0.79 + seam * 0.12 - grain * 0.6, 0.72, 0.93), top_face);
    SPECULAR = 0.30;
}
