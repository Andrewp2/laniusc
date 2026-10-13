// Publish a method only after the local inventory and every retained dependency
// page have contributed. Imported signatures are projected on a second visit.
import gpu_index;
import atomics;
import status;
import type_checker.methods.candidate;
import type_checker.mutable_checked_type_graph;
import type_checker.scoped_type_equality;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> module_value_path_call_path_id;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> method_call_selection_owned;
StructuredBuffer<uint> method_call_source_ref_tag;
StructuredBuffer<uint> method_call_source_ref_payload;
StructuredBuffer<uint> method_call_receiver_hir;
RWStructuredBuffer<MethodCandidate> method_candidate;
RWStructuredBuffer<uint> method_call_receiver_ref_tag;
RWStructuredBuffer<uint> method_call_receiver_ref_payload;
RWStructuredBuffer<uint> method_call_parameter_ref_tag;
RWStructuredBuffer<uint> method_call_parameter_ref_payload;
RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_dependency_library_id;
RWStructuredBuffer<uint> call_dependency_unit_id;
RWStructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> call_dependency_generic_requirements;
RWStructuredBuffer<uint> call_dependency_host_service;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> call_return_aggregate_word_count;
RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> call_context_owner_by_token;
RWStructuredBuffer<uint> call_result_instance;
RWStructuredBuffer<uint> call_inference_result_tag;
RWStructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> type_application_count;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_instance_aggregate_word_count;
RWStructuredBuffer<uint> type_native_word_count;
RWStructuredBuffer<uint> type_native_scalar_identity;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
#include "../type/instances/allocate_application.slang"

bool same_type(uint2 left, uint2 right)
{
    return scoped_type_refs_equal<MutableCheckedTypeGraph>(left.x, left.y, INVALID,
        right.x, right.y, INVALID, mutable_type_capacity(), gParams.n_tokens);
}

bool accepted_parameter(uint token, MethodCandidate candidate, out uint2 parameter)
{
    parameter = uint2(0u, INVALID);
    uint2 matched = uint2(candidate.matched_ref_tag, candidate.matched_ref_payload);
    uint2 current = uint2(method_call_source_ref_tag[token], method_call_source_ref_payload[token]);
    uint2 predecessor = uint2(0u, INVALID);
    for (uint depth = 0u; depth < candidate.deref_count; depth++)
    {
        if (current.x != 3u || current.y >= mutable_type_capacity() ||
            type_instance_kind[current.y] != 4u) return false;
        predecessor = current;
        current = uint2(type_instance_elem_ref_tag[current.y], type_instance_elem_ref_payload[current.y]);
    }
    if (!same_type(current, matched)) return false;
    if (candidate.receiver_mode == 0u)
        return method_call_receiver_hir[token] == INVALID && candidate.deref_count == 0u;
    if (method_call_receiver_hir[token] == INVALID) return false;
    if (candidate.receiver_mode == 1u) { parameter = matched; return true; }
    if (candidate.receiver_mode != 2u) return false;
    if (candidate.deref_count != 0u) { parameter = predecessor; return true; }

    // Accepted parameter cells are cleared at job start. Only a row allocated
    // in this job's checked arena can be reused; page rows are never candidates.
    uint tokens; uint stride;
    type_generic_param_slot_by_token.GetDimensions(tokens, stride);
    uint base = tokens + 64u;
    uint previous = method_call_parameter_ref_payload[token];
    if (method_call_parameter_ref_tag[token] == 3u && previous >= base &&
        previous < mutable_type_capacity() && previous - base < type_application_count[0u] &&
        type_instance_state[previous] == 1u && type_instance_kind[previous] == 4u &&
        same_type(uint2(type_instance_elem_ref_tag[previous],
            type_instance_elem_ref_payload[previous]), matched))
    { parameter = uint2(3u, previous); return true; }
    uint target = allocate_application(INVALID, 0u, 0u, INVALID, INVALID, INVALID, INVALID);
    if (target == INVALID) return false;
    type_instance_elem_ref_tag[target] = matched.x;
    type_instance_elem_ref_payload[target] = matched.y;
    type_native_word_count[target] = 1u;
    // Kind is published last; all children are already checked caller graphs.
    type_instance_kind[target] = 4u;
    parameter = uint2(3u, target);
    return true;
}

void clear_target(uint token)
{
    call_fn_index[token] = INVALID;
    call_dependency_library_id[token] = INVALID;
    call_dependency_unit_id[token] = INVALID;
    call_dependency_local_index[token] = INVALID;
    call_dependency_generic_requirements[token] = 0u;
    call_dependency_host_service[token] = INVALID;
    call_return_type[token] = 0u;
    call_return_type_token[token] = INVALID;
    call_return_aggregate_word_count[token] = 0u;
    call_param_count[token] = 0u;
    decl_type_ref_tag[token] = 0u;
    decl_type_ref_payload[token] = INVALID;
}

// Associated calls are looked up at their final segment, while explicit
// environments and checked call artifacts may use the qualified owner token.
void publish_local_owner_alias(uint token)
{
    if (method_call_receiver_hir[token] != INVALID) return;
    uint path = module_value_path_call_path_id[token];
    if (path >= min(path_count_out[0u], gParams.n_hir_nodes)) return;
    uint owner = path_owner_token[path];
    if (owner >= gParams.n_tokens || owner == token) return;
    method_candidate[owner] = method_candidate[token];
    method_call_receiver_ref_tag[owner] = method_call_receiver_ref_tag[token];
    method_call_receiver_ref_payload[owner] = method_call_receiver_ref_payload[token];
    method_call_parameter_ref_tag[owner] = method_call_parameter_ref_tag[token];
    method_call_parameter_ref_payload[owner] = method_call_parameter_ref_payload[token];
    call_fn_index[owner] = call_fn_index[token];
    call_dependency_library_id[owner] = call_dependency_library_id[token];
    call_dependency_unit_id[owner] = call_dependency_unit_id[token];
    call_dependency_local_index[owner] = call_dependency_local_index[token];
    call_dependency_generic_requirements[owner] = call_dependency_generic_requirements[token];
    call_dependency_host_service[owner] = call_dependency_host_service[token];
    call_return_type[owner] = call_return_type[token];
    call_return_type_token[owner] = call_return_type_token[token];
    call_return_aggregate_word_count[owner] = call_return_aggregate_word_count[token];
    call_param_count[owner] = call_param_count[token];
    decl_type_ref_tag[owner] = decl_type_ref_tag[token];
    decl_type_ref_payload[owner] = decl_type_ref_payload[token];
}

void invalidate_result(uint token)
{
    uint call = call_context_owner_by_token[token];
    uint capacity; uint stride;
    call_inference_result_tag.GetDimensions(capacity, stride);
    if (call < capacity)
    {
        call_inference_result_tag[call] = 0u;
        call_inference_result_payload[call] = INVALID;
        call_result_instance[call] = INVALID;
    }
    uint ignored;
    InterlockedAdd(call_inference_state[1u], 1u, ignored);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_thread_id_2d(dtid, 65535u, 256u);
    if (token >= min(token_count[0u], gParams.n_tokens) ||
        method_call_selection_owned[token] == 0u) return;
    MethodCandidate candidate = method_candidate[token];
    uint2 parameter;
    if (candidate.state == METHOD_CANDIDATE_UNIQUE &&
        !accepted_parameter(token, candidate, parameter))
    { candidate.state = METHOD_CANDIDATE_INVALID; method_candidate[token] = candidate; }
    bool prior = call_fn_index[token] != INVALID || call_dependency_library_id[token] != INVALID;
    if (candidate.state != METHOD_CANDIDATE_UNIQUE)
    {
        clear_target(token);
        method_call_receiver_ref_tag[token] = 0u;
        method_call_receiver_ref_payload[token] = INVALID;
        method_call_parameter_ref_tag[token] = 0u;
        method_call_parameter_ref_payload[token] = INVALID;
        if (prior) invalidate_result(token);
        publish_local_owner_alias(token);
        if (call_inference_state[0u] == 0u && candidate.state == METHOD_CANDIDATE_AMBIGUOUS)
            record_min_token_error(status, token, 10u, 0xffffff0cu);
        if (call_inference_state[0u] == 0u && candidate.state == METHOD_CANDIDATE_INVALID)
            record_min_token_error(status, token, 10u, 0xffffff0du);
        return;
    }
    bool same_callable = candidate.callable_kind == METHOD_CALLABLE_LOCAL
        ? call_fn_index[token] == candidate.local_index && call_dependency_library_id[token] == INVALID
        : call_fn_index[token] == INVALID &&
          call_dependency_library_id[token] == candidate.library_id &&
          call_dependency_unit_id[token] == candidate.unit_id &&
          call_dependency_local_index[token] == candidate.local_index;
    bool same_receiver = same_type(uint2(method_call_receiver_ref_tag[token],
        method_call_receiver_ref_payload[token]),
        uint2(candidate.matched_ref_tag, candidate.matched_ref_payload));
    bool same_parameter = candidate.receiver_mode == 0u
        ? method_call_parameter_ref_tag[token] == 0u
        : same_type(uint2(method_call_parameter_ref_tag[token],
            method_call_parameter_ref_payload[token]), parameter);
    if (!same_callable || !same_receiver || !same_parameter)
    { clear_target(token); invalidate_result(token); }
    method_call_receiver_ref_tag[token] = candidate.matched_ref_tag;
    method_call_receiver_ref_payload[token] = candidate.matched_ref_payload;
    method_call_parameter_ref_tag[token] = parameter.x;
    method_call_parameter_ref_payload[token] = parameter.y;
    if (candidate.callable_kind == METHOD_CALLABLE_LOCAL)
    {
        uint declaration = candidate.local_index;
        call_fn_index[token] = declaration;
        // Only declaration signature facts are copied here. Accepted concrete
        // results remain under the ordinary environment/materializer owner.
        call_return_type[token] = call_return_type[declaration];
        call_return_type_token[token] = call_return_type_token[declaration];
        call_param_count[token] = call_param_count[declaration];
        publish_local_owner_alias(token);
    }
    else
    {
        call_dependency_library_id[token] = candidate.library_id;
        call_dependency_unit_id[token] = candidate.unit_id;
        call_dependency_local_index[token] = candidate.local_index;
    }
}
