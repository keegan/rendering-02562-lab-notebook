// 02562 Rendering Framework
// Inspired by BSP tree in GEL (https://www2.compute.dtu.dk/projects/GEL/)
// BSP tree in GEL originally written by Bent Dalgaard Larsen.
// This file written by Jeppe Revall Frisvad, 2023
// Copyright (c) DTU Compute 2023

const max_objects = 4; // maximum number of objects in a leaf
const max_level = 20;  // maximum number of levels in the tree
const f_eps = 1.0e-6;
const d_eps = 1.0e-12;
const BspNodeType = {
  bsp_x_axis: 0,
  bsp_y_axis: 1,
  bsp_z_axis: 2,
  bsp_leaf:   3,
};
var tree_objects = [];
var root = null;
var treeIds, bspTree, bspPlanes;

function AccObj(idx, v0, v1, v2)
{
  this.prim_idx = idx;
  this.bbox = new Aabb(v0, v1, v2);
  return this;
}

function BspTree(objects)
{
  this.max_level = max_level;
  this.count = objects.length;
  this.id = 0;
  this.bbox = new Aabb();
  for(var i = 0; i < objects.length; ++i)
    this.bbox.include(objects[i].bbox);
  subdivide_node(this, this.bbox, 0, objects);
  return this;
}

function subdivide_node(node, bbox, level, objects)
{
  // console.log("SUBDNODE");
  // console.log("length "+ objects.length + ", level " + level);
  const TESTS = 4;

  if(objects.length <= max_objects || level == max_level)
  {
    node.axis_leaf = BspNodeType.bsp_leaf;
    node.id = tree_objects.length;
    node.count = objects.length;
    node.plane = 0.0;

    for(var i = 0; i < objects.length; ++i)
      tree_objects.push(objects[i]);
  }
  else
  {
    let left_objects = [];
    let right_objects = [];
    node.left = new Object();
    node.right = new Object();

    var min_cost = 1.0e27;
    // i iterates over the different 
    for(var i = 0; i < 3; ++i)
    {
      for(var k = 1; k < TESTS; ++k)
      {
        // try several (TEST) different dividing planes.
        // for each, we split the faces into left and right of that 
        // center plane, then calculate the cost of this division 
        // cost is box area * count in box
        // minimize this cost
        let left_bbox = new Aabb(bbox);
        let right_bbox = new Aabb(bbox);
        const max_corner = bbox.max[i];
        const min_corner = bbox.min[i];
        const center = (max_corner - min_corner)*k/TESTS + min_corner;
        left_bbox.max[i] = center;
        right_bbox.min[i] = center;

        // Try putting the triangles in the left and right boxes
        var left_count = 0;
        var right_count = 0;
        for(var j = 0; j < objects.length; ++j)
        {
          let obj = objects[j];
          left_count += left_bbox.intersects(obj.bbox);
          right_count += right_bbox.intersects(obj.bbox);
        }

        const cost = left_count*left_bbox.area() + right_count*right_bbox.area();
        if(cost < min_cost)
        {
          min_cost = cost;
          node.axis_leaf = i;
          node.plane = center;
          node.left.count = left_count;
          node.left.id = 0;
          node.right.count = right_count;
          node.right.id = 0;
        }
      }
    }
    
    // Now chose the right splitting plane
    const max_corner = bbox.max[node.axis_leaf];
    const min_corner = bbox.min[node.axis_leaf];
    const size = max_corner - min_corner;
    const diff = f_eps < size/8.0 ? size/8.0 : f_eps;
    let center = node.plane;

    if(node.left.count == 0)
    {
      // Find min position of all triangle vertices and place the center there
      center = max_corner;
      for(var j = 0; j < objects.length; ++j)
      {
        let obj = objects[j];
        obj_min_corner = obj.bbox.min[node.axis_leaf];
        if(obj_min_corner < center)
          center = obj_min_corner;
      }
      center -= diff;
    }
    if(node.right.count == 0)
    {
      // Find max position of all triangle vertices and place the center there
      center = min_corner;
      for(var j = 0; j < objects.length; ++j)
      {
        let obj = objects[j];
        obj_max_corner = obj.bbox.max[node.axis_leaf];
        if(obj_max_corner > center)
          center = obj_max_corner;
      }
      center += diff;
    }

    node.plane = center;
    let left_bbox = new Aabb(bbox);
    let right_bbox = new Aabb(bbox);
    left_bbox.max[node.axis_leaf] = center;
    right_bbox.min[node.axis_leaf] = center;

    // Now put the triangles in the right and left node
    for(var j = 0; j < objects.length; ++j)
    {
      let obj = objects[j];
      if(left_bbox.intersects(obj.bbox))
        left_objects.push(obj);
      if(right_bbox.intersects(obj.bbox))
        right_objects.push(obj);
    }

    objects = [];
    subdivide_node(node.left, left_bbox, level + 1, left_objects);
    subdivide_node(node.right, right_bbox, level + 1, right_objects);
  }
}

function build_bsp_tree(drawingInfo, device, buffers)
{
  var objects = [];
  for(var i = 0; i < drawingInfo.indices.length/4; ++i) {
    let face = [drawingInfo.indices[i*4]*4, drawingInfo.indices[i*4 + 1]*4, drawingInfo.indices[i*4 + 2]*4];
    let v0 = vec3(drawingInfo.vertices[face[0]], drawingInfo.vertices[face[0] + 1], drawingInfo.vertices[face[0] + 2]);
    let v1 = vec3(drawingInfo.vertices[face[1]], drawingInfo.vertices[face[1] + 1], drawingInfo.vertices[face[1] + 2]);
    let v2 = vec3(drawingInfo.vertices[face[2]], drawingInfo.vertices[face[2] + 1], drawingInfo.vertices[face[2] + 2]);
    let acc_obj = new AccObj(i, v0, v1, v2);
    objects.push(acc_obj);
  }
  console.log("BSP tree constructor");
  root = new BspTree(objects);
  console.log("BSP tree constructor done");

  treeIds = new Uint32Array(tree_objects.length);
  for(var i = 0; i < tree_objects.length; ++i)
    treeIds[i] = tree_objects[i].prim_idx;
  const bspTreeNodes = (1<<(max_level + 1)) - 1;
  bspPlanes = new Float32Array(bspTreeNodes);
  bspTree = new Uint32Array(bspTreeNodes*4);
  
  function build_bsp_array(node, level, branch)
  {
    if(level > max_level)
      return;
    let idx = (1<<level) - 1 + branch;
    bspTree[idx*4] = node.axis_leaf + (node.count<<2);
    bspTree[idx*4 + 1] = node.id;
    bspTree[idx*4 + 2] = (1<<(level + 1)) - 1 + 2*branch;
    bspTree[idx*4 + 3] = (1<<(level + 1)) + 2*branch;
    bspPlanes[idx] = node.plane;
    if(node.axis_leaf === BspNodeType.bsp_leaf)
      return;
    build_bsp_array(node.left, level + 1, branch*2);
    build_bsp_array(node.right, level + 1, branch*2 + 1);
  }
  build_bsp_array(root, 0, 0);

  buffers.positions = device.createBuffer({
    size: drawingInfo.vertices.byteLength,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
  });
  device.queue.writeBuffer(buffers.positions, 0, drawingInfo.vertices);

  buffers.normals = device.createBuffer({
    size: drawingInfo.normals.byteLength,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
  });
  device.queue.writeBuffer(buffers.normals, 0, drawingInfo.normals);

  buffers.colors = device.createBuffer({
    size: drawingInfo.colors.byteLength,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
  });
  device.queue.writeBuffer(buffers.colors, 0, drawingInfo.colors);
  console.log(drawingInfo.colors);

  buffers.indices = device.createBuffer({
    size: drawingInfo.indices.byteLength, 
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
  });
  device.queue.writeBuffer(buffers.indices, 0, drawingInfo.indices);
  
  buffers.treeIds = device.createBuffer({
    size: treeIds.byteLength, 
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
  });
  device.queue.writeBuffer(buffers.treeIds, 0, treeIds);

  buffers.bspTree = device.createBuffer({
    size: bspTree.byteLength, 
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
  });
  device.queue.writeBuffer(buffers.bspTree, 0, bspTree);

  buffers.bspPlanes = device.createBuffer({
    size: bspPlanes.byteLength, 
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE
  });
  device.queue.writeBuffer(buffers.bspPlanes, 0, bspPlanes);

  // flatten the AABB's min and max (both vec3fs) 
  // expand to vec4s for byte-aligning
  const bbox = new Float32Array([...root.bbox.min, 0.0, ...root.bbox.max, 0.0]);
  buffers.aabb = device.createBuffer({
    size: bbox.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  device.queue.writeBuffer(buffers.aabb, 0, bbox);

  return buffers;
}
