struct VSOut {
  @builtin(position) position: vec4f,
  @location(0) coords: vec2f
}

struct Uniforms {
  aspect: f32,
  cam_const: f32,
}
@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@vertex
fn main_vs(@builtin(vertex_index) VertexIndex: u32) -> VSOut {
  const pos = array<vec2f, 4>(vec2f(-1, 1), vec2f(-1, -1), vec2f(1, 1), vec2f(1, -1));
  var vsOut: VSOut;
  vsOut.position = vec4f(pos[VertexIndex], 0.0, 1.0);
  vsOut.coords = pos[VertexIndex];
  return vsOut;
}
struct Ray {
  direction: vec3f,
}
// eye point at (2, 1.5, 2)
// look-at point (0, 0.5, 0)
// up-vector (0, 1, 0)
// camera constant d = uniforms.cam_const

fn get_camera_ray(ipcoords: vec2f) -> Ray {
  const e = vec3f(2, 1.5, 2);
  const p = vec3f(0, 0.5, 0);
  let v = normalize(p - e);
  const u = vec3f(0, 1, 0);
  let d = uniforms.cam_const;

  let b1 = normalize(cross(v, u));
  let b2 = cross(b1, v); // b1 and v are magnitude 1 so their cross is already 1
  
  let x = ipcoords[0];
  let y = ipcoords[1];

  let q = (v)*d + (b1 * x) + (b2 * y);

  var dir = normalize(q);
  return Ray(dir);
}

// the fragment defines the shader function run at each pixel
@fragment
fn main_fs(@location(0) coords: vec2f) -> @location(0) vec4f{
  let ipcoords = vec2f(coords.x*uniforms.aspect*0.5, coords.y*0.5);
  var r = get_camera_ray(ipcoords); 
  return vec4f(r.direction*0.5 + 0.5, 1.0); 
}
