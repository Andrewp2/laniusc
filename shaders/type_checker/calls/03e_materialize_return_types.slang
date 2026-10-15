// Instantiate complete call returns: the declared result under the call's
// value environment (call_env.slang), substituted over canonical IDs and
// realized as a checked row. Argument claims retain the type of known values;
// result constraints fill missing bindings. A receiving context must not
// rewrite a known value and then feed that rewritten result back into its
// caller's argument claims.
import hir_records;
import status;
import dependency_interface;
import semantic_interface_layout;
import type_checker.checked_pattern_use;
import type_checker.mutable_checked_type_graph;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.checked_call_environment;
import type_checker.calls.checked_constant_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_dependency;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;
import type_checker.substitution.source_slots;
import type_checker.substitution.call_env;
import type_checker.calls.intrinsic_result;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_decl_generic_param_count;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> resolved_dependency_value_metadata;
StructuredBuffer<uint> module_value_path_call_head;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
RWStructuredBuffer<uint> call_result_instance;
RWStructuredBuffer<uint> struct_lit_context_decl_token;
RWStructuredBuffer<uint> struct_lit_context_instance;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
// [defer missing bindings, number of newly published type facts].
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> call_inference_result_tag;
RWStructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ARG_LIMIT = 32u;
// Failures, as the materializer reported them: 1 capacity, 2 limits, 3 a
// missing binding, 4 an unsupported type.
static const uint FAILURE_UNBOUND = 3u;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

#include "callable_header.slang"

// The canonical type of dependency node `t` of the resident page (its alias
// root's), or CT_UNKNOWN.
uint dependency_type(uint t)
{
    uint count = dependency_type_count();
    uint root = t < count ? canonical_type_roots[t] : INVALID;
    return root < count ? ct_dependency_state(root) : CT_UNKNOWN;
}

// The signature node of a dependency declaration, or INVALID.
uint declaration_signature(uint declaration)
{
    uint t = dependency_declaration_word(declaration * 14u + 7u);
    uint count = dependency_type_count();
    uint root = t < count ? canonical_type_roots[t] : INVALID;
    return root < count ? root : INVALID;
}

void publish_imported_result(uint token, uint callee, uint2 result, uint legacy)
{
    if (token >= gParams.n_tokens ||
        call_dependency_library_id[token] != call_dependency_library_id[callee] ||
        call_dependency_unit_id[token] != call_dependency_unit_id[callee] ||
        call_dependency_local_index[token] != call_dependency_local_index[callee]) return;
    decl_type_ref_tag[token] = result.x;
    decl_type_ref_payload[token] = result.y;
    call_return_type[token] = legacy;
    call_return_type_token[token] = result.x == 3u ? token : INVALID;
}

// The declared result of the call, CT_NONE to skip the call, or CT_UNKNOWN.
uint declared_result(uint call, uint token, bool record, bool unit, bool imported)
{
    if (unit)
    {
        // A nongeneric imported unit is a complete zero-argument application,
        // read while the owning dependency page is resident.
        uint path = path_id_by_owner_hir[call];
        if (path >= min(path_count_out[0u], gParams.n_hir_nodes) ||
            path_owner_hir[path] != call || resolved_dependency_value_metadata[path * 4u] != 9u ||
            module_value_path_call_head[token] != 0u ||
            checked_token_in_match_pattern(token, hir_count(), compact_hir_core,
                compact_match_arm_count, compact_match_arms)) return CT_NONE;
    }
    if (record)
    {
        // Explicit/receiving applications already own their complete type.
        // Only field-bound literals ask this producer to create one.
        if (struct_lit_context_instance[call] < mutable_type_capacity() ||
            call_context_owner_by_token[token] != call) return CT_NONE;
        if (external_type_library_id[token] == INVALID)
        {
            uint declaration = struct_lit_context_decl_token[call];
            if (declaration >= gParams.n_tokens || type_instance_kind[declaration] != 1u) return CT_NONE;
            return ct_ref(3u, declaration);
        }
    }
    if (record || unit)
    {
        uint declaration = dependency_find_declaration(external_type_library_id[token],
            external_type_unit_id[token], external_type_local_index[token]);
        if (declaration >= dependency_declaration_count()) return CT_NONE;
        uint signature = declaration_signature(declaration);
        return signature != INVALID ? ct_dependency_state(signature) : CT_NONE;
    }
    // A language intrinsic has no declaration. Its scalar result (the data
    // pointers) is complete, so a call passed directly as an argument has an
    // accepted value like any other call.
    if (!record && !unit && call_intrinsic_tag[token] != INTRINSIC_NONE)
    {
        uint scalar = intrinsic_scalar_result(call_intrinsic_tag[token]);
        return scalar != 0u ? ct_ref(1u, scalar) : CT_NONE;
    }
    if (imported)
    {
        // Read page-local types while their declaration page is resident.
        uint method = dependency_find_method(call_dependency_library_id[token],
            call_dependency_unit_id[token], call_dependency_local_index[token]);
        if (method < dependency_member_count())
        {
            uint owner = checked_call_application_owner(token);
            uint receiver = method_call_receiver_ref_payload[owner];
            if (method_call_receiver_ref_tag[owner] != 3u || receiver >= mutable_type_capacity()) return CT_NONE;
            return dependency_type(dependency_member_word(method * SEMANTIC_INTERFACE_MEMBER_WORDS + 7u));
        }
        uint declaration = dependency_find_declaration(call_dependency_library_id[token],
            call_dependency_unit_id[token], call_dependency_local_index[token]);
        if (declaration >= dependency_declaration_count()) return CT_NONE;
        uint signature = declaration_signature(declaration);
        if (signature == INVALID || dependency_type_word(signature * 9u) != 7u) return CT_NONE;
        uint start = dependency_type_word(signature * 9u + 3u);
        uint count = dependency_type_word(signature * 9u + 4u);
        uint edges = dependency_count(5u);
        if (count == 0u || start > edges || count > edges - start) return CT_NONE;
        // Every imported signature publishes its complete caller-side result.
        return dependency_type(dependency_type_edge_word(start + count - 1u));
    }
    uint declaration = call_fn_index[token];
    if (declaration >= gParams.n_tokens) return CT_NONE;
    uint header = callable_header_token(declaration);
    if (header >= gParams.n_tokens) return CT_NONE;
    if (type_decl_generic_param_count[header] > ARG_LIMIT)
    {
        record_min_token_error(status, token, 6u, 0x474e0002u);
        return CT_NONE;
    }
    // A target may resolve only after its receiver is inferred; every
    // resolved signature reaches the accepted result relation.
    uint tag = fn_return_ref_tag[declaration];
    uint payload = fn_return_ref_payload[declaration];
    return tag == 0u || payload == INVALID ? CT_NONE : ct_ref(tag, payload);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = dtid.x + dtid.y * 16776960u;
    if (call >= hir_count()) return;
    bool record = compact_hir_core[call].kind == 28u;
    bool unit = compact_hir_core[call].kind == 33u;
    if (!record && !unit && compact_hir_core[call].kind != 19u) return;
    uint callee = record || unit ? call : compact_hir_payload[call].a;
    if (callee >= hir_count()) return;
    uint kind = compact_hir_core[callee].kind;
    if (!record && kind != 21u && kind != 22u && kind != 33u) return;
    uint token = record || unit ? compact_hir_core[call].token_start
        : kind == 21u ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (token >= gParams.n_tokens) token = compact_hir_core[callee].token_start;
    if (token >= gParams.n_tokens) return;
    bool imported = !record && !unit && call_dependency_library_id[token] != INVALID;
    uint pattern = declared_result(call, token, record, unit, imported);
    if (pattern == CT_NONE) return;
    // Closed results need no environment; open ones use the published one.
    uint environment = ct_closed(pattern) ? CT_NONE : ct_call_env(token).x;
    CtSpare spare = ct_spare_none();
    uint result_id = ct_is_resolved(pattern) && (environment == CT_NONE || ct_is_record(environment))
        ? ct_subst(SourceSlots(), environment, pattern, true, spare) : CT_UNKNOWN;
    uint failure = ct_is_resolved(pattern) ? FAILURE_UNBOUND : CT_REALIZE_INVALID;
    uint2 result = uint2(0u, INVALID);
    if (ct_is_resolved(result_id)) result = ct_realize(result_id, failure);
    else
    {
        uint overflow = ct_subst_counts[CT_SUBST_COUNT_OVERFLOW];
        if ((overflow & (CT_SUBST_OVERFLOW_MEMO | CT_SUBST_OVERFLOW_ROWS | CT_SUBST_OVERFLOW_CONSTANTS)) != 0u ||
            ct_counts[CT_COUNT_OVERFLOW] != 0u)
            failure = CT_REALIZE_CAPACITY;
        else if ((overflow & CT_SUBST_OVERFLOW_WORK) != 0u) failure = CT_REALIZE_LIMIT;
    }
    if (result.x == 0u)
    {
        // Another lane is writing a row this result needs: next round.
        if (failure == CT_REALIZE_BUSY) { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); return; }
        if (checked_call_environment_rejected(token) || checked_call_constant_environment_rejected(token)) return;
        // Missing environment entries may become known from earlier call
        // results. They are still diagnosed by the final, nondeferred pass.
        if (call_inference_state[0u] == 0u || (failure != 3u && failure != 4u))
            record_min_token_error(status, token, 6u, 0x474e0000u | failure);
        return;
    }
    if (record)
    {
        if (result.x != 3u || result.y >= mutable_type_capacity())
        { record_min_token_error(status, token, 6u, 0x474e0003u); return; }
        struct_lit_context_instance[call] = result.y;
        struct_lit_context_decl_token[call] = type_instance_decl_token[result.y];
    }
    if (unit)
    {
        decl_type_ref_tag[token] = result.x;
        decl_type_ref_payload[token] = result.y;
    }
    uint legacy = result.x == 1u ? result.y : 0u;
    if (result.x == 3u)
    {
        // Completed substitution is in caller scope. A following producer
        // expands its declaration fields under nominal receiver environments.
        call_result_instance[call] = result.y;
        uint result_kind = type_instance_kind[result.y];
        if (result_kind == 4u) legacy = 8u;
        uint element = type_instance_elem_ref_payload[result.y];
        if ((result_kind == 2u || result_kind == 3u) &&
            type_instance_elem_ref_tag[result.y] == 1u && element < 128u)
            legacy = 128u + element;
        call_return_type[token] = legacy;
    }
    else if (result.x == 1u)
    {
        call_result_instance[call] = INVALID;
        call_return_type[token] = result.y;
    }
    if (imported)
    {
        // Only qualified calls own their leading-token aliases. A member's
        // source span starts at its receiver, which can be a different call
        // even when both calls select the same callable declaration.
        if (kind != 21u)
        {
            publish_imported_result(compact_hir_core[callee].token_start, token, result, legacy);
            publish_imported_result(compact_hir_core[call].token_start, token, result, legacy);
        }
        publish_imported_result(token, token, result, legacy);
    }
    // Provisional scalar caches and contextual result rows can be reset by
    // earlier passes. Progress belongs to a stable complete-type relation:
    // rows are unique per ID, and another producer's row compares by its ID.
    uint previous_tag = call_inference_result_tag[call];
    uint previous_payload = call_inference_result_payload[call];
    bool changed = (previous_tag != result.x || previous_payload != result.y) &&
        ct_ref(previous_tag, previous_payload) != result_id;
    call_inference_result_tag[call] = result.x;
    call_inference_result_payload[call] = result.y;
    if (changed)
    {
        uint ignored;
        InterlockedAdd(call_inference_state[1u], 1u, ignored);
    }
}
