// Validate dependency-call roots and publish one compact parallel comparison
// span per compound argument. Generic children are checked by
// 08b_validate_call_type_args after a prefix scan; this pass never walks a
// variable-width type argument list in one invocation.

import gpu_index;
import hir_expr_semantics;
import status;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};

ConstantBuffer<Params> gParams;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirCallArg { uint call; uint value; uint ordinal; uint file_id; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_subtree_end;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_instance_external_canonical;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> dependency_counts;
StructuredBuffer<uint> dependency_declaration_words;
StructuredBuffer<uint> dependency_type_words;
StructuredBuffer<uint> dependency_type_edge_words;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> canonical_type_subtree_start;
StructuredBuffer<uint> type_semantic_row_by_token;
StructuredBuffer<uint> type_semantic_scan_input;
StructuredBuffer<uint> type_semantic_prefix;
StructuredBuffer<uint> type_semantic_count_out;
RWStructuredBuffer<uint> dependency_call_compare_scan_input;
RWStructuredBuffer<uint> dependency_call_compare_expected_type;
RWStructuredBuffer<uint> dependency_call_compare_actual_instance;
RWStructuredBuffer<uint> dependency_call_compare_error_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint TYPE_WORDS = 9u;
static const uint EXPR_WORDS = 4u;
static const uint INTERFACE_TYPE_SCALAR = 1u;
static const uint INTERFACE_TYPE_GENERIC_PARAMETER = 2u;
static const uint INTERFACE_TYPE_FUNCTION = 7u;
static const uint INTERFACE_TYPE_DECLARATION = 3u;
static const uint INTERFACE_TYPE_ARRAY = 4u;
static const uint INTERFACE_TYPE_SLICE = 5u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count()
{
    return min(gParams.hir_capacity, compact_hir_count[0u]);
}

uint active_arg_count() { return min(gParams.hir_capacity, compact_call_arg_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }

uint callee_token(uint call)
{
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR) return INVALID;
    uint callee = compact_hir_payload[call].a;
    if (!valid_hir(callee)) return INVALID;
    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = core.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (token >= gParams.visible_capacity) token = core.token_start;
    return token < gParams.visible_capacity ? token : INVALID;
}

bool canonical_nominal_matches(uint expected_type_i, uint actual_type_i)
{
    uint type_count = dependency_counts[4u];
    if (expected_type_i >= type_count || actual_type_i >= type_count)
        return false;
    uint expected = canonical_type_roots[expected_type_i];
    uint actual = canonical_type_roots[actual_type_i];
    uint expected_base = expected * TYPE_WORDS;
    uint actual_base = actual * TYPE_WORDS;
    return dependency_type_words[expected_base] == INTERFACE_TYPE_DECLARATION &&
           dependency_type_words[actual_base] == INTERFACE_TYPE_DECLARATION &&
           dependency_type_words[expected_base + 1u] == dependency_type_words[actual_base + 1u] &&
           dependency_type_words[expected_base + 2u] == dependency_type_words[actual_base + 2u] &&
           dependency_type_words[expected_base + 8u] == dependency_type_words[actual_base + 8u];
}

uint canonical_subtree_count(uint root)
{
    uint type_count = dependency_counts[4u];
    if (root >= type_count)
        return INVALID;
    uint start = canonical_type_subtree_start[root];
    return start <= root ? root - start + 1u : INVALID;
}

uint local_type_subtree_count(uint instance)
{
    if (instance >= gParams.visible_capacity)
        return INVALID;
    uint root = type_semantic_row_by_token[instance];
    uint semantic_count = min(hir_semantic_count[0u], gParams.hir_capacity);
    if (root >= semantic_count || type_semantic_scan_input[root] == 0u)
        return INVALID;
    uint end = hir_semantic_subtree_end[root];
    if (end <= root || end > semantic_count)
        return INVALID;
    uint begin_ordinal = type_semantic_prefix[root];
    uint end_ordinal = end == semantic_count
        ? type_semantic_count_out[0u]
        : type_semantic_prefix[end];
    return end_ordinal > begin_ordinal ? end_ordinal - begin_ordinal : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= active_arg_count()) return;
    HirCallArg arg = compact_call_args[row];
    if (!valid_hir(arg.call) || !valid_hir(arg.value)) return;
    uint arg_node = arg.value;
    uint callee = callee_token(arg.call);
    if (callee == INVALID) return;
    uint declaration_i = call_dependency_decl[callee];
    if (declaration_i == INVALID || declaration_i >= gParams.declaration_count)
        return;

    uint signature_i = dependency_declaration_words[declaration_i * DECL_WORDS + 7u];
    uint signature_base = signature_i * TYPE_WORDS;
    if (dependency_type_words[signature_base] != INTERFACE_TYPE_FUNCTION)
        return;
    uint first_edge = dependency_type_words[signature_base + 3u];
    uint edge_count = dependency_type_words[signature_base + 4u];
    uint ordinal = arg.ordinal;
    if (edge_count == 0u || ordinal >= edge_count - 1u)
        return;
    uint expected_type_i = canonical_type_roots[dependency_type_edge_words[first_edge + ordinal]];
    uint expected_base = expected_type_i * TYPE_WORDS;
    uint expected_kind = dependency_type_words[expected_base];

    // Imported function generics participate in the shared compact call-row
    // claim pipeline. This late structural validator must not second-guess the
    // substitution relation with an uninstantiated interface node.
    if (expected_kind == INTERFACE_TYPE_GENERIC_PARAMETER)
        return;

    uint expr_node = arg_node;
    uint form = compact_hir_payload[expr_node].a;
    uint actual = hir_scalar_type_for_expr_form(form);
    uint arg_token = compact_hir_core[expr_node].token_start;
    if (expected_kind != INTERFACE_TYPE_SCALAR)
    {
        uint actual_ref_token = arg_token;
        if (arg_token < gParams.visible_capacity &&
            visible_decl[arg_token] < gParams.visible_capacity)
            actual_ref_token = visible_decl[arg_token];
        uint actual_tag = actual_ref_token < gParams.visible_capacity
            ? decl_type_ref_tag[actual_ref_token]
            : 0u;
        uint actual_payload = actual_ref_token < gParams.visible_capacity
            ? decl_type_ref_payload[actual_ref_token]
            : INVALID;
        uint expected_count = dependency_type_words[expected_base + 4u];
        bool matches = false;
        if (expected_kind == INTERFACE_TYPE_DECLARATION &&
            actual_tag == TYPE_REF_EXTERNAL_CANONICAL)
        {
            matches = canonical_nominal_matches(expected_type_i, actual_payload) &&
                      expected_count == 0u;
        }
        else if (expected_kind == INTERFACE_TYPE_DECLARATION &&
                 actual_tag == TYPE_REF_INSTANCE &&
                 actual_payload < gParams.visible_capacity)
        {
            uint actual_canonical = type_instance_external_canonical[actual_payload];
            matches = actual_canonical != INVALID &&
                      canonical_nominal_matches(expected_type_i, actual_canonical) &&
                      type_instance_arg_count[actual_payload] == expected_count;
            if (matches && expected_count != 0u)
            {
                uint expected_subtree_count = canonical_subtree_count(expected_type_i);
                uint actual_subtree_count = local_type_subtree_count(actual_payload);
                matches = expected_subtree_count != INVALID &&
                          expected_subtree_count == actual_subtree_count;
                dependency_call_compare_scan_input[arg_node] = matches
                    ? expected_subtree_count
                    : 0u;
                dependency_call_compare_expected_type[arg_node] = expected_type_i;
                dependency_call_compare_actual_instance[arg_node] = actual_payload;
                dependency_call_compare_error_token[arg_node] =
                    arg_token < gParams.visible_capacity ? arg_token : callee;
            }
        }
        else if ((expected_kind == INTERFACE_TYPE_ARRAY ||
                  expected_kind == INTERFACE_TYPE_SLICE) &&
                 actual_tag == TYPE_REF_INSTANCE &&
                 actual_payload < gParams.visible_capacity)
        {
            uint expected_instance_kind = expected_kind == INTERFACE_TYPE_ARRAY
                ? TYPE_INSTANCE_ARRAY
                : TYPE_INSTANCE_SLICE;
            matches = type_instance_kind[actual_payload] == expected_instance_kind &&
                      expected_count == 1u;
            if (matches && expected_kind == INTERFACE_TYPE_ARRAY)
                matches = type_instance_len_kind[actual_payload] ==
                              dependency_type_words[expected_base + 5u] &&
                          type_instance_len_payload[actual_payload] ==
                              dependency_type_words[expected_base + 6u];
            if (matches)
            {
                uint expected_subtree_count = canonical_subtree_count(expected_type_i);
                uint actual_subtree_count = local_type_subtree_count(actual_payload);
                matches = expected_subtree_count != INVALID &&
                          expected_subtree_count == actual_subtree_count;
                dependency_call_compare_scan_input[arg_node] = matches
                    ? expected_subtree_count
                    : 0u;
                dependency_call_compare_expected_type[arg_node] = expected_type_i;
                dependency_call_compare_actual_instance[arg_node] = actual_payload;
                dependency_call_compare_error_token[arg_node] =
                    arg_token < gParams.visible_capacity ? arg_token : callee;
            }
        }
        if (!matches)
            record_min_token_error(
                status,
                arg_token < gParams.visible_capacity ? arg_token : callee,
                ERR_ASSIGN_MISMATCH,
                HIR_SEM_TY_UNKNOWN);
        return;
    }
    uint expected = dependency_type_words[expected_base + 1u];
    if (actual == HIR_SEM_TY_UNKNOWN && arg_token < gParams.visible_capacity)
        actual = visible_type[arg_token];
    if (actual != expected)
        record_min_token_error(
            status,
            arg_token < gParams.visible_capacity ? arg_token : callee,
            ERR_ASSIGN_MISMATCH,
            expected * 256u + actual);
}
