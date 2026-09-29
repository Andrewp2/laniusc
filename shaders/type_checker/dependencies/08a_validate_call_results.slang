// Validate direct dependency-call results against the enclosing function's
// authoritative return type. Compound children are published into the same
// prefix-scanned comparison relation used for dependency-call arguments.

import dependency_interface;
import hir_records;
import gpu_index;
import status;
import type_checker.calls.claim_lookup;

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
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
StructuredBuffer<uint> declaration_generic_arity;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> canonical_type_roots;
StructuredBuffer<uint> canonical_type_subtree_start;
StructuredBuffer<uint> type_semantic_row_by_token;
StructuredBuffer<uint> type_semantic_scan_input;
StructuredBuffer<uint> type_semantic_prefix;
StructuredBuffer<uint> type_semantic_count_out;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_type;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_ref_payload;
StructuredBuffer<uint> call_generic_claim_lookup_head;
StructuredBuffer<uint> call_generic_claim_lookup_next;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> call_return_aggregate_word_count;
RWStructuredBuffer<uint> call_result_instance;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
RWStructuredBuffer<uint> aggregate_compare_scan_input;
RWStructuredBuffer<uint> aggregate_compare_expected_instance;
RWStructuredBuffer<uint> aggregate_compare_actual_instance;
RWStructuredBuffer<uint> aggregate_compare_error_token;
RWStructuredBuffer<uint> aggregate_compare_error_detail;
RWStructuredBuffer<uint> dependency_call_compare_scan_input;
RWStructuredBuffer<uint> dependency_call_compare_expected_type;
RWStructuredBuffer<uint> dependency_call_compare_actual_instance;
RWStructuredBuffer<uint> dependency_call_compare_error_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_WORDS = 9u;
static const uint DECL_WORDS = 14u;
static const uint MEMBER_WORDS = 11u;
static const uint MEMBER_ENUM_VARIANT = 5u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint INTERFACE_TYPE_SCALAR = 1u;
static const uint INTERFACE_TYPE_GENERIC_PARAMETER = 2u;
static const uint INTERFACE_TYPE_DECLARATION = 3u;
static const uint INTERFACE_TYPE_FUNCTION = 7u;
static const uint INTERFACE_TYPE_ARRAY = 4u;
static const uint INTERFACE_TYPE_SLICE = 5u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint HIR_STMT_CONST = 4u;
static const uint HIR_STMT_ASSIGN = 5u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;

uint active_hir_count()
{
    return min(gParams.hir_capacity, compact_hir_count[0u]);
}

uint enclosing_function_decl_token(uint token)
{
    if (token == INVALID || token >= gParams.visible_capacity)
        return INVALID;
    uint encoded_fn = enclosing_fn[token];
    uint fn_node = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    uint count = min(compact_hir_count[0u], gParams.hir_capacity);
    if (fn_node == INVALID || fn_node >= count)
        return INVALID;
    uint fn_token = compact_hir_payload[fn_node].b;
    return fn_token < gParams.visible_capacity ? fn_token : INVALID;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.visible_capacity;
}

uint dependency_call_token(uint call)
{
    if (!valid_node(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return INVALID;
    uint callee_node = compact_hir_payload[call].a;
    if (!valid_node(callee_node))
        return INVALID;
    HirCore callee_core = compact_hir_core[callee_node];
    HirPayload callee_payload = compact_hir_payload[callee_node];
    uint token = callee_core.kind == HIR_MEMBER_EXPR
        ? callee_payload.c
        : callee_payload.d;
    if (!valid_token(token)) token = callee_core.token_start;
    return valid_token(token) &&
                   call_dependency_library_id[token] != INVALID &&
                   dependency_find_declaration(
                       call_dependency_library_id[token],
                       call_dependency_unit_id[token],
                       call_dependency_local_index[token]) != INVALID
               ? token
               : INVALID;
}

void declaration_ref(uint token, out uint tag, out uint payload)
{
    tag = 0u;
    payload = INVALID;
    if (!valid_token(token)) return;
    uint declaration = visible_decl[token];
    if (!valid_token(declaration)) declaration = token;
    tag = decl_type_ref_tag[declaration];
    payload = decl_type_ref_payload[declaration];
}

void expected_ref_for_statement(
    uint node,
    out uint expression,
    out uint tag,
    out uint payload,
    out uint enclosing_function)
{
    expression = INVALID;
    tag = 0u;
    payload = INVALID;
    enclosing_function = INVALID;
    if (!valid_node(node)) return;
    HirCore core = compact_hir_core[node];
    HirPayload statement = compact_hir_payload[node];
    if (statement.a == HIR_STMT_LET ||
        (core.kind == HIR_STMT && statement.a == HIR_STMT_CONST))
    {
        expression = statement.c;
        if (valid_node(statement.d))
        {
            uint token = compact_hir_core[statement.d].token_start;
            if (valid_token(token))
            {
                tag = type_expr_ref_tag[token];
                payload = type_expr_ref_payload[token];
            }
        }
        if (tag == 0u)
            declaration_ref(compact_hir_core[node].token_start, tag, payload);
        if (tag == 0u)
            declaration_ref(statement.b, tag, payload);
    }
    else if (statement.a == HIR_STMT_ASSIGN)
    {
        expression = statement.c;
        if (valid_node(statement.b))
            declaration_ref(compact_hir_core[statement.b].token_start, tag, payload);
    }
    else if (statement.a == HIR_STMT_RETURN || core.kind == HIR_RETURN_STMT)
    {
        expression = statement.b;
        if (valid_token(core.token_start))
            enclosing_function = enclosing_function_decl_token(core.token_start);
        if (valid_token(enclosing_function))
        {
            tag = fn_return_ref_tag[enclosing_function];
            payload = fn_return_ref_payload[enclosing_function];
        }
    }
}

bool dependency_nominal_matches_token(uint expected_type_i, uint token)
{
    uint type_count = dependency_count(4u);
    if (expected_type_i >= type_count || !valid_token(token))
        return false;
    uint expected = canonical_type_roots[expected_type_i];
    uint base = expected * TYPE_WORDS;
    return dependency_type_word(base) == INTERFACE_TYPE_DECLARATION &&
           dependency_type_word(base + 1u) == external_type_library_id[token] &&
           dependency_type_word(base + 2u) == external_type_local_index[token] &&
           dependency_type_word(base + 8u) == external_type_unit_id[token];
}

bool stable_nominal_equal(uint lhs_token, uint rhs_token)
{
    return valid_token(lhs_token) && valid_token(rhs_token) &&
           external_type_library_id[lhs_token] != INVALID &&
           external_type_library_id[lhs_token] == external_type_library_id[rhs_token] &&
           external_type_unit_id[lhs_token] == external_type_unit_id[rhs_token] &&
           external_type_local_index[lhs_token] == external_type_local_index[rhs_token];
}

bool canonical_nominal_equal(uint lhs, uint rhs)
{
    uint type_count = dependency_count(4u);
    if (lhs >= type_count || rhs >= type_count)
        return false;
    lhs = canonical_type_roots[lhs];
    rhs = canonical_type_roots[rhs];
    if (lhs >= type_count || rhs >= type_count)
        return false;
    uint lhs_base = lhs * TYPE_WORDS;
    uint rhs_base = rhs * TYPE_WORDS;
    return dependency_type_word(lhs_base) == INTERFACE_TYPE_DECLARATION &&
           dependency_type_word(rhs_base) == INTERFACE_TYPE_DECLARATION &&
           dependency_type_word(lhs_base + 1u) == dependency_type_word(rhs_base + 1u) &&
           dependency_type_word(lhs_base + 2u) == dependency_type_word(rhs_base + 2u) &&
           dependency_type_word(lhs_base + 8u) == dependency_type_word(rhs_base + 8u);
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
    if (!valid_token(instance))
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

void mismatch(uint token)
{
    record_min_token_error(status, valid_token(token) ? token : 0u, ERR_ASSIGN_MISMATCH, 0u);
}

uint generic_claim_capacity()
{
    uint base = max(gParams.visible_capacity, gParams.hir_capacity);
    return base > 0xffffffffu / GENERIC_CLAIM_CAPACITY_MULTIPLIER
        ? 0xffffffffu
        : base * GENERIC_CLAIM_CAPACITY_MULTIPLIER;
}

uint concrete_claim_row(uint callee, uint slot, uint count)
{
    uint bucket = call_claim_lookup_bucket(callee, slot, count);
    uint link = call_generic_claim_lookup_head[bucket];
    uint result = INVALID;
    for (uint step = 0u; step < count && link != 0u; step += 1u)
    {
        uint row = link - 1u;
        if (row >= count)
            break;
        if (call_generic_claim_callee[row] == callee &&
            call_generic_claim_slot[row] == slot &&
            (call_generic_claim_type[row] != 0u || call_generic_claim_ref_tag[row] != 0u))
        {
            result = min(result, row);
        }
        link = call_generic_claim_lookup_next[row];
    }
    return result;
}

bool instance_arg_ref(uint instance, uint slot, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(instance) || slot >= type_instance_arg_count[instance])
        return false;
    uint start = type_instance_arg_row_start[instance];
    uint row = start == INVALID ? INVALID : start + slot;
    if (row != INVALID && row < type_instance_arg_row_count_out[0u])
    {
        tag = type_instance_arg_row_ref_tag[row];
        payload = type_instance_arg_row_ref_payload[row];
        if (tag != TYPE_REF_INVALID)
            return true;
    }
    if (slot >= 4u)
        return false;
    uint fixed = instance * 4u + slot;
    tag = type_instance_arg_ref_tag[fixed];
    payload = type_instance_arg_ref_payload[fixed];
    return tag != TYPE_REF_INVALID;
}

bool claim_matches_instance_arg(uint callee, uint slot, uint instance)
{
    uint expected_tag;
    uint expected_payload;
    if (!instance_arg_ref(instance, slot, expected_tag, expected_payload))
        return false;
    uint count = min(call_generic_claim_count_out[0u], generic_claim_capacity());
    uint claim = concrete_claim_row(callee, slot, count);
    if (claim == INVALID)
        return false;
    uint claim_tag = call_generic_claim_ref_tag[claim];
    uint claim_payload = call_generic_claim_ref_payload[claim];
    if (expected_tag == TYPE_REF_SCALAR)
        return (claim_tag == TYPE_REF_SCALAR && claim_payload == expected_payload) ||
               (claim_tag == TYPE_REF_INVALID &&
                call_generic_claim_type[claim] == expected_payload);
    if (expected_tag != TYPE_REF_INSTANCE || claim_tag != TYPE_REF_INSTANCE ||
        !valid_token(expected_payload) || !valid_token(claim_payload))
        return false;
    if (expected_payload == claim_payload)
        return true;
    if (type_instance_kind[expected_payload] != 1u ||
        type_instance_kind[claim_payload] != 1u ||
        type_instance_arg_count[expected_payload] != 0u ||
        type_instance_arg_count[claim_payload] != 0u)
        return false;
    uint expected_decl = type_instance_decl_token[expected_payload];
    uint claimed_decl = type_instance_decl_token[claim_payload];
    if (valid_token(expected_decl) || valid_token(claimed_decl))
        return valid_token(expected_decl) && expected_decl == claimed_decl;
    return stable_nominal_equal(expected_payload, claim_payload);
}

uint direct_payload_words(uint type_root, uint instance)
{
    uint base = type_root * TYPE_WORDS;
    uint kind = dependency_type_word(base);
    if (kind == INTERFACE_TYPE_SCALAR)
    {
        uint scalar = dependency_type_word(base + 1u);
        return scalar == 0u ? 0u : scalar == 7u ? 2u : scalar < 128u ? 1u : 0u;
    }
    if (kind != INTERFACE_TYPE_GENERIC_PARAMETER)
        return 0u;
    uint slot = dependency_type_word(base + 1u);
    uint tag;
    uint payload;
    if (!instance_arg_ref(instance, slot, tag, payload) ||
        tag != TYPE_REF_SCALAR)
        return 0u;
    return payload == 7u ? 2u : payload != 0u && payload < 128u ? 1u : 0u;
}

uint concrete_enum_words(uint parent, uint return_root, uint instance)
{
    uint parent_base = parent * DECL_WORDS;
    uint start = dependency_declaration_word(parent_base + 8u);
    uint count = dependency_declaration_word(parent_base + 9u);
    if (start > dependency_member_count() ||
        count > dependency_member_count() - start)
        return 0u;
    uint maximum = 0u;
    for (uint member_ordinal = 0u; member_ordinal < count; member_ordinal += 1u)
    {
        uint member_base = (start + member_ordinal) * MEMBER_WORDS;
        if (dependency_member_word(member_base + 1u) != MEMBER_ENUM_VARIANT)
            continue;
        uint signature = dependency_member_word(member_base + 7u);
        if (signature >= dependency_count(4u))
            return 0u;
        uint signature_root = canonical_type_roots[signature];
        uint signature_base = signature_root * TYPE_WORDS;
        if (dependency_type_word(signature_base) != INTERFACE_TYPE_FUNCTION)
            return 0u;
        uint edge_start = dependency_type_word(signature_base + 3u);
        uint edge_count = dependency_type_word(signature_base + 4u);
        if (edge_count == 0u || edge_start > dependency_count(5u) ||
            edge_count > dependency_count(5u) - edge_start)
            return 0u;
        uint return_edge = dependency_type_edge_word(edge_start + edge_count - 1u);
        if (return_edge >= dependency_count(4u) ||
            canonical_type_roots[return_edge] != return_root)
            return 0u;
        uint words = 1u;
        for (uint ordinal = 0u; ordinal + 1u < edge_count; ordinal += 1u)
        {
            uint payload = dependency_type_edge_word(edge_start + ordinal);
            if (payload >= dependency_count(4u))
                return 0u;
            uint payload_words = direct_payload_words(canonical_type_roots[payload], instance);
            if (payload_words == 0u || words > 0xffffffffu - payload_words)
                return 0u;
            words += payload_words;
        }
        maximum = max(maximum, words);
    }
    return maximum;
}

bool bare_generic_variant_result_matches(
    uint callee, uint return_root, uint expected_instance, out uint words)
{
    words = 0u;
    uint variant = dependency_find_declaration(
        call_dependency_library_id[callee],
        call_dependency_unit_id[callee],
        call_dependency_local_index[callee]);
    if (variant >= dependency_declaration_count() ||
        dependency_declaration_word(variant * DECL_WORDS + 6u) !=
            HIR_ITEM_KIND_ENUM_VARIANT)
        return false;
    uint parent = dependency_declaration_word(variant * DECL_WORDS + 10u);
    if (parent >= dependency_declaration_count() ||
        dependency_declaration_word(parent * DECL_WORDS + 6u) != HIR_ITEM_KIND_ENUM ||
        declaration_generic_arity[parent] != type_instance_arg_count[expected_instance])
        return false;
    uint parent_signature = dependency_declaration_word(parent * DECL_WORDS + 7u);
    uint type_count = dependency_count(4u);
    if (parent_signature >= type_count ||
        canonical_type_roots[parent_signature] != return_root)
        return false;
    uint signature = dependency_declaration_word(variant * DECL_WORDS + 7u);
    if (signature >= type_count)
        return false;
    uint signature_root = canonical_type_roots[signature];
    uint signature_base = signature_root * TYPE_WORDS;
    if (dependency_type_word(signature_base) != INTERFACE_TYPE_FUNCTION)
        return false;
    uint edge_start = dependency_type_word(signature_base + 3u);
    uint edge_count = dependency_type_word(signature_base + 4u);
    if (edge_count == 0u || edge_count > 5u ||
        edge_start > dependency_count(5u) ||
        edge_count > dependency_count(5u) - edge_start)
        return false;
    uint return_edge = dependency_type_edge_word(edge_start + edge_count - 1u);
    if (return_edge >= type_count || canonical_type_roots[return_edge] != return_root)
        return false;
    for (uint ordinal = 0u; ordinal + 1u < edge_count; ordinal += 1u)
    {
        uint child = dependency_type_edge_word(edge_start + ordinal);
        if (child >= type_count)
            return false;
        uint root = canonical_type_roots[child];
        uint base = root * TYPE_WORDS;
        uint kind = dependency_type_word(base);
        if (kind == INTERFACE_TYPE_SCALAR)
            continue;
        if (kind != INTERFACE_TYPE_GENERIC_PARAMETER)
            return false;
        uint slot = dependency_type_word(base + 1u);
        if (slot >= type_instance_arg_count[expected_instance] ||
            !claim_matches_instance_arg(callee, slot, expected_instance))
            return false;
    }
    words = concrete_enum_words(parent, return_root, expected_instance);
    return words != 0u;
}

void substitute_direct_generic_call(uint call_node)
{
    uint callee_node = compact_hir_payload[call_node].a;
    if (!valid_node(callee_node))
        return;
    HirCore callee_core = compact_hir_core[callee_node];
    HirPayload callee_payload = compact_hir_payload[callee_node];
    uint callee_token = callee_core.kind == HIR_MEMBER_EXPR
        ? callee_payload.c
        : callee_payload.d;
    if (!valid_token(callee_token)) callee_token = callee_core.token_start;
    if (!valid_token(callee_token) ||
        dependency_find_declaration(
            call_dependency_library_id[callee_token],
            call_dependency_unit_id[callee_token],
            call_dependency_local_index[callee_token]) == INVALID ||
        decl_type_ref_tag[callee_token] != TYPE_REF_EXTERNAL_CANONICAL)
        return;
    uint return_i = decl_type_ref_payload[callee_token];
    uint type_count = dependency_count(4u);
    if (return_i >= type_count)
        return;
    uint return_root = canonical_type_roots[return_i];
    uint return_base = return_root * TYPE_WORDS;
    if (dependency_type_word(return_base) != INTERFACE_TYPE_GENERIC_PARAMETER)
        return;
    uint slot = dependency_type_word(return_base + 1u);
    uint count = min(call_generic_claim_count_out[0u], generic_claim_capacity());
    uint row = concrete_claim_row(callee_token, slot, count);
    if (row == INVALID)
        return;
    uint inferred = call_generic_claim_type[row];
    uint inferred_tag = call_generic_claim_ref_tag[row];
    uint inferred_payload = call_generic_claim_ref_payload[row];
    if (inferred == 0u && inferred_tag == 0u)
        return;
    call_return_type[callee_token] = inferred_tag == TYPE_REF_INSTANCE ? 0u : inferred;
    if (inferred_tag != 0u)
    {
        call_return_type_token[callee_token] = callee_token;
        decl_type_ref_tag[callee_token] = inferred_tag;
        decl_type_ref_payload[callee_token] = inferred_payload;
    }
    else
    {
        call_return_type_token[callee_token] = INVALID;
        decl_type_ref_tag[callee_token] = TYPE_REF_SCALAR;
        decl_type_ref_payload[callee_token] = inferred;
    }
}

void validate_dependency_result(
    uint statement_node,
    uint call_node,
    uint callee_token,
    uint expected_tag,
    uint expected_payload,
    uint expected_external_token)
{
    if (!valid_token(callee_token)) return;
    uint actual_tag = decl_type_ref_tag[callee_token];
    uint actual_payload = decl_type_ref_payload[callee_token];
    if (actual_tag == TYPE_REF_INSTANCE && valid_token(actual_payload))
    {
        if (expected_tag != TYPE_REF_INSTANCE || !valid_token(expected_payload))
        {
            mismatch(callee_token);
            return;
        }
        uint child_count = type_instance_arg_count[actual_payload];
        if (!stable_nominal_equal(actual_payload, expected_payload) ||
            child_count != type_instance_arg_count[expected_payload])
        {
            mismatch(callee_token);
            return;
        }
        call_result_instance[call_node] = expected_payload;
        if (child_count != 0u)
        {
            aggregate_compare_scan_input[statement_node] = child_count;
            aggregate_compare_expected_instance[statement_node] = expected_payload;
            aggregate_compare_actual_instance[statement_node] = actual_payload;
            aggregate_compare_error_token[statement_node] = callee_token;
            aggregate_compare_error_detail[statement_node] = 0u;
        }
        return;
    }
    if (actual_tag != TYPE_REF_EXTERNAL_CANONICAL)
        return;

    uint actual_canonical = actual_payload;
    uint type_count = dependency_count(4u);
    if (actual_canonical >= type_count)
    {
        mismatch(callee_token);
        return;
    }
    uint actual_root = canonical_type_roots[actual_canonical];
    uint actual_base = actual_root * TYPE_WORDS;
    // The same pass first substitutes call nodes and is dispatched again after
    // a storage barrier for result validation. A statement lane may observe
    // the pre-substitution generic root during the first dispatch; defer it
    // rather than racing the call lane and recording a false mismatch.
    if (dependency_type_word(actual_base) == INTERFACE_TYPE_GENERIC_PARAMETER)
        return;
    uint actual_count = dependency_type_word(actual_base + 4u);
    if (expected_tag == TYPE_REF_EXTERNAL_CANONICAL)
    {
        bool matches = expected_payload < type_count &&
            (canonical_type_roots[expected_payload] == actual_root ||
             canonical_nominal_equal(expected_payload, actual_root));
        if (!matches && valid_token(expected_external_token))
            matches = dependency_nominal_matches_token(actual_root, expected_external_token);
        if (!matches || actual_count != 0u)
            mismatch(callee_token);
        return;
    }
    if (expected_tag != TYPE_REF_INSTANCE || !valid_token(expected_payload))
        return;
    uint actual_kind = dependency_type_word(actual_base);
    bool matches = false;
    bool contextual_bare_variant = false;
    uint contextual_enum_words = 0u;
    if (actual_kind == INTERFACE_TYPE_DECLARATION)
    {
        bool same_nominal = dependency_nominal_matches_token(
            actual_root, expected_payload);
        uint expected_count = type_instance_arg_count[expected_payload];
        // Variant signatures export the owning enum's bare nominal return.
        // Its type arguments come from the local result context. Accept this
        // only for a real imported variant whose direct generic payloads
        // agree with that context; other compound payloads fail closed.
        contextual_bare_variant = same_nominal && actual_count == 0u &&
            expected_count != 0u && bare_generic_variant_result_matches(
                callee_token, actual_root, expected_payload, contextual_enum_words);
        matches = same_nominal &&
            (expected_count == actual_count || contextual_bare_variant);
    }
    else if (actual_kind == INTERFACE_TYPE_ARRAY || actual_kind == INTERFACE_TYPE_SLICE)
    {
        uint expected_kind = actual_kind == INTERFACE_TYPE_ARRAY
            ? TYPE_INSTANCE_ARRAY
            : TYPE_INSTANCE_SLICE;
        matches = type_instance_kind[expected_payload] == expected_kind && actual_count == 1u;
        if (matches && actual_kind == INTERFACE_TYPE_ARRAY)
            matches = type_instance_len_kind[expected_payload] ==
                          dependency_type_word(actual_base + 5u) &&
                      type_instance_len_payload[expected_payload] ==
                          dependency_type_word(actual_base + 6u);
    }
    if (!matches)
    {
        mismatch(callee_token);
        return;
    }
    // The canonical result has the same nominal identity and arity as the
    // local instance. Publish the local instance for downstream expression
    // artifacts; child arguments are still checked through the dependency
    // comparison relation below.
    call_result_instance[call_node] = expected_payload;
    if (contextual_bare_variant)
    {
        call_return_aggregate_word_count[callee_token] = contextual_enum_words;
        return;
    }
    if (actual_count != 0u)
    {
        uint actual_subtree_count = canonical_subtree_count(actual_root);
        uint expected_subtree_count = local_type_subtree_count(expected_payload);
        if (actual_subtree_count == INVALID || actual_subtree_count != expected_subtree_count)
        {
            mismatch(callee_token);
            return;
        }
        dependency_call_compare_scan_input[statement_node] = actual_subtree_count;
        dependency_call_compare_expected_type[statement_node] = actual_root;
        dependency_call_compare_actual_instance[statement_node] = expected_payload;
        dependency_call_compare_error_token[statement_node] = callee_token;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (valid_node(node) && compact_hir_core[node].kind == HIR_CALL_EXPR)
    {
        substitute_direct_generic_call(node);
        return;
    }
    if (!valid_node(node))
        return;
    HirCore statement_core = compact_hir_core[node];
    HirPayload statement = compact_hir_payload[node];
    if (statement_core.kind != HIR_STMT &&
        statement_core.kind != HIR_LET_STMT &&
        statement_core.kind != HIR_RETURN_STMT &&
        statement_core.kind != HIR_ASSIGN_EXPR)
        return;
    uint expr = INVALID;
    uint expected_tag = 0u;
    uint expected_payload = INVALID;
    uint enclosing_function = INVALID;
    expected_ref_for_statement(
        node,
        expr,
        expected_tag,
        expected_payload,
        enclosing_function);
    if (!valid_node(expr) || compact_hir_core[expr].kind != HIR_CALL_EXPR)
        return;
    uint callee_token = dependency_call_token(expr);
    if (!valid_token(callee_token))
        return;
    validate_dependency_result(
        node,
        expr,
        callee_token,
        expected_tag,
        expected_payload,
        enclosing_function);
}
