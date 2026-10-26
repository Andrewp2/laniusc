import primitive_types;
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
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> semantic_iterable_kind;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<SemanticLirLocal> semantic_lir_locals;

static const uint DISPATCH_X_STRIDE = 16776960u;

#include "receiver_source.slang"

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
    // A call owns the stored copy of a `&self` receiver that is not a
    // place, keyed by its method name token (receiver_temporary.slang).
    // The copy has the type of the value under the receiver's fields.
    uint member = compact_hir_core[hir].kind == HIR_CALL_EXPR
        ? compact_hir_payload[hir].a : LIR_INVALID;
    bool receiver_temporary = member < hir_count;
    uint holder = receiver_temporary
        ? receiver_projection_root(compact_hir_payload[member].b, hir_count) : LIR_INVALID;
    uint holder_type = holder < hir_count ? semantic_value_type_by_hir[holder] : 0u;
    for (uint local = 0u; local < width; local += 1u)
    {
        bool match_result = compact_hir_core[hir].kind == HIR_MATCH_EXPR;
        bool match_binding = match_payload_binding(hir);
        // `value?` keeps its operand's enum address (try_rows).
        bool short_circuit = semantic_lir_is_short_circuit(
            compact_hir_core[hir], compact_hir_payload[hir]) ||
            compact_hir_core[hir].kind == HIR_TRY_EXPR;
        bool try_operand = compact_hir_core[hir].kind == HIR_TRY_EXPR;
        SemanticLirLocal result;
        result.function_id = function_id;
        result.declaration_id = match_result
            ? gParams.n_tokens + hir + local * hir_count
            : short_circuit ? gParams.n_tokens + hir
            : match_binding ? semantic_value_decl_by_hir[hir]
            : receiver_temporary ? compact_hir_payload[member].c
            : local == 0u ? compact_hir_payload[hir].b : gParams.n_tokens + hir;
        result.ordinal = row + local - function.local_start;
        result.type_id = try_operand ? SEMANTIC_LIR_TY_POINTER
            : short_circuit ? 2u
            : match_result && local == 1u ? SEMANTIC_LIR_TY_POINTER
            : receiver_temporary ? holder_type
            : local == 0u ? semantic_value_type_by_hir[hir] : 3u;
        HirCore core = compact_hir_core[hir];
        HirPayload payload = compact_hir_payload[hir];
        bool for_loop = core.kind == HIR_FOR_STMT ||
            (core.kind == HIR_STMT && payload.a == HIR_STMT_FOR);
        uint scalar = semantic_expr_ref_tag[hir] == 1u ? semantic_expr_ref_payload[hir] : 0u;
        if (for_loop && scalar_is_known(scalar))
        {
            uint form = payload.c < hir_count ? compact_hir_payload[payload.c].a : 0u;
            bool range_loop = (form >= HIR_EXPR_RANGE && form <= HIR_EXPR_RANGE_TO_INCLUSIVE) ||
                semantic_iterable_kind[hir] == 1u || semantic_iterable_kind[hir] == 2u;
            if (local == 0u || range_loop) result.type_id = scalar;
        }
        semantic_lir_locals[row + local] = result;
    }
}
