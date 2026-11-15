import gpu_index;
import type_checker.methods.candidate;
import type_checker.calls.inference_activity;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_context_owner_by_token;
RWStructuredBuffer<uint> call_context_arg_mask;
RWStructuredBuffer<uint> call_context_constant_mask;
RWStructuredBuffer<uint> method_call_selection_owned;
RWStructuredBuffer<MethodCandidate> method_candidate;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_thread_id_2d(dtid, 65535u, 256u);
    if (token >= min(token_count[0u], gParams.n_tokens) || !inference_item_active(token)) return;
    // A record whose state is NO_MATCH is the empty record: every producer
    // writes method_candidate_empty() or a record with another state (or a
    // copy of one), and 01_clear empties every record at the job's start.
    // Reading the state word alone keeps the reset from rewriting the whole
    // token range each transaction.
    if (method_candidate[token].state != METHOD_CANDIDATE_NO_MATCH)
        method_candidate[token] = method_candidate_empty();
    if (method_call_name_id[token] == 0xffffffffu) return;
    // Earlier direct-call resolution owns free and module-qualified functions.
    // Previous method winners remain eligible for replacement in later rounds.
    if (method_call_selection_owned[token] == 0u &&
        (call_fn_index[token] != 0xffffffffu ||
         call_dependency_library_id[token] != 0xffffffffu)) return;
    method_call_selection_owned[token] = 1u;
    uint context = call_context_owner_by_token[token];
    uint count; uint stride;
    call_context_arg_mask.GetDimensions(count, stride);
    if (context < count)
    {
        call_context_arg_mask[context] = 0u;
        call_context_constant_mask[context] = 0u;
    }
}
