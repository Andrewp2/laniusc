import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint local_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> semantic_local_flag;
StructuredBuffer<uint> semantic_local_prefix;
StructuredBuffer<uint> semantic_function_id;
StructuredBuffer<uint> visible_type;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<SemanticLirLocal> semantic_lir_locals;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint checked_type(uint token)
{
    if (token == LIR_INVALID || token >= gParams.n_tokens) return 0u;
    return visible_type[token];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (hir >= hir_count || semantic_local_flag[hir] == 0u) return;
    uint function_id = semantic_function_id[hir];
    if (function_id == LIR_INVALID) return;
    uint row = semantic_local_prefix[hir];
    HirPayload payload = compact_hir_payload[hir];
    SemanticLirFunction function = semantic_lir_functions[function_id];
    uint width = semantic_local_flag[hir];
    if (row + width > gParams.local_capacity) return;
    for (uint local = 0u; local < width; local += 1u)
    {
        SemanticLirLocal result;
        result.function_id = function_id;
        // Value ids below n_tokens retain source declaration identity. The
        // disjoint n_tokens + HIR domain names compiler-generated slots.
        result.declaration_id = local == 0u ? payload.b : gParams.n_tokens + hir;
        result.ordinal = row + local - function.local_start;
        result.type_id = local == 0u ? checked_type(payload.b) : 3u;
        semantic_lir_locals[row + local] = result;
    }
}
