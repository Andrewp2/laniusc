import native_value_layout;
import checked_semantic_artifact;
import hir_records;
import codegen.lir.semantic.common;
import codegen.lir.semantic.match_recipe;
import codegen.lir.semantic.loop_recipe;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint n_tokens; uint reserved1; uint reserved2; };
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
StructuredBuffer<uint> semantic_value_used;
StructuredBuffer<uint2> semantic_value_const_by_hir;
StructuredBuffer<uint> semantic_value_const_present_by_hir;
StructuredBuffer<uint> semantic_array_length;
StructuredBuffer<uint> semantic_iterable_kind;
StructuredBuffer<uint> semantic_argument_mode_by_hir;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> semantic_aggregate_word_count;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
StructuredBuffer<uint> type_instance_native_words;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
// Private checked copy plan per argument expression: words, storage kind.
RWStructuredBuffer<uint2> semantic_argument_value_layout;
RWStructuredBuffer<uint> semantic_lir_count;
RWStructuredBuffer<uint> semantic_place_original_count;
StructuredBuffer<uint> semantic_place_function_flags;
StructuredBuffer<uint> semantic_receiver_call_by_hir;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_match_arm_count()
{
    return min(compact_match_arm_count[0u], gParams.n_hir_nodes);
}

uint active_match_payload_count()
{
    return min(compact_match_payload_row_count[0u], gParams.n_hir_nodes);
}

#include "match_reference.slang"
#include "receiver_layout.slang"

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

// Combine the retained expected passing mode with the complete source type.
// This remains valid after a generic/imported callee's frontend page expires.
uint2 argument_value_layout(uint node, uint hir_count)
{
    uint receiver_call = semantic_receiver_call_by_hir[node];
    if (receiver_call != 0u && (semantic_calls_by_hir[receiver_call - 1u].receiver_deref_count != 0u ||
        semantic_calls_by_hir[receiver_call - 1u].receiver_adjustment_kind == 2u))
        return uint2(0u, 0u); // capture after the checked receiver adjustment
    uint mode = semantic_argument_mode_by_hir[node];
    if (mode == 4u)
    {
        // A fixed array coerced to a slice outside a call: capture a view
        // descriptor {&array, length, stride} aliasing the array's storage.
        uint tag = semantic_expr_ref_tag[node];
        uint payload = semantic_expr_ref_payload[node];
        uint capacity; uint stride;
        type_instance_kind.GetDimensions(capacity, stride);
        uint length = semantic_array_length[node];
        if (tag == 3u && payload < capacity && type_instance_kind[payload] == 2u &&
            length != LIR_INVALID && length != SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
            return uint2(NATIVE_SLICE_WORDS, 4u);
        return uint2(0u, 0u);
    }
    if (mode == 1u || mode == 2u)
    {
        uint tag = semantic_expr_ref_tag[node];
        uint payload = semantic_expr_ref_payload[node];
        uint capacity; uint stride;
        type_instance_kind.GetDimensions(capacity, stride);
        if (tag == 3u && payload < capacity)
        {
            uint kind = type_instance_kind[payload];
            // A slice borrows its backing array, but its pointer and length
            // are themselves a value. Capture the descriptor before a later
            // argument can replace a field containing it.
            if (kind == 3u) return uint2(NATIVE_SLICE_WORDS, 3u);
            if (mode == 2u) return uint2(0u, 0u);
            if (kind == 1u || kind == 2u)
            {
                uint words = type_instance_native_words[payload];
                bool packed = kind == 2u && type_instance_elem_ref_tag[payload] == 1u &&
                    type_instance_elem_ref_payload[payload] == 3u;
                return words != LIR_INVALID ? uint2(words, packed ? 2u : 1u) : uint2(0u, 0u);
            }
        }
        else if (mode == 1u && tag == 1u && payload >= 4096u)
        {
            uint words = semantic_aggregate_word_count[node];
            return words != LIR_INVALID ? uint2(words, 1u) : uint2(0u, 0u);
        }
        return uint2(0u, 0u);
    }
    return uint2(0u, 0u);
}

void count_original(uint3 dtid)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= gParams.n_hir_nodes) return;
    uint rows = 0u;
    uint2 capture = node < count && semantic_function_id[node] != LIR_INVALID
        ? argument_value_layout(node, count) : uint2(0u, 0u);
    semantic_argument_value_layout[node] = capture;
    uint capture_rows = capture.x != 0u ? 1u : 0u;
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
            uint declaration = semantic_value_id[node];
            // An unused payload needs no load or local. Preserve bindings
            // with unknown identities so missing metadata fails visibly.
            semantic_lir_count[node] = declaration < gParams.n_tokens &&
                semantic_value_used[declaration] == 0u ? 0u : 3u;
            return;
        }
        if (match_pattern_syntax(node, count))
        {
            semantic_lir_count[node] = 0u;
            return;
        }
        if (core.kind == HIR_MATCH_EXPR)
        {
            SemanticMatchRecipe match_recipe = semantic_match_recipe_for_hir(node, count);
            // Each successful arm stores its result and branches directly to
            // the enclosing match end. Only the no-match path reaches TRAP,
            // so every predecessor of the result read defines its value.
            if (!match_recipe.valid)
            {
                // Preserve a visible invalid row and reject independently of
                // target opcode support; neither target may drop this match.
                InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_SEMANTIC);
                InterlockedMin(lowering_status[0u].first_unsupported_hir, node);
                semantic_lir_count[node] = 1u + capture_rows;
            }
            else semantic_lir_count[node] = semantic_match_row_count(match_recipe) + capture_rows;
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
        uint iterable_type_kind = for_loop && payload.c < count
            ? receiver_kind(semantic_expr_ref_tag[payload.c], semantic_expr_ref_payload[payload.c]) : 0u;
        SemanticLoopRecipe recipe = semantic_loop_recipe(
            core, payload, iterable_form, iterable_kind, array_length, iterable_type_kind);
        rows = owned_syntax ? 0u : recipe.row_count;
    }
    semantic_lir_count[node] = rows != 0u ? rows + capture_rows : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    count_original(dtid);
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (node >= gParams.n_hir_nodes) return;
    uint original = semantic_lir_count[node];
    semantic_place_original_count[node] = original;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (node >= count || semantic_function_id[node] == LIR_INVALID) return;
    if (compact_hir_core[node].kind == 3u && semantic_place_function_flags[node] != 0u)
    {
        SemanticLirFunction function = semantic_lir_functions[semantic_function_id[node]];
        semantic_lir_count[node] = function.param_count + function.local_count;
        return;
    }
    uint extra = projection_adjustment_rows(node, count);
    uint words = 0u;
    uint encoded = semantic_receiver_call_by_hir[node];
    if (encoded != 0u)
    {
        CheckedCallArtifact call = semantic_calls_by_hir[encoded - 1u];
        if (extra != 0u) extra = LIR_INVALID; // one source expression has one value consumer
        else extra = receiver_adjustment_rows(call);
        words = receiver_native_words(call.receiver_matched_ref_tag, call.receiver_matched_ref_payload, count);
    }
    if (extra == 0u && encoded == 0u) return;
    if (original == 0u || extra == LIR_INVALID || words == LIR_INVALID || words > 0xffffu || original > LIR_INVALID - extra)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_SEMANTIC);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, node);
        return;
    }
    semantic_lir_count[node] = original + extra;
}
