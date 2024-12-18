
window.onload = function() {main();}

async function load_texture(device, filename){
  const resp = await fetch(filename);
  const blob = await resp.blob();
  const img = await createImageBitmap(blob, {colorSpaceConversion: 'none'});

  const tex = device.createTexture({
    size: [img.width, img.height, 1],
    format: "rgba8unorm",
    usage: GPUTextureUsage.COPY_DST | GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT
  });
  device.queue.copyExternalImageToTexture(
    {source: img, flipY: true},
    { texture: tex },
    {width: img.width, height: img.height},
  );
  return tex;
}

function fstop2apt(stop_num){
  return Math.pow(1.41421356237, stop_num);
}

const BOX_DEPTH = 559;
function space2canv(spacex, spacey){
  let x = (1-(spacex / 490)) * 512
  let y = (1 - (spacey / BOX_DEPTH)) * 512;
  return [x,y];
}

function draw_overhead_map(ctx, fdist, fstop) {
  ctx.clearRect(0, 0, 512, 512);
  let yfocus = 512 * (1.0 - (fdist / BOX_DEPTH));
  // draw focus line
  ctx.strokeStyle = "red";
  if(fdist > BOX_DEPTH){
    ctx.setLineDash([5, 10]);
    yfocus = 512 * ((fdist -BOX_DEPTH)/ BOX_DEPTH);
  } else {
    ctx.setLineDash([5, 0]);
  }
  ctx.beginPath();
  ctx.moveTo(0, yfocus);
  ctx.lineTo(512, yfocus);
  ctx.stroke();

  // draw depth of field
  const focal_length = 1.0;
  let fdist_here = 1.0*fdist + focal_length;
  console.log(`fdist_here: ${fdist_here}`);
  const circle_of_confusion = 0.0004;
  let H = (focal_length * focal_length / (fstop * circle_of_confusion)) + focal_length;
  let numerator = fdist_here * (H - focal_length);
  let near_depth = numerator / (H + fdist_here - (2 * focal_length));
  let far_depth = numerator / (H - fdist_here);
  if(far_depth < 0){
    // negative indicates infinity
    far_depth = 1e6;
  }
  console.log(`near: ${near_depth}, far: ${far_depth}`);
  ctx.fillStyle = "rgb(255 0 0 / 30%)";
  // let depth = (2 * fdist * fdist) * (fstop/200) * circle_of_confusion / focal_length;
  let depth_near_px = (1-(near_depth / BOX_DEPTH)) * 512;
  let depth_far_px = (1-(far_depth / BOX_DEPTH)) * 512;
  let depth_px = depth_far_px - depth_near_px;

  if(fdist > BOX_DEPTH){
    depth_near_px = -1 * depth_near_px;
    depth_far_px  = -1 * depth_far_px;
    depth_px = -(depth_near_px - depth_far_px);
  }
  ctx.fillRect(0, depth_near_px, 512, depth_px);
  
  ctx.setLineDash([5, 0]);

  // draw balls
  // const sphere_1_c = vec3f(490, 50, 80);
  // const sphere_2_c = vec3f(350, 50, 0);
  // const sphere_3_c = vec3f(400, 50, 150);
  // const sphere_4_c = vec3f(320, 50, 400);

  ctx.fillStyle = "rgb(190 215 230 / 50%)";
  ctx.beginPath();
  let s1 = space2canv(490, 80);
  let s2 = space2canv(350, 0);
  let s3 = space2canv(400, 150);
  let s4 = space2canv(320, 400);
  ctx.arc(s1[0]+50, s1[1]-50, 50, 0, 2*Math.PI);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(s2[0]+50, s2[1]-50, 50, 0, 2*Math.PI);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(s3[0]+50, s3[1]-50, 50, 0, 2*Math.PI);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(s4[0]+50, s4[1]-50, 50, 0, 2*Math.PI);
  ctx.fill();

  // draw short block
  // corners at (130, 65), (82, 225), (240, 272), (290, 114)
  let p1 = space2canv(120, 65);
  let p2 = space2canv(82, 225);
  let p3 = space2canv(240, 272);
  let p4 = space2canv(280, 114);
  ctx.beginPath();
  ctx.moveTo(p1[0], p1[1]);
  ctx.lineTo(p2[0], p2[1]);
  ctx.lineTo(p3[0], p3[1]);
  ctx.lineTo(p4[0], p4[1]);
  ctx.closePath();
  ctx.fillStyle = "rgb(190 215 230 / 50%)";
  ctx.strokeStyle = "rgb(100 150 180 / 80%)";
  ctx.fill();
  ctx.stroke();

  // draw overhead light
// g Light
// v 343.0 548.7 227.0
// v 343.0 548.7 332.0
// v 213.0 548.7 332.0
// v 213.0 548.7 227.0
let l1 = space2canv(343, 227);
let l2 = space2canv(343, 332);
let l3 = space2canv(213, 332);
let l4 = space2canv(213, 227);
ctx.beginPath();
ctx.moveTo(l1[0], l1[1]);
ctx.lineTo(l2[0], l2[1]);
ctx.lineTo(l3[0], l3[1]);
ctx.lineTo(l4[0], l4[1]);
ctx.closePath();
ctx.fillStyle = "rgb(255 220 122 / 50%)";
ctx.strokeStyle = "rgb(240 196 75 / 80%)";
ctx.stroke();
ctx.fill();
}

async function main() {
  console.log("Begin main function");
  if (!navigator.gpu) {
    throw new Error("WebGPU not supported on this browser.");
  }

  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    throw new Error("No appropriate GPUAdapter found.");
  }
  
  const device = await adapter.requestDevice();
  
  const canvas = document.getElementById("wgslcanvas");
  const overhead = document.getElementById("overheadcanvas");
  const ov_ctx = overhead.getContext("2d");
  const ctx = canvas.getContext("webgpu");
  const canvasFmt = navigator.gpu.getPreferredCanvasFormat();
  ctx.configure({device: device, format: canvasFmt});
  
  
  const wgsl = device.createShaderModule({
    code: await (await fetch("./shade.wgsl")).text()
  });
  
  const pipeline = device.createRenderPipeline({
    layout: "auto",
    vertex: {
      module: wgsl,
      entryPoint: "main_vs",
    },
    fragment: {
      module: wgsl,
      entryPoint: "main_fs",
      targets: [
        { format: canvasFmt },
        { format: "rgba32float" } // output to texture for progressive rendering
      ]
    },
    primitive: {
      topology: "triangle-strip",
    }
  });

  let textures = new Object();
  textures.width = canvas.width;
  textures.height = canvas.height; 
  textures.renderSrc = device.createTexture({
    size: [canvas.width, canvas.height],
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC, 
    format: 'rgba32float', 
  });   

  textures.renderDst = device.createTexture({
    size: [canvas.width, canvas.height],
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST, 
    format: 'rgba32float', 
  })

  render = (dev, context, pipe, texs, bg) => {
    const encoder = dev.createCommandEncoder();

    const pass = encoder.beginRenderPass({
      colorAttachments: [
        { 
          view: context.getCurrentTexture().createView(), 
          loadOp: "clear",
          storeOp: "store",
        },
        { 
          view: texs.renderSrc.createView(), 
          loadOp: "load",
          storeOp: "store",
        }
      ]
    });
    pass.setBindGroup(0, bg);

    pass.setPipeline(pipe);
    pass.draw(4);
    pass.end();

    encoder.copyTextureToTexture(
      {texture: texs.renderSrc}, 
      {texture: texs.renderDst},
      [textures.width, textures.height]
    );

    dev.queue.submit([encoder.finish()]); 
  };
  
   
  var filename = "data/CornellBoxWith1Block.obj";


  const aspect = canvas.width / canvas.height;
  const gamma = 2.5;
  var fdist = Number(document.getElementById("fdist").value);
  var fstop = fstop2apt(Number(document.getElementById("fstop").value));
  var a_rotation = Number(document.getElementById("arot").value);
  draw_overhead_map(ov_ctx, fdist, fstop);

  var uniforms_f = new Float32Array([aspect, gamma, fstop, fdist, a_rotation]);
  var frame_num = 0;
  let aperture_shape_selector = document.getElementById("apertureshape");

  aperture_shape = aperture_shape_selector.value;
  var uniforms_int = new Int32Array([canvas.width, canvas.height, frame_num, aperture_shape]);
  
  

  const uniformBuffer_f = device.createBuffer({ 
    size: uniforms_f.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  });  
  const uniformBuffer_int = device.createBuffer({ 
    size: uniforms_int.byteLength, // number of bytes 
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  }); 


  
  // bspTreeBuffers has the following:
  // - attribs (positions + normals?)
  // - colors
  // - indices
  // - treeIds
  // - bspTree
  // - bspPlanes
  // - aabb (stored in uniform buffer)

  // the build_bsp_tree function creates these buffer on the device
  // all we have to do is put them in the right spots in the bindGroup layout


  
  
  device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
  device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);




  console.log("Load OBJ File " + filename);

  const drawingInfo = await readOBJFile(filename, 1, true); // filename, scale, ccw vertices
  console.log("Start building tree");
  const bspTreeBuffers = build_bsp_tree(drawingInfo, device, {})
  console.log("done building tree");


  console.log("indices:");
console.log(drawingInfo.indices);
// To see every 4th element (material indices):
console.log("material indices:");
console.log(drawingInfo.indices.filter((_, i) => i % 4 === 3));
  console.log("vertices:");
console.log(drawingInfo.attribs.filter((_, i) => i % 8 < 3));
  
console.log("AABB:", root.bbox);
const lightIndicesBuffer = device.createBuffer({
    size: drawingInfo.light_indices.byteLength,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
  });

  device.queue.writeBuffer(lightIndicesBuffer, 0, drawingInfo.light_indices);

  
  // flatten into diffuse, then emitted
  const mats = drawingInfo.materials.map((m) => [m.color, m.emission]).flat().map((color) => [color.r, color.g, color.b, color.a]).flat();
  console.log("Mats");
  console.log(mats);
  const materialsArray = new Float32Array(mats);
  console.log(materialsArray);
  const materialsBuffer = device.createBuffer({
    size: materialsArray.byteLength,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  });

  device.queue.writeBuffer(materialsBuffer, 0, materialsArray);

  const wallTex = await load_texture(device, "data/plaster.jpg");


  const bindGroup = device.createBindGroup({
  layout: pipeline.getBindGroupLayout(0), 
  entries: [
    // uniforms 
    { binding: 0, resource: { buffer: uniformBuffer_f } },
    { binding: 1, resource: { buffer: uniformBuffer_int } },
    { binding: 3, resource: { buffer: bspTreeBuffers.aabb }},
    // storage buffers (max 8!)
    { binding: 4, resource: { buffer: bspTreeBuffers.attribs }},
    { binding: 6, resource: { buffer: materialsBuffer } },
    { binding: 7, resource: { buffer: bspTreeBuffers.indices } },
    { binding: 8, resource: { buffer: bspTreeBuffers.treeIds }},
    { binding: 9, resource: { buffer: bspTreeBuffers.bspTree }},
    { binding: 10, resource: { buffer: bspTreeBuffers.bspPlanes }},
    { binding: 11, resource: { buffer: lightIndicesBuffer}},
    { binding: 12, resource: textures.renderDst.createView()},
    { binding: 13, resource: wallTex.createView()},

  ], 
  });


  function animate(){
    uniforms_int[2] = frame_num;
    frame_num ++;
    device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);
    render(device, ctx, pipeline, textures, bindGroup);
  }

  const frameCounter = document.getElementById("framecount");

  requestAnimationFrame(animate);

  var running = true;
  document.getElementById("run").onclick = () => {
    running = !running;
  };

  let fstop_slider = document.getElementById("fstop");
  fstop_slider.addEventListener("change", (e) => {
    fstop = fstop2apt(e.target.value);
    uniforms_f[2] = fstop;
    device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
    // reset image
    frame_num = 0;
    draw_overhead_map(ov_ctx, fdist, fstop);
    fstop_slider.nextElementSibling.value = `f${Math.round(fstop * 10) / 10.0}`;

  });


  let arot_slider = document.getElementById("arot");
  arot_slider.addEventListener("change", (e) => {
    a_rotation = e.target.value;
    uniforms_f[4] = a_rotation;
    device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
    // reset image
    frame_num = 0;
    arot_slider.nextElementSibling.value = Math.round(a_rotation);
  });


  let fdist_slider = document.getElementById("fdist");
  fdist_slider.addEventListener("change", (e) => {
    fdist = e.target.value;
    console.log(fdist);
    uniforms_f[3] = fdist;
    fdist_slider.nextElementSibling.value = Math.round(fdist);
    device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
    // reset image
    frame_num = 0;
    draw_overhead_map(ov_ctx, fdist, fstop);
  });


  overhead.addEventListener("click", (e) => {
    // set fdist based on y component of click point
    const rect = overhead.getBoundingClientRect();
    let yclick = e.clientY - rect.top;
    console.log(yclick);
    let canvas_height = rect.height
    let dclick = ((canvas_height - yclick) /canvas_height)* BOX_DEPTH;
    console.log(dclick);
    fdist = dclick;
    fdist_slider.value = fdist;
    fdist_slider.nextElementSibling.value = Math.round(fdist);
    uniforms_f[3] = fdist;
    device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
    // reset image
    frame_num = 0;
    draw_overhead_map(ov_ctx, fdist, fstop);
  });

  aperture_shape_selector.addEventListener("change", () => {
    aperture_shape = Number(aperture_shape_selector.value);
    uniforms_int[3] = aperture_shape;
    device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);
    // change range of angle
    // based on symmetry of this shape
    var max_angle = 0;
    switch(aperture_shape) {
      case 0: // circle, 0 rotation possible
        break;
      case 1: // square
        max_angle = 90;
        break;
      case 2: // triangle
        max_angle = 120;
        break;
      case 3: // hex
        max_angle = 60;
        break;
      case 4: // star
        max_angle = 60;
        break;
      case 5: // pentagon
        max_angle = 72;
        break;
      case 6: // slit
        max_angle = 180;
        break;
      default: break;
    }
    console.log(`shape: ${aperture_shape}`);
    console.log(`Max Angle: ${max_angle}`);
    arot_slider.max = max_angle;
    a_rotation = max_angle / 2;
    arot_slider.value = a_rotation;
    arot_slider.nextElementSibling.value = Math.round(a_rotation);

    uniforms_f[4] = a_rotation;
    device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);

    frame_num = 0;
    requestAnimationFrame(animate);
  });

  // every millisecond, request a new frame
  setInterval(() => {
    frameCounter.innerText = "Frame: " + frame_num;
    if(running){
      requestAnimationFrame(animate);
    }

  }, 30);
  
}

