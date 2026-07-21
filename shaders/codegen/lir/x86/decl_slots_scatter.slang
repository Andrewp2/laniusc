import codegen.lowering_ir;
import gpu_index;

struct Params { uint token_capacity; uint parameter_capacity; uint local_capacity; uint function_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_param_total;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> semantic_lir_local_total;
StructuredBuffer<SemanticLirLocal> semantic_lir_locals;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> target_function_count;
StructuredBuffer<TargetLirFunction> target_functions;
StructuredBuffer<uint> target_function_index_by_semantic;
RWStructuredBuffer<uint> x86_frame_slot_by_decl_token;

static const uint DISPATCH_X_STRIDE = 16776960u;

bool valid_function(uint function_id)
{
    return function_id < min(gParams.function_capacity, semantic_lir_function_total[0u]) &&
        target_function_index_by_semantic[function_id] < target_function_count[0u];
}

TargetLirFunction target_function_for(uint semantic_id)
{
    return target_functions[target_function_index_by_semantic[semantic_id]];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint param_count = min(gParams.parameter_capacity, semantic_lir_param_total[0u]);
    if (row < param_count)
    {
        SemanticLirParam param = semantic_lir_params[row];
        if (param.declaration_id < gParams.token_capacity && valid_function(param.function_id))
        {
            TargetLirFunction function = target_function_for(param.function_id);
            x86_frame_slot_by_decl_token[param.declaration_id] =
                function.instruction_count + param.ordinal;
        }
    }

    uint local_count = min(gParams.local_capacity, semantic_lir_local_total[0u]);
    if (row < local_count)
    {
        SemanticLirLocal local = semantic_lir_locals[row];
        if (local.declaration_id < gParams.token_capacity && valid_function(local.function_id))
        {
            TargetLirFunction function = target_function_for(local.function_id);
            SemanticLirFunction semantic_function = semantic_lir_functions[local.function_id];
            x86_frame_slot_by_decl_token[local.declaration_id] =
                function.instruction_count + semantic_function.param_count + local.ordinal;
        }
    }
}
