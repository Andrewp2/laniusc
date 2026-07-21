import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_call_args; uint n_hir_nodes; uint lir_capacity; uint reserved; };
struct HirCallArg { uint call; uint value; uint ordinal; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_lir_offset;
RWStructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
RWStructuredBuffer<uint> semantic_lir_call_arg_total;
RWStructuredBuffer<uint> semantic_lir_call_arg_start_scratch;
RWStructuredBuffer<uint> semantic_lir_call_arg_count_scratch;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint lir_for_hir(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes &&
           semantic_lir_count[node] != 0u
        ? semantic_lir_offset[node]
        : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row == 0u)
        semantic_lir_call_arg_total[0u] = min(gParams.n_call_args, compact_call_arg_count[0u]);
    uint count = min(gParams.n_call_args, compact_call_arg_count[0u]);
    if (row >= count) return;
    HirCallArg source = compact_call_args[row];
    SemanticLirCallArg result;
    result.call_instruction = lir_for_hir(source.call);
    result.value_instruction = lir_for_hir(source.value);
    result.ordinal = source.ordinal;
    result.flags = source.file_id;
    semantic_lir_call_args[row] = result;
    if (result.call_instruction < gParams.lir_capacity)
    {
        uint ignored;
        InterlockedMin(semantic_lir_call_arg_start_scratch[result.call_instruction], row, ignored);
        InterlockedAdd(semantic_lir_call_arg_count_scratch[result.call_instruction], 1u, ignored);
    }
}
