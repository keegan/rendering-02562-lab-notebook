
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

function compute_jitters(buffer, divisions, pixelsize){
  // we divide each pixel into `divisions`^2 sub-pixels
  const subpixels = divisions * divisions;
  const step = 1 / divisions;
  for(var i = 0; i < subpixels; i ++){
    // generate x and y between [0, 1]
    // these are the centers of the subpixels
    // for example, if divisions = 2
    // x will be [0.25, 0.75]
    const x = step * ((i % divisions) + 0.5);
    const y = step * (Math.floor(i / divisions) + 0.5);
    //now generate some random x,y additions in range [-step/2, step/2]
    const x_offset = step * (Math.random() - 0.5);
    const y_offset = step * (Math.random() - 0.5);
    // recenter subpixels around (0, 0)
    buffer[i * 2] = (x + x_offset - 0.5) * pixelsize;
    buffer[i * 2 + 1] = (y + y_offset - 0.5) * pixelsize;
  }
}

async function main() {
  if (!navigator.gpu) {
    throw new Error("WebGPU not supported on this browser.");
  }

  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    throw new Error("No appropriate GPUAdapter found.");
  }
  
  const device = await adapter.requestDevice();
  
  const canvas = document.querySelector("canvas");
  const ctx = canvas.getContext("webgpu");
  const canvasFmt = navigator.gpu.getPreferredCanvasFormat();
  ctx.configure({device: device, format: canvasFmt});
  
  
  const wgsl = device.createShaderModule({
    code: await (await fetch("./part1.wgsl")).text()
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
      targets: [{format: canvasFmt}]
    },
    primitive: {
      topology: "triangle-strip",
    }
  });

  render = (dev, context, pipe, bg) => {
    const encoder = dev.createCommandEncoder();

    const pass = encoder.beginRenderPass({
      colorAttachments: [{
        view: context.getCurrentTexture().createView(),
        loadOp: "clear",
        storeOp: "store",
      }]
    });
    pass.setBindGroup(0, bg);

    pass.setPipeline(pipe);
    pass.draw(4);
    pass.end();
    dev.queue.submit([encoder.finish()]); 
  };
  
   



  var use_linear = 1;

  var use_texture = 1;
  const aspect = canvas.width / canvas.height;
  var cam_const = 1.0;
  var gloss_shader = 5;
  var matte_shader = 1;
  const numDivisions = 3;
  var uniforms_f = new Float32Array([aspect, cam_const]);
  var uniforms_int = new Int32Array([gloss_shader, matte_shader, use_texture, numDivisions, use_linear]);
  
  

  const uniformBuffer_f = device.createBuffer({ 
    size: uniforms_f.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  });  
  const uniformBuffer_int = device.createBuffer({ 
    size: uniforms_int.byteLength, // number of bytes 
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  }); 

  let jitter = new Float32Array(numDivisions * numDivisions * 2);
  const jitterBuffer = device.createBuffer({
    size: jitter.byteLength, 
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  });

  const obj_filename = "data/bunny.obj";
  const drawingInfo = await readOBJFile(obj_filename, 1, true); // filename, scale, ccw vertices
  

  const bspTreeBuffers = build_bsp_tree(drawingInfo, device, {})
  // bspTreeBuffers has the following:
  // - positions 
  // - normals
  // - colors
  // - indices
  // - treeIds
  // - bspTree
  // - bspPlanes
  // - aabb (stored in uniform buffer)

  // the build_bsp_tree function creates these buffer on the device
  // all we have to do is put them in the right spots in the bindGroup layout

  // flatten into diffuse, then emitted
  const mats = drawingInfo.materials.map((m) => [m.color, m.emission]).flat().map((color) => [color.r, color.g, color.b, color.a]).flat();
  console.log(mats);
  const materialsArray = new Float32Array(mats);
  console.log(materialsArray);
  console.log(drawingInfo);

  const bindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0), 
    entries: [
      // uniforms 
      { binding: 0, resource: { buffer: uniformBuffer_f } },
      { binding: 1, resource: { buffer: uniformBuffer_int } },
      { binding: 2, resource: { buffer: jitterBuffer } },
      { binding: 3, resource: { buffer: bspTreeBuffers.aabb }},
      // storage buffers (max 8!)
      { binding: 4, resource: { buffer: bspTreeBuffers.positions }},
      { binding: 5, resource: { buffer: bspTreeBuffers.normals }},
      { binding: 6, resource: { buffer: bspTreeBuffers.colors } },
      { binding: 7, resource: { buffer: bspTreeBuffers.indices } },
      { binding: 8, resource: { buffer: bspTreeBuffers.treeIds }},
      { binding: 9, resource: { buffer: bspTreeBuffers.bspTree }},
      { binding: 10, resource: { buffer: bspTreeBuffers.bspPlanes }},
    ], 
  });
  
  
  device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
  device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);


  const updateSubpixels = () => {
    uniforms_int[3] = numDivisions;
    compute_jitters(jitter, numDivisions, 1/canvas.height);
    device.queue.writeBuffer(jitterBuffer, 0, jitter);
    device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);
  };
  updateSubpixels();

  addEventListener("wheel", (event) => {
    cam_const *= 1.0 + 2.5e-4 * event.deltaY;
    uniforms_f[1] = cam_const;
    device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
    requestAnimationFrame(animate);
  });
  
  addEventListener("keydown", (event) => {
    if (event.code == 'ArrowUp') {
      cam_const *= 1.2;
    }
    else if (event.code == 'ArrowDown') {
        cam_const *= 0.8;
    }
    uniforms_f[1] = cam_const;
    device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
    requestAnimationFrame(animate);
  });


  function animate(){
    render(device, ctx, pipeline, bindGroup)
  }
  animate();

}

