import type_checker.constant_parameter_slots;
import semantic_interface_layout;
import native_value_layout;
import type_checker.calls.checked_constant_environment;
// Validate dependency call results by substituting the accepted environment
// through the complete canonical type graph. One parameter can stand for a
// compound graph larger than its declaration-side spelling.

import dependency_interface;
import type_checker.concrete_type_equality;
import type_checker.checked_type_graph;
import type_checker.scoped_type_equality;
import type_checker.instance_arguments;
import type_checker.dependencies.canonical_field_types;
import hir_records;
import hir_expr_semantics;
import gpu_index;
import status;
import type_checker.calls.claim_lookup;
import type_checker.calls.contextual_call_environment;
import type_checker.local_struct_layout;
import type_checker.argument_context;

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
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> argument_expected_ref_tag;
StructuredBuffer<uint> argument_expected_ref_payload;
StructuredBuffer<uint> struct_init_field_expected_ref_tag;
StructuredBuffer<uint> struct_init_field_expected_ref_payload;
StructuredBuffer<uint> struct_init_field_expected_context_instance;
StructuredBuffer<uint> type_instance_lookup_head;
StructuredBuffer<uint> type_instance_lookup_next;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> declaration_generic_arity;
StructuredBuffer<uint> type_instance_aggregate_word_count;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_type;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_ref_payload;
StructuredBuffer<uint> call_generic_claim_lookup_head;
StructuredBuffer<uint> call_generic_claim_lookup_next;
StructuredBuffer<uint> call_inference_state;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
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
RWStructuredBuffer<uint> dependency_call_compare_callee;
RWStructuredBuffer<uint> dependency_call_compare_error_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_WORDS = 9u;
static const uint DECL_WORDS = 14u;
static const uint MEMBER_WORDS =SEMANTIC_INTERFACE_MEMBER_WORDS;
static const uint MEMBER_ENUM_VARIANT = 5u;
static const uint MEMBER_ASSOCIATED_METHOD = 6u;
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


public struct CheckedConcreteTypeGraph : IScopedTypeGraph
{
    public static uint constant_parameter_slot(uint token) { return type_const_param_slot_by_token[token]; }
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { return checked_call_environment_constant_ref(environment, slot, kind, value); }
    public static uint parameter_slot(uint token) { return type_generic_param_slot_by_token[token]; }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    {
        tag = 0u; payload = INVALID;
        if (environment == INVALID || (environment & 0x80000000u) == 0u) return false;
        uint row = concrete_claim_row(environment & 0x7fffffffu, slot,
            min(call_generic_claim_count_out[0u], generic_claim_capacity()));
        if (row == INVALID) return false;
        tag = call_generic_claim_ref_tag[row]; payload = call_generic_claim_ref_payload[row];
        return tag != 0u && payload != INVALID;
    }
    public static uint metadata(uint instance, uint field)
    { return ScopedCheckedTypeGraph.metadata(instance, field); }

    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return ScopedCheckedTypeGraph.argument(instance, slot, tag, payload); }
}

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

bool valid_hir(uint node) { return valid_node(node); }

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.visible_capacity;
}

uint type_capacity()
{
    uint count; uint stride;
    type_instance_kind.GetDimensions(count, stride);
    return count;
}

bool valid_instance(uint instance) { return instance != INVALID && instance < type_capacity(); }

bool dependency_callable_in_active_page(uint token)
{
    if (!valid_token(token) || call_dependency_library_id[token] == INVALID)
        return false;
    if (dependency_find_declaration(
               call_dependency_library_id[token],
               call_dependency_unit_id[token],
               call_dependency_local_index[token]) != INVALID)
        return true;
    uint member_count = dependency_member_count();
    for (uint member = 0u; member < member_count; member += 1u)
    {
        uint base = member * MEMBER_WORDS;
        if (dependency_member_word(base + 1u) != MEMBER_ASSOCIATED_METHOD ||
            dependency_member_word(base + 9u) != call_dependency_local_index[token])
            continue;
        uint owner = dependency_member_word(base);
        if (owner < dependency_declaration_count() &&
            dependency_declaration_library_id(owner) ==
                call_dependency_library_id[token] &&
            dependency_declaration_unit_id(owner) ==
                call_dependency_unit_id[token])
            return true;
    }
    return false;
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
    if (dependency_callable_in_active_page(token))
        return token;
    token = callee_core.token_start;
    if (dependency_callable_in_active_page(token))
        return token;
    return INVALID;
}

bool dependency_nominal_matches_token(uint expected_type_i, uint token)
{
    uint type_count = dependency_count(4u);
    if (expected_type_i >= type_count || !valid_instance(token))
        return false;
    uint expected = canonical_type_roots[expected_type_i];
    uint base = expected * TYPE_WORDS;
    return dependency_type_word(base) == INTERFACE_TYPE_DECLARATION &&
           dependency_type_word(base + 1u) == external_type_library_id[token] &&
           dependency_type_word(base + 2u) == external_type_local_index[token] &&
           dependency_type_word(base + 8u) == external_type_unit_id[token];
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

void mismatch(uint token)
{
    // Result constraints may depend on expression facts from a later inference
    // round. Only the final validation phase can reject an unresolved relation.
    // Known argument conflicts are independently checked by claim validation.
    if (call_inference_state[0u] != 0u) return;
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
    return CheckedConcreteTypeGraph.argument(instance, slot, tag, payload);
}

// Declared result patterns bind independently from provisional argument types.
// Strict claim validation later compares those values with these constraints.
public struct DeclaredResultTypeGraph : IScopedTypeGraph
{
    public static uint constant_parameter_slot(uint token) { return CheckedConcreteTypeGraph.constant_parameter_slot(token); }
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { kind = 0u; value = INVALID; return false; }
    public static uint parameter_slot(uint token) { return CheckedConcreteTypeGraph.parameter_slot(token); }
    public static uint metadata(uint instance, uint field) { return CheckedConcreteTypeGraph.metadata(instance, field); }
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    { return CheckedConcreteTypeGraph.argument(instance, slot, tag, payload); }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    { tag = 0u; payload = INVALID; return false; }
}

#include "../result_expression_context.slang"

void publish_result_constraints(uint call, uint callee, uint2 inferred[32], uint mask)
{
    for (uint slot = 0u; slot < 32u; slot++)
        if ((mask & (1u << slot)) != 0u)
        {
            call_context_ref_tag[call * 32u + slot] = inferred[slot].x;
            call_context_ref_payload[call * 32u + slot] = inferred[slot].y;
        }
    call_context_arg_mask[call] |= mask;
    call_context_owner_by_token[callee] = call;
    uint node = compact_hir_payload[call].a;
    uint head = valid_node(node) ? compact_hir_core[node].token_start : INVALID;
    uint call_token = compact_hir_core[call].token_start;
    if (valid_token(head)) call_context_owner_by_token[head] = call;
    if (valid_token(call_token)) call_context_owner_by_token[call_token] = call;
}

void publish_result_environments(uint call, uint callee, uint2 inferred[32], uint mask,
    uint2 constants[32], uint constant_mask)
{
    publish_result_constraints(call, callee, inferred, mask);
    publish_context_constants(call, constants, constant_mask);
}

void publish_direct_generic_result(uint token, uint callee,
    uint inferred, uint tag, uint payload)
{
    if (!valid_token(token) ||
        call_dependency_library_id[token] != call_dependency_library_id[callee] ||
        call_dependency_unit_id[token] != call_dependency_unit_id[callee] ||
        call_dependency_local_index[token] != call_dependency_local_index[callee])
        return;
    call_return_type[token] = tag == TYPE_REF_SCALAR ? payload
        : tag == TYPE_REF_INSTANCE ? 0u : inferred;
    call_return_type_token[token] = tag != 0u ? token : INVALID;
    decl_type_ref_tag[token] = tag != 0u ? tag : TYPE_REF_SCALAR;
    decl_type_ref_payload[token] = tag != 0u ? payload : inferred;
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
    if (!valid_token(callee_token)) return;
    // The declaration owns the return pattern. Earlier iterations may have
    // replaced the expression reference with a concrete result; that must not
    // hide the pattern or prevent publication to qualified-call token aliases.
    uint return_i = dependency_callable_return_type(call_dependency_library_id[callee_token],
        call_dependency_unit_id[callee_token], call_dependency_local_index[callee_token]);
    uint type_count = dependency_count(4u);
    if (return_i >= type_count)
        return;
    uint return_root = canonical_type_roots[return_i];
    uint return_base = return_root * TYPE_WORDS;
    if (dependency_type_word(return_base) != INTERFACE_TYPE_GENERIC_PARAMETER)
        return;
    uint slot = dependency_generic_type_slot(return_root);
    uint count = min(call_generic_claim_count_out[0u], generic_claim_capacity());
    uint row = concrete_claim_row(callee_token, slot, count);
    if (row == INVALID)
        return;
    uint inferred = call_generic_claim_type[row];
    uint inferred_tag = call_generic_claim_ref_tag[row];
    uint inferred_payload = call_generic_claim_ref_payload[row];
    if (inferred == 0u && inferred_tag == 0u)
        return;
    // Qualified calls have head, leaf, and call-owner token aliases. Initial
    // dependency projection publishes all of them; substitution must do the
    // same so statement checking does not retain the head's unresolved void
    // machine type after the leaf has acquired its concrete result.
    publish_direct_generic_result(callee_core.token_start, callee_token,
        inferred, inferred_tag, inferred_payload);
    publish_direct_generic_result(compact_hir_core[call_node].token_start, callee_token,
        inferred, inferred_tag, inferred_payload);
    publish_direct_generic_result(callee_token, callee_token,
        inferred, inferred_tag, inferred_payload);
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
    {
        // Result constraints come from the immutable declaration signature,
        // even if an earlier iteration published a substituted scalar result.
        // The portable callable contract distinguishes a function signature
        // from a method's direct return pattern. Use its shared accessor for
        // both; method member types are not function-signature nodes.
        uint pattern = dependency_callable_return_type(call_dependency_library_id[callee_token],
            call_dependency_unit_id[callee_token], call_dependency_local_index[callee_token]);
        if (pattern < dependency_type_count())
        {
            uint2 inferred[32]; uint mask; uint2 constants[32]; uint constant_mask;
            if (canonical_type_and_constant_constraints<DeclaredResultTypeGraph>(
                0x80000000u | callee_token, pattern, expected_tag, expected_payload,
                type_capacity(), gParams.visible_capacity, true, inferred, mask,
                constants, constant_mask, true))
                publish_result_environments(call_node, callee_token, inferred, mask,
                    constants, constant_mask);
        }
    }
    uint actual_tag = call_inference_result_tag[call_node];
    uint actual_payload = call_inference_result_payload[call_node];
    bool accepted_result = actual_tag != 0u && actual_payload != INVALID;
    if (!accepted_result)
    {
        actual_tag = decl_type_ref_tag[callee_token];
        actual_payload = decl_type_ref_payload[callee_token];
    }
    if (actual_tag == TYPE_REF_INSTANCE && valid_instance(actual_payload))
    {
        // Declaration/method projection can overwrite provisional caches on
        // the next iteration. Complete caller-side results belong to the
        // stable accepted relation; pending instances must not diagnose before
        // their newly published result environment can be materialized.
        if (!accepted_result && call_inference_state[0u] != 0u) return;
        if (expected_tag != TYPE_REF_INSTANCE || !valid_instance(expected_payload))
        {
            mismatch(callee_token);
            return;
        }
        // Direct T results may name a caller-local declaration. Its checked
        // declaration token and arguments establish identity without an
        // imported declaration ID. Compare every concrete shape using the
        // same relation as argument checking.
        if (!scoped_type_refs_equal<CheckedConcreteTypeGraph>(TYPE_REF_INSTANCE, actual_payload, INVALID,
                TYPE_REF_INSTANCE, expected_payload, INVALID, type_capacity(), gParams.visible_capacity))
        {
            mismatch(callee_token);
            return;
        }
        call_result_instance[call_node] = expected_payload;
        if (type_instance_kind[actual_payload] == TYPE_INSTANCE_SLICE)
            call_return_aggregate_word_count[callee_token] = NATIVE_SLICE_WORDS;
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
    if (expected_tag != TYPE_REF_INSTANCE || !valid_instance(expected_payload))
        return;
    uint actual_kind = dependency_type_word(actual_base);
    bool matches = false;
    if (actual_kind == INTERFACE_TYPE_DECLARATION)
    {
        bool same_nominal = dependency_nominal_matches_token(
            actual_root, expected_payload);
        uint expected_count = type_instance_arg_count[expected_payload];
        matches = same_nominal && expected_count == actual_count;
    }
    else if (actual_kind == INTERFACE_TYPE_ARRAY || actual_kind == INTERFACE_TYPE_SLICE ||
             actual_kind == 6u)
    {
        uint expected_kind = actual_kind - 2u;
        matches = type_instance_kind[expected_payload] == expected_kind && actual_count == 1u;
        // Complete matching below substitutes constant lengths before comparison.
    }
    if (!matches)
    {
        mismatch(callee_token);
        return;
    }
    // A parameter's accepted type may have any number of structural children.
    // Compare the canonical result under its call environment instead of
    // requiring its unsubstituted syntax tree to have the same node count.
    uint2 inferred[32]; uint inferred_mask;
    if (!canonical_field_ref_constraints<CheckedConcreteTypeGraph>(
        0x80000000u | callee_token, actual_root, expected_payload,
        type_capacity(), gParams.visible_capacity, true, inferred, inferred_mask))
    {
        mismatch(callee_token);
        return;
    }
    publish_result_constraints(call_node, callee_token, inferred, inferred_mask);
    call_result_instance[call_node] = expected_payload;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_CALL_EXPR) return;
    substitute_direct_generic_call(node);
    // One call lane owns its result environment, including assignments.
    // The receiving-place projection supplies the complete destination type.
    uint2 reference;
    if (!result_expression_context<ScopedCheckedTypeGraph>(node, type_capacity(), reference)) return;
    uint callee_token = dependency_call_token(node);
    if (!valid_token(callee_token)) return;
    uint enclosing_function = enclosing_function_decl_token(compact_hir_core[node].token_start);
    validate_dependency_result(node, node, callee_token, reference.x, reference.y,
        enclosing_function);
}
