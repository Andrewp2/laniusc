// The constructor consumer publishes one complete result before payload
// validation. Readers must not independently infer a different context from
// the enclosing declaration or from another payload lane's expected-type writes.
uint enum_result_instance_for_call(uint call)
{
    if (call >= min(compact_hir_count[0u], gParams.n_hir_nodes)) return INVALID;
    uint instance = call_result_instance[call];
    uint capacity; uint stride;
    type_instance_decl_token.GetDimensions(capacity, stride);
    return instance < capacity ? instance : INVALID;
}
