import hir_records;
import codegen.lir.semantic.common;
import codegen.lir.semantic.loop_recipe;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint reserved0; uint reserved1; uint reserved2; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_expr_parent;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_start;
StructuredBuffer<uint> compact_match_payload_count;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> semantic_function_id;
StructuredBuffer<uint> semantic_value_id;
StructuredBuffer<uint> semantic_array_length;
StructuredBuffer<uint> semantic_iterable_kind;
RWStructuredBuffer<uint> semantic_lir_count;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_match_arm_count()
{
    return min(compact_match_arm_count[0u], gParams.n_hir_nodes);
}

uint active_match_payload_count()
{
    return min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
}

uint match_payload_for_pattern(uint node)
{
    uint lo = 0u;
    uint hi = active_match_payload_count();
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (compact_match_payloads[mid].pattern < node) lo = mid + 1u;
        else hi = mid;
    }
    if (lo >= active_match_payload_count() ||
        compact_match_payloads[lo].pattern != node)
        return LIR_INVALID;
    uint declaration_token = semantic_value_id[node];
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
    return variant_lo < variant_count &&
        compact_variants[variant_lo].name_token == declaration_token
            ? LIR_INVALID : lo;
}

bool match_pattern_syntax(uint node, uint hir_count)
{
    uint token = compact_hir_core[node].token_start;
    uint lo = 0u;
    uint hi = active_match_arm_count();
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint pattern = compact_match_arms[mid].pattern;
        uint start = pattern < hir_count
            ? compact_hir_core[pattern].token_start : 0xffffffffu;
        if (start <= token) lo = mid + 1u;
        else hi = mid;
    }
    if (lo == 0u) return false;
    uint pattern = compact_match_arms[lo - 1u].pattern;
    if (pattern >= hir_count) return false;
    HirCore span = compact_hir_core[pattern];
    HirCore candidate = compact_hir_core[node];
    return candidate.token_start >= span.token_start &&
        candidate.token_end <= span.token_end;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= gParams.n_hir_nodes) return;
    uint rows = 0u;
    // Executable LIR belongs to a concrete checked function. Compact HIR also
    // contains path/name expressions used by module, import, type, and other
    // declaration syntax; those remain semantic metadata and must never be
    // scheduled as top-level machine instructions.
    if (node < count && semantic_function_id[node] != LIR_INVALID)
    {
        HirCore core = compact_hir_core[node];
        HirPayload payload = compact_hir_payload[node];
        uint match_payload = match_payload_for_pattern(node);
        if (match_payload != LIR_INVALID)
        {
            semantic_lir_count[node] = 3u;
            return;
        }
        if (match_pattern_syntax(node, count))
        {
            semantic_lir_count[node] = 0u;
            return;
        }
        if (core.kind == HIR_MATCH_EXPR)
        {
            uint arm_count = payload.b < active_match_arm_count()
                ? min(payload.c, active_match_arm_count() - payload.b) : 0u;
            // Store the scrutinee once, reload it for each tag access, and
            // finish with the selected result value.
            // Store the scrutinee and a compiler-owned `matched` flag once,
            // then lower each arm as `!matched && pattern_matches`. This
            // preserves first-match semantics for wildcard/default arms as
            // well as for future overlapping pattern forms.
            semantic_lir_count[node] = arm_count * 12u + 4u;
            return;
        }
        uint parent = compact_expr_parent[node];
        bool owned_syntax = parent < count &&
            ((compact_hir_core[parent].kind == HIR_CALL_EXPR &&
              compact_hir_payload[parent].a == node) ||
             ((compact_hir_core[parent].kind == HIR_STMT ||
               compact_hir_core[parent].kind == HIR_ASSIGN_EXPR) &&
              compact_hir_payload[parent].a == HIR_STMT_ASSIGN &&
              compact_hir_payload[parent].b == node) ||
             ((compact_hir_core[parent].kind == HIR_FOR_STMT ||
              (compact_hir_core[parent].kind == HIR_STMT &&
               compact_hir_payload[parent].a == HIR_STMT_FOR)) &&
              compact_hir_payload[parent].c == node));
        bool for_loop = semantic_lir_is_for(core, payload);
        uint iterable_form = for_loop && payload.c < count
            ? compact_hir_payload[payload.c].a : 0u;
        uint iterable_kind = for_loop ? semantic_iterable_kind[node] : 0u;
        uint array_length = for_loop && payload.c < count
            ? semantic_array_length[payload.c] : 0xffffffffu;
        SemanticLoopRecipe recipe = semantic_loop_recipe(
            core, payload, iterable_form, iterable_kind, array_length);
        rows = owned_syntax ? 0u : recipe.row_count;
    }
    semantic_lir_count[node] = rows;
}
