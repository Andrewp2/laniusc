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
RWStructuredBuffer<uint> x86_decl_location_by_token;
RWStructuredBuffer<uint> x86_saved_gpr_mask_by_function;

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

bool scalar_gpr_type(uint type_id)
{
    return type_id == 1u || type_id == 2u || type_id == 3u ||
        type_id == 4u || type_id == 6u;
}

uint declaration_location(uint function_id, uint ordinal, uint type_id,
                          uint stack_slot)
{
    if (!scalar_gpr_type(type_id) || ordinal >= 4u)
        return stack_slot;
    uint physical = ordinal == 0u ? 3u : 11u + ordinal;
    uint ignored;
    InterlockedOr(x86_saved_gpr_mask_by_function[function_id],
        1u << physical, ignored);
    return X86_LOCATION_REGISTER | physical;
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
            uint slot = function.instruction_count + param.ordinal;
            x86_decl_location_by_token[param.declaration_id] =
                declaration_location(param.function_id, param.ordinal,
                    param.type_id, slot);
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
            uint ordinal = semantic_function.param_count + local.ordinal;
            uint slot = function.instruction_count + ordinal;
            x86_decl_location_by_token[local.declaration_id] =
                declaration_location(local.function_id, ordinal,
                    local.type_id, slot);
        }
    }
}
