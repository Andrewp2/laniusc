// Validate dependency-call roots through complete checked type graphs and the
// accepted callable environment. Array-to-slice arguments retain their borrowing
// conversion and parallel source comparison spans for 08b_validate_call_type_args.

import dependency_interface;
import type_checker.dependencies.method_receiver;
import hir_records;
import gpu_index;
import hir_expr_semantics;
import type_checker.checked_index_reference;
import type_checker.generic_result_type_origin;
import type_checker.calls.checked_call_type_graph;
import type_checker.checked_type_graph;
import type_checker.concrete_type_closure;
import type_checker.dependencies.canonical_field_types;
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
RWStructuredBuffer<uint> semantic_argument_mode_by_hir;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> call_generic_return_arg_node;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> canonical_type_subtree_start;
StructuredBuffer<uint> type_semantic_row_by_token;
StructuredBuffer<uint> type_semantic_scan_input;
StructuredBuffer<uint> type_semantic_prefix;
StructuredBuffer<uint> type_semantic_count_out;
RWStructuredBuffer<uint> dependency_call_compare_scan_input;
RWStructuredBuffer<uint> dependency_call_compare_expected_type;
RWStructuredBuffer<uint> dependency_call_compare_actual_instance;
RWStructuredBuffer<uint> dependency_call_compare_callee;
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
static const uint TYPE_REF_SCALAR = 1u;
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
static const uint TY_POINTER = 8u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR = 14u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
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
    for (uint step = 0u; step < 32u; step += 1u)
    {
        HirPayload forward = compact_hir_payload[node];
        if (forward.a != HIR_EXPR_FORWARD ||
            (compact_hir_core[node].kind != HIR_EXPR &&
             compact_hir_core[node].kind != HIR_BINARY_EXPR &&
             compact_hir_core[node].kind != HIR_UNARY_EXPR))
            break;
        if (!valid_hir(forward.b) || forward.b == node)
            break;
        node = forward.b;
    }
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    uint scalar = hir_scalar_type_for_hir(core.kind, payload.a);
    if (scalar != HIR_SEM_TY_UNKNOWN)
        return scalar;
    if (core.kind == HIR_CALL_EXPR)
    {
        uint callee = callee_token(node);
        if (callee != INVALID && callee < gParams.visible_capacity)
            return call_return_type[callee];
    }
    if (core.kind == HIR_INDEX_EXPR)
    {
        // The start token belongs to the base array, not the projected
        // element. Index checking publishes the result at this HIR token.
        uint tag; uint payload;
        if (checked_named_index_reference(node, active_hir_count(), gParams.visible_capacity,
            compact_hir_core, compact_hir_payload, visible_decl, decl_type_ref_tag,
            decl_type_ref_payload, type_instance_kind, type_instance_elem_ref_tag,
            type_instance_elem_ref_payload, tag, payload) ||
            checked_member_index_reference(node, active_hir_count(), gParams.visible_capacity,
                compact_hir_core, compact_hir_payload, member_result_ref_tag, member_result_ref_payload,
                type_instance_kind, type_instance_elem_ref_tag, type_instance_elem_ref_payload, tag, payload))
        {
            if (tag == TYPE_REF_SCALAR)
            return payload;
        }
        return core.token_start < gParams.visible_capacity
            ? call_return_type[core.token_start] : HIR_SEM_TY_UNKNOWN;
    }
    if (core.kind == HIR_EXPR || core.kind == HIR_BINARY_EXPR ||
        core.kind == HIR_UNARY_EXPR)
    {
        uint form = payload.a;
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_EQ ||
            form == HIR_EXPR_NE || form == HIR_EXPR_LT ||
            form == HIR_EXPR_GT || form == HIR_EXPR_LE ||
            form == HIR_EXPR_GE || form == HIR_EXPR_AND ||
            form == HIR_EXPR_OR)
            return HIR_SEM_TY_BOOL;
    }
    if (core.kind == HIR_MEMBER_EXPR)
    {
        // A member expression starts at its receiver, whose type is not the
        // argument type. Member projection publishes the field at payload.c.
        uint member = payload.c;
        return member < gParams.visible_capacity
            ? visible_type[member] : HIR_SEM_TY_UNKNOWN;
    }
    return token < gParams.visible_capacity ? visible_type[token] : HIR_SEM_TY_UNKNOWN;
}

bool concrete_direct_argument(uint tag, uint payload)
{
    return (tag == TYPE_REF_SCALAR && payload != 0u && payload != INVALID) ||
        (tag == TYPE_REF_INSTANCE && payload < checked_type_capacity() &&
         type_instance_kind[payload] >= 1u &&
         type_instance_kind[payload] <= TYPE_INSTANCE_SLICE);
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
    if (expected == TY_CHAR)
        return actual == TY_INT || actual == TY_UINT;
    if (expected == TY_FLOAT)
        return actual == TY_INT || actual == TY_UINT || actual == TY_CHAR;
    return false;
}

bool null_pointer_constant(uint node)
{
    if (!valid_hir(node)) return false;
    uint current = node;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        HirPayload payload = compact_hir_payload[current];
        if (payload.a != HIR_EXPR_FORWARD)
            return payload.a == HIR_EXPR_INT && payload.b == 0u;
        if (!valid_hir(payload.b) || payload.b == current) return false;
        current = payload.b;
    }
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

bool generic_element_parameter_matches(uint expected_root, uint instance)
{
    uint types = dependency_type_count();
    uint edge = dependency_type_word(expected_root * TYPE_WORDS + 3u);
    if (edge >= dependency_count(5u)) return false;
    uint child = dependency_type_edge_word(edge);
    if (child >= types) return false;
    child = canonical_type_roots[child];
    if (child >= types || dependency_type_word(child * TYPE_WORDS) !=
        INTERFACE_TYPE_GENERIC_PARAMETER) return false;
    // [T] has two source nodes, but T can expand to any checked type graph.
    // The compact call claims bind the complete element reference and check
    // every repeated T; equal flattened source lengths are not its contract.
    return concrete_direct_argument(type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
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
    uint expected_type = INVALID;
    uint first_edge = INVALID;
    uint edge_count = 0u;
    if (declaration_i != INVALID)
    {
        uint signature_i = dependency_declaration_word(declaration_i * DECL_WORDS + 7u);
        uint signature_base = signature_i * TYPE_WORDS;
        if (dependency_type_word(signature_base) != INTERFACE_TYPE_FUNCTION) return;
        first_edge = dependency_type_word(signature_base + 3u);
        edge_count = dependency_type_word(signature_base + 4u);
        if (edge_count == 0u || arg.ordinal >= edge_count - 1u) return;
        expected_type = dependency_type_edge_word(first_edge + arg.ordinal);
    }
    else
    {
        uint method = dependency_find_method(call_dependency_library_id[callee],
            call_dependency_unit_id[callee], call_dependency_local_index[callee]);
        if (method == INVALID) return; // The callable belongs to another page.
        edge_count = dependency_method_parameter_count(method) + 1u;
        uint call_callee = compact_hir_payload[arg.call].a;
        bool dotted_call = valid_hir(call_callee) &&
            compact_hir_core[call_callee].kind == HIR_MEMBER_EXPR;
        expected_type = dependency_method_parameter_type(
            method, arg.ordinal + (dotted_call ? 1u : 0u));
        // A resolved method without a complete parameter record must not
        // silently accept an argument of any type.
        if (expected_type == INVALID || arg.ordinal >= call_param_count[callee])
        {
            record_min_token_error(status, callee, ERR_ASSIGN_MISMATCH, 0u);
            return;
        }
    }
    if (expected_type >= dependency_type_count()) return;
    uint expected_type_i = canonical_type_roots[expected_type];
    uint expected_base = expected_type_i * TYPE_WORDS;
    uint expected_kind = dependency_type_word(expected_base);
    // Retain the passing mode of the bound parameter before this page expires.
    // A declaration-side T can denote a slice; copying its source array here
    // would sever the borrowed alias even though call checking accepted it.
    uint passing_kind = expected_kind;
    uint2 bound = uint2(TYPE_REF_EXTERNAL_CANONICAL, expected_type_i);
    if (canonical_field_leaf<ScopedCheckedCallTypeGraph>(0x80000000u | callee, bound) &&
        bound.x == TYPE_REF_INSTANCE && bound.y < checked_type_capacity())
        passing_kind = type_instance_kind[bound.y] + 2u;
    semantic_argument_mode_by_hir[arg.value] =
        passing_kind == 6u ? 3u : passing_kind == 5u ? 2u : 1u;

    // Imported function generics participate in the shared compact call-row
    // claim pipeline. This late structural validator must not second-guess the
    // substitution relation with an uninstantiated interface node.
    uint receiver_scalar = TY_UNKNOWN;
    if (expected_kind == INTERFACE_TYPE_GENERIC_PARAMETER)
    {
        uint method = dependency_find_method(call_dependency_library_id[callee],
            call_dependency_unit_id[callee], call_dependency_local_index[callee]);
        uint tag;
        uint payload;
        if (method_call_receiver_ref_tag[callee] != TYPE_REF_INSTANCE ||
            !dependency_method_receiver_generic_ref(method, expected_type_i,
                method_call_receiver_ref_payload[callee], gParams.visible_capacity,
                canonical_type_roots, type_instance_arg_count, type_instance_arg_start,
                type_instance_arg_ref_tag, type_instance_arg_ref_payload,
                type_instance_arg_row_start, type_instance_arg_row_count_out,
                type_instance_arg_row_ref_tag, type_instance_arg_row_ref_payload,
                tag, payload) || tag != TYPE_REF_SCALAR)
            return;
        receiver_scalar = payload;
    }

    uint expr_node = generic_result_type_origin(arg_node, active_hir_count(),
        compact_hir_core, compact_hir_payload, call_generic_return_arg_node);
    if (!valid_hir(expr_node))
    {
        record_min_token_error(status, callee, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }
    uint arg_token = compact_hir_core[arg_node].token_start;
    uint actual = scalar_type_for_argument(expr_node, arg_token);
    if (expected_kind != INTERFACE_TYPE_SCALAR && receiver_scalar == TY_UNKNOWN)
    {
        uint actual_ref_token = compact_hir_core[expr_node].token_start;
        // A method call starts at its receiver's token, but the argument is
        // the method's result. Read the projected callee result reference;
        // resolving the start token would compare the receiver type instead.
        if (compact_hir_core[expr_node].kind == HIR_CALL_EXPR)
            actual_ref_token = callee_token(expr_node);
        else if (actual_ref_token < gParams.visible_capacity &&
            visible_decl[actual_ref_token] < gParams.visible_capacity)
            actual_ref_token = visible_decl[actual_ref_token];
        uint actual_tag = actual_ref_token < gParams.visible_capacity
            ? decl_type_ref_tag[actual_ref_token]
            : 0u;
        uint actual_payload = actual_ref_token < gParams.visible_capacity
            ? decl_type_ref_payload[actual_ref_token]
            : INVALID;
        // Complete expression results take precedence over token aliases and
        // identity-call origin shortcuts. This includes synthetic &self
        // references, whose checked type has no source annotation subtree.
        uint completed_tag = call_inference_result_tag[arg_node];
        uint completed_payload = call_inference_result_payload[arg_node];
        if (completed_tag == 0u || completed_payload == INVALID)
        {
            completed_tag = semantic_expr_ref_tag_by_hir[arg_node];
            completed_payload = semantic_expr_ref_payload_by_hir[arg_node];
        }
        if (completed_tag == 3u && completed_payload < checked_type_capacity() &&
            type_instance_kind[completed_payload] != 0u)
        {
            actual_tag = completed_tag;
            actual_payload = completed_payload;
        }
        else if (compact_hir_core[arg_node].kind == HIR_CALL_EXPR)
        {
            uint result = call_result_instance[arg_node];
            if (concrete_instance_is_closed(result, checked_type_capacity(),
                type_instance_kind, type_instance_arg_count, type_instance_arg_start,
                type_instance_arg_ref_tag, type_instance_arg_ref_payload,
                type_instance_arg_row_start, type_instance_arg_row_count_out,
                type_instance_arg_row_ref_tag, type_instance_arg_row_ref_payload,
                type_instance_elem_ref_tag, type_instance_elem_ref_payload,
                type_instance_len_kind, gParams.visible_capacity))
            { actual_tag = 3u; actual_payload = result; }
        }
        // Nominal operands and complete arrays are checked references, including
        // arguments absent from the source type subtree. Compare their graph
        // under the accepted callable environment in declaration order.
        // Array-to-slice conversion keeps its distinct borrowing rule below.
        if (actual_tag == TYPE_REF_INSTANCE &&
            (actual_payload >= gParams.visible_capacity || expected_kind == 6u ||
             expected_kind == INTERFACE_TYPE_ARRAY ||
             expected_kind == INTERFACE_TYPE_DECLARATION) &&
            actual_payload < checked_type_capacity() &&
            !(expected_kind == INTERFACE_TYPE_SLICE &&
              type_instance_kind[actual_payload] == TYPE_INSTANCE_ARRAY))
        {
            // Receiver and method-owned parameters already compose into the
            // checked call environment. A receiver instance alone omits the
            // method's own type and constant slots.
            uint environment = 0x80000000u | callee;
            if (!canonical_field_ref_matches<ScopedCheckedCallTypeGraph>(environment,
                expected_type_i, actual_payload, checked_type_capacity(), gParams.visible_capacity))
                record_min_token_error(status, arg_token < gParams.visible_capacity ? arg_token : callee,
                    ERR_ASSIGN_MISMATCH, HIR_SEM_TY_UNKNOWN);
            return;
        }
        uint expected_count = dependency_type_word(expected_base + 4u);
        bool matches = false;
        if (expected_kind == INTERFACE_TYPE_DECLARATION &&
            actual_tag == TYPE_REF_EXTERNAL_CANONICAL)
        {
            matches = stable_nominal_matches(
                          expected_type_i, actual_ref_token, actual_payload) &&
                      expected_count == 0u;
        }
        else if (expected_kind == INTERFACE_TYPE_SLICE &&
                 actual_tag == TYPE_REF_INSTANCE &&
                 actual_payload < checked_type_capacity())
        {
            uint actual_instance_kind = type_instance_kind[actual_payload];
            // A fixed array can supply a slice parameter. The call lowering
            // builds the slice view, just as it does for a local callee.
            matches = expected_count == 1u &&
                (actual_instance_kind == TYPE_INSTANCE_SLICE ||
                 actual_instance_kind == TYPE_INSTANCE_ARRAY);
            if (matches)
            {
                uint expected_subtree_count = canonical_subtree_count(expected_type_i);
                uint actual_subtree_count = local_type_subtree_count(actual_payload);
                bool same_source_shape = expected_subtree_count != INVALID &&
                    expected_subtree_count == actual_subtree_count;
                matches = same_source_shape ||
                    generic_element_parameter_matches(expected_type_i, actual_payload);
                dependency_call_compare_scan_input[arg_node] = same_source_shape
                    ? expected_subtree_count : 0u;
                dependency_call_compare_expected_type[arg_node] = expected_type_i;
                dependency_call_compare_actual_instance[arg_node] = actual_payload;
                dependency_call_compare_callee[arg_node] = callee;
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
    uint expected = receiver_scalar != TY_UNKNOWN
        ? receiver_scalar : dependency_type_word(expected_base + 1u);
    if (actual == HIR_SEM_TY_UNKNOWN && arg_token < gParams.visible_capacity)
        actual = visible_type[arg_token];
    if (!assignable(expected, actual) &&
        !(expected == TY_POINTER && actual == TY_INT && null_pointer_constant(arg_node)))
        record_min_token_error(
            status,
            arg_token < gParams.visible_capacity ? arg_token : callee,
            ERR_ASSIGN_MISMATCH,
            expected * 256u + actual);
}
