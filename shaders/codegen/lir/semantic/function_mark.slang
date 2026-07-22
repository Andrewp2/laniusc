import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
RWStructuredBuffer<uint> semantic_function_flag;
RWStructuredBuffer<uint> semantic_const_function_by_root;

static const uint HIR_FUNCTION = 3u;
static const uint HIR_CONST_ITEM = 25u;
static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (hir >= gParams.n_hir_nodes) return;
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    semantic_const_function_by_root[hir] = INVALID;
    semantic_function_flag[hir] = hir < hir_count &&
        (compact_hir_core[hir].kind == HIR_FUNCTION ||
         compact_hir_core[hir].kind == HIR_CONST_ITEM) ? 1u : 0u;
}
