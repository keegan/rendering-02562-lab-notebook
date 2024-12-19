struct VSOut {
  @builtin(position) position: vec4f,
  @location(0) coords: vec2f
}

struct UniformsF { // float values
  aspect: f32,
  gamma: f32,
  aperture: f32, // aperture f stop
  fdist: f32, // focus distance
  aperture_rotation: f32 // rotation in degrees
}
struct UniformsInt { // unsigned int values
  canvas_width: u32,
  canvas_height: u32,
  frame_num: u32,
  aperture_shape: u32,
}


// Axis-Aligned Bounding box (box between the points min and max)
struct AABB {
  min: vec3f,
  max: vec3f,
};

struct VertexAttrib {
  pos: vec4f,
  normal: vec4f,
}

struct Material {
  diffuse: vec4f,
  emission: vec4f,
}

@group(0) @binding(0) var<uniform> uniforms_f: UniformsF;
@group(0) @binding(1) var<uniform> uniforms_int: UniformsInt;
// 3x3 jitter, 2 floats (x, y) per point
// rounded up to a multiple of 16 bytes
@group(0) @binding(3) var<uniform> aabb: AABB;

@group(0) @binding(4) var<storage> vert_attribs: array<VertexAttrib>;
@group(0) @binding(6) var<storage> materials: array<Material>; // colors
@group(0) @binding(7) var<storage> vert_indices: array<vec4u>;
@group(0) @binding(8) var<storage> treeIds: array<u32>;
@group(0) @binding(9) var<storage> bspTree: array<vec4u>;
@group(0) @binding(10) var<storage> bspPlanes: array<f32>;

@group(0) @binding(11) var<storage> light_indices: array<u32>;
@group(0) @binding(12) var renderTexture: texture_2d<f32>;
@group(0) @binding(13) var wallTexture: texture_2d<f32>;


@vertex
fn main_vs(@builtin(vertex_index) VertexIndex: u32) -> VSOut {
  const pos = array<vec2f, 4>(vec2f(-1, 1), vec2f(-1, -1), vec2f(1, 1), vec2f(1, -1));
  var vsOut: VSOut;
  vsOut.position = vec4f(pos[VertexIndex], 0.0, 1.0);
  vsOut.coords = pos[VertexIndex];
  return vsOut;
}

struct Ray {
  origin: vec3f,
  direction: vec3f,
  tmin: f32,
  tmax: f32,
}

struct HitInfo {
  hit: bool,
  distance: f32,
  position: vec3f,
  normal: vec3f,
  color_amb: vec3f, // ambient component of color (always on)
  color_diff: vec3f, // diffuse (lambertian) component of color
  color_specular: vec3f, // specular reflectance
  shine: f32, // shininess Phong exponent
  refractive_ratio: f32, // ratio of incident to transmitted refractive index
  shader: u32,
  texcoords: vec2f, // xy coordinates of texture collision point
}
// shader type names:
const shader_reflect: u32 = 2;
const shader_refract: u32 = 3;
const shader_phong: u32 = 4;
const shader_glossy: u32 = 5;
const shader_matte: u32 = 1;
const shader_transparent: u32 = 6;


fn tea(val0: u32, val1: u32) -> u32 {
  const N = 16u;
  var v0 = val1;
  var v1 = val0;
  var s0 = 0u;
  for(var n = 0u; n < N; n ++){
    s0 += 0x9e3779b9;
    v0 += ((v1<<4)+0xa341316c)^(v1+s0)^((v1>>5)+0xc8013ea4); 
    v1 += ((v0<<4)+0xad90777d)^(v0+s0)^((v0>>5)+0x7e95761e); 
  }
  return v0;
}

fn mcg31(prev: ptr<function, u32>) -> u32 {
  const LCG_A = 1977654935u; //  from Hui-Ching Tang [EJOR 2007
  *prev = (LCG_A * (*prev)) & 0x7FFFFFFF;
  return *prev; 
}

// generates pseudo random f32 in range [0, 1)
fn rnd(prev: ptr<function, u32>) -> f32 {
  return f32(mcg31(prev)) / f32(0x80000000);
}

const tex_scale = 3e-3;
// these are all arrays so we can choose the settings
// for the loaded OBJ file
// eye point
// these are in the order bunny, teapot, dragon
const e = vec3f(277, 275.0, -560.0);
// camera constant
const d = 1.0f;
// up vector
const u = vec3f(0, 1, 0);
// look at point
const p = vec3f(277.0, 275.0, 0.0);
// directional light direction
const dir_light_dir = vec3f(-0.3, -0.1, -0.8);

struct Onb { // orthonormal basis for plane
  tangent: vec3f,
  binormal: vec3f,
  normal: vec3f,
};

// use int_plane to find point where camera ray intersects focus plane
fn int_plane_pt(origin: vec3f, raydir: vec3f, plane_point: vec3f, planenormal: vec3f) -> vec3f{
  const plane_color = vec3f(0.1, 0.7, 0.0);

  let omega_dot_n = dot(raydir, planenormal);
  if(abs(omega_dot_n) > 1e-4){
    // make sure that the ray isnt parallel to 
    // the plane (this would lead to a divide by 0 and would never intersect)
    let t = dot((plane_point - origin), planenormal) / omega_dot_n;
    // r(t) = o + t w
    let x = origin + t * raydir;
    return x;
  }
  // shouldnt happen bc the focus plane cant be parallel to camera but for completeness
  return vec3f(0);
}

fn sample_unity_circle(seed: ptr<function, u32>) -> vec2f {
  // first sample on a unit-radius circle
  let theta = rnd(seed) * radians(360f); // radians(360) = 2pi
  let r = sqrt(rnd(seed)) * 0.564189583548; // sqrt(rnd) gives equal distribution across area of circle
  // r is divided by sqrt(pi) ... pi^(-1/2) = 0.564189583548, 
  // so that the area is 1

  let x = r * cos(theta);
  let y = r * sin(theta);

  return vec2f(x, y);
}

fn sample_unity_rect(seed: ptr<function, u32>, aspect: f32, skew: f32) -> vec2f {
  // aspect is the ratio of width : height
  // so aspect = 1 is square
  // aspect = 2 is wider than tall
  // aspect = 0.5 is taller than wide

  // want to be centered at origin so get results on [-1/2, 1/2)
  let x = (rnd(seed) - 0.5) / aspect;
  let y = (rnd(seed) - 0.5) * aspect;

  // rotate by angle skew
  // rotation matrix
  // [ cos(x)   -sin(x) ]
  // [ sin(x)   cos(x)  ]

  let cos_theta = cos(skew);
  let sin_theta = sin(skew);

  let x_rotated = x * cos_theta - y * sin_theta;
  let y_rotated = x * sin_theta + y * cos_theta;

  return vec2f(x_rotated, y_rotated);
}


fn sample_unity_hex(seed: ptr<function, u32>, skew: f32) -> vec2f {
  // choose one of 6 triangles
  let tri_num = floor(rnd(seed) * 6f);
  const shift_r = 0.877382675302; // triangle r 

  // find point in the request triangle, then translate it to have its center at the center 
  // of this segment of the hexagon
  let translation = shift_r * vec2f(
    cos(radians(60.0) * tri_num),
    sin(radians(60.0) * tri_num)
  );
  const skew_factor = radians(60);
  // default triangle points to the right, which in our hexagon is triangle 3
  // so subtract 3 from tri_num to find the # of 60degree rotations needed
  let tri_sample = sample_unity_tri(seed, skew_factor * (tri_num - 3));
  let tri_sample_translated = tri_sample + translation;

  let cos_theta = cos(skew);
  let sin_theta = sin(skew);

  let rotated = vec2f(
    tri_sample_translated.x * cos_theta - tri_sample_translated.y * sin_theta,
    tri_sample_translated.x * sin_theta + tri_sample_translated.y * cos_theta
  );

  const area_scale = 0.40824829046; //sqrt(1/6)

  // translate then scale for whole hexagon to have unity area (each triangle has area 1/6)
  return rotated * area_scale;
}



fn sample_unity_pent(seed: ptr<function, u32>, skew: f32) -> vec2f {
  // choose one of 5 triangles
  let tri_num = floor(rnd(seed) * 5f);
  const shift_r = 0.8196266435; // triangle r (after stretching)

  // find point in the request triangle, then translate it to have its center at the center 
  // of this segment of the pentagon
  // each triangle is 72 degrees offset
  let angle = (radians(72.0) * tri_num) + skew;
  let translation = shift_r * vec2f(
     cos(angle + 3.14159),
    sin(angle + 3.14159)
  );

  // default triangle is equlateral.. so sample at angle 0 then we can stretch x and y before rotating and translating
  let tri_sample = sample_unity_tri(seed, 0.0);
  const stretch_x = 0.934172358963; // cos(36)/cos(30)
  const stretch_y = 1.17557050458; // sin(36 deg)/sin(30)
  let tri_stretched = vec2f(
    tri_sample.x * stretch_x,
    tri_sample.y * stretch_y
  );

  let cos_theta = cos(angle);
  let sin_theta = sin(angle);

  let tri_rotated = vec2f(
    tri_stretched.x * cos_theta - tri_stretched.y * sin_theta,
    tri_stretched.x * sin_theta + tri_stretched.y * cos_theta,
  );

  const area_scale = 0.4472135955; // sqrt(1/5)

  // translate then scale for whole hexagon to have unity area (each triangle has area 1/6)
  return (tri_rotated + translation) * area_scale;
}

fn sample_unity_star(seed: ptr<function, u32>, skew: f32) -> vec2f {
  // we model a pentagram as a pentagon in the middle and 5 triangles around it
  // first find the relative areas of the pentagon vs triangles
  // area of a pentagon is (side-length)^2 * (1/4) * sqrt(5*(5+2sqrt(5)))
  // = (side_length)^2 * 
  // choose one of 5 triangles
  const pent_area_factor = 1.72047740059;
  // pentagon area = side_length^2 * pent_area_factor
  // area of equilateral triangle is
  // sqrt(3)/4 * (side_length)^2
  // so for unity equilateral triangle, side length = sqrt(4/sqrt(3)) = 1.5196713713
  const tri_side_len = 1.5196713713;
  // therefore the total area will be
  // 1.72047740059 * (1.5196713713)^2 + 5(1) --- 5 triangles + 1 pentagon
  const pent_area = pent_area_factor * tri_side_len * tri_side_len;
  const total_area = pent_area + 5;
  let shape_hit = total_area * rnd(seed);

  // just have to scale this correctly 
  // so area of while star is 1
  // of this whole star is 1
  const area_scale = 1.0 / total_area;
  const lin_scale = sqrt(area_scale);

  if(shape_hit < pent_area) {
    // we are inside the pentagon
    let pent_pt = sample_unity_pent(seed, skew);
    const pent_area_scale = pent_area / total_area;
    const lin_pent_scale = -sqrt(pent_area_scale);
    return lin_pent_scale * pent_pt;
  }
  // not inside the pentagon, so pick one of the 5 triangles
  let tri_num = floor(rnd(seed) * 5f);
  // now we need to shift by the apothem of the pentagon + the radius of the triangle 
  // the apothem of a pentagon is 0.688190960236 * side length
  const apothem = tri_side_len * 0.688190960236;
  // apothem of the triangle is its radius * tan(30) = radius *  0.577350269
  const shift_r = ( 0.577350269 * 0.877382675302) + apothem; // triangle r + apothem

  // find point in the request triangle, then translate it to have its center at the center 
  // of this segment of the pentagon
  // each triangle is 72 degrees offset
  let angle = radians(72.0) * tri_num + skew;
  let translation = shift_r * vec2f(
    cos(angle),
    sin(angle)
  );
  // default triangle points to the right, which in our hexagon is triangle 3
  // so subtract 3 from tri_num to find the # of 60degree rotations needed
  let tri_sample = sample_unity_tri(seed, angle);

  // translate then scale for whole hexagon to have unity area (each triangle has area 1/6)
  return (tri_sample + translation) * lin_scale;
}



fn sample_unity_tri(seed: ptr<function, u32>, skew: f32) -> vec2f {
  const r = 0.877382675302; // 2 / sqrt(3 * sqrt(3))
  let q = array<vec2f, 3>(
    vec2f(r, 0),
    vec2f(-r/2, r*sqrt(3)/2),
    vec2f(-r/2, -r*sqrt(3)/2),
  );

  // we use the same technique as for area lights
  let r1 = rnd(seed);
  let r2 = rnd(seed);

  let alpha = 1f - sqrt(r1);
  let beta = (1f - r2) * sqrt(r1);
  let gamma = r2 * sqrt(r1);

  // randomly sampled point on light
  let point = alpha*q[0] + beta*q[1] + gamma*q[2];

  let cos_theta = cos(skew);
  let sin_theta = sin(skew);

  let x_rotated = point.x * cos_theta - point.y * sin_theta;
  let y_rotated = point.x * sin_theta + point.y * cos_theta;

  return vec2f(x_rotated, y_rotated);
}



const apt_circle: u32 = 0;
const apt_sq: u32 = 1;
const apt_tri: u32 = 2;
const apt_hex: u32 = 3;
const apt_star: u32 = 4;
const apt_pent: u32 = 5;
const apt_slit: u32 = 6;


// sample a point on the aperture
// use a uniform sample across the aperture shape
fn sample_aperture_pt(seed: ptr<function, u32>) -> vec2f {
  // f/stop = focal length / aperture diameter
  // taking the camera constant as focal length..
  let aperture_area = 1000.0 * d * d / (uniforms_f.aperture * uniforms_f.aperture);
  
  let angle = radians(uniforms_f.aperture_rotation);

  var unity_sample = vec2f(0);
  switch(uniforms_int.aperture_shape) {
    case apt_circle {unity_sample = sample_unity_circle(seed);}
    // radius * sqrt(pi) for correct area conversion
    case apt_sq {unity_sample= sample_unity_rect(seed, 1.0, angle);}
    case apt_tri {unity_sample= sample_unity_tri(seed, angle);}
    case apt_hex {unity_sample= sample_unity_hex(seed, angle);}
    case apt_star {unity_sample= sample_unity_star(seed, angle);}
    case apt_pent {unity_sample= sample_unity_pent(seed, angle);}
    case apt_slit {unity_sample= sample_unity_rect(seed, 0.3, angle);}
    default {}
  }

  return unity_sample * aperture_area;
}

// using a depth of field model, 
fn get_camera_ray(ipcoords: vec2f, seed: ptr<function, u32>) -> Ray {
  // this code is same as for a pinhole
  // v is the unit vector from eye to look at point (direction were looking)
  let v = normalize(p - e);

  let b1 = normalize(cross(v, u));
  let b2 = cross(b1, v); // b1 and v are magnitude 1 so their cross is already 1
  
  let x = ipcoords[0];
  let y = ipcoords[1];

  let q = (v)*d + (b1 * x) + (b2 * y);
  // this gives direction from pixel to scene.
  var pin_ray_dir = normalize(q);
  
  // now find a ray from a random point in the aperture that intersects the ideal
  // pinhole ray at the plane of focus (because everything should be in focus there)
  // point on aperture for aperture-scene ray
  let apt_pt_xy = sample_aperture_pt(seed);
  // translate x-y coords to xyz
  // aperture is centered around the eye point
  // and perpendicular to the direction of looking (v)
  let apt_pt = e + (apt_pt_xy.x * b2) + (apt_pt_xy.y * b1);
  // find intersection with aperture plane
  let plane_pt = v * uniforms_f.fdist;

  let int_pt = int_plane_pt(e, pin_ray_dir, plane_pt, v);

  // find ray from apt_pt to int_pt then trace it
  let dir = normalize(int_pt - apt_pt);
  // trace a ray from the aperture point, in the direction calculated,
  // into the scene
  return Ray(apt_pt, dir, 1e-9, 1e9);
}

fn int_scene(ray: ptr<function, Ray>,  hit: ptr<function, HitInfo>) -> bool {

  const sphere_1_c = vec3f(490, 50, 80);
  const sphere_2_c = vec3f(350, 50, 0);
  const sphere_3_c = vec3f(400, 50, 150);
  const sphere_4_c = vec3f(320, 50, 400);
  const sphere_r = 50;

  if(int_sphere(*ray, hit, sphere_4_c, sphere_r, shader_reflect)){
    (*ray).tmax = (*hit).distance;
  }
  if(int_sphere(*ray, hit, sphere_3_c, sphere_r, shader_reflect)){
    (*ray).tmax = (*hit).distance;
  }
  if(int_sphere(*ray, hit, sphere_1_c, sphere_r, shader_reflect)){
    (*ray).tmax = (*hit).distance;
  }
  if(int_sphere(*ray, hit, sphere_2_c, sphere_r, shader_reflect)){
    (*ray).tmax = (*hit).distance;
  }

  // check outer binding box
  if(int_aabb(ray)){
    if(int_trimesh(ray, hit)){
      (*ray).tmax = (*hit).distance;
    }
  }

  // textured back wall
  // tangent, binormal, normal
  const bg_plane = Onb(
    vec3f(1, 0, 0),
    vec3f(0, 1, 0),
    vec3f(0, 0, 1),
  );
  let bg_plane_pt = aabb.max + vec3f(0, 0, -1e-2);

  if(int_plane(*ray, hit, bg_plane_pt, bg_plane, shader_reflect)){
    (*ray).tmax = (*hit).distance;
  }

  // textured floor
  const floor_plane = Onb(
    vec3f(1, 0, 0),
    vec3f(0, 0, 1),
    vec3f(0, 1, 0),
  );
  let floor_plane_pt = aabb.min + vec3f(0, 1e-5, 0);

  if(int_plane(*ray, hit, floor_plane_pt, floor_plane, shader_matte)){
    (*ray).tmax = (*hit).distance;
  }

  return (*hit).hit;
}


fn texture_linear(texture: texture_2d<f32>, texcoords:vec2f) -> vec3f {
  // perform bilinear average of nearst 4 texels (those surrounding the desired point)
  // get dimensions of texture
  let res = textureDimensions(texture);
  let st = texcoords - floor(texcoords);
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

fn int_plane(ray: Ray, hit: ptr<function, HitInfo>, plane_point: vec3f, plane: Onb, shader: u32) -> bool{
  const plane_color = vec3f(0.1, 0.7, 0.0);

  let omega_dot_n = dot(ray.direction, plane.normal);
  if(abs(omega_dot_n) > 1e-4){
    // make sure that the ray isnt parallel to 
    // the plane (this would lead to a divide by 0 and would never intersect)
    let t = dot((plane_point - ray.origin), plane.normal) / omega_dot_n;
    if(ray.tmax >= t && ray.tmin <= t){
      // good intersection!
      (*hit).hit = true;
      (*hit).distance = t;
      // r(t) = o + t w
      let x = ray.origin + t * ray.direction;
      (*hit).position = x;
      (*hit).normal = plane.normal;
      (*hit).shader = shader;
      // compute texture coordinates
      // use tex_scale = 0.2

      // find U,V coordinates from orthonormal basis
      let offset = x - plane_point;
      let u = dot(offset, plane.tangent);
      let v = dot(offset, plane.binormal);
      (*hit).texcoords = vec2f(u, v) * tex_scale;


       // get color from texture
      let texture_color = texture_linear(wallTexture, (*hit).texcoords);
      (*hit).color_amb = vec3f(0.0);
      (*hit).color_diff = texture_color;
    }
  }

  return (*hit).hit;
}


fn int_sphere(ray: Ray, hit: ptr<function, HitInfo>, center: vec3f, radius: f32, shade_mode: u32) -> bool {
  const sphere_color = vec3f(0,0,0);
  const refr_exit= 1.5; // ray entering object
  const refr_enter= 0.667; // ray entering object
  // a = w dot w = 1
  // b/2 = poly_half_b = (O-C) dot w
  let dist_from_origin = ray.origin - center;
  let half_b = dot(dist_from_origin, ray.direction);
  // polynomial c = poly_c = (o-c) dot (o-c) - r^2
  let c = dot(dist_from_origin, dist_from_origin) - (radius * radius);
  let desc = (half_b * half_b) - c;
  // if desc < 0 then no intersection occurs
  if(desc < 0){
    return (*hit).hit;
  }
  // we have an intersection. at desc = 0 just one; otherwise 2
  let t = -1 * half_b;
  if(desc <= 1e-4){
    // we graze just tangent to the sphere
    if(ray.tmax >= t && ray.tmin <= t){
      (*hit).color_diff = sphere_color * 0.9;
      (*hit).color_amb = sphere_color * 0.1;
      (*hit).color_specular = vec3f(0.1);
      (*hit).shine = 42;
      (*hit).hit = true;
      (*hit).distance = t;
      // r(t) = o + t w
      let pos = ray.origin + t * ray.direction;
      (*hit).position = pos;
      (*hit).normal = normalize(pos - center);
      (*hit).shader = shade_mode;
      // we hit tangent, so no refraction should occur
      (*hit).refractive_ratio = 1.0;
    }

  } else { // we hit the sphere, but not tangent so we have
  // an entry and exit point. calculate both and find which is closer
    let sqrt_desc = sqrt(desc);
    let t1 = t - sqrt_desc;
    let t2 = t + sqrt_desc;
    if(ray.tmax >= t1 && ray.tmin <= t1){ // if t1 in bounds its always closer
      (*hit).distance = t1;
      (*hit).hit = true;
    } else if (ray.tmax >= t2 && ray.tmin <= t2){
      (*hit).distance = t2;
      (*hit).hit = true;
    }
    if((*hit).hit){
      // r(t) = o + (t * w)
      let pos = ray.origin + ((*hit).distance * ray.direction);
      (*hit).position = pos;

      (*hit).color_amb = sphere_color * 0.1;
      (*hit).color_diff = sphere_color * 0.9;
      (*hit).color_specular = vec3f(0.1);
      (*hit).shine = 42;
      (*hit).normal = normalize((*hit).position - center);
      // we need to see if the selected hit was entering or exiting the sphere
      (*hit).shader = shade_mode;
      (*hit).refractive_ratio = refr_enter;
      // if ray exiting sphere rather than entering, flip refractive
      // ratio and normal direction
      if (dot(ray.direction, (*hit).normal) > 0) {
          (*hit).normal = -(*hit).normal;
          (*hit).refractive_ratio = refr_exit;
      }
    }
    
  }
  return (*hit).hit;
}

fn int_aabb(r: ptr<function, Ray>) -> bool {
  let p1 = (aabb.min - r.origin) / r.direction;
  let p2 = (aabb.max - r.origin) / r.direction;

  let pmin = min(p1, p2);
  let pmax = max(p1, p2);
  let tmin = max(pmin.x, max(pmin.y, pmin.z));
  let tmax = min(pmax.x, min(pmax.y, pmax.z));
  if(tmin > tmax || tmin > r.tmax || tmax < r.tmin){
    // ray doesnt intersect AABB
    return false;
  }
  // ray does intersect, constrain search to AABB
  r.tmin = max(tmin - 1e-3f, r.tmin);
  r.tmax = min(tmax + 1e-3f, r.tmax);
  return true;
}

const MAX_LEVEL = 20u;
const BSP_LEAF = 3u;
var  <private> branch_node: array<vec2u, MAX_LEVEL>; 
var  <private> branch_ray: array<vec2f, MAX_LEVEL>;

fn int_trimesh(ray: ptr<function, Ray>, hit: ptr<function, HitInfo>) -> bool{
  var branch_level = 0u;
  var near_node = 0u;
  var far_node = 0u;
  var t = 0.0f;
  var node = 0u;
  for(var i = 0u; i <= MAX_LEVEL; i ++){
    let tree_node = bspTree[node];
    // if tree_node.x has the 2 least significant bits set
    let node_axis_leaf = tree_node.x &3u;
    if(node_axis_leaf == BSP_LEAF){
      // leaf found
      let node_count = tree_node.x >> 2u;
      let node_id = tree_node.y;
      var found = false;
      for(var j = 0u; j < node_count; j++){
        let obj_idx = treeIds[node_id + j];
        if(int_triangle(*ray, hit, obj_idx)){
          (*ray).tmax = (*hit).distance;
          found = true;
        }
      }
      if(found){ return true;}
      else if(0u == branch_level){
        // traversed whole tree, no intersection
        return false;
      }
      else {
        branch_level --;
        i = branch_node[branch_level].x;
        node = branch_node[branch_level].y;
        (*ray).tmin = branch_ray[branch_level].x;
        (*ray).tmax = branch_ray[branch_level].y;
        continue;
      }
    }
    let axis_direction = (*ray).direction[node_axis_leaf];
    let axis_origin = (*ray).origin[node_axis_leaf];
    if(axis_direction >= 0.0){
      near_node = tree_node.z; // left node
      far_node = tree_node.w; // right
    } else {
      near_node = tree_node.w; // right
      far_node = tree_node.z; // left
    }
    let node_plane = bspPlanes[node];
    var denom = axis_direction;
    if(abs(denom) < 1e-8){
      if(denom < 0){
        denom = -1e-8;
      } else {
        denom = 1e-8;
      }
    }
    t = (node_plane - axis_origin) / denom;
    if(t >= (*ray).tmax){
      node = near_node;
    } else if(t <= (*ray).tmin) {
      node = far_node;
    } else {
      branch_node[branch_level].x = i;
      branch_node[branch_level].y = far_node;
      branch_ray[branch_level].x = t;
      branch_ray[branch_level].y = (*ray).tmax;
      branch_level ++;
      (*ray).tmax = t;
      node = near_node;
    }

  }
  return false;
}

fn int_triangle(ray: Ray, hit: ptr<function, HitInfo>, i: u32) -> bool {
  // verts is a u32 representing the vertices of the triangle 
  let verts = vert_indices[i].xyz;
  let v = array<vec3f, 3>(
    vert_attribs[verts[0]].pos.xyz,
    vert_attribs[verts[1]].pos.xyz,
    vert_attribs[verts[2]].pos.xyz
  );

  let norms = array<vec3f, 3>(
    vert_attribs[verts[0]].normal.xyz,
    vert_attribs[verts[1]].normal.xyz,
    vert_attribs[verts[2]].normal.xyz,
  );

  let e0 = v[1] - v[0];
  let e1 = v[2] - v[0];
  // crude normal for intersection calculation
  let n = cross(e0, e1);
  let omega_dot_n = dot(ray.direction, n);

  if(abs(omega_dot_n) > 1e-8){
    // make sure ray isnt parallel to triangle plane
    let origin_to_v0 = v[0] - ray.origin;
    let t = dot(origin_to_v0, n)/omega_dot_n;
    if(t <= ray.tmax && ray.tmin <= t){
      let partial = cross(origin_to_v0, ray.direction);

      let beta = dot(partial, e1) / omega_dot_n;
      if(beta >= 0){
        let gamma = -dot(partial, e0) / omega_dot_n;
        if(gamma >= 0 && (beta + gamma) <= 1){
          let matIndex = vert_indices[i].w;
          if (matIndex >= arrayLength(&materials)) {
            // Handle invalid material index
            (*hit).color_amb = vec3f(1.0);
          } else {
            let material = materials[matIndex];
            (*hit).color_diff = material.diffuse.rgb;
            (*hit).color_amb = material.emission.rgb;
          }
          (*hit).hit = true;
          (*hit).distance = t;
          // r(t) = o + t w
          (*hit).position = ray.origin + t * ray.direction;
          // find more precise normal for shading based on barycentric coordinates
          // weighted of the vertex normals
          let alpha = 1.0 - (beta + gamma);
          (*hit).normal = normalize(alpha * norms[0] + beta * norms[1] + gamma*norms[2]);
          (*hit).shader = shader_matte;
        }
      }
    }
  }

  return (*hit).hit;
}

struct Light {
  Li: vec3f,
  wi: vec3f,
  dist: f32,
}

// take a random montie-carlo sample of the area light
fn sample_trimesh_light(p: vec3f, seed: ptr<function, u32>) -> Light {
  // take a sample of a random triangle,
  // where the prob of each triangle is
  // that triangle's area out of total area
  let numTriangles = arrayLength(&light_indices);
  var totalArea = 0f;
  for(var i = 0u; i < numTriangles; i ++){
    let idx = light_indices[i];
    let vs = vert_indices[idx].xyz;
    let q = array<vec3f, 3>(
      vert_attribs[vs[0]].pos.xyz,
      vert_attribs[vs[1]].pos.xyz,
      vert_attribs[vs[2]].pos.xyz
    );
    let area = length(cross(q[1]-q[0], q[2]-q[0]));
    totalArea += abs(area);
  }
  let sampled_triangle_area = rnd(seed) * totalArea;
  var sample_idx = 0u;
  var cumulArea = 0f;
  // find which triangle the sampled area corresponds to
  // basically use sampled_triangle_area as the CDF
  // and invert it to find the sampled item
  for(var i = 0u; i < numTriangles; i ++){
    // have to calculate areas again...
    let idx = light_indices[i];
    let vs = vert_indices[idx].xyz;
    let q = array<vec3f, 3>(
      vert_attribs[vs[0]].pos.xyz,
      vert_attribs[vs[1]].pos.xyz,
      vert_attribs[vs[2]].pos.xyz
    );
    let area = length(cross(q[1]-q[0], q[2]-q[0]));
    cumulArea += area;
    if(cumulArea >= sampled_triangle_area){
      sample_idx = i;
      break;
    }
  }
  // get triangle
  let index = light_indices[sample_idx];
  let verts = vert_indices[index].xyz;
  // coords of the 3 corner vertices of light
  let q = array<vec3f, 3>(
    vert_attribs[verts[0]].pos.xyz,
    vert_attribs[verts[1]].pos.xyz,
    vert_attribs[verts[2]].pos.xyz
  );
  // vertex normals
  let norms = array<vec3f, 3>(
    vert_attribs[verts[0]].normal.xyz,
    vert_attribs[verts[1]].normal.xyz,
    vert_attribs[verts[2]].normal.xyz,
  );
  // generate uniformly random barycentric coordinates
  // two random with pdf(x)=1 for 0<=x<1
  let r1 = rnd(seed);
  let r2 = rnd(seed);
  let alpha = 1f - sqrt(r1);
  let beta = (1f - r2) * sqrt(r1);
  let gamma = r2 * sqrt(r1);

  // randomly sampled point on light
  let point = alpha*q[0] + beta*q[1] + gamma*q[2];
  let norm = alpha*norms[0] + beta*norms[1] + gamma*norms[2];

  let e0 = q[1] - q[0];
  let e1 = q[2] - q[0];


  let areaCross = cross(e0, e1);
  // magnitude of vector = sqrt(dot(vector, vector))
  let area = length(areaCross) * 0.5; // area = 1/2 | e0 X e1 |

  // direction from point to light
  var Le = materials[vert_indices[index].w].emission.rgb;

  let dist = distance(p, point);

  let wi = normalize(point - p);
  let Li = dot(-wi, norm) * Le * area * pow(1/dist, 2);;

  return Light(Li, wi, dist);

}


fn check_shadow(pos: vec3f, lightdir: vec3f, lightdist: f32) -> bool{
  var lightray =  Ray(pos, lightdir, 1e-3, lightdist-10e-4);
  var lighthit = HitInfo(false, 0.0, vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), 1.0, 1.0, 0, vec2f(0.0));
  return int_scene(&lightray, &lighthit);
}

fn lambert(r: ptr<function, Ray>, hit: ptr<function, HitInfo>, seed: ptr<function, u32>) -> vec3f {
  var Lr = ((*hit).color_amb / 3.14159);
  let light = sample_trimesh_light((*hit).position, seed);
  // distant area light, so just use one sample point for visibility chekc
  if(!check_shadow((*hit).position, light.wi, light.dist)){
    Lr += ((*hit).color_diff / (3.14159)) * light.Li * max(dot((*hit).normal, light.wi), 0.0);;
  }
  // use ambient light and reflected light
  return Lr;
}

fn phong(r: ptr<function, Ray>, hit: ptr<function, HitInfo>, seed: ptr<function, u32>) -> vec3f {
  let wo = normalize((*r).origin - (*hit).position);
  var Lr = ((*hit).color_amb / 3.14159);

  let light = sample_trimesh_light((*hit).position, seed);
  // see if path to the light intersects an object (ie we are in shadow)
  if(!check_shadow((*hit).position, light.wi, light.dist)){
    let wr = reflect(light.wi, (*hit).normal);
    Lr += 
    light.Li * 
    dot(light.wi, (*hit).normal) *
    (
      ((*hit).color_diff / 3.14159) + 
      (
        (*hit).color_specular * 
        ((*hit).shine + 2) * 0.15915494309 * // 1/2pi = 0.15915494309
        pow(max(dot(wo, wr), 0.0), (*hit).shine)
      )
    );
  }

  

  if(dot(Lr, Lr) < 0.5){
    return vec3f(0);
  }
  return Lr;
}

fn shade_transparent(r: ptr<function, Ray>, hit: ptr<function, HitInfo>, seed: ptr<function, u32>) -> vec3f {
  // case 3 indicates a refractive material. The ray is re-cast but
  // deflected according to the relative indices or refraction
  (*r).origin = (*hit).position; // cast ray from intersection position
  (*r).tmin = 1e-2; // make sure we dont collide with the surface the ray is reflected off
  (*r).tmax = 1e6; // reset tmax b/c casting a new ray
  (*hit).hit = false; // tell iterator to re-trace ray

  let n = (*hit).refractive_ratio;
  // bend the direction by the ratio of refractive indices
  // cos(in) = ( r \cdot n ) / (|r|*|n|)
  let cos_in = -dot((*r).direction, (*hit).normal);
  let sin_sq_in = (1.0 - cos_in * cos_in);
  let sin_sq_out = (n * n) * sin_sq_in;
  let cos_sq_out = 1.0 - sin_sq_out;
  let cos_out = sqrt(cos_sq_out);
  var R = fresnel_R(cos_in, cos_out, n);
  if(cos_sq_out < 0){
    // total internal reflection
    R = 1f;
  }
  let sample = rnd(seed);
  if(sample <= R){
    // reflect case
    (*r).direction = reflect((*r).direction, (*hit).normal); // reflect the incoming ray about the surface normal
    return vec3f(0);
  }
  // refract case
  (*r).direction = 
      (n * (*r).direction) + (n  * cos_in - cos_out) * (*hit).normal;
  return vec3f(0);
}

fn fresnel_R(cos_in: f32, cos_out: f32, index: f32) -> f32 { 
  let r_perp = abs(index * (cos_in - (cos_out / index)) / (index * cos_in + cos_out));
  let r_parallel = abs(index * ((cos_in/index) - cos_out) / (cos_in + index*cos_out));
  let r_perp_sq = r_perp * r_perp;
  let r_par_sq = r_parallel * r_parallel;
  let R = (0.5) * (r_perp_sq + r_par_sq);
  return R;
}

fn shade_refract(r: ptr<function, Ray>, hit: ptr<function, HitInfo>) -> vec3f {
  // case 3 indicates a refractive material. The ray is re-cast but
  // deflected according to the relative indices or refraction
  (*r).origin = (*hit).position; // cast ray from intersection position
  (*r).tmin = 1e-2; // make sure we dont collide with the surface the ray is reflected off
  (*r).tmax = 1e6; // reset tmax b/c casting a new ray
  (*hit).hit = false; // tell iterator to re-trace ray

  let n = (*hit).refractive_ratio;
  // bend the direction by the ratio of refractive indices
  // cos(in) = ( r \cdot n ) / (|r|*|n|)
  let cos_in = dot((*r).direction, (*hit).normal);
  let sin_sq_in = (1.0 - cos_in * cos_in);
  let sin_sq_out = (n * n) * sin_sq_in;
  let cos_sq_out = 1.0 - sin_sq_out;
  if(cos_sq_out < 0){
    // total internal reflection
    (*r).direction = reflect((*r).direction, (*hit).normal); // reflect the incoming ray about the surface normal
    return vec3f(1);
  }
  (*r).direction = 
      (n * (*r).direction) - (n  * cos_in + sqrt(cos_sq_out)) * (*hit).normal;
  return vec3f(0);
}

fn shade(r: ptr<function, Ray>, hit: ptr<function, HitInfo>, seed: ptr<function, u32>) -> vec3f{
  switch (*hit).shader {
    case shader_matte { return lambert(r, hit, seed);}
    case shader_reflect {
      // case 2 indicates a reflective material. we need to re-cast a ray from the reflected position
      // on the intersected surface. this means modifying the ray
      (*hit).hit = false; // tell iterator to re-trace ray
      (*r).origin = (*hit).position; // cast ray from intersection position
      (*r).direction = reflect((*r).direction, (*hit).normal); // reflect the incoming ray about the surface normal
      (*r).tmin = 1e-2; // make sure we dont collide with the surface the ray is reflected off
      (*r).tmax = 1e10;
      return vec3f(0.0);
    } 
    case shader_refract {
      return shade_refract(r, hit);
    }
    case shader_phong {
      return phong(r, hit, seed);
    }
    case shader_glossy {
      return phong(r, hit, seed) + shade_refract(r, hit);
    }
    case shader_transparent {
      return shade_transparent(r, hit, seed);
    }
    //case default { return -(*r).direction;}
    case default {return (*hit).color_diff + (*hit).color_amb;}
  }  
}

struct FSOut {
  @location(0) frame: vec4f,
  @location(1) accum: vec4f,
}

// the fragment defines the shader function run at each pixel
@fragment
fn main_fs(@builtin(position) fragcoord: vec4f, @location(0) coords: vec2f) -> FSOut {
  let launch_idx = u32(fragcoord.y)*uniforms_int.canvas_width + u32(fragcoord.x);
  var t = tea(launch_idx, uniforms_int.frame_num); 
  // x-y jitter in the range [0, 1)
  let jitter = vec2f(rnd(&t), rnd(&t)) / f32(uniforms_int.canvas_height);

  const bgcolor = vec4f(0.1, 0.3, 0.6, 0.9);
  const max_depth = 10;
  var result = vec3f(0.0);
  // iterate over each sub-pixel position
  var hit = HitInfo(false, 0.0, vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), 1.0, 1.0, 0, vec2f(0.0));
  var ipcoords = vec2f((coords.x)*uniforms_f.aspect*0.5, (coords.y)*0.5);
  var r = get_camera_ray(ipcoords + jitter, &t); 
  for(var i = 0; i < max_depth; i ++){
    if(int_scene(&r, &hit)){
      result += shade(&r, &hit, &t);
      if(hit.hit){
        break;
      }
      if(dot(result, result) >= 0.99){
        // save some computation if saturated already
        break;
      }
    } else {
      result += bgcolor.rgb;
      break;
    }
  }

  let result_clamped = max(vec3f(0.0), result);
  let curr_sum = textureLoad(renderTexture, vec2u(fragcoord.xy), 0).rgb
    * f32(uniforms_int.frame_num);
  let accum_color = (result_clamped + curr_sum)/ f32(uniforms_int.frame_num + 1u);
  var out: FSOut;
  out.frame = vec4f(pow(accum_color, vec3f(1.0 / uniforms_f.gamma)), 1.0);
  out.accum = vec4f(accum_color, 1.0);
  return out; 
}