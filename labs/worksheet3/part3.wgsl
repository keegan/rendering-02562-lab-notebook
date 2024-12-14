struct VSOut {
  @builtin(position) position: vec4f,
  @location(0) coords: vec2f
}

struct UniformsF { // float values
  aspect: f32,
  cam_const: f32,
}
struct UniformsInt { // unsigned int values
  glass_shader: u32,
  matte_shader: u32,
  texture_enabled: u32,
  subdivisions: u32, // sqrt of number of subpixels
  use_linear: u32,
}

@group(0) @binding(0) var<uniform> uniforms_f: UniformsF;
@group(0) @binding(1) var<uniform> uniforms_int: UniformsInt;
@group(0) @binding(2) var grass_texture: texture_2d<f32>;
@group(0) @binding(3) var<storage> subpixels: array<vec2f>;


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


const tex_scale = 0.02;
// eye point at (2, 1.5, 2)
// look-at point (0, 0.5, 0)
// up-vector (0, 1, 0)
// camera constant d = uniforms.cam_const
const e = vec3f(2, 1.5, 2);

struct Onb { // orthonormal basis for plane
  tangent: vec3f,
  binormal: vec3f,
  normal: vec3f,
};


fn get_camera_ray(ipcoords: vec2f) -> Ray {
  const p = vec3f(0, 0.5, 0);
  let v = normalize(p - e);
  const u = vec3f(0, 1, 0);
  let d = uniforms_f.cam_const;

  let b1 = normalize(cross(v, u));
  let b2 = cross(b1, v); // b1 and v are magnitude 1 so their cross is already 1
  
  let x = ipcoords[0];
  let y = ipcoords[1];

  let q = (v)*d + (b1 * x) + (b2 * y);

  var dir = normalize(q);
  return Ray(e, dir, 0.1, 10000);
}


fn texture_nearest(texture: texture_2d<f32>, texcoords:vec2f) -> vec3f {
  // get dimensions of texture
  let res = textureDimensions(texture);
  // if repeat, we want the texcoords modulo 1.0
  // otherwise, we just clamp the coords between 0 and 1
  let st = texcoords - floor(texcoords);
  let ab = st * vec2f(res);
  let UV = vec2u(ab + 0.5) % res; // get closest texel coords UV
  let texcolor = textureLoad(texture, UV, 0);
  return texcolor.rgb;
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


fn int_scene(ray: ptr<function, Ray>,  hit: ptr<function, HitInfo>) -> bool {
  const sphere_c = vec3f(0.0, 0.5, 0.0);
  const sphere_r = 0.3;

  const plane_point = vec3f(0.0, 0.0, 0.0);
  const plane_onb = Onb(
    vec3f(-1.0, 0.0, 0.0),
    vec3f(0.0, 0.0, 1.0),
    vec3f(0.0, 1.0, 0.0)
  );
  const triangle_v = array(
    vec3f(-0.2, 0.1, 0.9),
    vec3f(0.2, 0.1, 0.9),
    vec3f(-0.2, 0.1, -0.1),
  );
  if( int_sphere(*ray, hit, sphere_c, sphere_r) ){(*ray).tmax = (*hit).distance;}
  if(int_triangle(*ray, hit, triangle_v)){ (*ray).tmax = (*hit).distance; }  

  if( int_plane(*ray, hit, plane_point, plane_onb) ){
    (*ray).tmax = (*hit).distance;
  }
  

  return (*hit).hit;
}

fn int_sphere(ray: Ray, hit: ptr<function, HitInfo>, center: vec3f, radius: f32) -> bool {
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
      (*hit).shader = uniforms_int.glass_shader;
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
      (*hit).shader = uniforms_int.glass_shader;
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

fn int_plane(ray: Ray, hit: ptr<function, HitInfo>, plane_point: vec3f, plane: Onb) -> bool{
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
      (*hit).shader = uniforms_int.matte_shader;
      // compute texture coordinates
      // use tex_scale = 0.2

      // find U,V coordinates from orthonormal basis
      let offset = x - plane_point;
      let u = dot(offset, plane.tangent);
      let v = dot(offset, plane.binormal);
      (*hit).texcoords = vec2f(u, v) * tex_scale;


       // get color from texture
      let texture_color = select(
        plane_color, 
        select(
          texture_nearest(grass_texture, (*hit).texcoords),
          texture_linear(grass_texture, (*hit).texcoords),
          uniforms_int.use_linear != 0
        ), 
        uniforms_int.texture_enabled != 0
      );
      (*hit).color_amb = 0.1 * texture_color;
      (*hit).color_diff = 0.9 * texture_color;
    }
  }

  return (*hit).hit;
}
fn int_triangle(ray: Ray, hit: ptr<function, HitInfo>, v: array<vec3f, 3>) -> bool {
  const triangle_color = vec3f(0.4, 0.3, 0.2);

  let e0 = v[1] - v[0];
  let e1 = v[2] - v[0];
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
          (*hit).color_amb = triangle_color * 0.1;
          (*hit).color_diff = triangle_color * 0.9;
          (*hit).hit = true;
          (*hit).distance = t;
          // r(t) = o + t w
          (*hit).position = ray.origin + t * ray.direction;
          (*hit).normal = normalize(n);
          (*hit).shader = uniforms_int.matte_shader;
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

fn sample_point_light(p: vec3f) -> Light {
  // return light info at the point p
  // light source is at (0, 1, 0) w/ intensity (pi, pi, pi)
  let x = vec3f(0.0, 1.0, 0.0);
  let I = vec3f(3.14159, 3.14159, 3.14159);
  let dist = distance(p, x);
  let wi = normalize(x - p);
  let Li = I / pow(dist, 2);

  return Light(Li, wi, dist);
}

fn check_shadow(pos: vec3f, lightdir: vec3f, lightdist: f32) -> bool{
  var lightray =  Ray(pos, lightdir, 10e-4, lightdist-10e-4);
  var lighthit = HitInfo(false, 0.0, vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), 1.0, 1.0, 0, vec2f(0.0));
  return int_scene(&lightray, &lighthit);
}

fn lambert(r: ptr<function, Ray>, hit: ptr<function, HitInfo>) -> vec3f {
  // find light intensity Li at intersection point
  let light = sample_point_light((*hit).position);
  // see if path to the light intersects an object (ie we are in shadow)
  var Lr = ((*hit).color_amb / 3.14159);
  if(!check_shadow((*hit).position, light.wi, light.dist)){
    Lr += ((*hit).color_diff / (3.14159)) * light.Li * dot((*hit).normal, light.wi);
  }
  // use ambient light and reflected light
  return Lr;
}

fn phong(r: ptr<function, Ray>, hit: ptr<function, HitInfo>) -> vec3f {
  let light = sample_point_light((*hit).position);
  

  let wo = normalize((*r).origin - (*hit).position);
  let wr = reflect(-light.wi, (*hit).normal);

  var Lr = ((*hit).color_amb / 3.14159);
  if(!check_shadow((*hit).position, light.wi, light.dist)){
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

fn shade_refract(r: ptr<function, Ray>, hit: ptr<function, HitInfo>) -> vec3f {
  // case 3 indicates a refractive material. The ray is re-cast but
  // deflected according to the relative indices or refraction
  (*r).origin = (*hit).position; // cast ray from intersection position
  (*r).tmin = 1e-4; // make sure we dont collide with the surface the ray is reflected off
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

fn shade(r: ptr<function, Ray>, hit: ptr<function, HitInfo>) -> vec3f{
  switch (*hit).shader {
    case shader_matte { return lambert(r, hit);}
    case shader_reflect {
      // case 2 indicates a reflective material. we need to re-cast a ray from the reflected position
      // on the intersected surface. this means modifying the ray
      (*hit).hit = false; // tell iterator to re-trace ray
      (*r).origin = (*hit).position; // cast ray from intersection position
      (*r).direction = reflect((*r).direction, (*hit).normal); // reflect the incoming ray about the surface normal
      (*r).tmin = 1e-4; // make sure we dont collide with the surface the ray is reflected off
      (*r).tmax = 10000;
      return vec3f(0.0);
    } 
    case shader_refract {
      return shade_refract(r, hit);
    }
    case shader_phong {
      return phong(r, hit);
    }
    case shader_glossy {
      return phong(r, hit) + shade_refract(r, hit);
    }
    //case default { return -(*r).direction;}
    case default {return (*hit).color_diff + (*hit).color_amb;}
  }  
}

// the fragment defines the shader function run at each pixel
@fragment
fn main_fs(@location(0) coords: vec2f) -> @location(0) vec4f{
  const bgcolor = vec4f(0.1, 0.3, 0.6, 1.0);
  const max_depth = 10;
  var result = vec3f(0.0);
  // iterate over each sub-pixel position
  let num_subpixels = uniforms_int.subdivisions * uniforms_int.subdivisions;
  let inv_subpixels = 1.0 / f32(num_subpixels);
  for(var sub_idx = u32(0); sub_idx < num_subpixels; sub_idx ++){
    var hit = HitInfo(false, 0.0, vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), 1.0, 1.0, 0, vec2f(0.0));
    var thisResult = vec3f(0.0);
    let thisSub = subpixels[sub_idx]; // add jittered subpixel coordinates
    var ipcoords = vec2f((coords.x + thisSub.x)*uniforms_f.aspect*0.5, (coords.y + thisSub.y)*0.5);
    var r = get_camera_ray(ipcoords); 
    for(var i = 0; i < max_depth; i ++){
      if(int_scene(&r, &hit)){
        thisResult += shade(&r, &hit);
        if(hit.hit){
          break;
        }
        if(dot(thisResult, thisResult) >= 0.99){
          // save some computation if saturated already
          break;
        }
      } else {
        thisResult += bgcolor.rgb;
        break;
      }
    }
    result += inv_subpixels * thisResult;
  }
  return vec4f(result, bgcolor.a); 
  //return vec4f(f32(uniforms_int.subdivisions) / 10.0, 0, 0, 1.0);
}