import type_checker.constant_atoms_identity;
// Validate dependency-call roots through complete checked type graphs and the
// accepted callable environment, including the root array-to-slice borrowing
// conversion. Portable constant children do not align with source HIR ordinals.

import dependency_interface;
import type_checker.dependencies.method_receiver;
import hir_records;
import gpu_index;
import hir_expr_semantics;
import primitive_types;
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
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> call_generic_return_arg_node;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
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
static const uint TY_UNKNOWN = 0u;
static const uint TY_INT = 3u;
static const uint TY_POINTER = 8u;
static const uint HIR_EXPR_INT = 3u;
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

// The checked expression relation includes contextual literal types and
// arithmetic results. An already typed value never acquires its parameter's
// scalar identity at this final validation boundary.
uint accepted_scalar_type(uint node)
{
    if (!valid_hir(node) || call_inference_result_tag[node] != TYPE_REF_SCALAR)
        return TY_UNKNOWN;
    uint scalar = call_inference_result_payload[node];
    return scalar_is_known(scalar) ? scalar : TY_UNKNOWN;
}

bool null_pointer_constant(uint node)
{
    if (!valid_hir(node)) return false;
    uint current = node;
    for (uint step = 0u; step < active_hir_count(); step += 1u)
    {
        HirCore core = compact_hir_core[current];
        HirPayload payload = compact_hir_payload[current];
        if (!hir_is_forward_expression(core.kind, payload.a))
            return core.kind == HIR_SEM_KIND_LITERAL_EXPR &&
                payload.a == HIR_EXPR_INT && payload.b == 0u && payload.c == 0u;
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
        if (!dependency_method_bound_parameter_ref(method, expected_type_i,
                callee, tag, payload) || tag != TYPE_REF_SCALAR)
            return;
        receiver_scalar = payload;
    }

    uint arg_token = compact_hir_core[arg_node].token_start;
    if (expected_kind != INTERFACE_TYPE_SCALAR && receiver_scalar == TY_UNKNOWN)
    {
        uint expr_node = generic_result_type_origin(arg_node, active_hir_count(),
            compact_hir_core, compact_hir_payload, call_generic_return_arg_node);
        if (!valid_hir(expr_node))
        {
            record_min_token_error(status, callee, ERR_ASSIGN_MISMATCH, 0u);
            return;
        }
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
            if (concrete_instance_is_closed<ScopedCheckedTypeGraph, CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(result, checked_type_capacity(), gParams.visible_capacity))
            { actual_tag = 3u; actual_payload = result; }
        }
        // Nominal operands and complete arrays are checked references, including
        // arguments absent from the source type subtree. Compare their graph
        // under the accepted callable environment in declaration order.
        // Array-to-slice conversion is allowed only at this comparison's root;
        // nested element/constant relationships remain exact.
        if (actual_tag == TYPE_REF_INSTANCE &&
            (actual_payload >= gParams.visible_capacity || expected_kind == 6u ||
             expected_kind == INTERFACE_TYPE_ARRAY || expected_kind == INTERFACE_TYPE_SLICE ||
             expected_kind == INTERFACE_TYPE_DECLARATION) &&
            actual_payload < checked_type_capacity())
        {
            // Receiver and method-owned parameters already compose into the
            // checked call environment. A receiver instance alone omits the
            // method's own type and constant slots.
            uint environment = 0x80000000u | callee;
            if (!canonical_field_ref_matches<ScopedCheckedCallTypeGraph>(environment,
                expected_type_i, actual_payload, checked_type_capacity(), gParams.visible_capacity,
                expected_kind == INTERFACE_TYPE_SLICE))
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
    uint actual = accepted_scalar_type(arg_node);
    if (!(scalar_is_known(expected) && expected == actual) &&
        !(expected == TY_POINTER && actual == TY_INT && null_pointer_constant(arg_node)))
        record_min_token_error(
            status,
            arg_token < gParams.visible_capacity ? arg_token : callee,
            ERR_ASSIGN_MISMATCH,
            expected * 256u + actual);
}
