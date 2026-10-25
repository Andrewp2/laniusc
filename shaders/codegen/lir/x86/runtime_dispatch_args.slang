// Size the runtime emitter from the final checked layout, including object
// status normalization. Every invocation replaces all three indirect words.
import codegen.lowering_ir;

struct Params
{
    uint target_capacity;
    uint token_capacity;
    uint function_capacity;
    uint artifact_capacity;
    uint target_start;
    uint page_capacity;
    uint reserved0;
    uint reserved1;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
RWStructuredBuffer<uint> x86_runtime_dispatch_args;

static const uint THREADS_PER_GROUP = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    uint groups = 0u;
    if (layout.status == 0u &&
        layout.runtime_offset <= gParams.artifact_capacity &&
        layout.runtime_length <= gParams.artifact_capacity - layout.runtime_offset)
    {
        // Division before addition also handles the largest uint length.
        groups = layout.runtime_length / THREADS_PER_GROUP;
        if (layout.runtime_length % THREADS_PER_GROUP != 0u) groups += 1u;
    }
    x86_runtime_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    x86_runtime_dispatch_args[1u] = max(1u,
        groups / MAX_GROUPS_X + (groups % MAX_GROUPS_X != 0u ? 1u : 0u));
    x86_runtime_dispatch_args[2u] = 1u;
}
