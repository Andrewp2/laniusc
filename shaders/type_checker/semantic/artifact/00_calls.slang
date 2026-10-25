// Project resolved call facts from the type checker's token-indexed working
// tables into one canonical record per dense call-expression HIR row.
//
// Token tables have intentionally different domains: call_fn_index stores a
// declaration-name token, backend_call_fn_index stores a function-start token,
// and call_return_type at the callee token stores the checked per-call result
// after generic/method substitution. This pass is the only boundary that joins
// those domains; downstream semantic passes consume the dense record directly.

import hir_records;
import gpu_index;
import checked_semantic_artifact;
import type_checker.methods.candidate;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_dependency_value_metadata;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> backend_call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> call_dependency_host_service;
StructuredBuffer<uint> call_dependency_native_abi;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> call_return_aggregate_word_count;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> type_instance_aggregate_word_count;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<MethodCandidate> method_candidate;
StructuredBuffer<uint> method_call_receiver_hir;
StructuredBuffer<uint> method_call_parameter_ref_tag;
StructuredBuffer<uint> method_call_parameter_ref_payload;
RWStructuredBuffer<uint> semantic_argument_mode_by_hir;
RWStructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
RWStructuredBuffer<uint> semantic_call_native_abi_by_hir;
RWStructuredBuffer<uint> semantic_aggregate_word_count_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint IMPORTED_PAYLOAD_VARIANT = 10u;
static const uint IMPORTED_GENERIC_UNIT_VARIANT = 11u;
static const uint CALLABLE_NONE = 0u;
static const uint CALLABLE_FUNCTION = 1u;
static const uint CALLABLE_INTRINSIC = 2u;
static const uint CALLABLE_DEPENDENCY = 3u;
static const uint CALLABLE_ENUM_VARIANT = 4u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[ForceInline]
uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
uint active_path_count() { return min(gParams.n_hir_nodes, compact_path_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint path_node_for_callee(uint callee)
{
    if (!valid_hir(callee)) return INVALID;
    if (compact_hir_core[callee].kind == HIR_PATH_EXPR) return callee;
    if (compact_hir_core[callee].kind != HIR_NAME_EXPR) return INVALID;
    uint child = compact_hir_links[callee].first_child;
    return valid_hir(child) && compact_hir_core[child].kind == HIR_PATH_EXPR
               ? child
               : INVALID;
}

uint callee_token_for_call(uint call)
{
    uint callee = compact_hir_payload[call].a;
    if (!valid_hir(callee)) return INVALID;
    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = core.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(token)) token = core.token_start;
    return valid_token(token) ? token : INVALID;
}

uint path_for_callee(uint callee)
{
    uint owner = path_node_for_callee(callee);
    if (!valid_hir(owner)) return INVALID;
    uint path = path_id_by_owner_hir[owner];
    return path < active_path_count() ? path : INVALID;
}

bool local_enum_variant_for_call(
    uint call,
    out uint variant_hir,
    out uint variant_ordinal)
{
    variant_hir = INVALID;
    variant_ordinal = INVALID;
    uint callee = compact_hir_payload[call].a;
    uint path = path_for_callee(callee);
    uint decl = path != INVALID ? resolved_value_decl[path] : INVALID;
    if (decl >= gParams.n_hir_nodes)
    {
        uint callee_token = callee_token_for_call(call);
        uint declaration_token = valid_token(callee_token)
            ? call_fn_index[callee_token] : INVALID;
        decl = valid_token(declaration_token)
            ? decl_id_by_name_token[declaration_token] : INVALID;
    }
    if (decl >= gParams.n_hir_nodes || decl_kind[decl] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;
    uint variant = decl_hir_node[decl];
    uint count = min(compact_variant_count[0u], gParams.n_hir_nodes);
    if (variant >= count) return false;
    HirVariant record = compact_variants[variant];
    variant_hir = variant;
    variant_ordinal = record.ordinal;
    return true;
}

uint imported_constructor_ordinal(uint call)
{
    uint callee = compact_hir_payload[call].a;
    uint path = path_for_callee(callee);
    if (path == INVALID) return INVALID;
    uint base = path * 4u;
    uint kind = resolved_dependency_value_metadata[base];
    return kind == HIR_ITEM_KIND_ENUM_VARIANT || kind == IMPORTED_PAYLOAD_VARIANT ||
        kind == IMPORTED_GENERIC_UNIT_VARIANT
        ? resolved_dependency_value_metadata[base + 2u]
        : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    // This HIR-keyed table is sparse by contract: consumers inspect it only
    // for call-expression rows. Avoid writing an empty record for every
    // other syntax node. Active call rows are still rewritten in full on every
    // daemon job, so stale workspace contents cannot cross the semantic ABI.
    if (!valid_hir(row) || compact_hir_core[row].kind != HIR_CALL_EXPR) return;
    semantic_aggregate_word_count_by_hir[row] = 0u;

    CheckedCallArtifact call;
    call.target_token = INVALID;
    call.dependency_library_id = INVALID;
    call.dependency_unit_id = INVALID;
    call.dependency_local_index = INVALID;
    call.dependency_host_service = INVALID;
    call.intrinsic_tag = 0u;
    call.return_type = 0u;
    call.receiver_hir = INVALID;
    call.arg_count = 0u;
    call.return_ref_tag = 0u;
    call.return_ref_payload = INVALID;
    call.callable_kind = CALLABLE_NONE;
    call.callable_hir = INVALID;
    call.callable_ordinal = INVALID;
    call.receiver_adjustment_kind = 0u;
    call.receiver_deref_count = 0u;
    call.receiver_matched_ref_tag = 0u;
    call.receiver_matched_ref_payload = INVALID;
    call.receiver_parameter_ref_tag = 0u;
    call.receiver_parameter_ref_payload = INVALID;
    call.symbolic_type_environment = 0u;
    {
        uint callee = compact_hir_payload[row].a;
        uint callee_token = callee_token_for_call(row);
        if (valid_token(callee_token))
        {
            uint local_variant_hir;
            uint local_variant_ordinal;
            bool local_variant = local_enum_variant_for_call(
                row, local_variant_hir, local_variant_ordinal);
            uint imported_variant_ordinal = imported_constructor_ordinal(row);
            call.target_token = backend_call_fn_index[callee_token];
            if (call_dependency_library_id[callee_token] != INVALID)
            {
                call.dependency_library_id = call_dependency_library_id[callee_token];
                call.dependency_unit_id = call_dependency_unit_id[callee_token];
                call.dependency_local_index = call_dependency_local_index[callee_token];
                call.dependency_host_service = call_dependency_host_service[callee_token];
            }
            call.intrinsic_tag = call_intrinsic_tag[callee_token];
            if (call.intrinsic_tag != 0u)
                call.callable_kind = CALLABLE_INTRINSIC;
            else if (local_variant)
            {
                call.callable_kind = CALLABLE_ENUM_VARIANT;
                call.callable_hir = local_variant_hir;
                call.callable_ordinal = local_variant_ordinal;
                call.target_token = INVALID;
            }
            else if (imported_variant_ordinal != INVALID &&
                     call.dependency_library_id != INVALID)
            {
                call.callable_kind = CALLABLE_ENUM_VARIANT;
                call.callable_ordinal = imported_variant_ordinal;
                call.target_token = INVALID;
            }
            else if (call.dependency_library_id != INVALID)
                call.callable_kind = CALLABLE_DEPENDENCY;
            else if (call.target_token != INVALID)
                call.callable_kind = CALLABLE_FUNCTION;
            else
            {
                // Unresolved callables remain explicit so lowering can reject
                // them at the checked semantic boundary.
            }
            call.return_type = call_return_type[callee_token];
            semantic_aggregate_word_count_by_hir[row] =
                call_return_aggregate_word_count[callee_token];
            uint return_token = call_return_type_token[callee_token];
            if (valid_token(return_token))
            {
                call.return_ref_tag = type_expr_ref_tag[return_token];
                call.return_ref_payload = type_expr_ref_payload[return_token];
                if (call.return_ref_tag == 0u)
                {
                    call.return_ref_tag = decl_type_ref_tag[return_token];
                    call.return_ref_payload = decl_type_ref_payload[return_token];
                }
            }
            if (call.return_ref_tag == 0u)
            {
                uint target = call_fn_index[callee_token];
                if (valid_token(target))
                {
                    call.return_ref_tag = decl_type_ref_tag[target];
                    call.return_ref_payload = decl_type_ref_payload[target];
                }
            }
            // Generic and aggregate call checking publishes a concrete result
            // instance by dense call HIR row. Prefer that checked call-site
            // fact over the callee declaration's potentially symbolic return
            // instance so downstream semantic consumers never have to repeat
            // generic substitution.
            uint result_instance = call_result_instance[row];
            uint instance_capacity; uint instance_stride;
            type_instance_aggregate_word_count.GetDimensions(instance_capacity, instance_stride);
            if (result_instance < instance_capacity)
            {
                call.return_ref_tag = 3u;
                call.return_ref_payload = result_instance;
                uint instance_words = type_instance_aggregate_word_count[result_instance];
                if (instance_words != 0u)
                    semantic_aggregate_word_count_by_hir[row] = instance_words;
            }
            // The complete producer also returns nominal leaves, encoded in
            // the existing scalar reference protocol. Preserve those accepted
            // call-site facts instead of the declaration's symbolic T or an
            // early void cache. Downstream checks and layout use this record.
            uint inferred_tag = call_inference_result_tag[row];
            uint inferred_payload = call_inference_result_payload[row];
            // A result bound only by the call's context (a trait parameter
            // through a bound, methods/07a and dependencies/15b) has no
            // argument claim for generic_call_results to read, and the
            // declaration's reference is the trait's or a routed impl's
            // symbolic T. The accepted result, which replay specializes, is
            // the call-site fact.
            // The accepted relation owns compound results too. A provisional
            // instance cache may still contain declaration-side parameters;
            // it cannot override the complete checked caller-side result.
            if (inferred_tag == 3u && inferred_payload < instance_capacity)
            {
                call.return_ref_tag = 3u;
                call.return_ref_payload = inferred_payload;
                uint instance_words = type_instance_aggregate_word_count[inferred_payload];
                if (instance_words != 0u)
                    semantic_aggregate_word_count_by_hir[row] = instance_words;
            }
            if (inferred_tag == 1u && inferred_payload != 0u && inferred_payload != INVALID)
            {
                call.return_ref_tag = inferred_tag;
                call.return_ref_payload = inferred_payload;
                call.return_type = inferred_payload;
            }
            // A substituted generic scalar reference is authoritative even
            // when the declaration's original machine return code was zero.
            // In particular, strings must retain their pointer/length result.
            if (call.return_ref_tag == 1u && call.return_ref_payload >= 1u &&
                call.return_ref_payload <= 7u)
                call.return_type = call.return_ref_payload;
            // Dependency projection proved this monomorphic struct empty
            // while retaining its nominal type for all semantic checks. The
            // backend consumes its unit machine representation, rather than
            // truncating an external-canonical tag and treating a page row
            // number as a scalar/aggregate type code.
            if (call.return_type == 1u && call.return_ref_tag == 5u &&
                semantic_aggregate_word_count_by_hir[row] == 0u)
            {
                call.return_ref_tag = 1u;
                call.return_ref_payload = 1u;
            }
        }
        call.receiver_hir = valid_hir(callee) &&
                            compact_hir_core[callee].kind == HIR_MEMBER_EXPR
                                ? compact_hir_payload[callee].b
                                : INVALID;
        call.arg_count = compact_hir_payload[row].c;
        if (call.callable_kind == CALLABLE_INTRINSIC && valid_hir(call.receiver_hir))
        {
            // Intrinsic syntax has explicit arguments and no receiver plan.
            // Do not release a member-shaped call under that classification.
            call.callable_kind = CALLABLE_NONE;
            call.intrinsic_tag = 0u;
            call.target_token = INVALID;
        }
        if ((call.callable_kind == CALLABLE_FUNCTION || call.callable_kind == CALLABLE_DEPENDENCY)
            && valid_hir(call.receiver_hir))
        {
            uint token = callee_token_for_call(row);
            uint capacity; uint stride;
            method_candidate.GetDimensions(capacity, stride);
            bool accepted = token < capacity;
            if (accepted)
            {
                MethodCandidate candidate = method_candidate[token];
                bool local = call.callable_kind == CALLABLE_FUNCTION;
                uint declaration = local ? call_fn_index[token] : call.dependency_local_index;
                accepted = method_candidate_is_winner(candidate,
                    local ? METHOD_CALLABLE_LOCAL : METHOD_CALLABLE_DEPENDENCY,
                    local ? INVALID : call.dependency_library_id,
                    local ? INVALID : call.dependency_unit_id, declaration) &&
                    method_call_receiver_hir[token] == call.receiver_hir &&
                    candidate.receiver_mode >= 1u && candidate.receiver_mode <= 2u &&
                    method_call_parameter_ref_tag[token] != 0u &&
                    method_call_parameter_ref_payload[token] != INVALID;
                if (accepted)
                {
                    call.receiver_adjustment_kind = candidate.receiver_mode;
                    call.receiver_deref_count = candidate.deref_count;
                    call.receiver_matched_ref_tag = candidate.matched_ref_tag;
                    call.receiver_matched_ref_payload = candidate.matched_ref_payload;
                    call.receiver_parameter_ref_tag = method_call_parameter_ref_tag[token];
                    call.receiver_parameter_ref_payload = method_call_parameter_ref_payload[token];
                    semantic_argument_mode_by_hir[call.receiver_hir] =
                        candidate.receiver_mode == 2u ? 3u : 1u;
                }
            }
            // A callable and receiver adjustment are one accepted fact. A
            // missing or stale plan cannot fall back to forwarding the source
            // value with a different reference depth. Lowering rejects NONE.
            if (!accepted)
            {
                call.callable_kind = CALLABLE_NONE;
                call.target_token = INVALID;
                call.dependency_library_id = INVALID;
                call.dependency_unit_id = INVALID;
                call.dependency_local_index = INVALID;
            }
        }
        if (call.callable_kind == CALLABLE_ENUM_VARIANT)
        {
            uint start = compact_hir_payload[row].b;
            uint total = compact_call_arg_count[0u];
            for (uint i = 0u; i < call.arg_count && start + i < total; ++i)
            {
                HirCallArg argument = compact_call_args[start + i];
                // The callable binder owns borrowed/reference parameter modes,
                // including enum payloads. Only an unset mode defaults to value.
                if (argument.call == row && valid_hir(argument.value) &&
                    semantic_argument_mode_by_hir[argument.value] == 0u)
                    semantic_argument_mode_by_hir[argument.value] = 1u;
            }
        }
    }
    uint abi_token = callee_token_for_call(row);
    semantic_call_native_abi_by_hir[row] = call.callable_kind == CALLABLE_DEPENDENCY &&
        valid_token(abi_token) ? call_dependency_native_abi[abi_token] : 0u;
    semantic_calls_by_hir[row] = call;
}
