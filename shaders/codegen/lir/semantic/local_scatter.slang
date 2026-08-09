import hir_records;
import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint local_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> semantic_local_flag;
StructuredBuffer<uint> semantic_local_prefix;
StructuredBuffer<uint> semantic_function_id;
StructuredBuffer<uint> semantic_value_type_by_hir;
StructuredBuffer<uint> semantic_value_decl_by_hir;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<SemanticLirLocal> semantic_lir_locals;

static const uint DISPATCH_X_STRIDE = 16776960u;

bool match_payload_binding(uint hir)
{
    uint count = min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
    uint lo = 0u;
    uint hi = count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_match_payloads[mid].pattern < hir) lo = mid + 1u;
        else hi = mid;
    }
    if (lo >= count || compact_match_payloads[lo].pattern != hir)
        return false;
    uint declaration_token = semantic_value_decl_by_hir[hir];
    uint variant_count = min(compact_variant_count[0u], gParams.n_hir_nodes);
    uint variant_lo = 0u;
    uint variant_hi = variant_count;
    while (variant_lo < variant_hi)
    {
        uint mid = variant_lo + (variant_hi - variant_lo) / 2u;
        if (compact_variants[mid].name_token < declaration_token)
            variant_lo = mid + 1u;
        else
            variant_hi = mid;
    }
    return variant_lo >= variant_count ||
        compact_variants[variant_lo].name_token != declaration_token;
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
    SemanticLirFunction function = semantic_lir_functions[function_id];
    uint width = semantic_local_flag[hir];
    if (row + width > gParams.local_capacity) return;
    for (uint local = 0u; local < width; local += 1u)
    {
        bool match_result = compact_hir_core[hir].kind == HIR_MATCH_EXPR;
        bool match_binding = match_payload_binding(hir);
        SemanticLirLocal result;
        result.function_id = function_id;
        result.declaration_id = match_result
            ? gParams.n_tokens + hir + local * hir_count
            : match_binding ? semantic_value_decl_by_hir[hir]
            : local == 0u ? compact_hir_payload[hir].b : gParams.n_tokens + hir;
        result.ordinal = row + local - function.local_start;
        result.type_id = match_result && local == 1u ? SEMANTIC_LIR_TY_POINTER
            : local == 0u ? semantic_value_type_by_hir[hir] : 3u;
        semantic_lir_locals[row + local] = result;
    }
}
