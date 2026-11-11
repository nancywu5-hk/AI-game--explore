shader_type canvas_item;

uniform float bottom_width = 1.0;
uniform float top_width = 0.5;

void vertex() {
    // Standard perspective trapeze
    // Map UV.y (0 to 1) to a width multiplier
    float w = mix(top_width, bottom_width, UV.y);
    
    // Scale the x-coordinate around the center (0.5)
    // We modify VERTEX data which is simpler for CanvasItem shaders in some cases,
    // but typically for a 2D distortion we might rely on fragment UVs. 
    // However, distortion is best done in Vertex function if we want to change shape.
    
    // Calculate offset from center
    // We rely on the object's local origin being center or managing it via offset.
    // For a simple SubViewportContainer filling screen, VERTEX coordinates are typically pixels.
    // Let's assume standard UV manipulation for texture readout is safer for simply 'squishing' result.
}

void fragment() {
    // To achieve the Star Wars effect, we need to map the screen UVs to a wider UV at bottom and narrower at top.
    
    // Input UV (0,0 is top-left, 1,1 is bottom-right)
    float y = UV.y;
    
    // Calculate the horizontal spread at this vertical position
    // We want the TOP to be narrower (showing wider range of X)
    // We want the BOTTOM to be wider (showing narrower range of X, wait...)
    // Actually, Star Wars text:
    // Top is FAR AWAY -> looks small -> so we see MORE content compressed? No.
    // Top is FAR AWAY -> things are smaller.
    // Bottom is NEAR -> things are bigger.
    
    // We want to transform the screen coordinate (0..1) into the texture coordinate.
    // At y=0 (top), we want to read from a wider range of X? No, we want to compress the texture horizontally.
    // Let's just do a simple inverse trapzoid mapping.
    
    // Width factor: 1.0 at y=1 (bottom), top_width at y=0 (top)
    float current_width = mix(top_width, 1.0, y);
    
    // Center UV.x around 0.5
    float centered_x = UV.x - 0.5;
    
    // Adjust x based on width. If width is 0.5, we want x to cover 1.0 distance when screen covers 0.5. 
    // Wait. If the quad is shrinking, we just modify vertex. 
    // If we are doing this strictly in 2D post-process style:
    
    // To make content look "smaller" (far away) at the top:
    // We need to squeeze the texture horizontally. 
    // So the texture coordinates should span a wider range? 
    // If we display 0..1 texture on a 0.25..0.75 screen space, it looks small.
    // So for a full-screen shader properly displaying into a trapezoid:
    // We need to map screen UV.x to Texture UV.x.
    
    // Let's try a simple mapping:
    // modified_x = centered_x / current_width
    // texture_x = modified_x + 0.5
    
    float modified_x = centered_x / current_width;
    float tex_x = modified_x + 0.5;
    
    // If tex_x is out of bounds [0,1], we clip
    if (tex_x < 0.0 || tex_x > 1.0) {
        COLOR = vec4(0.0);
    } else {
        COLOR = texture(TEXTURE, vec2(tex_x, UV.y));
    }
}
