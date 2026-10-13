import codegen.lowering_ir;
import gpu_index;
struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint local_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_param_total;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> semantic_lir_local_total;
StructuredBuffer<SemanticLirLocal> semantic_lir_locals;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint4> semantic_place_storage_by_token;
StructuredBuffer<uint> semantic_lir_offset;
RWStructuredBuffer<uint> semantic_place_address_by_token;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (row < min(gParams.param_capacity, semantic_lir_param_total[0u]))
    {
        SemanticLirParam param = semantic_lir_params[row];
        if (param.declaration_id < gParams.n_tokens && semantic_place_storage_by_token[param.declaration_id].x != 0u)
            semantic_place_address_by_token[param.declaration_id] =
                semantic_lir_offset[semantic_lir_functions[param.function_id].hir_function] + param.ordinal;
    }
    if (row < min(gParams.local_capacity, semantic_lir_local_total[0u]))
    {
        SemanticLirLocal local = semantic_lir_locals[row];
        if (local.declaration_id < gParams.n_tokens && semantic_place_storage_by_token[local.declaration_id].x != 0u)
        {
            SemanticLirFunction function = semantic_lir_functions[local.function_id];
            semantic_place_address_by_token[local.declaration_id] =
                semantic_lir_offset[function.hir_function] + function.param_count + local.ordinal;
        }
    }
}
