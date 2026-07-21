import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };
struct HirRange { uint start; uint count; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> semantic_function_flag;
StructuredBuffer<uint> semantic_function_prefix;
StructuredBuffer<uint> semantic_local_prefix;
StructuredBuffer<uint> semantic_local_total;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> fn_entrypoint_tag;
RWStructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<uint> semantic_function_id_by_token;

static const uint DISPATCH_X_STRIDE = 16776960u;

bool valid_token(uint token) { return token != LIR_INVALID && token < gParams.n_tokens; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (hir >= hir_count || semantic_function_flag[hir] == 0u) return;

    uint function_id = semantic_function_prefix[hir];
    HirCore core = compact_hir_core[hir];
    HirPayload payload = compact_hir_payload[hir];
    HirRange range = compact_param_ranges[hir];
    SemanticLirFunction result;
    result.hir_function = hir;
    result.name_token = payload.b;
    result.param_start = range.count == 0u ? LIR_INVALID : range.start;
    result.param_count = range.count;
    result.result_type = valid_token(core.token_start) ? call_return_type[core.token_start] : 0u;
    result.flags = valid_token(core.token_start) && fn_entrypoint_tag[core.token_start] != 0u
        ? SEMANTIC_FUNCTION_FLAG_ENTRYPOINT : 0u;
    result.file_id = compact_hir_links[hir].file_id;
    uint local_start = semantic_local_prefix[hir];
    uint local_end = compact_hir_links[hir].subtree_end < hir_count
        ? semantic_local_prefix[compact_hir_links[hir].subtree_end]
        : semantic_local_total[0u];
    result.local_start = local_start;
    result.local_count = local_end - local_start;
    result.reserved0 = 0u;
    result.reserved1 = 0u;
    result.reserved2 = 0u;
    semantic_lir_functions[function_id] = result;

    // Type checking deliberately exposes backend call targets in the
    // function-start-token domain. Translate that boundary once, here, so all
    // downstream LIR uses compact function IDs.
    if (valid_token(core.token_start)) semantic_function_id_by_token[core.token_start] = function_id;
    if (valid_token(payload.b)) semantic_function_id_by_token[payload.b] = function_id;
}
