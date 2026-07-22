import codegen.lir.wasm.common;
import codegen.lir.wasm.host_abi;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint target_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<SemanticLirSchedule> semantic_lir_schedule;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
StructuredBuffer<uint> semantic_lir_string_total;
StructuredBuffer<SemanticLirString> semantic_lir_strings;
StructuredBuffer<uint> target_lir_offset;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<uint> semantic_to_target_start;
RWStructuredBuffer<WasmLirInstruction> target_lir_core;
RWStructuredBuffer<WasmLirOperands> target_lir_operands;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WASM_SYNTHETIC_I32_TEMP = 0xfffffffeu;
static const uint WASM_SYNTHETIC_F32_TEMP = 0xfffffffdu;

uint scheduled_owner(uint target_row, uint semantic_count)
{
    uint lo = 0u;
    uint hi = semantic_count;
    while (lo + 1u < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (target_lir_offset[mid] <= target_row) lo = mid;
        else hi = mid;
    }
    return lo;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint target_total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= target_total) return;
    uint semantic_count = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (semantic_count == 0u) return;

    uint scheduled_row = scheduled_owner(row, semantic_count);
    uint semantic_row = semantic_schedule_order[scheduled_row];
    uint target_start = target_lir_offset[scheduled_row];
    uint local_row = row - target_start;
    semantic_to_target_start[semantic_row] = target_start;
    SemanticLirCore core = semantic_lir_core[semantic_row];
    SemanticLirOperands operands = semantic_lir_operands[semantic_row];
    bool host_operation = core.op == SEMANTIC_LIR_OP_CALL_HOST;
    bool inline_host_operation = host_operation && operands.a == HOST_SERVICE_I32_TO_F32;
    uint host_import = host_operation && !inline_host_operation
        ? wasm_host_import_for_service(operands.a) : WASM_HOST_INVALID;
    bool imported_host_operation = host_import != WASM_HOST_INVALID;
    bool supported_intrinsic = core.op == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
        operands.a == 1u;
    uint flags = wasm_lir_supported(core) || inline_host_operation ||
        imported_host_operation || supported_intrinsic
        ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
    flags |= semantic_lir_schedule[semantic_row].function_id == WASM_LIR_INVALID
        ? 0u : (1u << 8u);

    uint opcode = wasm_scalar_opcode(core, operands);
    if (inline_host_operation) opcode = WASM_LIR_OP_F32_CONVERT_I32_S;
    else if (imported_host_operation) opcode = WASM_LIR_OP_CALL;
    uint immediate = 0u;
    if (core.op == SEMANTIC_LIR_OP_CONST_STRING)
    {
        uint string_count = semantic_lir_string_total[0u];
        if (operands.a < string_count)
        {
            SemanticLirString string = semantic_lir_strings[operands.a];
            opcode = WASM_LIR_OP_I32_CONST;
            immediate = local_row == 0u ? string.data_offset : string.decoded_len;
        }
        else flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    }
    else if (core.op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
    {
        uint element_rows = operands.b * 6u;
        if (local_row < element_rows)
        {
            uint element = operands.b - 1u - local_row / 6u;
            uint phase = local_row % 6u;
            SemanticLirAggregateElement aggregate_element =
                semantic_lir_aggregate_elements[operands.a + element];
            bool element_is_f32 = aggregate_element.value_instruction < semantic_count &&
                semantic_lir_core[aggregate_element.value_instruction].type_id == TY_FLOAT;
            uint temporary = element_is_f32
                ? WASM_SYNTHETIC_F32_TEMP : WASM_SYNTHETIC_I32_TEMP;
            opcode = phase == 0u ? WASM_LIR_OP_LOCAL_SET
                : phase == 1u ? WASM_LIR_OP_GLOBAL_GET
                : phase == 2u ? WASM_LIR_OP_I32_CONST
                : phase == 3u ? WASM_LIR_OP_I32_ADD
                : phase == 4u ? WASM_LIR_OP_LOCAL_GET
                : element_is_f32 ? WASM_LIR_OP_F32_STORE : WASM_LIR_OP_I32_STORE;
            immediate = phase == 0u || phase == 4u ? temporary
                : phase == 2u ? aggregate_element.ordinal * 4u : 0u;
        }
        else
        {
            uint phase = local_row - element_rows;
            opcode = phase == 0u || phase == 1u ? WASM_LIR_OP_GLOBAL_GET
                : phase == 2u ? WASM_LIR_OP_I32_CONST
                : phase == 3u ? WASM_LIR_OP_I32_ADD
                : WASM_LIR_OP_GLOBAL_SET;
            immediate = phase == 2u ? operands.b * 4u : 0u;
        }
    }
    else if (core.op == SEMANTIC_LIR_OP_LOAD &&
             (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
    {
        opcode = local_row == 0u ? WASM_LIR_OP_I32_CONST
            : local_row == 1u ? WASM_LIR_OP_I32_MUL
            : local_row == 2u ? WASM_LIR_OP_I32_ADD
            : core.type_id == TY_FLOAT ? WASM_LIR_OP_F32_LOAD : WASM_LIR_OP_I32_LOAD;
        immediate = local_row == 0u ? 4u : 0u;
    }
    else if (core.op == SEMANTIC_LIR_OP_LOAD &&
             (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
    {
        opcode = local_row == 0u ? WASM_LIR_OP_I32_CONST
            : local_row == 1u ? WASM_LIR_OP_I32_CONST
            : local_row == 2u ? WASM_LIR_OP_I32_MUL
            : local_row == 3u ? WASM_LIR_OP_I32_ADD
            : core.type_id == TY_FLOAT ? WASM_LIR_OP_F32_LOAD : WASM_LIR_OP_I32_LOAD;
        immediate = local_row == 0u ? operands.b
            : local_row == 1u ? 4u : 0u;
    }
    else if (core.op == SEMANTIC_LIR_OP_NEGATE && core.type_id != TY_FLOAT)
    {
        opcode = local_row == 0u ? WASM_LIR_OP_I32_CONST : WASM_LIR_OP_I32_MUL;
        if (local_row == 0u)
        {
            operands.result = target_start;
            operands.a = 0xffffffffu;
            operands.b = WASM_LIR_INVALID;
            operands.c = WASM_LIR_INVALID;
            immediate = 0xffffffffu;
        }
    }
    else if (core.op == SEMANTIC_LIR_OP_CALL_INTRINSIC && operands.a == 1u)
    {
        opcode = local_row == 0u
            ? WASM_LIR_OP_I64_EXTEND_I32_S : WASM_LIR_OP_CALL;
        immediate = 0u;
    }
    else if (core.op == SEMANTIC_LIR_OP_BRANCH_IF &&
             (core.flags & SEMANTIC_LIR_FLAG_BRANCH_FALSE) != 0u)
    {
        opcode = local_row == 0u ? WASM_LIR_OP_I32_EQZ : WASM_LIR_OP_BRANCH_IF;
        immediate = local_row == 0u ? 0u : operands.b;
    }
    else if (imported_host_operation)
        immediate = host_import;
    else if (core.op == SEMANTIC_LIR_OP_CONST_I32 || core.op == SEMANTIC_LIR_OP_CONST_F32 ||
             core.op == SEMANTIC_LIR_OP_VALUE_GET || core.op == SEMANTIC_LIR_OP_VALUE_SET ||
             core.op == SEMANTIC_LIR_OP_STORE ||
             core.op == SEMANTIC_LIR_OP_CALL || core.op == SEMANTIC_LIR_OP_CALL_HOST ||
             core.op == SEMANTIC_LIR_OP_BRANCH || core.op == SEMANTIC_LIR_OP_BRANCH_IF)
        immediate = core.op == SEMANTIC_LIR_OP_CALL
            ? WASM_HOST_IMPORT_COUNT + operands.a
            : (core.op == SEMANTIC_LIR_OP_BRANCH ||
                     core.op == SEMANTIC_LIR_OP_BRANCH_IF) &&
                    (core.flags & SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID) != 0u
            ? operands.b : operands.a;

    WasmLirInstruction inst;
    inst.opcode = opcode;
    inst.immediate = immediate;
    inst.semantic_instruction = semantic_row;
    inst.flags = flags;
    target_lir_core[row] = inst;
    WasmLirOperands target_operands;
    // Preserve both kinds of relocatable target. Local calls retain the
    // semantic function id; symbolic calls retain their exact declaration
    // identity. The object projector therefore never has to recover a target
    // from an already encoded immediate or from source/HIR rows.
    target_operands.a = core.op == SEMANTIC_LIR_OP_CALL_SYMBOL ||
        core.op == SEMANTIC_LIR_OP_CALL ? operands.a : 0u;
    target_operands.b = core.op == SEMANTIC_LIR_OP_CALL_SYMBOL ? operands.b : 0u;
    target_operands.c = core.op == SEMANTIC_LIR_OP_CALL_SYMBOL ? operands.c : 0u;
    target_operands.metadata = core.type_id;
    target_lir_operands[row] = target_operands;
}
