import codegen.lir.x86.common;
import codegen.lir.x86.location_common;
import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint call_arg_capacity;
    uint aggregate_capacity;
    uint function_capacity;
    uint token_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> x86_function_start;
StructuredBuffer<uint> x86_function_end;
StructuredBuffer<uint> x86_live_by_semantic;
StructuredBuffer<uint> x86_location_by_semantic;
StructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
StructuredBuffer<X86DeclarationAnalysis> x86_decl_analysis_by_token;
StructuredBuffer<uint> x86_decl_location_by_token;
StructuredBuffer<uint> x86_frame_slot_count_by_function;
StructuredBuffer<uint> x86_saved_gpr_mask_by_function;
StructuredBuffer<uint> x86_direct_call_count_by_function;
RWStructuredBuffer<X86InlineInfo> x86_inline_info_by_function;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint MAX_SCHEDULE_ROWS = 256u;
static const uint MAX_TARGET_ROWS = 64u;

bool scalar_gpr_type(uint type_id)
{
    return type_id == 1u || type_id == 2u || type_id == 3u ||
        type_id == 4u || type_id == 6u || type_id == 8u;
}

bool caller_saved_register(uint location)
{
    if (!x86_location_is_register(location)) return false;
    uint physical = x86_location_payload(location);
    return physical == 0u || physical == 1u || physical == 2u ||
        physical == 6u || physical == 7u ||
        (physical >= 8u && physical <= 11u);
}

uint value_location(uint row, uint total)
{
    if (row >= total) return INVALID;
    uint replacement = x86_value_by_semantic[row].replacement;
    if (replacement < total) row = replacement;
    OptIrNodeCore core = opt_ir_core[row];
    uint allocated = x86_location_by_semantic[row];
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET)
    {
        uint declaration = opt_ir_operands[row].a;
        if (declaration < gParams.token_capacity)
        {
            uint declaration_location = x86_decl_location_by_token[declaration];
            bool parameter_read =
                x86_decl_analysis_by_token[declaration].definition == INVALID;
            bool explicit_alias =
                x86_live_by_semantic[row] == X86_SEMANTIC_COALESCED_ALIAS;
            if (declaration_location != INVALID &&
                (parameter_read || explicit_alias))
                return declaration_location;
        }
    }
    if ((allocated & X86_LOCATION_DECLARATION) != 0u)
    {
        uint declaration = allocated & X86_LOCATION_PAYLOAD_MASK;
        return declaration < gParams.token_capacity
            ? x86_decl_location_by_token[declaration] : INVALID;
    }
    return allocated;
}

bool inline_value_op(uint op)
{
    return op == SEMANTIC_LIR_OP_CONST_I32 ||
        op == SEMANTIC_LIR_OP_VALUE_GET ||
        op == SEMANTIC_LIR_OP_VALUE_SET ||
        (op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_CONVERT) ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND ||
        op == SEMANTIC_LIR_OP_LOGICAL_OR;
}

bool inline_control_op(uint op)
{
    return op == SEMANTIC_LIR_OP_BLOCK_BEGIN ||
        op == SEMANTIC_LIR_OP_IF_BEGIN ||
        op == SEMANTIC_LIR_OP_ELSE ||
        op == SEMANTIC_LIR_OP_CONTROL_END ||
        op == SEMANTIC_LIR_OP_BRANCH ||
        op == SEMANTIC_LIR_OP_BRANCH_IF;
}

bool row_produces_value(uint op)
{
    return op == SEMANTIC_LIR_OP_CONST_I32 ||
        op == SEMANTIC_LIR_OP_VALUE_GET ||
        (op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_CONVERT) ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND ||
        op == SEMANTIC_LIR_OP_LOGICAL_OR;
}

X86InlineInfo rejected_info()
{
    X86InlineInfo info;
    info.return_value = INVALID;
    info.body_row_count = 0u;
    info.schedule_start = INVALID;
    info.schedule_end = INVALID;
    return info;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint function_total = min(gParams.function_capacity,
        semantic_lir_function_total[0u]);
    if (function_id >= gParams.function_capacity) return;
    X86InlineInfo info = rejected_info();
    if (function_id >= function_total ||
        x86_direct_call_count_by_function[function_id] != 1u)
    {
        x86_inline_info_by_function[function_id] = info;
        return;
    }

    SemanticLirFunction function = semantic_lir_functions[function_id];
    if ((function.flags & (SEMANTIC_FUNCTION_FLAG_ENTRYPOINT |
                           SEMANTIC_FUNCTION_FLAG_EXTERN)) != 0u ||
        (gParams.reserved2 != 0u && function.symbol_local_index != INVALID) ||
        function.result_word_count != 0u ||
        !scalar_gpr_type(function.result_type) ||
        function.param_count > 6u ||
        x86_frame_slot_count_by_function[function_id] != 0u ||
        x86_saved_gpr_mask_by_function[function_id] != 0u)
    {
        x86_inline_info_by_function[function_id] = info;
        return;
    }

    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
    {
        SemanticLirParam param =
            semantic_lir_params[function.param_start + ordinal];
        uint abi_ordinal = x86_parameter_abi_ordinal(function, ordinal);
        uint expected_location = X86_LOCATION_REGISTER |
            x86_abi_argument_register(abi_ordinal);
        if (!scalar_gpr_type(param.type_id) ||
            param.declaration_id >= gParams.token_capacity ||
            abi_ordinal >= 6u ||
            x86_decl_location_by_token[param.declaration_id] !=
                expected_location)
        {
            x86_inline_info_by_function[function_id] = info;
            return;
        }
    }

    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    uint start = x86_function_start[function_id];
    uint end = min(x86_function_end[function_id], total);
    if (start >= end || end - start > MAX_SCHEDULE_ROWS)
    {
        x86_inline_info_by_function[function_id] = info;
        return;
    }

    uint return_value = INVALID;
    uint return_count = 0u;
    uint body_rows = 0u;
    for (uint position = start; position < end; position += 1u)
    {
        uint row = semantic_schedule_order[position];
        if (row >= total || x86_live_by_semantic[row] == 0u) continue;
        OptIrNodeCore core = opt_ir_core[row];
        uint op = opt_ir_op(core);
        if (op == SEMANTIC_LIR_OP_NOP)
            continue;
        if (op == SEMANTIC_LIR_OP_RETURN)
        {
            return_count += 1u;
            return_value = opt_ir_operands[row].a;
            continue;
        }
        bool select_store =
            x86_live_by_semantic[row] == X86_SEMANTIC_SELECT;
        bool scalar_local_store = op == SEMANTIC_LIR_OP_STORE &&
            (core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                           SEMANTIC_LIR_FLAG_FIELD)) == 0u &&
            scalar_gpr_type(core.type_id);
        bool declaration_write = op == SEMANTIC_LIR_OP_VALUE_SET ||
            scalar_local_store;
        uint declaration = opt_ir_operands[row].a;
        if ((!select_store && !inline_value_op(op) && !inline_control_op(op) &&
             !scalar_local_store) ||
            (select_store && op != SEMANTIC_LIR_OP_CONTROL_END) ||
            x86_lir_count(core, opt_ir_operands[row]) != 1u ||
            (row_produces_value(op) &&
             !caller_saved_register(value_location(row, total))) ||
            (declaration_write &&
             (declaration >= gParams.token_capacity ||
              !caller_saved_register(
                  x86_decl_location_by_token[declaration]))))
        {
            x86_inline_info_by_function[function_id] = info;
            return;
        }
        body_rows += 1u;
        if (body_rows > MAX_TARGET_ROWS)
        {
            x86_inline_info_by_function[function_id] = info;
            return;
        }
    }
    if (return_count != 1u || return_value >= total)
    {
        x86_inline_info_by_function[function_id] = info;
        return;
    }
    if (!caller_saved_register(value_location(return_value, total)))
    {
        x86_inline_info_by_function[function_id] = info;
        return;
    }

    info.return_value = return_value;
    info.body_row_count = body_rows;
    info.schedule_start = start;
    info.schedule_end = end;
    x86_inline_info_by_function[function_id] = info;
}
