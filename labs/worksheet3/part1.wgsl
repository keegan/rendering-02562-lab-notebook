struct VSOut {
  @builtin(position) position: vec4f,
  @location(0) coords: vec2f
}

struct Uniforms_f { // float values
  aspect: f32,
  cam_const: f32,
}
struct Uniforms_int { // unsigned int values
  use_linear: u32,
  use_repeat: u32,
}
@group(0) @binding(0) var<uniform> uniforms_f: Uniforms_f;
@group(0) @binding(1) var<uniform> uniforms_int: Uniforms_int;
@group(0) @binding(2) var grass_texture: texture_2d<f32>;

@vertex
fn main_vs(@builtin(vertex_index) VertexIndex: u32) -> VSOut {
  const pos = array<vec2f, 4>(vec2f(-1, 1), vec2f(-1, -1), vec2f(1, 1), vec2f(1, -1));
  var vsOut: VSOut;
  vsOut.position = vec4f(pos[VertexIndex], 0.0, 1.0);
  vsOut.coords = pos[VertexIndex];
  return vsOut;
}

fn texture_nearest(texture: texture_2d<f32>, texcoords:vec2f, repeat:bool) -> vec3f {
  // get dimensions of texture
  let res = textureDimensions(texture);
  // if repeat, we want the texcoords modulo 1.0
  // otherwise, we just clamp the coords between 0 and 1
  let st = select(clamp(texcoords, vec2f(0), vec2f(1)), texcoords - floor(texcoords), repeat);
  let ab = st * vec2f(res);
  let UV = vec2u(ab + 0.5) % res; // get closest texel coords UV
  let texcolor = textureLoad(texture, UV, 0);
  return texcolor.rgb;
}

fn texture_linear(texture: texture_2d<f32>, texcoords:vec2f, repeat:bool) -> vec3f {
  // perform bilinear average of nearst 4 texels (those surrounding the desired point)
  // get dimensions of texture
  let res = textureDimensions(texture);
  let st = select(clamp(texcoords, vec2f(0), vec2f(1)), texcoords - floor(texcoords), repeat);
  let ab = st * vec2f(res);

  // find 4 bounding UV coordinates
  let x1: u32 = u32(ab.x);
  let x2: u32 = u32(ab.x + 1);
  let y1: u32 = u32(ab.y);
  let y2: u32 = u32(ab.y + 1);
  let x1_f = f32(x1);
  let x2_f = f32(x2);
  let y1_f = f32(y1);
  let y2_f = f32(y2);
  let UV11 = vec2u(x1, y1); // round a and b down
  let UV12 = vec2u(x1, y2); // round a down, b up
  let UV22 = vec2u(x2, y2);
  let UV21 = vec2u(x2, y1);
  var texcolor = vec3f(0.0);
  let denom = f32(((x2 - x1) * (y2 - y1)));
  texcolor += textureLoad(texture, UV11, 0).rgb * ((x2_f - ab.x)*(y2_f - ab.y)) / denom;
  texcolor += textureLoad(texture, UV12, 0).rgb * ((x2_f - ab.x)*(ab.y - y1_f)) / denom;
  texcolor += textureLoad(texture, UV21, 0).rgb * ((ab.x - x1_f)*(y2_f - ab.y)) / denom;
  texcolor += textureLoad(texture, UV22, 0).rgb * ((ab.x - x1_f)*(ab.y - y1_f)) / denom;
  return texcolor;
}



// the fragment defines the shader function run at each pixel
@fragment
fn main_fs(@location(0) coords: vec2f) -> @location(0) vec4f{
  let uv = vec2f(coords.x * uniforms_f.aspect* 0.5, coords.y*0.5);
  let use_repeat = uniforms_int.use_repeat != 0;
  let use_linear = uniforms_int.use_linear != 0;
  // if linear, do bilinear aliasing; otherwise use nearest-neighbor
  let color = select(texture_nearest(grass_texture, uv, use_repeat), texture_linear(grass_texture, uv, use_repeat), use_linear); 
  return vec4f(color, 1.0);
}