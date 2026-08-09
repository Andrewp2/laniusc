import hir_records;
import codegen.lir.semantic.common;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> semantic_value_id;
RWStructuredBuffer<uint> semantic_local_flag;

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
    uint declaration_token = semantic_value_id[hir];
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
    if (hir >= gParams.n_hir_nodes) return;
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (hir < hir_count)
    {
        HirCore core = compact_hir_core[hir];
        HirPayload payload = compact_hir_payload[hir];
        bool source_local = (core.kind == HIR_LET_STMT ||
            (core.kind == HIR_STMT &&
             (payload.a == HIR_STMT_LET || payload.a == HIR_STMT_CONST))) &&
            payload.b != LIR_INVALID;
        // Range lowering owns two value slots: the source-visible binding and
        // a compiler-generated snapshot of the end bound. Prefix scanning the
        // per-HIR width keeps both in the same dense local family as ordinary
        // declarations without a serial allocation pass.
        bool range_for = core.kind == HIR_FOR_STMT ||
            (core.kind == HIR_STMT && payload.a == HIR_STMT_FOR);
        bool match_result = core.kind == HIR_MATCH_EXPR;
        bool match_binding = match_payload_binding(hir);
        semantic_local_flag[hir] = match_result ? 3u
            : source_local || match_binding ? 1u : range_for ? 2u : 0u;
        return;
    }
    semantic_local_flag[hir] = 0u;
}
