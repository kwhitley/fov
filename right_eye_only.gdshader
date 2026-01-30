shader_type spatial;
render_mode unshaded;

void fragment() {
    // Use camera position to detect which eye - right eye has positive X offset
    if (EYE_OFFSET.x < 0.0) {
        discard;
    }
    ALBEDO = vec3(1.0, 0.0, 1.0);
}
