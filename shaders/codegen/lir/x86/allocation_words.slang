import native_value_layout;
import primitive_types;
// Assigns value locations and spill widths for every scheduled OptIR node.
// Small functions use one invocation to linear-scan general-purpose registers
// over the values' [definition, last use] intervals; see walk_function. Large
// functions use independent, bounded schedule segments; see walk_segment.
// The subsequent global
// prefix scan turns the spill widths into function-relative stack offsets.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.location_common;
import codegen.lir.x86.runtime_abi;
import gpu_index;
import codegen.lir.x86.aggregate_facts;

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
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement>
    semantic_lir_aggregate_elements;
StructuredBuffer<uint> x86_aggregate_facts;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> x86_live_by_semantic;
StructuredBuffer<uint> x86_last_use_by_semantic;
StructuredBuffer<X86FunctionRegisterAnalysis>
    x86_register_analysis_by_function;
StructuredBuffer<uint> x86_position_by_semantic;
StructuredBuffer<uint> x86_function_start;
StructuredBuffer<uint> x86_function_end;
StructuredBuffer<uint> semantic_lir_param_total;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> semantic_lir_local_total;
StructuredBuffer<SemanticLirLocal> semantic_lir_locals;
RWStructuredBuffer<uint> x86_location_by_semantic;
RWStructuredBuffer<uint> x86_stack_words_by_position;
RWStructuredBuffer<uint> x86_saved_gpr_mask_by_function;
// walk_function adds loop weights for small functions; optimize_init has
// already added them for segmented functions. decl_slots uses those weights
// to give registers to the most-read locals.
RWStructuredBuffer<X86DeclarationAnalysis> x86_decl_analysis_by_token;
StructuredBuffer<uint4> semantic_place_storage_by_token;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool produces_scalar_value(uint op)
{
    uint kind = semantic_lir_op_properties(op).result_kind;
    return kind == SEMANTIC_LIR_RESULT_SCALAR ||
        kind == SEMANTIC_LIR_RESULT_BOOL ||
        kind == SEMANTIC_LIR_RESULT_ADDRESS ||
        kind == SEMANTIC_LIR_RESULT_DYNAMIC;
}

bool scalar_gpr_result(OptIrNodeCore core)
{
    uint op = opt_ir_op(core);
    // 64-bit integers use full-width moves like pointers; see decl_slots_scatter.
    return op == SEMANTIC_LIR_OP_COMPARE || core.type_id == 1u ||
        core.type_id == 2u || core.type_id == 3u || core.type_id == 4u ||
        core.type_id == 6u || core.type_id == 8u || core.type_id == 9u ||
        core.type_id == 10u || core.type_id == 16u || core.type_id == 17u ||
        (core.type_id >= 11u && core.type_id <= 14u);
}

bool produces_float_value(uint op)
{
    // Comparisons and logical operations keep their operand type in the IR,
    // but produce an integer Boolean. They must never enter the XMM domain.
    return produces_scalar_value(op) &&
        op != SEMANTIC_LIR_OP_COMPARE &&
        op != SEMANTIC_LIR_OP_LOGICAL_NOT &&
        op != SEMANTIC_LIR_OP_LOGICAL_AND &&
        op != SEMANTIC_LIR_OP_LOGICAL_OR;
}

uint function_for_node(uint row)
{
    uint owner = opt_ir_source_hir[row];
    return owner < gParams.function_capacity
        ? semantic_function_id_by_hir[owner] : INVALID;
}

bool interval_crosses_call(uint position, uint last, uint total)
{
    // The bounded allocator admits intervals shorter than four positions, so
    // checking their interior is constant work per node. A call at `last`
    // consumes its arguments before clobbering caller-saved registers.
    for (uint cursor = position + 1u; cursor < last; ++cursor)
    {
        uint row = semantic_schedule_order[cursor];
        if (row < total && semantic_lir_is_call(opt_ir_op(opt_ir_core[row])))
            return true;
    }
    return false;
}

// The location every value gets independently of register pressure: INVALID
// for a stack home, RAX for a value returned at once, or an XMM register.
// `gpr` is set when the value may instead take a general-purpose register,
// which walk_function decides.
uint parallel_register_location(uint row, uint position, uint total, out bool gpr,
                                out bool argument)
{
    gpr = false;
    argument = false;
    OptIrNodeCore core = opt_ir_core[row];
    uint op = opt_ir_op(core);
    // An element address read only by the next row's field load stays in
    // RAX: INDEX_ADDRESS (or an aggregate element's INDEX_LOAD) computes it
    // there and FIELD_LOAD starts from RAX.
    bool element_address = op == SEMANTIC_LIR_OP_INDEX_ADDRESS ||
        (op == SEMANTIC_LIR_OP_LOAD &&
         (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u &&
         x86_semantic_type_is_aggregate(core));
    if (element_address &&
        x86_last_use_by_semantic[row] == position + 1u && position + 1u < total)
    {
        uint consumer = semantic_schedule_order[position + 1u];
        if (consumer < total &&
            opt_ir_op(opt_ir_core[consumer]) == SEMANTIC_LIR_OP_LOAD &&
            (opt_ir_core[consumer].flags & SEMANTIC_LIR_FLAG_FIELD) != 0u &&
            (opt_ir_core[consumer].flags & SEMANTIC_LIR_FLAG_INDEXED) == 0u &&
            // A string or slice field is loaded one word per target row, and
            // the first row's value replaces the address in RAX.
            opt_ir_core[consumer].type_id != SEMANTIC_LIR_TY_STRING &&
            (opt_ir_core[consumer].flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) == 0u &&
            opt_ir_operands[consumer].a == row &&
            opt_ir_operands[consumer].b != row && opt_ir_operands[consumer].c != row)
            return X86_LOCATION_REGISTER;
    }
    if (!produces_scalar_value(op)) return INVALID;
    if (op == SEMANTIC_LIR_OP_PLACE_LOAD) return INVALID;
    // A direct descriptor needs adjacent stack slots even when its final
    // consumer is RETURN. The single-register return shortcut below cannot
    // represent the length component.
    if (core.type_id == SEMANTIC_LIR_TY_STRING ||
        (core.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u)
        return INVALID;
    // A raw-parts slice has three components even when its source type tag
    // looks scalar. Its emitter needs four adjacent stack slots:
    // one result address and three payload words. Never assign it a GPR.
    if (op == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
        intrinsic_slice_from_raw_parts(opt_ir_operands[row].a))
        return INVALID;
    // Aggregate values are represented by an address, even when their payload
    // is returned in RAX/RDX.  That address must remain stable while the
    // aggregate's individual words are loaded.  Treating a CALL's dynamic
    // result as an ordinary scalar lets the first load overwrite RAX and makes
    // the second load dereference field zero as a pointer.
    if (x86_semantic_type_is_aggregate(core)) return INVALID;
    // Imported canonical refs can have no nominal type ID on the OptIR row.
    // Their checked result width still requires an address and payload slots;
    // assigning a register here makes the emitter write beyond the frame and
    // can overwrite a callee-saved register's home.
    if (op == SEMANTIC_LIR_OP_CALL_SYMBOL &&
        x86_imported_call_result_words(core) != 0u)
        return INVALID;
    if (op == SEMANTIC_LIR_OP_CALL)
    {
        uint callee = opt_ir_operands[row].a;
        uint function_total = min(gParams.function_capacity,
            semantic_lir_function_total[0u]);
        if (callee < function_total &&
            semantic_lir_functions[callee].result_word_count != 0u)
            return INVALID;
    }
    uint last = x86_last_use_by_semantic[row];
    if (last <= position) return INVALID;

    // CALL_ARG rows are expanded only after allocation and assign the SysV
    // argument registers in ascending order (after any stack pushes). A
    // source in one of those registers could be overwritten by an earlier
    // assignment. Of the temporaries' registers only R8 and R9 are argument
    // registers, and R9 is assigned last, so an integer value whose final
    // consumer is a direct or imported call may take any register but R8
    // (`argument`; walk_function). Every other call consumer (intrinsics,
    // float arguments) keeps a stack home.
    if (last < total)
    {
        uint consumer = semantic_schedule_order[last];
        uint consumer_op = consumer < total ? opt_ir_op(opt_ir_core[consumer]) : 0u;
        if (consumer < total && semantic_lir_is_call(consumer_op))
        {
            if ((consumer_op == SEMANTIC_LIR_OP_CALL ||
                 consumer_op == SEMANTIC_LIR_OP_CALL_SYMBOL) &&
                !scalar_is_float(core.type_id) && scalar_gpr_result(core))
            {
                gpr = true;
                argument = true;
            }
            return INVALID;
        }
    }

    // A value returned, or tested by a branch (test; jcc), at once stays in RAX.
    if (last == position + 1u && last < total)
    {
        uint consumer = semantic_schedule_order[last];
        uint consumer_op = consumer < total ? opt_ir_op(opt_ir_core[consumer]) : 0u;
        if (consumer < total && opt_ir_operands[consumer].a == row &&
            (consumer_op == SEMANTIC_LIR_OP_RETURN ||
             ((consumer_op == SEMANTIC_LIR_OP_IF_BEGIN ||
               consumer_op == SEMANTIC_LIR_OP_BRANCH_IF) &&
              scalar_gpr_result(core) && !scalar_is_float(core.type_id))))
            return X86_LOCATION_REGISTER;
    }
    uint function_id = function_for_node(row);
    if (function_id >= gParams.function_capacity) return INVALID;

    if (scalar_is_float(core.type_id) && produces_float_value(op))
    {
        if (last - position >= 8u ||
            interval_crosses_call(position, last, total))
            return INVALID;
        return x86_xmm_location(position & 7u);
    }

    gpr = scalar_gpr_result(core);
    return INVALID;
}

uint aggregate_copy_word_count(uint row, uint total, uint function_total)
{
    OptIrNodeCore core = opt_ir_core[row];
    OptIrNodeOperands operands = opt_ir_operands[row];
    uint op = opt_ir_op(core);
    if (x86_lir_opcode(core) != X86_LIR_OP_STORE_LOCAL ||
        operands.b >= total)
        return 0u;
    OptIrNodeCore value_core = opt_ir_core[operands.b];
    if (x86_direct_array_pair(value_core)) return 0u;
    OptIrNodeOperands value_operands = opt_ir_operands[operands.b];
    uint call_words = opt_ir_op(value_core) == SEMANTIC_LIR_OP_CALL &&
        value_operands.a < function_total
            ? semantic_lir_functions[value_operands.a].result_word_count : 0u;
    uint value_words = max(call_words,
        x86_aggregate_value_word_count(value_core, value_operands));
    return x86_semantic_type_is_aggregate(core) || value_words != 0u
        ? max(core.value_word_count, value_words) : 0u;
}

uint aggregate_new_word_count(uint row, OptIrNodeCore core,
                              OptIrNodeOperands operands)
{
    uint words = 0u;
    uint element_total = min(gParams.aggregate_capacity,
        semantic_lir_aggregate_element_total[0u]);
    if (x86_dense_aggregate(x86_aggregate_facts, row, operands.b))
        words = operands.b * semantic_lir_aggregate_elements[operands.a].word_count;
    else for (uint element = 0u; element < operands.b; element += 1u)
    {
        uint element_row = operands.a + element;
        if (element_row >= element_total) break;
        words += semantic_lir_aggregate_elements[element_row].word_count;
    }
    return max(core.value_word_count, words);
}

uint spill_word_count(uint row, uint total, uint function_total)
{
    OptIrNodeCore core = opt_ir_core[row];
    OptIrNodeOperands operands = opt_ir_operands[row];
    uint op = opt_ir_op(core);
    if (op == SEMANTIC_LIR_OP_PLACE_STORE) return 0u;
    if (op == SEMANTIC_LIR_OP_PLACE_LOAD)
    {
        if ((core.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u) return NATIVE_SLICE_WORDS;
        if ((core.flags & SEMANTIC_LIR_FLAG_PLACE_VIEW) != 0u) return 1u;
        if (core.type_id == SEMANTIC_LIR_TY_STRING) return 2u;
        return x86_semantic_type_is_aggregate(core) ? 1u + max(core.value_word_count, 1u) : 1u;
    }
    if (op == SEMANTIC_LIR_OP_VALUE_SET || op == SEMANTIC_LIR_OP_STORE)
    {
        uint words = aggregate_copy_word_count(row, total, function_total);
        return words == 0u ? 0u : 1u + words;
    }
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
        return 1u + aggregate_new_word_count(row, core, operands);
    if (op == SEMANTIC_LIR_OP_AGGREGATE_COPY)
        return 1u + core.value_word_count;
    if (core.type_id == SEMANTIC_LIR_TY_STRING && produces_scalar_value(op))
        return 2u;
    if (op == SEMANTIC_LIR_OP_CONST_STRING ||
        ((op == SEMANTIC_LIR_OP_VALUE_GET ||
          (op == SEMANTIC_LIR_OP_LOAD &&
           (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)) &&
         core.type_id == SEMANTIC_LIR_TY_STRING))
        return 2u;
    if (op == SEMANTIC_LIR_OP_VALUE_GET &&
        (core.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u)
        return NATIVE_SLICE_WORDS;
    if (op == SEMANTIC_LIR_OP_CALL)
    {
        uint words = operands.a < function_total
            ? semantic_lir_functions[operands.a].result_word_count : 0u;
        return 1u + words;
    }
    if (op == SEMANTIC_LIR_OP_CALL_SYMBOL)
        return 1u + x86_imported_call_result_words(core);
    if (op == SEMANTIC_LIR_OP_CALL_HOST)
        return operands.a == HOST_SERVICE_I32_TO_F32 ||
            x86_runtime_service_has_result(operands.a) ? 1u : 0u;
    if (op == SEMANTIC_LIR_OP_CALL_INTRINSIC)
        return intrinsic_argument_word(operands.a) ? 1u :
            intrinsic_slice_from_raw_parts(operands.a) ?
                1u + NATIVE_SLICE_WORDS : 0u;
    return produces_scalar_value(op) ? 1u : 0u;
}

// ---- Linear-scan general-purpose registers, one invocation per function ----
//
// Temporaries may use R8-R11 (caller-saved) and RBX, R12-R14 (callee-saved;
// R15 holds the host-runtime stack pointer). RAX, RCX and RDX stay emitter
// scratch and RDI/RSI belong to copies and call arguments. Declarations are
// placed later by decl_slots_scatter, which gives ordinals 0..5 RDI, RSI,
// R10, R11, R8, R9 in a call-free function and ordinals 0..3 RBX, R12-R14
// otherwise; the registers those ordinals can take are reserved here.
//
// A value holds its register over [definition, last use]. Two rules keep
// that sound across control flow:
// * Loops. At the target t of a back edge from s, every register still
//   holding a value defined before t stays held until s, because the value
//   is read again on the next iteration.
// * Calls. In a function with calls, a value whose interval contains a call
//   or a back-edge target (and so may be extended over a loop that calls)
//   takes a callee-saved register or a stack home.

static const uint TEMP_CALLER_REGISTERS = 0x0f00u; // R8-R11
static const uint TEMP_CALLEE_REGISTERS = (1u << 3u) | (1u << 12u) |
    (1u << 13u) | (1u << 14u);
// Preference order, one nibble per register from the low end: R8-R11, RBX,
// R12-R14. Caller-saved registers come first: they need no prologue save and
// keep small leaf functions inlinable.
static const uint TEMP_REGISTER_ORDER = 0xedc3ba98u;
static const uint NEAR_MASK = 0xffffu;
// decl_slots_scatter looks at most this many locals for a register slot.
static const uint LOCAL_SLOT_SCAN_LIMIT = 256u;

struct RegisterEnds
{
    // One past each register's current interval; free at p when <= p.
    uint rbx;
    uint r8;
    uint r9;
    uint r10;
    uint r11;
    uint r12;
    uint r13;
    uint r14;
};

uint register_end(RegisterEnds ends, uint physical)
{
    return physical == 3u ? ends.rbx : physical == 8u ? ends.r8 :
        physical == 9u ? ends.r9 : physical == 10u ? ends.r10 :
        physical == 11u ? ends.r11 : physical == 12u ? ends.r12 :
        physical == 13u ? ends.r13 : ends.r14;
}

void set_register_end(inout RegisterEnds ends, uint physical, uint end)
{
    if (physical == 3u) ends.rbx = end;
    else if (physical == 8u) ends.r8 = end;
    else if (physical == 9u) ends.r9 = end;
    else if (physical == 10u) ends.r10 = end;
    else if (physical == 11u) ends.r11 = end;
    else if (physical == 12u) ends.r12 = end;
    else if (physical == 13u) ends.r13 = end;
    else ends.r14 = end;
}

uint held_until(uint end, uint label, uint until)
{
    return end > label ? max(end, until) : end;
}

// A back edge from `source` reaches `label`: keep every value live at the
// label in its register through the whole loop.
void hold_over_loop(inout RegisterEnds ends, uint label, uint source)
{
    uint until = source + 1u;
    ends.rbx = held_until(ends.rbx, label, until);
    ends.r8 = held_until(ends.r8, label, until);
    ends.r9 = held_until(ends.r9, label, until);
    ends.r10 = held_until(ends.r10, label, until);
    ends.r11 = held_until(ends.r11, label, until);
    ends.r12 = held_until(ends.r12, label, until);
    ends.r13 = held_until(ends.r13, label, until);
    ends.r14 = held_until(ends.r14, label, until);
}

uint free_register(RegisterEnds ends, uint allowed, uint position)
{
    for (uint index = 0u; index < 8u; index += 1u)
    {
        uint physical = (TEMP_REGISTER_ORDER >> (index * 4u)) & 0xfu;
        if ((allowed & (1u << physical)) != 0u &&
            register_end(ends, physical) <= position)
            return physical;
    }
    return INVALID;
}

// The same type test decl_slots_scatter applies to declaration homes.
bool declaration_register_type(uint type_id)
{
    return type_id == 1u || type_id == 2u || type_id == 3u ||
        type_id == 4u || type_id == 6u || (type_id >= 8u && type_id <= 14u) ||
        type_id == 16u || type_id == 17u;
}

uint declaration_register(uint ordinal, bool has_call)
{
    return has_call ? (ordinal == 0u ? 3u : 11u + ordinal)
        : x86_caller_declaration_register(ordinal);
}

// Register slots (declaration ordinals for the RDI, RSI, R10, R11, R8, R9 or
// RBX, R12-R14 sequences) that decl_slots_scatter may give this function's
// declarations. Without calls, a register-typed parameter keeps its own
// ordinal unless a hidden result pointer or a (data, length, stride)
// parameter shifts the incoming registers; then the first two take slots 2
// and 3. Register-typed locals take the remaining slots in order
// (parameter_register_slot, local_register_slot). With calls, register-typed
// parameters and locals share the callee-saved slots by weight
// (ranked_slot), so the first free slots, one per declaration, are held;
// those declarations never use a caller-saved register.
uint declaration_register_mask(SemanticLirFunction function, bool has_call,
                               bool header)
{
    uint limit = has_call ? 4u : 6u;
    uint param_total = semantic_lir_param_total[0u];
    uint local_total = semantic_lir_local_total[0u];
    if (x86_parameter_range_outside(function, param_total) ||
        function.local_start + function.local_count > local_total)
        return 0xffffu;
    if (has_call)
    {
        uint wanted = 0u;
        for (uint ordinal = 0u; ordinal < min(function.param_count, LOCAL_SLOT_SCAN_LIMIT); ordinal += 1u)
            if (declaration_register_type(
                    semantic_lir_params[function.param_start + ordinal].type_id))
                wanted += 1u;
        for (uint index = 0u; index < min(function.local_count, LOCAL_SLOT_SCAN_LIMIT); index += 1u)
            if (declaration_register_type(
                    semantic_lir_locals[function.local_start + index].type_id))
                wanted += 1u;
        uint taken = header ? X86_HEADER_CALL_SLOTS : 0u;
        uint held = 0u;
        for (uint slot = 0u; slot < limit && wanted != 0u; slot += 1u)
        {
            if ((taken & (1u << slot)) != 0u) continue;
            held |= 1u << declaration_register(slot, true);
            wanted -= 1u;
        }
        return held;
    }
    bool shifted = function.result_word_count > 2u;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
        if (x86_abi_param_width(semantic_lir_params[function.param_start + ordinal]) > 1u)
            shifted = true;
    uint slots = 0u;
    uint shifted_slot = 2u;
    for (uint ordinal = 0u; ordinal < min(function.param_count, LOCAL_SLOT_SCAN_LIMIT); ordinal += 1u)
    {
        if (!declaration_register_type(
                semantic_lir_params[function.param_start + ordinal].type_id))
            continue;
        if (!shifted && ordinal < limit) slots |= 1u << ordinal;
        if (shifted && shifted_slot < 4u) slots |= 1u << shifted_slot;
        shifted_slot += 1u;
    }
    uint cursor = 0u;
    uint scanned = min(function.local_count, LOCAL_SLOT_SCAN_LIMIT);
    for (uint index = 0u; index < scanned; index += 1u)
    {
        if (!declaration_register_type(
                semantic_lir_locals[function.local_start + index].type_id))
            continue;
        while (cursor < limit && (slots & (1u << cursor)) != 0u) cursor += 1u;
        if (cursor >= limit) break;
        slots |= 1u << cursor;
        cursor += 1u;
    }
    uint mask = 0u;
    for (uint slot = 0u; slot < limit; slot += 1u)
        if ((slots & (1u << slot)) != 0u)
            mask |= 1u << declaration_register(slot, false);
    return mask;
}

// The function's slice parameter whose header stays in registers (see
// x86_header_parameter), or INVALID. decl_slots_scatter makes the same choice.
uint header_parameter(SemanticLirFunction function)
{
    if (x86_parameter_range_outside(function, semantic_lir_param_total[0u]))
        return INVALID;
    for (uint ordinal = 0u; ordinal < min(function.param_count, LOCAL_SLOT_SCAN_LIMIT); ordinal += 1u)
    {
        SemanticLirParam param = semantic_lir_params[function.param_start + ordinal];
        uint declaration = param.declaration_id;
        if (declaration < gParams.token_capacity &&
            x86_header_parameter(param, x86_decl_analysis_by_token[declaration],
                semantic_place_storage_by_token[declaration]))
            return function.param_start + ordinal;
    }
    return INVALID;
}

bool control_label(uint op)
{
    return op == SEMANTIC_LIR_OP_BLOCK_BEGIN || op == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        op == SEMANTIC_LIR_OP_CONTROL_END || op == SEMANTIC_LIR_OP_ELSE;
}

// The row a branch jumps to, as the x86 branch lowering reads it.
uint branch_target(uint op, OptIrNodeOperands operands)
{
    if (op == SEMANTIC_LIR_OP_IF_BEGIN) return operands.b;
    if (op == SEMANTIC_LIR_OP_BRANCH_IF) return operands.c;
    if (op == SEMANTIC_LIR_OP_BRANCH || op == SEMANTIC_LIR_OP_ELSE) return operands.a;
    return INVALID;
}

uint near_distance(uint from, uint to)
{
    return to == INVALID || to - from >= NEAR_MASK ? NEAR_MASK : to - from;
}

// True when an event `distance` positions after `position` lies before
// `last` (or at it when `inclusive`); saturated distances count as inside.
bool event_inside(uint position, uint distance, uint last, bool inclusive)
{
    if (distance == NEAR_MASK) return last - position >= NEAR_MASK;
    return inclusive ? position + distance <= last : position + distance < last;
}

// A VALUE_GET that locations' value_location reads from its declaration's
// home: a coalesced alias (that home cannot change before its last use), or
// a parameter read no call can reach before its last use (in a function with
// calls a parameter's home is a callee-saved register or a stack slot, so a
// call argument may read it there too). It needs no register or slot.
bool in_place_read(uint row, uint op, bool across)
{
    if (op != SEMANTIC_LIR_OP_VALUE_GET ||
        !declaration_register_type(opt_ir_core[row].type_id))
        return false;
    if (x86_live_by_semantic[row] == X86_SEMANTIC_COALESCED_ALIAS) return true;
    uint declaration = opt_ir_operands[row].a;
    return !across && declaration < gParams.token_capacity &&
        x86_decl_analysis_by_token[declaration].definition == INVALID;
}

bool reads_declaration(uint value, uint declaration, uint total)
{
    return value < total && opt_ir_op(opt_ir_core[value]) == SEMANTIC_LIR_OP_VALUE_GET &&
        opt_ir_operands[value].a == declaration;
}

// The local a value is produced straight into: the next row stores it there
// (VALUE_SET or a plain STORE) and nothing else reads it, so the producer writes the local's
// home (X86_LOCATION_DECLARATION) and the store is a self-move. Writing the
// home one row early is safe because no in-place read of the local lives
// across it (if_convert's alias proof stops at the store) unless it is an
// operand of the producer itself, which is excluded, as are calls, whose
// result moves span several rows. INVALID when there is no such local.
uint store_home(uint row, uint op, uint position, uint last, uint total)
{
    if (last != position + 1u || last >= total || semantic_lir_is_call(op))
        return INVALID;
    uint consumer = semantic_schedule_order[last];
    if (consumer >= total || x86_live_by_semantic[consumer] == 0u ||
        opt_ir_operands[consumer].b != row)
        return INVALID;
    // A let (VALUE_SET) or an assignment to the local itself (STORE).
    OptIrNodeCore store = opt_ir_core[consumer];
    uint store_op = opt_ir_op(store);
    if (store_op != SEMANTIC_LIR_OP_VALUE_SET &&
        (store_op != SEMANTIC_LIR_OP_STORE ||
         (store.flags & (SEMANTIC_LIR_FLAG_INDEXED | SEMANTIC_LIR_FLAG_FIELD)) != 0u))
        return INVALID;
    uint declaration = opt_ir_operands[consumer].a;
    OptIrNodeOperands operands = opt_ir_operands[row];
    if (declaration >= gParams.token_capacity || declaration >= X86_LOCATION_PAYLOAD_MASK ||
        semantic_place_storage_by_token[declaration].x != 0u ||
        !declaration_register_type(opt_ir_core[consumer].type_id) ||
        opt_ir_core[consumer].type_id != opt_ir_core[row].type_id ||
        reads_declaration(operands.b, declaration, total) ||
        reads_declaration(operands.c, declaration, total))
        return INVALID;
    // `x = x op constant`: an immediate binary moves its one register operand
    // into the result first (plan_binary_immediate), so it may be the local.
    bool immediate_update = (op == SEMANTIC_LIR_OP_ADD || op == SEMANTIC_LIR_OP_SUB ||
        op == SEMANTIC_LIR_OP_MUL || (op >= SEMANTIC_LIR_OP_BIT_AND &&
        op <= SEMANTIC_LIR_OP_SHIFT_RIGHT)) &&
        operands.b < total && x86_live_by_semantic[operands.b] == 0u;
    if (reads_declaration(operands.a, declaration, total) && !immediate_update)
        return INVALID;
    return declaration;
}

void walk_function(uint function_id, uint start, uint end, uint total,
                   uint function_total)
{
    // Backward pass. Each non-label row's location word temporarily holds the
    // distances to the next call and the next back-edge target after it; a
    // back-edge target's word holds the farthest position that jumps back
    // to it. The forward pass replaces every one of these words.
    //
    // The same pass weighs every declaration read by its loop depth: the
    // headers of the (at most three innermost) loops around `cursor`, which
    // the back-edges met so far open, are `inner`, `middle` and `outer`.
    bool sound = true;
    bool has_loop = false;
    uint next_call = INVALID;
    uint next_target = INVALID;
    uint inner = INVALID;
    uint middle = INVALID;
    uint outer = INVALID;
    uint depth = 0u;
    for (uint cursor = end; cursor > start; )
    {
        cursor -= 1u;
        if (depth != 0u && cursor < inner)
        {
            inner = middle;
            middle = outer;
            outer = INVALID;
            depth -= 1u;
        }
        uint row = semantic_schedule_order[cursor];
        if (row >= total || function_for_node(row) != function_id) continue;
        uint op = opt_ir_op(opt_ir_core[row]);
        if (depth != 0u && (op == SEMANTIC_LIR_OP_VALUE_GET || op == SEMANTIC_LIR_OP_ADDRESS))
        {
            uint declaration = opt_ir_operands[row].a;
            uint ignored;
            if (declaration < gParams.token_capacity)
                InterlockedAdd(x86_decl_analysis_by_token[declaration].read_count,
                    (1u << (3u * depth)) - 1u, ignored);
        }
        uint target = branch_target(op, opt_ir_operands[row]);
        if (target < total)
        {
            uint target_position = x86_position_by_semantic[target];
            if (target_position <= cursor)
            {
                if (target_position < start || target_position == cursor ||
                    function_for_node(target) != function_id ||
                    !control_label(opt_ir_op(opt_ir_core[target])))
                    sound = false;
                else
                {
                    if (depth == 0u || target_position > inner)
                    {
                        outer = middle;
                        middle = inner;
                        inner = target_position;
                        depth = min(depth + 1u, 3u);
                    }
                    has_loop = true;
                    uint prior = x86_location_by_semantic[target];
                    x86_location_by_semantic[target] =
                        prior == INVALID ? cursor : max(prior, cursor);
                }
            }
        }
        if (control_label(op))
        {
            // Only a loop with a call in its body makes the values it holds
            // need callee-saved registers.
            uint source = x86_location_by_semantic[row];
            if (source != INVALID && next_call <= source) next_target = cursor;
        }
        else
            x86_location_by_semantic[row] = near_distance(cursor, next_call) |
                (near_distance(cursor, next_target) << 16u);
        if (semantic_lir_is_call(op)) next_call = cursor;
    }

    bool has_call =
        x86_register_analysis_by_function[function_id].first_call != INVALID;
    SemanticLirFunction function = semantic_lir_functions[function_id];
    // Only a loop repays the saved registers (and the lost inlining), and the
    // three header registers come out of the temporaries' pool: keep at
    // least two temporaries free.
    uint plain_free = countbits((TEMP_CALLER_REGISTERS | TEMP_CALLEE_REGISTERS) &
        ~declaration_register_mask(function, has_call, false));
    bool header = has_loop && sound && plain_free >= 5u &&
        header_parameter(function) != INVALID;
    uint reserved = declaration_register_mask(function, has_call, header);
    if (header) reserved |= X86_HEADER_REGISTERS;
    uint caller_free = TEMP_CALLER_REGISTERS & ~reserved;
    uint callee_free = TEMP_CALLEE_REGISTERS & ~reserved;
    RegisterEnds ends;
    ends.rbx = 0u; ends.r8 = 0u; ends.r9 = 0u; ends.r10 = 0u;
    ends.r11 = 0u; ends.r12 = 0u; ends.r13 = 0u; ends.r14 = 0u;
    uint saved = header ? X86_HEADER_REGISTERS | X86_HEADER_CACHE_FLAG : 0u;

    for (uint position = start; position < end; position += 1u)
    {
        uint row = semantic_schedule_order[position];
        if (row >= total || function_for_node(row) != function_id) continue;
        uint op = opt_ir_op(opt_ir_core[row]);
        uint pending = x86_location_by_semantic[row];
        uint location = INVALID;
        uint words = 0u;
        if (control_label(op))
        {
            if (pending != INVALID) hold_over_loop(ends, position, pending);
        }
        bool in_place = false;
        if (x86_live_by_semantic[row] != 0u)
        {
            bool gpr;
            bool argument;
            location = parallel_register_location(row, position, total, gpr, argument);
            uint last = x86_last_use_by_semantic[row];
            bool across = has_call &&
                (event_inside(position, pending & NEAR_MASK, last, false) ||
                 event_inside(position, pending >> 16u, last, true));
            in_place = gpr && sound && in_place_read(row, op, across);
            uint home = gpr && sound && !in_place && !control_label(op)
                ? store_home(row, op, position, last, total) : INVALID;
            if (home != INVALID)
            {
                location = X86_LOCATION_DECLARATION | home;
                in_place = true;
            }
            if (gpr && sound && !control_label(op) && !in_place)
            {
                uint allowed = across ? callee_free : caller_free | callee_free;
                if (argument) allowed &= ~(1u << 8u);
                uint physical = free_register(ends, allowed, position);
                if (physical != INVALID)
                {
                    set_register_end(ends, physical, last + 1u);
                    if ((TEMP_CALLEE_REGISTERS & (1u << physical)) != 0u)
                        saved |= 1u << physical;
                    location = X86_LOCATION_REGISTER | physical;
                }
            }
            if (location == INVALID && !in_place)
                words = spill_word_count(row, total, function_total);
        }
        x86_location_by_semantic[row] = location;
        x86_stack_words_by_position[position] = words;
    }
    if (saved != 0u)
    {
        uint ignored;
        InterlockedOr(x86_saved_gpr_mask_by_function[function_id], saved, ignored);
    }
}

// Independent segments bound the allocation critical path for large functions.
// Declaration homes are reserved for the entire function exactly as in the
// serial allocator. Temporary intervals may use a register only when they end
// in this segment and do not cross a control label. In particular, a value
// defined before a loop header keeps a stack home: a back edge in another
// segment cannot extend an interval into a register reused here. Thus no
// segment reads or writes another segment's temporary allocation state.
//
// Within a segment we retain greedy allocation, callee-saved registers across
// calls, coalesced declaration reads, and direct writes to declaration homes.
// optimize_init has already published loop-weighted declaration reads. Every
// segment makes the same slice-header decision from immutable function
// analysis, so its three registers stay reserved for the entire function.
void walk_segment(uint function_id, uint start, uint end, uint total,
                  uint function_total)
{
    uint next_call = INVALID;
    uint next_label = INVALID;
    for (uint cursor = end; cursor > start; )
    {
        cursor -= 1u;
        uint row = semantic_schedule_order[cursor];
        if (row >= total || function_for_node(row) != function_id) continue;
        uint op = opt_ir_op(opt_ir_core[row]);
        x86_location_by_semantic[row] = near_distance(cursor, next_call) |
            (near_distance(cursor, next_label) << 16u);
        if (semantic_lir_is_call(op)) next_call = cursor;
        if (control_label(op)) next_label = cursor;
    }

    X86FunctionRegisterAnalysis analysis = x86_register_analysis_by_function[function_id];
    bool has_call = analysis.first_call != INVALID;
    bool has_loop = (analysis.flags & X86_ALLOCATION_HAS_LOOP) != 0u;
    SemanticLirFunction function = semantic_lir_functions[function_id];
    uint plain_free = countbits((TEMP_CALLER_REGISTERS | TEMP_CALLEE_REGISTERS) &
        ~declaration_register_mask(function, has_call, false));
    bool header = has_loop && plain_free >= 5u && header_parameter(function) != INVALID;
    uint reserved = declaration_register_mask(function, has_call, header);
    if (header) reserved |= X86_HEADER_REGISTERS;
    uint caller_free = TEMP_CALLER_REGISTERS & ~reserved;
    uint callee_free = TEMP_CALLEE_REGISTERS & ~reserved;
    RegisterEnds ends;
    ends.rbx = 0u; ends.r8 = 0u; ends.r9 = 0u; ends.r10 = 0u;
    ends.r11 = 0u; ends.r12 = 0u; ends.r13 = 0u; ends.r14 = 0u;
    uint saved = header ? X86_HEADER_REGISTERS | X86_HEADER_CACHE_FLAG : 0u;

    for (uint position = start; position < end; position += 1u)
    {
        uint row = semantic_schedule_order[position];
        if (row >= total || function_for_node(row) != function_id) continue;
        uint location = INVALID;
        uint words = 0u;
        if (x86_live_by_semantic[row] != 0u)
        {
            uint op = opt_ir_op(opt_ir_core[row]);
            uint pending = x86_location_by_semantic[row];
            uint last = x86_last_use_by_semantic[row];
            bool contained = last < end &&
                !event_inside(position, pending >> 16u, last, true);
            // Outside this segment, either a call or a loop back edge may
            // reach the parameter's last use. Keep its ordinary stack copy
            // unless if_convert already proved the read a coalesced alias.
            bool across = has_call && (!contained ||
                event_inside(position, pending & NEAR_MASK, last, false));
            bool gpr;
            bool argument;
            location = parallel_register_location(row, position, total, gpr, argument);
            bool in_place = gpr && in_place_read(row, op, across);
            uint home = gpr && !in_place && !control_label(op)
                ? store_home(row, op, position, last, total) : INVALID;
            if (home != INVALID)
            {
                location = X86_LOCATION_DECLARATION | home;
                in_place = true;
            }
            if (gpr && contained && !control_label(op) && !in_place)
            {
                uint allowed = across ? callee_free : caller_free | callee_free;
                if (argument) allowed &= ~(1u << 8u);
                uint physical = free_register(ends, allowed, position);
                if (physical != INVALID)
                {
                    set_register_end(ends, physical, last + 1u);
                    if ((TEMP_CALLEE_REGISTERS & (1u << physical)) != 0u)
                        saved |= 1u << physical;
                    location = X86_LOCATION_REGISTER | physical;
                }
            }
            if (location == INVALID && !in_place)
                words = spill_word_count(row, total, function_total);
        }
        x86_location_by_semantic[row] = location;
        x86_stack_words_by_position[position] = words;
    }
    if (saved != 0u)
    {
        uint ignored;
        InterlockedOr(x86_saved_gpr_mask_by_function[function_id], saved, ignored);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (position >= total) return;
    uint row = semantic_schedule_order[position];
    uint function_total = min(gParams.function_capacity,
        semantic_lir_function_total[0u]);
    uint function_id = row < total ? function_for_node(row) : INVALID;
    if (function_id < function_total)
    {
        uint start = x86_function_start[function_id];
        uint end = min(x86_function_end[function_id], total);
        if (end > start && end - start > X86_ALLOCATION_SERIAL_FUNCTION_LIMIT)
        {
            if ((position - start) % X86_ALLOCATION_SEGMENT_SIZE == 0u)
                walk_segment(function_id, position,
                    min(position + X86_ALLOCATION_SEGMENT_SIZE, end), total, function_total);
        }
        else if (start == position && start < end)
            walk_function(function_id, start, end, total, function_total);
        return;
    }
    uint words = 0u;
    if (row < total && x86_live_by_semantic[row] != 0u)
    {
        bool gpr;
        bool argument;
        uint location = parallel_register_location(row, position, total, gpr, argument);
        if (location != INVALID)
            x86_location_by_semantic[row] = location;
        else
            words = spill_word_count(row, total, function_total);
    }
    x86_stack_words_by_position[position] = words;
}
