struct VSOut {
  @builtin(position) position: vec4f,
  @location(0) coords: vec2f
}

struct Uniforms {
  aspect: f32,
  cam_const: f32,
  glass_shader: u32,
  matte_shader: u32,
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
}
// shader type names:
const shader_reflect: u32 = 2;
const shader_refract: u32 = 3;
const shader_phong: u32 = 4;
const shader_glossy: u32 = 5;
const shader_matte: u32 = 1;

// eye point at (2, 1.5, 2)
// look-at point (0, 0.5, 0)
// up-vector (0, 1, 0)
// camera constant d = uniforms.cam_const
const e = vec3f(2, 1.5, 2);

fn get_camera_ray(ipcoords: vec2f) -> Ray {
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
  return Ray(e, dir, 0.1, 10000);
}


fn int_scene(ray: ptr<function, Ray>,  hit: ptr<function, HitInfo>) -> bool {
  const sphere_c = vec3f(0.0, 0.5, 0.0);
  const sphere_r = 0.3;

  const plane_point = vec3f(0.0, 0.0, 0.0);
  const plane_normal = vec3f(0.0, 1.0, 0.0);

  const triangle_v = array(
    vec3f(-0.2, 0.1, 0.9),
    vec3f(0.2, 0.1, 0.9),
    vec3f(-0.2, 0.1, -0.1),
  );

  if( int_sphere(*ray, hit, sphere_c, sphere_r) ){(*ray).tmax = (*hit).distance;}
  if( int_plane(*ray, hit, plane_point, plane_normal) ){(*ray).tmax = (*hit).distance;}
  int_triangle(*ray, hit, triangle_v);

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
      (*hit).shader = uniforms.glass_shader;
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
      (*hit).shader = uniforms.glass_shader;
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

fn int_plane(ray: Ray, hit: ptr<function, HitInfo>, plane_point: vec3f, plane_normal: vec3f) -> bool{
  const plane_color = vec3f(0.1, 0.7, 0.0);

  let omega_dot_n = dot(ray.direction, plane_normal);
  if(abs(omega_dot_n) > 1e-4){
    // make sure that the ray isnt parallel to 
    // the plane (this would lead to a divide by 0 and would never intersect)
    let t = dot((plane_point - ray.origin), plane_normal) / omega_dot_n;
    if(ray.tmax >= t && ray.tmin <= t){
    // good intersection!
    (*hit).color_amb = plane_color * 0.1;
    (*hit).color_diff = plane_color * 0.9;
    (*hit).hit = true;
    (*hit).distance = t;
    // r(t) = o + t w
    (*hit).position = ray.origin + t * ray.direction;
    (*hit).normal = plane_normal;
    (*hit).shader = uniforms.matte_shader;
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
          (*hit).shader = uniforms.matte_shader;
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
  var lighthit = HitInfo(false, 0.0, vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), 1.0, 1.0, 0);
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
  var Lr = ((*hit).color_amb / 3.14159);

  let wo = normalize((*r).origin - (*hit).position);
  let wr = reflect(light.wi, (*hit).normal);
  if(!check_shadow((*hit).position, light.wi, light.dist)){
    Lr += 
    light.Li * 
    dot(light.wi, (*hit).normal) *
    (
      ((*hit).color_diff / 3.14159) + 
      (
        (*hit).color_specular * 
        ((*hit).shine + 2) * 0.15915494309 * // 1/2pi = 0.15915494309
        pow(dot(wo, wr), (*hit).shine)
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
      (*r).tmax = 10000; // reset tmax b/c casting a new ray
      (*hit).hit = false; // tell iterator to re-trace ray

      // bend the direction by the ratio of refractive indices
      // cos(in) = ( r \cdot n ) / (|r|*|n|)
      let cos_in = dot((*r).direction, (*hit).normal);
      let sin_sq_in = 1 - (cos_in*cos_in);
      let sin_sq_out = 
        ((*hit).refractive_ratio * (*hit).refractive_ratio)
        * sin_sq_in;
      let cos_sq_out = 1 - sin_sq_out;
      if(cos_sq_out < 0){
        // total internal reflection
        (*r).direction = reflect((*r).direction, (*hit).normal); // reflect the incoming ray about the surface normal
        return vec3f(0);
      }
      let n = (*hit).refractive_ratio;
      (*r).direction = 
        (*hit).normal * (n * cos_in - sqrt(cos_sq_out))
        + (*r).direction * n;
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
  let ipcoords = vec2f(coords.x*uniforms.aspect*0.5, coords.y*0.5);
  var r = get_camera_ray(ipcoords); 
  var result = vec3f(0.0);
  var hit = HitInfo(false, 0.0, vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), vec3f(0.0), 1.0, 1.0, 0);
  for(var i = 0; i < max_depth; i ++){
    if(int_scene(&r, &hit)){
      result += shade(&r, &hit);
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
  return vec4f(result, bgcolor.a); 
}