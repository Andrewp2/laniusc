import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.parameter_values;
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
RWStructuredBuffer<uint4> x86_place_storage_by_token;
StructuredBuffer<uint> x86_place_words_by_local;
StructuredBuffer<uint> x86_place_prefix_by_local;
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
                        uint declaration_token, uint incoming_register,
                        bool stack_parameter)
{
    // Incoming stack arguments must not occupy a still-live ABI input
    // register while the prologue materializes register arguments.
    uint location = stack_parameter || semantic_place_storage_by_token[declaration_token].x != 0u
        ? X86_LOCATION_INVALID :
        register_location(function_id, ordinal, type_id,
            declaration_token, incoming_register);
    if (location != X86_LOCATION_INVALID) return location;
    // Stack declaration homes use stable source ordinals, keeping allocation
    // constant-time and parallel. Dead locals are filtered before this point;
    // live declarations may still leave holes for earlier register-resident
    // declarations.
    uint slot = x86_stack_slot_count_by_function[function_id] +
        x86_declaration_slot_offset(ordinal);
    uint ignored;
    InterlockedMax(x86_frame_slot_count_by_function[function_id],
        slot + x86_declaration_slot_offset(1u), ignored);
    return slot;
}

bool local_needs_home(uint declaration_token)
{
    if (semantic_place_storage_by_token[declaration_token].x != 0u) return true;
    X86DeclarationAnalysis analysis =
        x86_decl_analysis_by_token[declaration_token];
    uint definition_live = 0u;
    if (analysis.definition != X86_DECLARATION_MULTIPLE_DEFINITIONS &&
        analysis.definition != X86_LOCATION_INVALID)
        definition_live = x86_live_by_semantic[analysis.definition];
    return x86_declaration_needs_home(analysis, definition_live);
}

bool function_has_pair_parameter(SemanticLirFunction function)
{
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
        if (x86_abi_param_width(
                semantic_lir_params[function.param_start + ordinal]) > 1u)
            return true;
    return false;
}

uint local_payload_words(SemanticLirFunction function)
{
    if (function.local_count == 0u) return 0u;
    uint last = function.local_start + function.local_count - 1u;
    return x86_place_prefix_by_local[last] + x86_place_words_by_local[last] -
        x86_place_prefix_by_local[function.local_start];
}

uint payload_base(uint function_id, SemanticLirFunction function)
{
    return x86_stack_slot_count_by_function[function_id] +
        x86_declaration_slot_count(function.param_count, function.local_count);
}

void publish_place(uint token, uint slot)
{
    uint4 storage = semantic_place_storage_by_token[token];
    if (storage.x != 0u)
    {
        // All homes use at least native-word alignment, and machine frame
        // displacements must fit signed 32 bits. Invalid geometry is retained
        // as an invalid place and rejected by target validation.
        bool valid = storage.x <= 3u && storage.z != 0u && storage.z <= 8u &&
            (storage.z & (storage.z - 1u)) == 0u &&
            (storage.x == 3u || (storage.y != 0u && storage.y <= 3u)) &&
            slot < 0x0fffffffu && max(storage.y, 1u) <= 0x0fffffffu - slot;
        x86_place_storage_by_token[token] = uint4(valid ? slot : X86_LOCATION_INVALID,
            storage.y, storage.x, 0u);
    }
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
            bool pair_parameters = function_has_pair_parameter(function);
            uint copied_parameters = x86_parameter_storage_total(function, semantic_lir_params);
            uint own_words = x86_parameter_storage_words(row, param.declaration_id);
            uint copy_offset = 0u;
            if (own_words != 0u)
            {
                for (uint prior = 0u; prior < param.ordinal; prior++)
                    copy_offset += x86_parameter_storage_words(function.param_start + prior,
                        semantic_lir_params[function.param_start + prior].declaration_id);
                uint base = payload_base(param.function_id, function) + local_payload_words(function);
                uint ignored;
                InterlockedMax(x86_frame_slot_count_by_function[param.function_id],
                    base + copy_offset + own_words, ignored);
            }
            uint abi_ordinal = function.result_word_count > 2u ? 1u : 0u;
            for (uint prior = 0u; prior < param.ordinal; prior += 1u)
                abi_ordinal += x86_abi_param_width(
                    semantic_lir_params[function.param_start + prior]);
            x86_decl_location_by_token[param.declaration_id] =
                assign_declaration(param.function_id, param.ordinal,
                    param.type_id, param.declaration_id,
                    abi_ordinal < 6u ? x86_abi_argument_register(abi_ordinal) : X86_LOCATION_INVALID,
                    // A hidden return pointer shifts the incoming register
                    // sequence. Keep those parameters in stack homes until
                    // allocation supports a parallel prologue move schedule.
                    abi_ordinal >= 6u || function.result_word_count > 2u ||
                    // Parameter copies use RSI/RDI/RCX after every incoming
                    // component is saved. Keep their parameter homes stable.
                    pair_parameters || copied_parameters != 0u);
            uint home = semantic_place_storage_by_token[param.declaration_id].x == 3u
                ? payload_base(param.function_id, function) +
                    local_payload_words(function) + copy_offset
                : x86_decl_location_by_token[param.declaration_id];
            publish_place(param.declaration_id, home);
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
                    X86_LOCATION_INVALID, false);
            uint4 storage = semantic_place_storage_by_token[local.declaration_id];
            uint home = x86_decl_location_by_token[local.declaration_id];
            if (storage.x == 3u)
            {
                home = payload_base(local.function_id, semantic_function) +
                    x86_place_prefix_by_local[row] -
                    x86_place_prefix_by_local[semantic_function.local_start];
                uint ignored;
                // Parameter invocations independently reserve their later
                // copy region; this local only owns its prefix-scanned home.
                InterlockedMax(x86_frame_slot_count_by_function[local.function_id],
                    home + max(storage.y, 1u), ignored);
            }
            publish_place(local.declaration_id, home);
        }
    }
}
