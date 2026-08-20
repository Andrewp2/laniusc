import codegen.lowering_ir;
import codegen.lir.x86.common;
import gpu_index;

struct Params { uint token_capacity; uint parameter_capacity; uint local_capacity; uint function_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_param_total;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> semantic_lir_local_total;
StructuredBuffer<SemanticLirLocal> semantic_lir_locals;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<uint> x86_decl_location_by_token;
RWStructuredBuffer<uint> x86_saved_gpr_mask_by_function;
StructuredBuffer<X86FunctionRegisterAnalysis>
    x86_register_analysis_by_function;
StructuredBuffer<X86DeclarationAnalysis> x86_decl_analysis_by_token;
StructuredBuffer<uint> x86_live_by_semantic;
StructuredBuffer<uint> x86_stack_slot_count_by_function;
RWStructuredBuffer<uint> x86_frame_slot_count_by_function;

static const uint DISPATCH_X_STRIDE = 16776960u;

bool valid_function(uint function_id)
{
    return function_id < min(gParams.function_capacity,
        semantic_lir_function_total[0u]);
}

bool scalar_gpr_type(uint type_id)
{
    return type_id == 1u || type_id == 2u || type_id == 3u ||
        type_id == 4u || type_id == 6u || type_id == 8u;
}

uint register_location(uint function_id, uint ordinal, uint type_id,
                       uint declaration_token, uint incoming_register)
{
    if (!scalar_gpr_type(type_id) || ordinal >= 6u)
        return X86_LOCATION_INVALID;
    X86FunctionRegisterAnalysis register_analysis =
        x86_register_analysis_by_function[function_id];
    uint last_read = x86_decl_analysis_by_token[declaration_token].last_read;
    bool repeated_after_call =
        (register_analysis.flags &
         X86_FUNCTION_REGISTER_CALL_WITH_LOOP) != 0u && last_read != 0u;
    if (register_analysis.first_call == 0u ||
        (last_read < register_analysis.first_call && !repeated_after_call))
    {
        uint physical = x86_caller_declaration_register(ordinal);
        if ((register_analysis.flags &
             X86_FUNCTION_REGISTER_DIRECT_ABI_HOMES) != 0u &&
            incoming_register != X86_LOCATION_INVALID)
        {
            bool before_fixed_clobber = incoming_register == 2u
                ? register_analysis.first_rdx_clobber == 0u ||
                  last_read < register_analysis.first_rdx_clobber
                : incoming_register == 1u
                    ? register_analysis.first_rcx_clobber == 0u ||
                      last_read < register_analysis.first_rcx_clobber
                    : true;
            if (before_fixed_clobber) physical = incoming_register;
        }
        return X86_LOCATION_REGISTER | physical;
    }
    if (ordinal >= 4u) return X86_LOCATION_INVALID;
    uint physical = ordinal == 0u ? 3u : 11u + ordinal;
    uint ignored;
    InterlockedOr(x86_saved_gpr_mask_by_function[function_id],
        1u << physical, ignored);
    return X86_LOCATION_REGISTER | physical;
}

uint assign_declaration(uint function_id, uint ordinal, uint type_id,
                        uint declaration_token, uint incoming_register)
{
    uint location = register_location(function_id, ordinal, type_id,
        declaration_token, incoming_register);
    if (location != X86_LOCATION_INVALID) return location;
    // Stack declaration homes use stable source ordinals, keeping allocation
    // constant-time and parallel. Dead locals are filtered before this point;
    // live declarations may still leave holes for earlier register-resident
    // declarations.
    uint slot = x86_stack_slot_count_by_function[function_id] +
        ordinal * 2u;
    uint ignored;
    InterlockedMax(x86_frame_slot_count_by_function[function_id],
        slot + 2u, ignored);
    return slot;
}

bool local_needs_home(uint declaration_token)
{
    X86DeclarationAnalysis analysis =
        x86_decl_analysis_by_token[declaration_token];
    uint definition_live = 0u;
    if (analysis.definition != X86_DECLARATION_MULTIPLE_DEFINITIONS &&
        analysis.definition != X86_LOCATION_INVALID)
        definition_live = x86_live_by_semantic[analysis.definition];
    return x86_declaration_needs_home(analysis, definition_live);
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
            SemanticLirFunction function =
                semantic_lir_functions[param.function_id];
            x86_decl_location_by_token[param.declaration_id] =
                assign_declaration(param.function_id, param.ordinal,
                    param.type_id, param.declaration_id,
                    x86_abi_argument_register(
                        x86_parameter_abi_ordinal(function, param.ordinal)));
        }
    }

    uint local_count = min(gParams.local_capacity, semantic_lir_local_total[0u]);
    if (row < local_count)
    {
        SemanticLirLocal local = semantic_lir_locals[row];
        if (local.declaration_id < gParams.token_capacity &&
            valid_function(local.function_id) &&
            local_needs_home(local.declaration_id))
        {
            SemanticLirFunction semantic_function = semantic_lir_functions[local.function_id];
            uint ordinal = semantic_function.param_count + local.ordinal;
            x86_decl_location_by_token[local.declaration_id] =
                assign_declaration(local.function_id, ordinal,
                    local.type_id, local.declaration_id,
                    X86_LOCATION_INVALID);
        }
    }
}
