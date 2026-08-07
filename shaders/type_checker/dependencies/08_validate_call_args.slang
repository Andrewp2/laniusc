// Validate dependency-call roots and publish one compact parallel comparison
// span per compound argument. Generic children are checked by
// 08b_validate_call_type_args after a prefix scan; this pass never walks a
// variable-width type argument list in one invocation.

import dependency_interface;
import hir_records;
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
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
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
static const uint TYPE_LEN_CONST_PARAM = 2u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
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

uint scalar_type_for_argument(uint node, uint token)
{
    if (!valid_hir(node))
        return HIR_SEM_TY_UNKNOWN;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    uint scalar = hir_scalar_type_for_expr_form(payload.a);
    if (scalar != HIR_SEM_TY_UNKNOWN)
        return scalar;
    if (core.kind == HIR_CALL_EXPR)
    {
        uint callee = callee_token(node);
        if (callee != INVALID && callee < gParams.visible_capacity)
            return call_return_type[callee];
    }
    return token < gParams.visible_capacity ? visible_type[token] : HIR_SEM_TY_UNKNOWN;
}

// Dependency calls use the same implicit scalar conversions as local calls.
// In particular, an unsuffixed integer literal is initially typed as i32 but
// is valid when the imported signature expects u32/usize (and vice versa).
bool assignable(uint expected, uint actual)
{
    if (expected == TY_UNKNOWN || actual == TY_UNKNOWN || expected == actual)
        return true;
    if (expected == TY_INT)
        return actual == TY_UINT || actual == TY_CHAR;
    if (expected == TY_UINT)
        return actual == TY_INT || actual == TY_CHAR;
    if (expected == TY_FLOAT)
        return actual == TY_INT || actual == TY_UINT || actual == TY_CHAR;
    return false;
}

bool stable_nominal_matches(
    uint expected_type_i,
    uint actual_token,
    uint actual_canonical_type)
{
    uint type_count = dependency_count(4u);
    if (expected_type_i >= type_count || actual_token >= gParams.visible_capacity)
        return false;
    uint expected = canonical_type_roots[expected_type_i];
    uint expected_base = expected * TYPE_WORDS;
    if (dependency_type_word(expected_base) != INTERFACE_TYPE_DECLARATION)
        return false;
    uint actual_library = external_type_library_id[actual_token];
    uint actual_unit = external_type_unit_id[actual_token];
    uint actual_local = external_type_local_index[actual_token];
    if (actual_library != INVALID && actual_unit != INVALID && actual_local != INVALID)
        return dependency_type_word(expected_base + 1u) == actual_library &&
               dependency_type_word(expected_base + 2u) == actual_local &&
               dependency_type_word(expected_base + 8u) == actual_unit;

    // A direct external-canonical reference already carries the page-local
    // canonical row. Use that row when the declaration-level stable identity
    // columns have not yet been republished after workspace clearing.
    if (actual_canonical_type >= type_count)
        return false;
    uint actual = canonical_type_roots[actual_canonical_type];
    if (actual >= type_count)
        return false;
    uint actual_base = actual * TYPE_WORDS;
    return dependency_type_word(actual_base) == INTERFACE_TYPE_DECLARATION &&
           dependency_type_word(expected_base + 1u) == dependency_type_word(actual_base + 1u) &&
           dependency_type_word(expected_base + 2u) == dependency_type_word(actual_base + 2u) &&
           dependency_type_word(expected_base + 8u) == dependency_type_word(actual_base + 8u);
}

uint canonical_subtree_count(uint root)
{
    uint type_count = dependency_count(4u);
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
    uint semantic_count = min(compact_hir_count[0u], gParams.hir_capacity);
    if (root >= semantic_count || type_semantic_scan_input[root] == 0u)
        return INVALID;
    uint end = compact_hir_links[root].subtree_end;
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
    uint declaration_i = dependency_find_declaration(
        call_dependency_library_id[callee],
        call_dependency_unit_id[callee],
        call_dependency_local_index[callee]);
    if (declaration_i == INVALID)
        return;

    uint signature_i = dependency_declaration_word(declaration_i * DECL_WORDS + 7u);
    uint signature_base = signature_i * TYPE_WORDS;
    if (dependency_type_word(signature_base) != INTERFACE_TYPE_FUNCTION)
        return;
    uint first_edge = dependency_type_word(signature_base + 3u);
    uint edge_count = dependency_type_word(signature_base + 4u);
    uint ordinal = arg.ordinal;
    if (edge_count == 0u || ordinal >= edge_count - 1u)
        return;
    uint expected_type_i = canonical_type_roots[dependency_type_edge_word(first_edge + ordinal)];
    uint expected_base = expected_type_i * TYPE_WORDS;
    uint expected_kind = dependency_type_word(expected_base);

    // Imported function generics participate in the shared compact call-row
    // claim pipeline. This late structural validator must not second-guess the
    // substitution relation with an uninstantiated interface node.
    if (expected_kind == INTERFACE_TYPE_GENERIC_PARAMETER)
        return;

    uint expr_node = arg_node;
    uint arg_token = compact_hir_core[expr_node].token_start;
    uint actual = scalar_type_for_argument(expr_node, arg_token);
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
        uint expected_count = dependency_type_word(expected_base + 4u);
        bool matches = false;
        if (expected_kind == INTERFACE_TYPE_DECLARATION &&
            actual_tag == TYPE_REF_EXTERNAL_CANONICAL)
        {
            matches = stable_nominal_matches(
                          expected_type_i, actual_ref_token, actual_payload) &&
                      expected_count == 0u;
        }
        else if (expected_kind == INTERFACE_TYPE_DECLARATION &&
                 actual_tag == TYPE_REF_INSTANCE &&
                 actual_payload < gParams.visible_capacity)
        {
            matches = stable_nominal_matches(expected_type_i, actual_payload, INVALID) &&
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
            // A dependency interface preserves a const-generic array length
            // as TYPE_LEN_CONST_PARAM. Its concrete value is inferred from
            // the argument; only literal-length parameters require an exact
            // equality at this stage.
            bool generic_length = expected_kind == INTERFACE_TYPE_ARRAY &&
                dependency_type_word(expected_base + 5u) == TYPE_LEN_CONST_PARAM;
            if (matches && expected_kind == INTERFACE_TYPE_ARRAY && !generic_length)
                matches = type_instance_len_kind[actual_payload] ==
                              dependency_type_word(expected_base + 5u) &&
                          type_instance_len_payload[actual_payload] ==
                              dependency_type_word(expected_base + 6u);
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
    uint expected = dependency_type_word(expected_base + 1u);
    if (actual == HIR_SEM_TY_UNKNOWN && arg_token < gParams.visible_capacity)
        actual = visible_type[arg_token];
    if (!assignable(expected, actual))
        record_min_token_error(
            status,
            arg_token < gParams.visible_capacity ? arg_token : callee,
            ERR_ASSIGN_MISMATCH,
            expected * 256u + actual);
}
