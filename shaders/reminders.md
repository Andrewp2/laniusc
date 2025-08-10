When converting from .wgsl to .slang

1. The order of the select condition changes. Instead of `select(false, true, condition)` in slang its `select(condition, true, false)`.
2. Instead of using `arrayLength(x)` use `length(x)`.
3. When importing, instead of using `module::thing_im_importing` use `thing_im_importing`.
4. Remember to set the visibility of functions to `public` when using them from a different module.
5. Remember to use `var` for mutable variables and `let` for immutable variables.
6. Prefer the modern syntax to traditional C. So instead of

`float addSomeThings(int x, float y)
{
    return x + y;
}`

do

`func add_some_things(x : int, y : float) -> float
{
    return x + y;
}`
7. Instead of using explicit binding markup, please rely on the bindings that slang generates.
8. Do not use `cbuffer`, instead use `ConstantBuffer<MyData>`.
9. All shader entry points are compute. For reference, here's how you define an entry point:

```
RWStructuredBuffer<float> ioBuffer;

[shader("compute")]
[numthreads(4, 1, 1)]
void computeMain(uint3 dispatchThreadID : SV_DispatchThreadID)
{
    uint tid = dispatchThreadID.x;

    float i = ioBuffer[tid];
    float o = i < 0.5 ? (i + i) : sqrt(i);

    ioBuffer[tid] = o;
}
```

1.  Here are the following built-ins:

System-Value semantics
The system-value semantics are translated to the following WGSL code.

| SV semantic name          | WGSL code                        |
| ------------------------- | -------------------------------- |
| SV_Barycentrics           | Not supported                    |
| SV_ClipDistance           | Not supported                    |
| SV_CullDistance           | Not supported                    |
| SV_Coverage               | @builtin(sample_mask)            |
| SV_CullPrimitive          | Not supported                    |
| SV_Depth                  | @builtin(frag_depth)             |
| SV_DepthGreaterEqual      | Not supported                    |
| SV_DepthLessEqual         | Not supported                    |
| SV_DispatchThreadID       | @builtin(global_invocation_id)   |
| SV_DomainLocation         | Not supported                    |
| SV_GSInstanceID           | Not supported                    |
| SV_GroupID                | @builtin(workgroup_id)           |
| SV_GroupIndex             | @builtin(local_invocation_index) |
| SV_GroupThreadID          | @builtin(local_invocation_id)    |
| SV_InnerCoverage          | Not supported                    |
| SV_InsideTessFactor       | Not supported                    |
| SV_InstanceID             | @builtin(instance_index)         |
| SV_IntersectionAttributes | Not supported                    |
| SV_IsFrontFace            | @builtin(front_facing)           |
| SV_OutputControlPointID   | Not supported                    |
| SV_PointSize              | Not supported                    |
| SV_Position               | @builtin(position)               |
| SV_PrimitiveID            | Not supported                    |
| SV_RenderTargetArrayIndex | Not supported                    |
| SV_SampleIndex            | @builtin(sample_index)           |
| SV_ShadingRate            | Not supported                    |
| SV_StartVertexLocation    | Not supported                    |
| SV_StartInstanceLocation  | Not supported                    |
| SV_StencilRef             | Not supported                    |
| SV_Target                 | Not supported                    |
| SV_TessFactor             | Not supported                    |
| SV_VertexID               | @builtin(vertex_index)           |
| SV_ViewID                 | Not supported                    |
| SV_ViewportArrayIndex     | Not supported                    |

11. Here is how you define a struct in slang.

struct SurfaceGeometry {
  float3 position;
  float3 normal;
  float2 uv;
};

12. By default, all globals get a binding (are shader parameters). If you want to declare a static value, you have to use the `static` keyword even if its `const`.
13. Follow rust rules when typing cases: Functions, methods, and local variables are `snake_case`, constants are `SCREAMING_SNAKE_CASE`, and types are `PascalCase`.