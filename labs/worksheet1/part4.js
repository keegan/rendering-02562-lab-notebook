
window.onload = function() {main();}

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
    code: await (await fetch("./part4.wgsl")).text()
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
  
  
  
  const uniformBuffer = device.createBuffer({ 
    size: 8, // number of bytes 
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  }); 
  const bindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0), 
    entries: [{ 
      binding: 0, 
      resource: { buffer: uniformBuffer } 
    }], 
  }); 


  const aspect = canvas.width / canvas.height;
  var cam_const = 1.0;
  var uniforms = new Float32Array([aspect, cam_const]);
  device.queue.writeBuffer(uniformBuffer, 0, uniforms);

  addEventListener("wheel", (event) => {
    cam_const *= 1.0 + 2.5e-4 * event.deltaY;
    requestAnimationFrame(animate);
  });
  
  addEventListener("keydown", (event) => {
    if (event.code == 'ArrowUp') {
      cam_const *= 1.2;
    }
    else if (event.code == 'ArrowDown') {
        cam_const *= 0.8;
    }
    requestAnimationFrame(animate);
  });

  function animate(){
    uniforms[1] = cam_const;
    device.queue.writeBuffer(uniformBuffer, 0, uniforms);
    render(device, ctx, pipeline, bindGroup)
  }
  animate();



}

