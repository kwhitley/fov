shader_type spatial;
render_mode unshaded;

void fragment() {
    // Use camera position to detect which eye - left eye has negative X offset
    if (EYE_OFFSET.x > 0.0) {
        discard;
    }
    ALBEDO = vec3(0.0, 1.0, 1.0);
}
