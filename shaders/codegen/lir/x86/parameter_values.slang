// Private checked parameter storage. The public native argument convention
// passes aggregate addresses and (data, length, stride) array views.
import codegen.lowering_ir;
import codegen.lir.x86.location_common;

StructuredBuffer<uint> semantic_param_value_layout;
StructuredBuffer<uint4> semantic_place_storage_by_token;

uint x86_parameter_value_words(uint row)
{
    return semantic_param_value_layout[row * 2u];
}

bool x86_parameter_is_packed(uint row)
{
    return semantic_param_value_layout[row * 2u + 1u] == 2u;
}

bool x86_parameter_home_is_packed(uint row, uint declaration)
{
    return x86_parameter_is_packed(row) &&
        semantic_place_storage_by_token[declaration].x != 3u;
}

uint x86_parameter_storage_words(uint row, uint declaration)
{
    uint words = x86_parameter_value_words(row);
    if (semantic_place_storage_by_token[declaration].x == 3u)
        return max(words, 1u);
    return x86_parameter_is_packed(row) ? words / 2u + words % 2u : words;
}

uint x86_parameter_storage_total(SemanticLirFunction function,
    StructuredBuffer<SemanticLirParam> parameters)
{
    uint total = 0u;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal++)
        total += x86_parameter_storage_words(function.param_start + ordinal,
            parameters[function.param_start + ordinal].declaration_id);
    return total;
}

uint x86_parameter_copy_bytes(TargetLirFunction target,
    SemanticLirFunction function,
    StructuredBuffer<SemanticLirParam> parameters,
    StructuredBuffer<uint> declaration_locations)
{
    uint total = x86_parameter_storage_total(function, parameters);
    uint slot = (target.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK) - total;
    uint bytes = 0u;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal++)
    {
        uint row = function.param_start + ordinal;
        uint words = x86_parameter_value_words(row);
        uint declaration = parameters[row].declaration_id;
        uint storage = x86_parameter_storage_words(row, declaration);
        if (storage == 0u) continue;
        bool packed = x86_parameter_home_is_packed(row, declaration);
        uint base_slot = slot + (packed ? storage - 1u : 0u);
        uint home = declaration_locations[parameters[row].declaration_id];
        if (words == 0u)
        {
            bytes += x86_stack64_operand_bytes(base_slot) +
                x86_stack64_operand_bytes(home);
            slot += storage;
            continue;
        }
        if (x86_parameter_is_packed(row) && !packed)
        {
            // Convert the unchanged packed by-value argument ABI to the
            // canonical reference home: mov eax,[rsi+i*4]; mov [rdi-i*8],rax.
            bytes += 2u * x86_stack64_operand_bytes(home) +
                x86_stack64_operand_bytes(base_slot) + words * 13u;
            slot += storage;
            continue;
        }
        // Source load, destination LEA, home update, optional native-word
        // address adjustment, immediate count, and REP MOVS.
        bytes += 2u * x86_stack64_operand_bytes(home) +
            x86_stack64_operand_bytes(base_slot) +
            (!packed && words > 1u ? 14u : 0u) + 5u + (packed ? 2u : 3u);
        slot += storage;
    }
    return bytes;
}
