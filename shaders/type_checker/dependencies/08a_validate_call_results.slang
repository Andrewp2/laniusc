import type_checker.constant_atoms;
import type_checker.constant_parameter_slots;
import semantic_interface_layout;
import native_value_layout;
import type_checker.calls.checked_constant_environment;
// Validate dependency call results over canonical IDs. The declared result
// pattern is matched against the receiving type (ct_match) and its bindings
// become the call's context; an imported canonical result is matched against
// the receiving type under the call's claims. One parameter can stand for a
// compound graph larger than its declaration-side spelling.

import dependency_interface;
import type_checker.concrete_type_equality;
import type_checker.mutable_checked_type_graph;
import type_checker.scoped_type_equality;
import type_checker.instance_arguments;
import type_checker.dependencies.canonical_field_types;
import hir_records;
import hir_expr_semantics;
import gpu_index;
import status;
import type_checker.calls.claim_lookup;
import type_checker.calls.contextual_call_environment;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_rows;
import type_checker.substitution.source_slots;
import type_checker.match.ct_match;
import type_checker.match.ct_context_publish;
import type_checker.match.field_expected;
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
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_WORDS = 9u;
static const uint DECL_WORDS = 14u;
static const uint MEMBER_WORDS =SEMANTIC_INTERFACE_MEMBER_WORDS;
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

[ForceInline]
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
    return dependency_find_method(call_dependency_library_id[token],
        call_dependency_unit_id[token], call_dependency_local_index[token]) != INVALID;
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
    // A method on another dependency page must wait for its own page;
    // its receiver's leading token cannot supply a replacement callable.
    if (callee_core.kind == HIR_MEMBER_EXPR)
        return dependency_callable_in_active_page(callee_payload.c)
            ? callee_payload.c : INVALID;
    uint token = callee_payload.d;
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

// The argument claim of (callee, slot) that binds a result pattern: the
// first claim row of the slot.
struct ResultClaims : ICtClaims
{
    static bool claim(uint token, uint slot, out uint tag, out uint payload)
    {
        tag = 0u; payload = INVALID;
        uint row = concrete_claim_row(token, slot,
            min(call_generic_claim_count_out[0u], generic_claim_capacity()));
        if (row == INVALID) return false;
        tag = call_generic_claim_ref_tag[row]; payload = call_generic_claim_ref_payload[row];
        return tag != 0u && payload != INVALID;
    }
}

// The canonical type of dependency node `t` of the resident page (its alias
// root's), or CT_UNKNOWN.
uint dependency_type(uint t)
{
    uint count = dependency_type_count();
    uint root = t < count ? canonical_type_roots[t] : INVALID;
    uint base = dependency_constant_type_span_base();
    uint capacity = ct_dependency_capacity();
    if (root >= count || base > capacity || root >= capacity - base) return CT_UNKNOWN;
    return canonical_dependency_type[base + root];
}

// Struct-literal field contexts in caller scope (declared_expression_context
// reads them through this): the field's reference `reference` as it is when
// it has no context instance, else the checked row of its substituted ID
// (field_expected.slang), never a scoped hash walk.
bool canonical_field_reference(uint token, uint scope, uint type_capacity, uint tokens,
    inout uint2 reference)
{
    if (scope == INVALID)
    {
        uint tag = reference.x;
        uint payload = reference.y;
        if (tag == TYPE_REF_SCALAR) return payload != 0u;
        if (tag == 2u) return payload < tokens && MutableCheckedTypeGraph.parameter_slot(payload) != INVALID;
        uint kind = tag == TYPE_REF_INSTANCE && payload < type_capacity
            ? MutableCheckedTypeGraph.metadata(payload, 0u) : 0u;
        return kind >= 1u && kind <= 4u;
    }
    reference = ct_realized_ref(ct_field_expected(token));
    return reference.x >= TYPE_REF_SCALAR && reference.x <= TYPE_REF_INSTANCE;
}

#define CANONICAL_FIELD_EXPECTATION
#include "../result_expression_context.slang"

// The call owns its published context, through the callee token and, for a
// call that is not dotted, its head and call tokens.
void publish_result_owner(uint call, uint callee)
{
    call_context_owner_by_token[callee] = call;
    uint node = compact_hir_payload[call].a;
    // The member leaf owns a dotted call; leading tokens can name another
    // call in its receiver and must keep that call's context owner.
    if (!valid_node(node) || compact_hir_core[node].kind != 21u)
    {
        uint head = valid_node(node) ? compact_hir_core[node].token_start : INVALID;
        uint call_token = compact_hir_core[call].token_start;
        if (valid_token(head)) call_context_owner_by_token[head] = call;
        if (valid_token(call_token)) call_context_owner_by_token[call_token] = call;
    }
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
    // Equal callable identities do not make a receiver call the same call.
    // Dotted results therefore publish only the member leaf's token row.
    if (callee_core.kind != HIR_MEMBER_EXPR)
    {
        publish_direct_generic_result(callee_core.token_start, callee_token,
            inferred, inferred_tag, inferred_payload);
        publish_direct_generic_result(compact_hir_core[call_node].token_start, callee_token,
            inferred, inferred_tag, inferred_payload);
    }
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
    uint actual_tag = call_inference_result_tag[call_node];
    uint actual_payload = call_inference_result_payload[call_node];
    bool accepted_result = actual_tag != 0u && actual_payload != INVALID;
    if (!accepted_result)
    {
        actual_tag = decl_type_ref_tag[callee_token];
        actual_payload = decl_type_ref_payload[callee_token];
    }
    bool instance_result = actual_tag == TYPE_REF_INSTANCE && valid_instance(actual_payload);
    // Step 0 infers the declared result pattern's bindings from the receiving
    // type. Result constraints come from the immutable declaration signature,
    // even if an earlier iteration published a substituted scalar result. The
    // portable callable contract distinguishes a function signature from a
    // method's direct return pattern; its shared accessor serves both.
    // Step 1 validates the accepted result.
    uint declared = dependency_callable_return_type(call_dependency_library_id[callee_token],
        call_dependency_unit_id[callee_token], call_dependency_local_index[callee_token]);
    SourceSlots slots;
    CtSpare spare = ct_spare_none();
    // The canonical IDs of the receiving type and of an instance result.
    uint expected_id = CT_UNKNOWN;
    uint actual_id = CT_UNKNOWN;
    uint operands = instance_result ? 2u : 1u;
    uint interned_operands = 0u;
    uint step = 0u;
    bool matched = false;
    uint environment = CT_MATCH_FAILED;
    uint count_mask = 0u;
    uint3 interned = uint3(0u, INVALID, CT_NONE);
    // One interning site serves the receiving type, an instance result and
    // each prior operand the publisher asks for; one matcher and one
    // publisher serve both steps.
    uint2 operand = uint2(expected_tag, expected_payload);
    [loop]
    for (uint work = 0u; work < 4u + 2u * CT_PUBLISH_REQUEST_LIMIT; work++)
    {
        uint outcome = CT_PUBLISH_REJECTED;
        bool ready = true;
        if (interned_operands < operands || operand.x != 0u)
        {
            uint id = operand.x == TYPE_REF_EXTERNAL_CANONICAL ? dependency_type(operand.y)
                : ct_intern_checked<CtMutableRows>(operand.x, operand.y, spare.record);
            if (interned_operands < operands)
            {
                if (interned_operands == 0u) expected_id = id;
                else actual_id = id;
                interned_operands++;
                operand = interned_operands < operands ? uint2(actual_tag, actual_payload) : uint2(0u, INVALID);
                if (interned_operands < operands) continue;
            }
            // A prior that has no ID agrees with no binding.
            else if (!ct_is_resolved(id)) ready = false;
            else
            {
                interned = uint3(operand, id);
                operand = uint2(0u, INVALID);
            }
        }
        if (ready && !matched)
        {
            uint pattern = CT_UNKNOWN;
            if (step == 0u)
            {
                // A callee without a declared result pattern publishes nothing.
                if (declared >= dependency_type_count()) { step = 1u; continue; }
                pattern = dependency_type(declared);
            }
            else
            {
                if (instance_result)
                {
                    // Declaration/method projection can overwrite provisional
                    // caches on the next iteration. Complete caller-side results
                    // belong to the stable accepted relation; pending instances
                    // must not diagnose before their newly published result
                    // environment can be materialized.
                    if (!accepted_result && call_inference_state[0u] != 0u) return;
                    // Direct T results may name a caller-local declaration; IDs
                    // compare every concrete shape as argument checking does.
                    if (expected_tag != TYPE_REF_INSTANCE || !valid_instance(expected_payload) ||
                        !ct_is_resolved(actual_id) || actual_id != expected_id)
                    {
                        mismatch(callee_token);
                        return;
                    }
                    call_result_instance[call_node] = expected_payload;
                    if (type_instance_kind[actual_payload] == TYPE_INSTANCE_SLICE)
                        call_return_aggregate_word_count[callee_token] = NATIVE_SLICE_WORDS;
                    return;
                }
                if (actual_tag != TYPE_REF_EXTERNAL_CANONICAL) return;
                uint actual_canonical = actual_payload;
                uint type_count = dependency_count(4u);
                if (actual_canonical >= type_count)
                {
                    mismatch(callee_token);
                    return;
                }
                uint actual_root = canonical_type_roots[actual_canonical];
                uint actual_base = actual_root * TYPE_WORDS;
                // The same pass first substitutes call nodes and is dispatched
                // again after a storage barrier for result validation. A
                // statement lane may observe the pre-substitution generic root
                // during the first dispatch; defer it rather than racing the
                // call lane and recording a false mismatch.
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
                    uint expected_edges = actual_kind == INTERFACE_TYPE_ARRAY ? 2u : 1u;
                    matches = type_instance_kind[expected_payload] == expected_kind && actual_count == expected_edges;
                }
                if (!matches)
                {
                    mismatch(callee_token);
                    return;
                }
                // A parameter's accepted type may have any number of
                // structural children: the canonical result is matched under
                // the call's claims instead of requiring its unsubstituted
                // syntax tree to have the same node count.
                pattern = dependency_type(actual_root);
            }
            count_mask = 0u;
            environment = ct_is_resolved(pattern) && ct_is_resolved(expected_id)
                ? ct_match<SourceSlots>(slots, pattern, expected_id, CT_NONE, CT_NONE, CT_NONE, 0u, true, spare, count_mask)
                : CT_MATCH_FAILED;
            matched = true;
        }
        if (ready)
        {
            if (environment == CT_MATCH_OVERFLOW) outcome = CT_PUBLISH_BUSY;
            else if (ct_is_record(environment))
            {
                uint3 words = ct_words(environment);
                outcome = ct_publish_context<ResultClaims>(call_node, callee_token, environment,
                    words.y, words.z, count_mask, step == 0u ? CT_PUBLISH_ADMIT : CT_PUBLISH_ADMIT | CT_PUBLISH_CLAIMS,
                    interned, operand);
                if (outcome == CT_PUBLISH_INTERN) continue;
                if (outcome == CT_PUBLISHED) publish_result_owner(call_node, callee_token);
            }
        }
        if (step == 0u)
        {
            // A declared result that does not match publishes nothing; a
            // match whose constants cannot be published is the publication
            // error.
            if (outcome == CT_PUBLISH_CAPACITY || (outcome == CT_PUBLISH_REJECTED && ct_is_record(environment)))
                record_min_token_error(status, callee_token, 6u, 0x474e0001u);
            step = 1u;
            matched = false;
            interned = uint3(0u, INVALID, CT_NONE);
            operand = uint2(0u, INVALID);
            continue;
        }
        if (outcome == CT_PUBLISH_BUSY) return;
        if (outcome != CT_PUBLISHED)
        {
            mismatch(callee_token);
            return;
        }
        call_result_instance[call_node] = expected_payload;
        return;
    }
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
    if (!result_expression_context<MutableCheckedTypeGraph>(node, type_capacity(), reference)) return;
    uint callee_token = dependency_call_token(node);
    if (!valid_token(callee_token)) return;
    uint enclosing_function = enclosing_function_decl_token(compact_hir_core[node].token_start);
    validate_dependency_result(node, node, callee_token, reference.x, reference.y,
        enclosing_function);
}
