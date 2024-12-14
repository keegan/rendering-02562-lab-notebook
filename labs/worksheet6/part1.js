
window.onload = function() {main();}

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
    // stored in a vec4f for byte-aligning with WGSL
    buffer[i * 4] = (x + x_offset - 0.5) * pixelsize;
    buffer[i * 4 + 1] = (y + y_offset - 0.5) * pixelsize;
    buffer[i * 4 + 2] = 0;
    buffer[i * 4 + 3] = 0;
  }
}

async function main() {
  const statBox = document.getElementById("stattext");
  statBox.innerText = "JS loaded";
  console.log("Begin main function");
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
  
   



  var obj_idx = 0;
  var filename = "data/bunny.obj";


  var use_texture = 1;
  const aspect = canvas.width / canvas.height;
  var cam_const = 1.0;
  var gloss_shader = 5;
  var matte_shader = 1;
  const numDivisions = 3;
  var uniforms_f = new Float32Array([aspect, cam_const]);
  var uniforms_int = new Int32Array([gloss_shader, matte_shader, use_texture, numDivisions, obj_idx]);
  
  

  const uniformBuffer_f = device.createBuffer({ 
    size: uniforms_f.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  });  
  const uniformBuffer_int = device.createBuffer({ 
    size: uniforms_int.byteLength, // number of bytes 
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  }); 

  let jitter = new Float32Array(numDivisions * numDivisions * 2 * 2); // *2 to fit in vec4f for alignment
  const jitterBuffer = device.createBuffer({
    size: jitter.byteLength, 
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST, 
  });


  
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


  
  
  device.queue.writeBuffer(uniformBuffer_f, 0, uniforms_f);
  device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);


  const updateSubpixels = () => {
    uniforms_int[3] = numDivisions;
    compute_jitters(jitter, numDivisions, 1/canvas.height);
    device.queue.writeBuffer(jitterBuffer, 0, jitter);
    device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);
  };
  updateSubpixels();


  async function animate(){

    console.log("Load OBJ File " + filename);

    statBox.innerHTML = "<p style='background-color:red;color:white'>Loading OBJ File " + filename + "</p>";
    const drawingInfo = await readOBJFile(filename, 1, true); // filename, scale, ccw vertices
    console.log("Start building tree");
    const bspTreeBuffers = build_bsp_tree(drawingInfo, device, {})
    console.log("done building tree");

    statBox.innerHTML = "Done loading " + filename;

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
    render(device, ctx, pipeline, bindGroup);
  }

  

  if (document.querySelector('input[name="obj"]')) {
    document.querySelectorAll('input[name="obj"]').forEach((elem) => {
      elem.addEventListener("change", function(event) {
        obj_idx = event.target.value;
        console.log("OBJ IDX: " + obj_idx);
        if(obj_idx == 0){
          filename = "data/bunny.obj";
        } else if (1 == obj_idx ){
          filename = "data/teapot.obj";
        } else {
          filename = "data/dragon.obj";
        }
        uniforms_int[4] = obj_idx;
        device.queue.writeBuffer(uniformBuffer_int, 0, uniforms_int);
        requestAnimationFrame(animate);
      });
    });
  }

  requestAnimationFrame(animate);

}

