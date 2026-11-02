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
// allocation_words scans the same number of locals (LOCAL_SLOT_SCAN_LIMIT).
static const uint LOCAL_SLOT_SCAN_LIMIT = 256u;

bool valid_function(uint function_id)
{
    return function_id < min(gParams.function_capacity,
        semantic_lir_function_total[0u]);
}

// 64-bit integers (i64 9, u64 10, isize 16, usize 17) share the pointer's
// full-width GPR moves, and 8- and 16-bit integers (i8 11, i16 12, u8 13,
// u16 14) are normalized 32-bit values; every such body moves through
// RAX/RCX with the width taken from its metadata, so a register home needs
// no other form.
bool scalar_gpr_type(uint type_id)
{
    return type_id == 1u || type_id == 2u || type_id == 3u ||
        type_id == 4u || type_id == 6u || (type_id >= 8u && type_id <= 14u) ||
        type_id == 16u || type_id == 17u;
}

uint register_location(uint function_id, uint ordinal, uint type_id,
                       uint declaration_token, uint incoming_register)
{
    if (!scalar_gpr_type(type_id) || ordinal >= 6u)
        return X86_LOCATION_INVALID;
    X86FunctionRegisterAnalysis register_analysis =
        x86_register_analysis_by_function[function_id];
    uint last_read = x86_decl_analysis_by_token[declaration_token].last_read;
    // allocation_words lets temporaries use R8-R11 throughout a function with
    // calls, so a declaration there that is written but never read (and so
    // would pass the caller-register test below) keeps a stack home.
    if (register_analysis.first_call != 0u && last_read == 0u)
        return X86_LOCATION_INVALID;
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

// `register_ordinal` picks the declaration's register in the RDI, RSI, R10,
// R11, R8, R9 (call-free) or RBX, R12-R14 sequence; INVALID means none.
// `ordinal` keeps its stack home distinct.
uint assign_declaration(uint function_id, uint ordinal, uint register_ordinal,
                        uint type_id, uint declaration_token,
                        uint incoming_register, bool stack_parameter)
{
    // Incoming stack arguments must not occupy a still-live ABI input
    // register while the prologue materializes register arguments.
    uint location = stack_parameter || semantic_place_storage_by_token[declaration_token].x != 0u
        ? X86_LOCATION_INVALID :
        register_location(function_id, register_ordinal, type_id,
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

// A hidden result pointer or a (data, length, stride) parameter shifts the
// incoming ABI registers away from the parameter ordinals.
bool shifted_parameters(SemanticLirFunction function)
{
    return function.result_word_count > 2u || function_has_pair_parameter(function);
}

// The register slot of the parameter at `ordinal`, or INVALID. Without
// shifted parameters a register-typed parameter keeps its ordinal. With them,
// the first two register-typed parameters take slots 2 and 3 (R10/R11, or
// R13/R14 across calls): no incoming argument arrives there, so the
// right-to-left prologue moves cannot overwrite an argument not yet saved.
// A cached slice header holds slots 0-2 (RBX, R12, R13) across calls, so
// there only slot 3 is left. allocation_words reserves the same slots
// (declaration_register_mask).
// With calls every declaration register is callee-saved (register_location),
// so no incoming argument register can be overwritten by a parameter's home:
// register-typed parameters a register may hold (assign_declaration) and
// register-typed locals share the free slots, the most-read (by loop-weighted
// reads, then parameters before locals, then by order) first. `index` counts
// parameters, then locals. allocation_words' declaration_register_mask holds
// as many slots as there are register-typed declarations.
bool ranked_declaration(SemanticLirFunction function, uint index, out uint weight)
{
    weight = 0u;
    bool parameter = index < function.param_count;
    uint type_id;
    uint declaration;
    if (parameter)
    {
        SemanticLirParam param = semantic_lir_params[function.param_start + index];
        if (!shifted_parameters(function) && index >= 6u) return false;
        type_id = param.type_id;
        declaration = param.declaration_id;
    }
    else
    {
        SemanticLirLocal local = semantic_lir_locals[function.local_start + index - function.param_count];
        type_id = local.type_id;
        declaration = local.declaration_id;
    }
    if (!scalar_gpr_type(type_id) || declaration >= gParams.token_capacity ||
        semantic_place_storage_by_token[declaration].x != 0u)
        return false;
    weight = x86_decl_analysis_by_token[declaration].read_count;
    return true;
}

uint ranked_slot(SemanticLirFunction function, uint index, bool header)
{
    uint params = min(function.param_count, LOCAL_SLOT_SCAN_LIMIT);
    uint locals = min(function.local_count, LOCAL_SLOT_SCAN_LIMIT);
    if (function.param_start + function.param_count > semantic_lir_param_total[0u] ||
        function.local_start + function.local_count >
            min(gParams.local_capacity, semantic_lir_local_total[0u]))
        return X86_LOCATION_INVALID;
    // Copied parameters keep every parameter in its stack home.
    bool copied = x86_parameter_storage_total(function, semantic_lir_params) != 0u;
    bool parameter = index < function.param_count;
    uint weight;
    if ((parameter ? index >= params || copied : index - function.param_count >= locals) ||
        !ranked_declaration(function, index, weight))
        return X86_LOCATION_INVALID;
    uint rank = 0u;
    for (uint other = copied ? params : 0u; other < params + locals; other += 1u)
    {
        uint other_index = other < params ? other : function.param_count + other - params;
        uint other_weight;
        if (other_index != index && ranked_declaration(function, other_index, other_weight) &&
            (other_weight > weight || (other_weight == weight && other_index < index)))
            rank += 1u;
    }
    uint slots = header ? X86_HEADER_CALL_SLOTS : 0u;
    for (uint cursor = 0u; cursor < 4u; cursor += 1u)
    {
        if ((slots & (1u << cursor)) != 0u) continue;
        if (rank == 0u) return cursor;
        rank -= 1u;
    }
    return X86_LOCATION_INVALID;
}

uint parameter_register_slot(SemanticLirFunction function, uint ordinal, bool has_call,
                             bool header)
{
    if (has_call) return ranked_slot(function, ordinal, header);
    uint limit = 6u;
    if (function.param_start + function.param_count > semantic_lir_param_total[0u] ||
        ordinal >= function.param_count ||
        !scalar_gpr_type(semantic_lir_params[function.param_start + ordinal].type_id))
        return X86_LOCATION_INVALID;
    if (!shifted_parameters(function))
        return ordinal < limit ? ordinal : X86_LOCATION_INVALID;
    uint slot = 2u;
    for (uint prior = 0u; prior < ordinal; prior += 1u)
        if (scalar_gpr_type(semantic_lir_params[function.param_start + prior].type_id))
            slot += 1u;
    return slot < 4u ? slot : X86_LOCATION_INVALID;
}

// A local's claim on a register: its reads, each weighted by loop depth
// (allocation_words' walk_function).
uint local_read_weight(SemanticLirFunction function, uint index)
{
    uint declaration = semantic_lir_locals[function.local_start + index].declaration_id;
    return declaration < gParams.token_capacity
        ? x86_decl_analysis_by_token[declaration].read_count : 0u;
}

// The register slot of the function's local at `index`, or INVALID.
// Register-typed locals take the slots parameters leave free, the most-read
// (by loop-weighted reads, then by order) first, so a slice parameter or a
// non-register local does not use up a register. Whichever locals get them,
// the slots taken are the first free ones (allocation_words'
// declaration_register_mask).
uint local_register_slot(SemanticLirFunction function, uint index, bool has_call,
                         bool header)
{
    if (has_call) return ranked_slot(function, function.param_count + index, header);
    uint limit = 6u;
    uint param_total = semantic_lir_param_total[0u];
    uint local_total = min(gParams.local_capacity, semantic_lir_local_total[0u]);
    if (index >= LOCAL_SLOT_SCAN_LIMIT ||
        function.param_start + function.param_count > param_total ||
        function.local_start + function.local_count > local_total)
        return X86_LOCATION_INVALID;
    uint slots = 0u;
    for (uint ordinal = 0u; ordinal < min(function.param_count, LOCAL_SLOT_SCAN_LIMIT); ordinal += 1u)
    {
        uint slot = parameter_register_slot(function, ordinal, false, header);
        if (slot != X86_LOCATION_INVALID) slots |= 1u << slot;
    }
    if (!scalar_gpr_type(semantic_lir_locals[function.local_start + index].type_id))
        return X86_LOCATION_INVALID;
    uint weight = local_read_weight(function, index);
    uint rank = 0u;
    for (uint other = 0u; other < min(function.local_count, LOCAL_SLOT_SCAN_LIMIT); other += 1u)
    {
        if (other == index ||
            !scalar_gpr_type(semantic_lir_locals[function.local_start + other].type_id))
            continue;
        uint other_weight = local_read_weight(function, other);
        if (other_weight > weight || (other_weight == weight && other < index)) rank += 1u;
    }
    for (uint cursor = 0u; cursor < limit; cursor += 1u)
    {
        if ((slots & (1u << cursor)) != 0u) continue;
        if (rank == 0u) return cursor;
        rank -= 1u;
    }
    return X86_LOCATION_INVALID;
}

// allocation_words' choice (header_parameter): the first slice parameter
// whose header may stay in registers.
uint header_parameter(SemanticLirFunction function)
{
    if (function.param_start + function.param_count > semantic_lir_param_total[0u])
        return X86_LOCATION_INVALID;
    for (uint ordinal = 0u; ordinal < min(function.param_count, LOCAL_SLOT_SCAN_LIMIT); ordinal += 1u)
    {
        SemanticLirParam param = semantic_lir_params[function.param_start + ordinal];
        uint declaration = param.declaration_id;
        if (declaration < gParams.token_capacity &&
            x86_header_parameter(param, x86_decl_analysis_by_token[declaration],
                semantic_place_storage_by_token[declaration]))
            return function.param_start + ordinal;
    }
    return X86_LOCATION_INVALID;
}

bool header_cached(uint function_id)
{
    return (x86_saved_gpr_mask_by_function[function_id] & X86_HEADER_CACHE_FLAG) != 0u;
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
            bool shifted = shifted_parameters(function);
            bool has_call =
                x86_register_analysis_by_function[param.function_id].first_call != 0u;
            uint register_slot = parameter_register_slot(function, param.ordinal, has_call,
                header_cached(param.function_id));
            x86_decl_location_by_token[param.declaration_id] =
                assign_declaration(param.function_id, param.ordinal, register_slot,
                    param.type_id, param.declaration_id,
                    !shifted && abi_ordinal < 6u ? x86_abi_argument_register(abi_ordinal)
                        : X86_LOCATION_INVALID,
                    // Unshifted stack arguments stay in their stack homes;
                    // shifted ones may take slots 2 and 3, which no incoming
                    // register uses. Parameter copies use RSI/RDI/RCX after
                    // every incoming component is saved; keep those homes
                    // stable.
                    register_slot == X86_LOCATION_INVALID ||
                    (!shifted && abi_ordinal >= 6u) ||
                    copied_parameters != 0u);
            uint home = semantic_place_storage_by_token[param.declaration_id].x == 3u
                ? payload_base(param.function_id, function) +
                    local_payload_words(function) + copy_offset
                : x86_decl_location_by_token[param.declaration_id];
            publish_place(param.declaration_id, home);
            uint header_home = x86_decl_location_by_token[param.declaration_id];
            if (header_cached(param.function_id) && header_parameter(function) == row &&
                header_home < X86_HEADER_HOME_LIMIT)
            {
                uint ignored;
                InterlockedOr(x86_saved_gpr_mask_by_function[param.function_id],
                    (header_home + 1u) << X86_HEADER_HOME_SHIFT, ignored);
            }
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
            bool has_call =
                x86_register_analysis_by_function[local.function_id].first_call != 0u;
            x86_decl_location_by_token[local.declaration_id] =
                assign_declaration(local.function_id, ordinal,
                    local_register_slot(semantic_function, local.ordinal, has_call,
                        header_cached(local.function_id)),
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
