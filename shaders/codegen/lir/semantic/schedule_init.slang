import codegen.lowering_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
RWStructuredBuffer<uint> target_schedule_order;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (row >= total) return;
    target_schedule_order[row] = row;
}
