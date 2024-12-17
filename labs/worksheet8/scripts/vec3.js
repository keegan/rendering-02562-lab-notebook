
// Helper to create a vec3 function similar to GLSL
function vec3(x = 0, y = x, z = x) {
    return [x, y, z];
}

// publish 
window.vec3 = vec3;