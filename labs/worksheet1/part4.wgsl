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
  color: vec3f,
  shader: u32,
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
  return Ray(e, dir, 0.1, 100);
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
  const sphere_color = vec3f(0.0, 0.0, 0.0);
  // a = w dot w = 1
  // b/2 = poly_half_b = (O-C) dot w
  let dist_from_origin = ray.origin - center;
  let half_b = dot((dist_from_origin), ray.direction);
  // polynomial c = poly_c = (o-c) dot (o-c) - r^2
  let c = dot(dist_from_origin, dist_from_origin) - (radius*radius);
  let det = (half_b * half_b) - c;
  // if det < 0 then no intersection occurs
  if(det >= 0){
    // we have an intersection. at det = 0 just one otherwise 2
    let t = -1 * half_b;
    if(det == 0){
      // we graze just tange to the sphere
      if(ray.tmax >= t && ray.tmin <= t){
        (*hit).color = sphere_color;
        (*hit).hit = true;
        (*hit).distance = t;
        // r(t) = o + t w
        let pos = ray.origin + t * ray.direction;
        (*hit).position = pos;
        (*hit).normal = normalize(pos - center);
        (*hit).shader = 0;
      }
  
    } else { // we hit the sphere, but not tange so we have
    // an entry and exit point. calculate both and find which is closer
      let sqrt_det = sqrt(det);
      let t1 = t - sqrt_det;
      let t2 = t + sqrt_det;
      if(ray.tmax >= t1 && ray.tmin <= t1){ // if t1 in bounds its always closer
        (*hit).color = sphere_color;
        (*hit).hit = true;
        (*hit).distance = t1;
        // r(t) = o + t w
        let pos = ray.origin + t1 * ray.direction;
        (*hit).position = pos;
        (*hit).normal = normalize(pos - center);
        (*hit).shader = 0;
      } else if (ray.tmax >= t2 && ray.tmin <= t2){
        (*hit).color = sphere_color;
        (*hit).hit = true;
        (*hit).distance = t2;
        // r(t) = o + t w
        let pos = ray.origin + t2 * ray.direction;
        (*hit).position = pos;
        (*hit).normal = normalize(pos - center);
        (*hit).shader = 0;
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
    (*hit).color = plane_color;
    (*hit).hit = true;
    (*hit).distance = t;
    // r(t) = o + t w
    (*hit).position = ray.origin + t * ray.direction;
    (*hit).normal = plane_normal;
    (*hit).shader = 0;
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

  if(abs(omega_dot_n) > 1e-4){
    // make sure ray isnt parallel to triangle plane
    let t = dot((v[0] - ray.origin), n)/omega_dot_n;
    if(t <= ray.tmax && ray.tmin <= t){
      let partial = cross(v[0] - ray.origin, ray.direction);

      let beta = dot(partial, e1) / omega_dot_n;
      let gamma = -dot(partial, e0) / omega_dot_n;

      if(beta >= 0 && gamma >= 0 && (beta + gamma) <= 1){
        (*hit).color = triangle_color;
        (*hit).hit = true;
        (*hit).distance = t;
        // r(t) = o + t w
        (*hit).position = ray.origin + t * ray.direction;
        (*hit).normal = normalize(n);
        (*hit).shader = 0;
      }
    }
  }

  return (*hit).hit;
}

fn shade(r: ptr<function, Ray>, hit: ptr<function, HitInfo>) -> vec3f{
  switch (*hit).shader {
    case default {return (*hit).color;}
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
  var hit = HitInfo(false, 0.0, vec3f(0.0), vec3f(0.0), vec3f(0.0), 0);
  for(var i = 0; i < max_depth; i ++){
    if(int_scene(&r, &hit)){
      result += shade(&r, &hit);
      break;
    } else {
      result += bgcolor.rgb;
      break;
    }
  }
  return vec4f(result, bgcolor.a); 
}
