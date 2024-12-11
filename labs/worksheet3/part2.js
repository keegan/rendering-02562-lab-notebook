
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
    code: await (await fetch("./part2.wgsl")).text()
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
    size: 12, // number of bytes 
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



  var texToggle = document.getElementById("texturetoggle");
  var use_texture = texToggle.selectedIndex;
  const aspect = canvas.width / canvas.height;
  var cam_const = 1.0;
  var gloss_shader = 5;
  var matte_shader = 1;
  var uniforms_f = new Float32Array([aspect, cam_const]);
  var uniforms_int = new Int32Array([gloss_shader, matte_shader, use_texture]);
  device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
  device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);

  texToggle.addEventListener("click", () => {
    use_repeat = texToggle.selectedIndex;
    uniforms_int[2] = use_repeat;
    device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);
    requestAnimationFrame(animate);
  });

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

  if (document.querySelector('input[name="glossy"]')) {
    document.querySelectorAll('input[name="glossy"]').forEach((elem) => {
      elem.addEventListener("change", function(event) {
        gloss_shader = event.target.value;
        uniforms_int[0] = gloss_shader;
        device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);
        requestAnimationFrame(animate);
      });
    });
  }

  if (document.querySelector('input[name="matte"]')) {
    document.querySelectorAll('input[name="matte"]').forEach((elem) => {
      elem.addEventListener("change", function(event) {
        matte_shader = event.target.value;
        uniforms_int[1] = matte_shader;
        device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);
        requestAnimationFrame(animate);
      });
    });
  }

  function animate(){
    render(device, ctx, pipeline, bindGroup)
  }
  animate();



}

