import codegen.lir.wasm.common;
import codegen.lir.wasm.host_abi;
import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;
import hir_records;
import primitive_types;

struct Params { uint semantic_capacity; uint target_capacity; uint target_start; uint page_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<uint> semantic_lir_layout_word_offset;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
StructuredBuffer<uint4> semantic_place_storage_by_token;
StructuredBuffer<uint> semantic_place_address_by_token;
StructuredBuffer<uint> wasm_frame_slots;
StructuredBuffer<uint> wasm_frame_bounds;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> semantic_param_value_layout;
StructuredBuffer<uint> semantic_lir_string_total;
StructuredBuffer<SemanticLirString> semantic_lir_strings;
StructuredBuffer<uint> target_lir_offset;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<uint> semantic_to_target_start;
RWStructuredBuffer<WasmLirInstruction> target_lir_core;
RWStructuredBuffer<WasmLirOperands> target_lir_operands;

static const uint DISPATCH_X_STRIDE = 16776960u;

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
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    uint target_total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= target_total) return;
    uint semantic_count = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (semantic_count == 0u) return;

    uint scheduled_row = scheduled_owner(row, semantic_count);
    uint semantic_row = semantic_schedule_order[scheduled_row];
    uint target_start = target_lir_offset[scheduled_row];
    OptIrNodeCore core = opt_ir_core[semantic_row];
    OptIrNodeOperands operands = opt_ir_operands[semantic_row];

    WasmPlanRow plan = wasm_plan_row_at(scheduled_row, semantic_count, semantic_lir_functions,
        semantic_schedule_order,
        opt_ir_core, opt_ir_operands, opt_ir_source_hir, semantic_function_id_by_hir,
        compact_hir_core, semantic_lir_layout_word_offset, semantic_place_storage_by_token,
        semantic_place_address_by_token, wasm_frame_slots, wasm_frame_bounds);
    wasm_plan_rows(plan, row - target_start, semantic_lir_aggregate_elements, opt_ir_core,
        semantic_lir_params, semantic_param_value_layout);
    // Relocations address the row's first instruction after any prologue.
    semantic_to_target_start[semantic_row] = target_start + wasm_plan_body_start;
    bool legacy = wasm_plan_opcode == WASM_PLAN_LEGACY;
    // The scalar lowering's own row within its range.
    uint local_row = legacy ? wasm_plan_immediate : 0u;

    uint value_type = operands.b < semantic_count ? opt_ir_core[operands.b].type_id : core.type_id;
    uint shift_amount_opcode = wasm_shift_amount_opcode(core, value_type);
    uint previous_row = scheduled_row > 0u
        ? semantic_schedule_order[scheduled_row - 1u] : WASM_LIR_INVALID;
    OptIrNodeOperands previous_operands = opt_ir_operands[min(previous_row, semantic_row)];
    bool reload_short_circuit = previous_row < semantic_count &&
        wasm_reloads_short_circuit(core, operands, opt_ir_core[previous_row], previous_operands);
    bool host_operation = opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_HOST;
    bool inline_host_operation = host_operation && operands.a == HOST_SERVICE_I32_TO_F32;
    uint host_import = host_operation && !inline_host_operation
        ? wasm_host_import_for_service(operands.a) : WASM_HOST_INVALID;
    bool imported_host_operation = host_import != WASM_HOST_INVALID;
    bool supported_intrinsic = opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
        wasm_intrinsic_supported(operands.a);
    uint flags = wasm_lir_supported(core) || inline_host_operation ||
        imported_host_operation || supported_intrinsic
        ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
    // Host/intrinsic support cannot override an unsupported checked width.
    if (core.type_id == SCALAR_F64) flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if (wasm_plan_unsupported) flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    // An `||` negation whose operand is not the just-stored left side.
    if (wasm_short_circuit_not(core) && !reload_short_circuit)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    // Rows the semantic pass could not lower (an unknown layout, a
    // declaration type with no zero value, an unsupported iterable) are
    // rejected as on x86, never lowered from their placeholder operands.
    if ((core.flags & (SEMANTIC_LIR_FLAG_UNSUPPORTED |
                       SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE)) != 0u)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    flags |= semantic_function_id_by_hir[
        opt_ir_source_hir[semantic_row]] == WASM_LIR_INVALID
        ? 0u : (1u << 8u);

    uint opcode = wasm_plan_opcode;
    uint immediate = wasm_plan_immediate;
    if (legacy)
    {
        opcode = wasm_scalar_opcode(core, operands);
        if (inline_host_operation) opcode = WASM_LIR_OP_F32_CONVERT_I32_S;
        else if (imported_host_operation) opcode = WASM_LIR_OP_CALL;
        immediate = 0u;
    }
    bool discarded = local_row >= 1u && wasm_discarded_result_values(core,
        wasm_statement_call(compact_hir_core, opt_ir_source_hir[semantic_row])) != 0u;
    if (!legacy) {}
    else if (wasm_never_call(core) && local_row == 1u)
        opcode = WASM_LIR_OP_UNREACHABLE;
    else if (discarded)
        opcode = WASM_LIR_OP_DROP;
    else if (reload_short_circuit)
    {
        opcode = local_row == 0u ? WASM_LIR_OP_LOCAL_GET : WASM_LIR_OP_I32_EQZ;
        immediate = local_row == 0u ? previous_operands.a : 0u;
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
             operands.a == WASM_INTRINSIC_ASSERT)
    {
        // Trap when the checked condition is false.
        opcode = local_row == 0u ? WASM_LIR_OP_I32_EQZ
            : local_row == 1u ? WASM_LIR_OP_IF
            : local_row == 2u ? WASM_LIR_OP_UNREACHABLE : WASM_LIR_OP_END;
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_STRING)
    {
        uint string_count = semantic_lir_string_total[0u];
        if (operands.a < string_count)
        {
            SemanticLirString string = semantic_lir_strings[operands.a];
            opcode = WASM_LIR_OP_I32_CONST;
            immediate = local_row == 0u ? string.data_offset : string.decoded_len;
            if (local_row == 0u)
                flags |= TARGET_LIR_FLAG_DATA_RELOCATION;
        }
        else flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    }
    else if ((opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET ||
              opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET) &&
             core.type_id == TY_STRING)
    {
        opcode = opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET
            ? WASM_LIR_OP_LOCAL_GET : WASM_LIR_OP_LOCAL_SET;
        immediate = operands.a;
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_I64)
    {
        // An i32-class (pointer-sized) constant keeps its low word. A long
        // i64 constant is `zext(lo) | (hi << 32)`.
        bool wide = wasm_scalar_class(core.type_id) == WASM_CLASS_I64;
        if (!wide || wasm_const_i64_is_short(operands))
        {
            opcode = wide ? WASM_LIR_OP_I64_CONST : WASM_LIR_OP_I32_CONST;
            immediate = operands.a;
        }
        else
        {
            opcode = local_row == 0u ? WASM_LIR_OP_I64_CONST_U32
                : local_row <= 2u ? WASM_LIR_OP_I64_CONST
                : local_row == 3u ? WASM_LIR_OP_I64_SHL : WASM_LIR_OP_I64_OR;
            immediate = local_row == 0u ? operands.a
                : local_row == 1u ? operands.b : local_row == 2u ? 32u : 0u;
        }
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONVERT)
    {
        // The class change, then renormalize a narrow i32-class target.
        uint class_opcode = wasm_convert_class_opcode(core.type_id, operands.b);
        uint class_rows = wasm_convert_class_rows(core, operands);
        if (class_opcode == WASM_LIR_OP_UNREACHABLE) flags |= TARGET_LIR_FLAG_UNSUPPORTED;
        uint narrow_row = local_row - class_rows;
        bool narrow_target = wasm_scalar_class(core.type_id) == WASM_CLASS_I32;
        bool mask = narrow_target &&
            (core.type_id == SCALAR_U8 || core.type_id == SCALAR_U16);
        opcode = local_row < class_rows ? class_opcode
            : mask ? (narrow_row == 0u ? WASM_LIR_OP_I32_CONST : WASM_LIR_OP_I32_AND)
            : narrow_target && core.type_id == SCALAR_I8 ? WASM_LIR_OP_I32_EXTEND8_S
            : narrow_target && core.type_id == SCALAR_I16 ? WASM_LIR_OP_I32_EXTEND16_S
            : WASM_LIR_OP_NOP;
        immediate = local_row >= class_rows && mask && narrow_row == 0u
            ? (core.type_id == SCALAR_U8 ? 0xffu : 0xffffu) : 0u;
    }
    else if (shift_amount_opcode != WASM_LIR_OP_NOP)
    {
        // Bring the shift amount to the shifted value's class, then shift.
        if (shift_amount_opcode == WASM_LIR_OP_UNREACHABLE)
            flags |= TARGET_LIR_FLAG_UNSUPPORTED;
        if (local_row == 0u) opcode = shift_amount_opcode;
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_NEGATE && core.type_id != TY_FLOAT)
    {
        bool wide = wasm_scalar_class(core.type_id) == WASM_CLASS_I64;
        opcode = local_row == 0u
            ? (wide ? WASM_LIR_OP_I64_CONST : WASM_LIR_OP_I32_CONST)
            : (wide ? WASM_LIR_OP_I64_MUL : WASM_LIR_OP_I32_MUL);
        if (local_row == 0u) immediate = 0xffffffffu;
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_INTRINSIC && operands.a == 1u)
    {
        // The argument is the value scheduled just before; an i64 one is
        // already the import's width.
        bool wide_argument = previous_row < semantic_count &&
            wasm_row_value_class(opt_ir_core[previous_row]) == WASM_CLASS_I64;
        opcode = local_row == 0u
            ? (wide_argument ? WASM_LIR_OP_NOP : WASM_LIR_OP_I64_EXTEND_I32_S)
            : WASM_LIR_OP_CALL;
        immediate = 0u;
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH_IF &&
             (core.flags & SEMANTIC_LIR_FLAG_BRANCH_FALSE) != 0u)
    {
        // A range loop's exhaustion exit pushes the induction value again.
        uint reload = local_row == 2u
            ? wasm_exhaustion_reload(core, operands, opt_ir_core, opt_ir_operands, semantic_count)
            : WASM_LIR_INVALID;
        opcode = local_row == 0u ? WASM_LIR_OP_I32_EQZ
            : local_row == 1u ? WASM_LIR_OP_BRANCH_IF : WASM_LIR_OP_LOCAL_GET;
        immediate = local_row == 0u ? 0u : local_row == 1u ? operands.b : reload;
    }
    else if (imported_host_operation)
        immediate = host_import;
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_I32 || opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_F32 ||
             opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET || opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET ||
             opt_ir_op(core) == SEMANTIC_LIR_OP_STORE ||
             opt_ir_op(core) == SEMANTIC_LIR_OP_CALL || opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_HOST ||
             opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH || opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH_IF)
        immediate = opt_ir_op(core) == SEMANTIC_LIR_OP_CALL
            ? WASM_HOST_IMPORT_COUNT + operands.a
            : (opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH ||
                     opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH_IF) &&
                    (core.flags & SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID) != 0u
            ? operands.b : operands.a;

    WasmLirInstruction inst;
    inst.opcode = opcode;
    inst.immediate = immediate;
    inst.semantic_instruction = semantic_row;
    inst.flags = flags;
    target_lir_core[page_row] = inst;
    WasmLirOperands target_operands;
    // Preserve both kinds of relocatable target. Local calls retain the
    // semantic function id; symbolic calls retain their exact declaration
    // identity. The object projector therefore never has to recover a target
    // from an already encoded immediate or from source/HIR rows.
    bool call_row = legacy && (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ||
        opt_ir_op(core) == SEMANTIC_LIR_OP_CALL);
    target_operands.a = call_row ? operands.a : 0u;
    target_operands.b = call_row && opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ? operands.b : 0u;
    target_operands.c = call_row && opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ? operands.c : 0u;
    target_operands.metadata = core.type_id;
    if (legacy && (opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET ||
                   opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET) && core.type_id == TY_STRING)
    {
        target_operands.a = operands.a;
        // local.set consumes the top stack value. Assign a two-word string
        // in reverse component order so `(data_ptr, byte_len)` remains the
        // ordered local pair after the stores.
        target_operands.c = opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET
            ? 1u - local_row : local_row;
    }
    else if (!legacy && wasm_plan_component != WASM_LIR_INVALID)
    {
        // One component of a string parameter's local pair.
        target_operands.a = immediate;
        target_operands.c = wasm_plan_component;
        target_operands.metadata = TY_STRING;
    }
    else if (!legacy && core.type_id == TY_STRING) target_operands.metadata = 0u;
    target_lir_operands[page_row] = target_operands;
}
