
window.onload = () => main();

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
  
  
  
  const uniformBuffer_f = device.createBuffer({ 
    size: 8, // 2 * 32 bits = 64 bits = 8 bytes
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  });  const uniformBuffer_int = device.createBuffer({ 
    size: 8, // number of bytes 
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  }); 

  const texture = await load_texture(device, "data/grass.jpg");

  const bindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0), 
    entries: [
      { binding: 0, resource: { buffer: uniformBuffer_f } },
      { binding: 1, resource: { buffer: uniformBuffer_int } },
      { binding: 2, resource: texture.createView() },
    ], 
  }); 


  const aspect = canvas.width / canvas.height;
  var cam_const = 1.0;
  var use_linear = 1;
  var use_repeat = 1;


  var addrMenu = document.getElementById("addressmode");
  var filterMenu = document.getElementById("filtermode");
  use_linear = filterMenu.selectedIndex;
  use_repeat = addrMenu.selectedIndex;


  var uniforms_f = new Float32Array([aspect, cam_const]);
  var uniforms_int = new Int32Array([use_linear, use_repeat]);
  device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
  device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);

  addrMenu.addEventListener("click", () => {
    use_repeat = addrMenu.selectedIndex;
    uniforms_int[1] = use_repeat;
    device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);
    requestAnimationFrame(animate);
  });


  filterMenu.addEventListener("click", () => {
    use_linear = filterMenu.selectedIndex;
    uniforms_int[0] = use_linear;
    device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);
    requestAnimationFrame(animate);
  });

  function animate(){
    render(device, ctx, pipeline, bindGroup)
  }
  animate();



}

