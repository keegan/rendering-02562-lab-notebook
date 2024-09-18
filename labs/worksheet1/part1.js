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

const encoder = device.createCommandEncoder();

const pass = encoder.beginRenderPass({
  colorAttachments: [{
    view: ctx.getCurrentTexture().createView(),
    loadOp: "clear",
    storeOp: "store",
  }]
});

pass.end();

const commandBuffer = encoder.finish()

device.queue.submit([commandBuffer]);
