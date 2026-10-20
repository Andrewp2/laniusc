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
StructuredBuffer<uint> semantic_lir_string_total;
StructuredBuffer<SemanticLirString> semantic_lir_strings;
StructuredBuffer<uint> target_lir_offset;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<uint> semantic_to_target_start;
RWStructuredBuffer<WasmLirInstruction> target_lir_core;
RWStructuredBuffer<WasmLirOperands> target_lir_operands;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint TARGET_PAGE_ROWS = 65536u;
static const uint WASM_SYNTHETIC_I32_TEMP = 0xfffffffeu;
static const uint WASM_SYNTHETIC_F32_TEMP = 0xfffffffdu;
static const uint WASM_SYNTHETIC_I32_ADDRESS_TEMP = 0xfffffffcu;

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
    uint local_row = row - target_start;
    semantic_to_target_start[semantic_row] = target_start;
    OptIrNodeCore core = opt_ir_core[semantic_row];
    OptIrNodeOperands operands = opt_ir_operands[semantic_row];
    // Inline aggregate layout: aggregate fields and elements are addresses,
    // element strides span the element's words, and aggregate stores copy.
    bool aggregate_value = wasm_inline_aggregate(core);
    uint stride = aggregate_value ? core.value_word_count * WASM_WORD_BYTES : WASM_WORD_BYTES;
    bool store_copy = wasm_store_copies_aggregate(core);
    uint value_op = operands.b < semantic_count
        ? opt_ir_op(opt_ir_core[operands.b]) : SEMANTIC_LIR_OP_INVALID;
    bool copy_set_value = wasm_set_copies_aggregate(core, value_op);
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
        (operands.a == WASM_INTRINSIC_PRINT || operands.a == WASM_INTRINSIC_ASSERT ||
         operands.a == INTRINSIC_I32_ARRAY_DATA_PTR);
    uint flags = wasm_lir_supported(core) || inline_host_operation ||
        imported_host_operation || supported_intrinsic
        ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
    // Host/intrinsic support cannot override an unsupported checked width.
    if (core.type_id == SCALAR_F64) flags |= TARGET_LIR_FLAG_UNSUPPORTED;
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

    uint opcode = wasm_scalar_opcode(core, operands);
    if (inline_host_operation) opcode = WASM_LIR_OP_F32_CONVERT_I32_S;
    else if (imported_host_operation) opcode = WASM_LIR_OP_CALL;
    uint immediate = 0u;
    bool discarded = local_row >= 1u && wasm_discarded_result_values(core,
        wasm_statement_call(compact_hir_core, opt_ir_source_hir[semantic_row])) != 0u;
    if (wasm_never_call(core) && local_row == 1u)
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
    else if (wasm_aggregate_copy_is_view(core))
    {
        opcode = WASM_LIR_OP_NOP;
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_COPY ||
             (copy_set_value && local_row < WASM_HEAP_COPY_ROWS))
    {
        // The stack holds the source address. Copy its words to the heap
        // top, push that address, then bump the heap past the copy.
        uint byte_count = core.value_word_count * WASM_WORD_BYTES;
        opcode = local_row == 0u ? WASM_LIR_OP_LOCAL_SET
            : local_row == 1u ? WASM_LIR_OP_GLOBAL_GET
            : local_row == 2u ? WASM_LIR_OP_LOCAL_GET
            : local_row == 3u ? WASM_LIR_OP_I32_CONST
            : local_row == 4u ? WASM_LIR_OP_MEMORY_COPY
            : local_row == 5u || local_row == 6u ? WASM_LIR_OP_GLOBAL_GET
            : local_row == 7u ? WASM_LIR_OP_I32_CONST
            : local_row == 8u ? WASM_LIR_OP_I32_ADD
            : WASM_LIR_OP_GLOBAL_SET;
        immediate = local_row == 0u || local_row == 2u ? WASM_SYNTHETIC_I32_TEMP
            : local_row == 3u || local_row == 7u ? byte_count : 0u;
    }
    else if (copy_set_value)
    {
        // The snapshot's address is on the stack: set the local to it.
        opcode = WASM_LIR_OP_LOCAL_SET;
        immediate = operands.a;
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_NEW)
    {
        // Each element is 7 rows: save the value, form the element address,
        // then store a scalar (and pad), or copy a nested aggregate's words.
        uint element_rows = operands.b * 7u;
        // `[value; count]` stores its one element, then doubles it in place.
        uint repeat_words = wasm_repeat_element_words(
            core, operands, semantic_lir_aggregate_elements);
        if (operands.c == SEMANTIC_LIR_AGGREGATE_REPEAT && repeat_words == WASM_LIR_INVALID)
            flags |= TARGET_LIR_FLAG_UNSUPPORTED;
        uint repeat_rows = WASM_REPEAT_STEP_ROWS *
            wasm_repeat_steps(repeat_words, core.value_word_count);
        bool tagged_enum = (operands.c & SEMANTIC_LIR_AGGREGATE_ENUM) != 0u;
        uint tag_rows = tagged_enum ? 5u : 0u;
        if (local_row < element_rows)
        {
            uint element = operands.b - 1u - local_row / 7u;
            uint phase = local_row % 7u;
            SemanticLirAggregateElement aggregate_element =
                semantic_lir_aggregate_elements[operands.a + element];
            if (wasm_scalar_class(aggregate_element.value_metadata &
                    SEMANTIC_LIR_VALUE_TYPE_MASK) != WASM_CLASS_I32 &&
                (aggregate_element.value_metadata &
                 SEMANTIC_LIR_VALUE_TYPE_MASK) != SCALAR_F32)
                flags |= TARGET_LIR_FLAG_UNSUPPORTED;
            bool element_is_f32 =
                (aggregate_element.value_metadata &
                 SEMANTIC_LIR_VALUE_TYPE_MASK) == TY_FLOAT;
            // A fixed array that initializes a slice field stores its
            // address: a Wasm slice is the address of its first element.
            bool element_is_aggregate =
                (aggregate_element.value_metadata & SEMANTIC_LIR_VALUE_AGGREGATE) != 0u &&
                (aggregate_element.value_metadata & SEMANTIC_LIR_VALUE_ARRAY_PAIR) == 0u &&
                aggregate_element.slice_array_length == WASM_LIR_INVALID &&
                aggregate_element.word_count != 0u &&
                aggregate_element.word_count != WASM_LIR_INVALID;
            uint temporary = element_is_f32
                ? WASM_SYNTHETIC_F32_TEMP : WASM_SYNTHETIC_I32_TEMP;
            opcode = phase == 0u ? WASM_LIR_OP_LOCAL_SET
                : phase == 1u ? WASM_LIR_OP_GLOBAL_GET
                : phase == 2u ? WASM_LIR_OP_I32_CONST
                : phase == 3u ? WASM_LIR_OP_I32_ADD
                : phase == 4u ? WASM_LIR_OP_LOCAL_GET
                : element_is_aggregate
                    ? (phase == 5u ? WASM_LIR_OP_I32_CONST : WASM_LIR_OP_MEMORY_COPY)
                : phase == 6u ? WASM_LIR_OP_NOP
                : element_is_f32 ? WASM_LIR_OP_F32_STORE : WASM_LIR_OP_I32_STORE;
            immediate = phase == 0u || phase == 4u ? temporary
                : phase == 2u ? aggregate_element.word_offset * WASM_WORD_BYTES
                : phase == 5u && element_is_aggregate
                    ? aggregate_element.word_count * WASM_WORD_BYTES : 0u;
        }
        else if (local_row < element_rows + repeat_rows)
        {
            // memory.copy(heap + filled, heap, length).
            uint step_row = local_row - element_rows;
            uint phase = step_row % WASM_REPEAT_STEP_ROWS;
            uint filled_bytes;
            uint length_bytes;
            wasm_repeat_step(repeat_words, core.value_word_count,
                step_row / WASM_REPEAT_STEP_ROWS, filled_bytes, length_bytes);
            opcode = phase == 0u || phase == 3u ? WASM_LIR_OP_GLOBAL_GET
                : phase == 1u || phase == 4u ? WASM_LIR_OP_I32_CONST
                : phase == 2u ? WASM_LIR_OP_I32_ADD : WASM_LIR_OP_MEMORY_COPY;
            immediate = phase == 1u ? filled_bytes : phase == 4u ? length_bytes : 0u;
        }
        else if (local_row < element_rows + repeat_rows + tag_rows)
        {
            uint phase = local_row - element_rows - repeat_rows;
            opcode = phase == 0u ? WASM_LIR_OP_GLOBAL_GET
                : phase == 1u ? WASM_LIR_OP_I32_CONST
                : phase == 2u ? WASM_LIR_OP_I32_ADD
                : phase == 3u ? WASM_LIR_OP_I32_CONST
                : WASM_LIR_OP_I32_STORE;
            immediate = phase == 3u
                ? operands.c & SEMANTIC_LIR_AGGREGATE_TAG_MASK : 0u;
        }
        else
        {
            uint phase = local_row - element_rows - repeat_rows - tag_rows;
            opcode = phase == 0u || phase == 1u ? WASM_LIR_OP_GLOBAL_GET
                : phase == 2u ? WASM_LIR_OP_I32_CONST
                : phase == 3u ? WASM_LIR_OP_I32_ADD
                : WASM_LIR_OP_GLOBAL_SET;
            immediate = phase == 2u ? core.value_word_count * WASM_WORD_BYTES : 0u;
        }
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOAD &&
             (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
    {
        bool call_index_base = operands.a < semantic_count && previous_row == operands.a &&
            (opt_ir_op(opt_ir_core[operands.a]) == SEMANTIC_LIR_OP_CALL ||
             opt_ir_op(opt_ir_core[operands.a]) == SEMANTIC_LIR_OP_CALL_SYMBOL);
        if (call_index_base)
        {
            // Calls are effect rows and therefore follow the already emitted
            // subscript expression. Save the returned aggregate address, then
            // consume the remaining subscript without assuming an implicit
            // operand swap in Wasm's stack machine.
            opcode = local_row == 0u ? WASM_LIR_OP_LOCAL_SET
                : local_row == 1u ? WASM_LIR_OP_I32_CONST
                : local_row == 2u ? WASM_LIR_OP_I32_MUL
                : local_row == 3u ? WASM_LIR_OP_LOCAL_GET
                : local_row == 4u ? WASM_LIR_OP_I32_ADD
                : aggregate_value ? WASM_LIR_OP_NOP
                : core.type_id == TY_FLOAT ? WASM_LIR_OP_F32_LOAD : WASM_LIR_OP_I32_LOAD;
            immediate = local_row == 0u || local_row == 3u
                ? WASM_SYNTHETIC_I32_TEMP : local_row == 1u ? stride : 0u;
        }
        else
        {
            opcode = local_row == 0u ? WASM_LIR_OP_I32_CONST
                : local_row == 1u ? WASM_LIR_OP_I32_MUL
                : local_row == 2u ? WASM_LIR_OP_I32_ADD
                : aggregate_value ? WASM_LIR_OP_NOP
                : core.type_id == TY_FLOAT ? WASM_LIR_OP_F32_LOAD : WASM_LIR_OP_I32_LOAD;
            immediate = local_row == 0u ? stride : 0u;
        }
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_STORE &&
             (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
    {
        bool call_index_base = operands.a < semantic_count &&
            (opt_ir_op(opt_ir_core[operands.a]) == SEMANTIC_LIR_OP_CALL ||
             opt_ir_op(opt_ir_core[operands.a]) == SEMANTIC_LIR_OP_CALL_SYMBOL);
        uint value_temporary = core.type_id == TY_FLOAT
            ? WASM_SYNTHETIC_F32_TEMP : WASM_SYNTHETIC_I32_TEMP;
        if (call_index_base)
        {
            // The stack is `(index, aggregate, value)`: preserve both values,
            // scale the index, restore the aggregate, and then restore the RHS.
            opcode = local_row == 0u ? WASM_LIR_OP_LOCAL_SET
                : local_row == 1u ? WASM_LIR_OP_LOCAL_SET
                : local_row == 2u ? WASM_LIR_OP_I32_CONST
                : local_row == 3u ? WASM_LIR_OP_I32_MUL
                : local_row == 4u ? WASM_LIR_OP_LOCAL_GET
                : local_row == 5u ? WASM_LIR_OP_I32_ADD
                : local_row == 6u ? WASM_LIR_OP_LOCAL_GET
                : store_copy ? (local_row == 7u ? WASM_LIR_OP_I32_CONST : WASM_LIR_OP_MEMORY_COPY)
                : core.type_id == TY_FLOAT ? WASM_LIR_OP_F32_STORE : WASM_LIR_OP_I32_STORE;
            immediate = local_row == 0u || local_row == 6u ? value_temporary
                : local_row == 1u || local_row == 4u
                ? WASM_SYNTHETIC_I32_ADDRESS_TEMP
                : local_row == 2u ? stride
                : store_copy && local_row == 7u ? stride : 0u;
        }
        else
        {
            // The stack is `(aggregate, index, value)`. Wasm stores consume
            // `(address, value)`, so preserve the RHS while forming the address.
            opcode = local_row == 0u ? WASM_LIR_OP_LOCAL_SET
                : local_row == 1u ? WASM_LIR_OP_I32_CONST
                : local_row == 2u ? WASM_LIR_OP_I32_MUL
                : local_row == 3u ? WASM_LIR_OP_I32_ADD
                : local_row == 4u ? WASM_LIR_OP_LOCAL_GET
                : store_copy ? (local_row == 5u ? WASM_LIR_OP_I32_CONST : WASM_LIR_OP_MEMORY_COPY)
                : core.type_id == TY_FLOAT ? WASM_LIR_OP_F32_STORE : WASM_LIR_OP_I32_STORE;
            immediate = local_row == 0u || local_row == 4u ? value_temporary
                : local_row == 1u ? stride
                : store_copy && local_row == 5u ? stride : 0u;
        }
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOAD &&
             (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
    {
        // A nested aggregate field is the address inside its owner.
        opcode = local_row == 0u ? WASM_LIR_OP_I32_CONST
            : local_row == 1u ? WASM_LIR_OP_I32_CONST
            : local_row == 2u ? WASM_LIR_OP_I32_MUL
            : local_row == 3u ? WASM_LIR_OP_I32_ADD
            : aggregate_value ? WASM_LIR_OP_NOP
            : core.type_id == TY_FLOAT ? WASM_LIR_OP_F32_LOAD : WASM_LIR_OP_I32_LOAD;
        immediate = local_row == 0u ? semantic_lir_layout_word_offset[semantic_row]
            : local_row == 1u ? WASM_WORD_BYTES : 0u;
    }
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_STORE &&
             (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
    {
        bool direct_receiver = operands.a < semantic_count &&
            opt_ir_op(opt_ir_core[operands.a]) == SEMANTIC_LIR_OP_VALUE_GET;
        uint receiver_declaration = direct_receiver
            ? opt_ir_operands[operands.a].a : WASM_LIR_INVALID;
        uint temporary = core.type_id == TY_FLOAT
            ? WASM_SYNTHETIC_F32_TEMP : WASM_SYNTHETIC_I32_TEMP;
        if (direct_receiver)
        {
            opcode = local_row == 0u ? WASM_LIR_OP_LOCAL_SET
                : local_row == 1u ? WASM_LIR_OP_LOCAL_GET
                : local_row == 2u ? WASM_LIR_OP_I32_CONST
                : local_row == 3u ? WASM_LIR_OP_I32_CONST
                : local_row == 4u ? WASM_LIR_OP_I32_MUL
                : local_row == 5u ? WASM_LIR_OP_I32_ADD
                : local_row == 6u ? WASM_LIR_OP_LOCAL_GET
                : store_copy ? (local_row == 7u ? WASM_LIR_OP_I32_CONST : WASM_LIR_OP_MEMORY_COPY)
                : core.type_id == TY_FLOAT ? WASM_LIR_OP_F32_STORE : WASM_LIR_OP_I32_STORE;
            immediate = local_row == 0u || local_row == 6u ? temporary
                : local_row == 1u ? receiver_declaration
                : local_row == 2u ? semantic_lir_layout_word_offset[semantic_row]
                : local_row == 3u ? WASM_WORD_BYTES
                : store_copy && local_row == 7u ? stride : 0u;
        }
        else
        {
            opcode = local_row == 0u ? WASM_LIR_OP_LOCAL_SET
                : local_row == 1u ? WASM_LIR_OP_I32_CONST
                : local_row == 2u ? WASM_LIR_OP_I32_CONST
                : local_row == 3u ? WASM_LIR_OP_I32_MUL
                : local_row == 4u ? WASM_LIR_OP_I32_ADD
                : local_row == 5u ? WASM_LIR_OP_LOCAL_GET
                : store_copy ? (local_row == 6u ? WASM_LIR_OP_I32_CONST : WASM_LIR_OP_MEMORY_COPY)
                : core.type_id == TY_FLOAT ? WASM_LIR_OP_F32_STORE : WASM_LIR_OP_I32_STORE;
            immediate = local_row == 0u || local_row == 5u ? temporary
                : local_row == 1u ? semantic_lir_layout_word_offset[semantic_row]
                : local_row == 2u ? WASM_WORD_BYTES
                : store_copy && local_row == 6u ? stride : 0u;
        }
    }
    else if ((opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET ||
              opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET) &&
             core.type_id == 7u)
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
        if (local_row == 0u)
        {
            operands.result = target_start;
            operands.a = 0xffffffffu;
            operands.b = WASM_LIR_INVALID;
            operands.c = WASM_LIR_INVALID;
            immediate = 0xffffffffu;
        }
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
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
             operands.a == INTRINSIC_I32_ARRAY_DATA_PTR)
    {
        // Aggregate values are represented by their linear-memory pointer on
        // the Wasm value stack.  The compiler-only projection must preserve
        // that pointer without calling the source-level placeholder body.
        opcode = local_row == 0u ? WASM_LIR_OP_LOCAL_SET : WASM_LIR_OP_LOCAL_GET;
        immediate = WASM_SYNTHETIC_I32_TEMP;
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
    target_operands.a = opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ||
        opt_ir_op(core) == SEMANTIC_LIR_OP_CALL ? operands.a : 0u;
    target_operands.b = opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ? operands.b : 0u;
    target_operands.c = opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ? operands.c : 0u;
    target_operands.metadata = core.type_id;
    if ((opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET ||
         opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET) && core.type_id == 7u)
    {
        target_operands.a = operands.a;
        // local.set consumes the top stack value. Assign a two-word string
        // in reverse component order so `(data_ptr, byte_len)` remains the
        // ordered local pair after the stores.
        target_operands.c = opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET
            ? 1u - local_row : local_row;
    }
    target_lir_operands[page_row] = target_operands;
}
