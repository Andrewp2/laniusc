import primitive_types;
import native_value_layout;
import codegen.lir.x86.common;
import codegen.lir.x86.storage_layout;
import codegen.lir.x86.runtime_abi;
import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint target_capacity;
    uint target_start;
    uint page_capacity;
    uint token_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<uint> semantic_lir_layout_word_offset;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
StructuredBuffer<uint> semantic_lir_string_total;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> x86_live_by_semantic;
StructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
StructuredBuffer<X86SelectInfo> x86_select_by_semantic;
StructuredBuffer<X86InlineInfo> x86_inline_info_by_function;
StructuredBuffer<uint> target_lir_offset;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<uint> semantic_to_target_start;
RWStructuredBuffer<X86LirCore> target_lir_core;
RWStructuredBuffer<X86LirOperands> target_lir_operands;
RWStructuredBuffer<uint> target_semantic_origin;
RWStructuredBuffer<uint> target_lir_flags;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint TARGET_PAGE_ROWS = 65536u;

uint inline_body_semantic_row(X86InlineInfo info, uint ordinal, uint total)
{
    uint start = info.schedule_start;
    uint end = min(info.schedule_end, total);
    uint current = 0u;
    for (uint position = start; position < end; position += 1u)
    {
        uint candidate = semantic_schedule_order[position];
        if (candidate >= total || x86_live_by_semantic[candidate] == 0u)
            continue;
        uint op = opt_ir_op(opt_ir_core[candidate]);
        if (op == SEMANTIC_LIR_OP_NOP || op == SEMANTIC_LIR_OP_RETURN)
            continue;
        if (current == ordinal) return candidate;
        current += 1u;
    }
    return INVALID;
}

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

uint call_argument_width(SemanticLirCallArg argument)
{
    return x86_abi_argument_width(argument.value_metadata);
}

uint call_abi_argument_count(uint start, uint count)
{
    uint result = 0u;
    for (uint arg_i = 0u; arg_i < count; arg_i += 1u)
        result += call_argument_width(semantic_lir_call_args[start + arg_i]);
    return result;
}

// The checked C profile contains only scalar eightbytes. INTEGER and SSE
// registers are independent banks; an exhausted bank spills its subsequent
// arguments without consuming registers in the other bank.
uint native_c_stack_words(uint start, uint count)
{
    uint floats = 0u;
    for (uint i = 0u; i < count; i++)
        if (scalar_is_float(semantic_lir_call_args[start + i].value_metadata &
            SEMANTIC_LIR_VALUE_TYPE_MASK)) floats++;
    uint integers = count - floats;
    return (floats > 8u ? floats - 8u : 0u) +
        (integers > 6u ? integers - 6u : 0u);
}

// Register destinations use their bank ordinal (GPR 0..5, XMM 0..7), while
// stack destinations use 16 + their source-order stack index. Expansion emits
// reversed stack arguments first, followed by register arguments in source
// order. Every source has a stable home before these parallel copies run.
SemanticLirCallArg native_c_argument(uint start, uint count, uint row,
    uint stack_words, out uint destination)
{
    uint integers = 0u;
    uint floats = 0u;
    uint stack = 0u;
    uint registers = 0u;
    destination = INVALID;
    SemanticLirCallArg selected = semantic_lir_call_args[start];
    for (uint i = 0u; i < count; i++)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[start + i];
        bool floating = scalar_is_float(argument.value_metadata & SEMANTIC_LIR_VALUE_TYPE_MASK);
        uint ordinal;
        if (floating) { ordinal = floats; floats++; }
        else { ordinal = integers; integers++; }
        bool spilled = ordinal >= (floating ? 8u : 6u);
        uint position = spilled ? stack_words - 1u - stack : stack_words + registers;
        if (position == row)
        {
            selected = argument;
            destination = spilled ? 16u + stack : ordinal;
        }
        if (spilled) stack++;
        else registers++;
    }
    return selected;
}

bool direct_i32_constant(uint semantic_row, uint semantic_count,
                         out uint value)
{
    value = 0u;
    if (semantic_row >= semantic_count) return false;
    X86ValueAnalysis analysis = x86_value_by_semantic[semantic_row];
    value = analysis.value;
    return analysis.known != 0u;
}

bool single_word_compare_operands(uint left, uint right, uint semantic_count)
{
    if (left >= semantic_count || right >= semantic_count) return false;
    return opt_ir_core[left].value_word_count == 1u &&
        opt_ir_core[right].value_word_count == 1u;
}

bool direct_packed_i32_array(uint semantic_row, uint semantic_count)
{
    if (semantic_row >= semantic_count) return false;
    OptIrNodeCore core = opt_ir_core[semantic_row];
    OptIrNodeOperands operands = opt_ir_operands[semantic_row];
    // A zero aggregate has no elements; an i32 array of them uses the
    // packed layout that every i32-array consumer expects.
    if (x86_zero_aggregate(core, operands)) return core.type_id == 131u;
    if (opt_ir_op(core) != SEMANTIC_LIR_OP_AGGREGATE_NEW ||
        (operands.c != 0u && operands.c != SEMANTIC_LIR_AGGREGATE_REPEAT) ||
        operands.b == 0u)
        return false;
    uint element_total = semantic_lir_aggregate_element_total[0u];
    if (operands.a >= element_total) return false;
    SemanticLirAggregateElement first =
        semantic_lir_aggregate_elements[operands.a];
    return first.aggregate_instruction == semantic_row &&
        first.word_count == 1u &&
        (first.value_metadata & SEMANTIC_LIR_VALUE_TYPE_MASK) == 3u;
}

bool packed_i32_array_source(uint row, uint count)
{
    if (row >= count) return false;
    return x86_array_storage_kind(opt_ir_core[row], direct_packed_i32_array(row, count))
        == X86_STORAGE_PACKED_I32;
}

// The row after an aggregate's address row zeroes its `words` storage
// slots, which begin at this row's own frame slot.
void write_fill(uint page_row, uint row, uint semantic_row, uint source_hir,
                uint words, bool valid)
{
    X86LirCore core;
    core.source_hir = source_hir;
    core.local_ordinal = 0u;
    core.op = X86_LIR_OP_AGGREGATE_FILL;
    core.result_or_target = row;
    X86LirOperands operands;
    operands.a = 0u;
    operands.b = 0u;
    operands.c = words;
    operands.metadata = 0u;
    target_lir_core[page_row] = core;
    target_lir_operands[page_row] = operands;
    target_semantic_origin[page_row] = semantic_row;
    target_lir_flags[page_row] = valid && words <= 0x0fffffffu
        ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
}

void write_call_arg(uint page_row, uint row, uint semantic_row, uint source_hir, uint abi_row,
                    OptIrNodeCore source, uint argument_start,
                    uint argument_count, uint call_result_words,
                    uint semantic_count)
{
    SemanticLirCallArg argument;
    argument.call_instruction = INVALID;
    argument.value_instruction = INVALID;
    argument.ordinal = INVALID;
    argument.value_metadata = 0u;
    argument.array_length = INVALID;
    uint component = 0u;
    uint abi_ordinal = 0u;
    uint cursor = 0u;
    uint sret_shift = call_result_words > 2u && opt_ir_op(source) != SEMANTIC_LIR_OP_CALL_INTRINSIC ? 1u : 0u;
    uint argument_rows = call_abi_argument_count(argument_start, argument_count);
    bool native_c = (source.flags & SEMANTIC_LIR_FLAG_NATIVE_C_CALL) != 0u;
    uint stack_words = native_c ? native_c_stack_words(argument_start, argument_count)
        : argument_rows + sret_shift > 6u
        ? argument_rows + sret_shift - 6u : 0u;
    // Push excess arguments right-to-left before moving register arguments.
    uint value_row = abi_row < stack_words
        ? argument_rows - 1u - abi_row : abi_row - stack_words;
    if (native_c)
        argument = native_c_argument(argument_start, argument_count, abi_row, stack_words, abi_ordinal);
    else for (uint arg_i = 0u; arg_i < argument_count; arg_i += 1u)
    {
        SemanticLirCallArg candidate = semantic_lir_call_args[argument_start + arg_i];
        uint width = call_argument_width(candidate);
        if (value_row >= cursor && value_row < cursor + width)
        {
            argument = candidate;
            component = value_row - cursor;
            abi_ordinal = cursor + component;
            break;
        }
        cursor += width;
    }
    X86LirCore core;
    core.source_hir = source_hir;
    // CALL_ARG local_ordinal is pre-push alignment padding in bytes.
    core.local_ordinal = abi_row == 0u && (stack_words & 1u) != 0u ? 8u : 0u;
    core.op = X86_LIR_OP_CALL_ARG;
    core.result_or_target = INVALID;
    X86LirOperands operands;
    operands.a = argument.value_instruction;
    operands.b = abi_ordinal + sret_shift;
    operands.c = component;
    // Carry the checked semantic value type through target resolution. The
    // emitter uses this target-IR fact to choose word- versus dword-sized ABI
    // moves without chasing the source expression's producer shape.
    uint argument_type =
        argument.value_metadata & SEMANTIC_LIR_VALUE_TYPE_MASK;
    bool string_value =
        (argument.value_metadata & SEMANTIC_LIR_VALUE_STRING) != 0u;
    bool direct_slice_intrinsic = false;
    bool indirect_slice_value = false;
    if (argument.value_instruction < semantic_count)
    {
        OptIrNodeCore argument_core = opt_ir_core[argument.value_instruction];
        OptIrNodeOperands argument_operands =
            opt_ir_operands[argument.value_instruction];
        direct_slice_intrinsic =
            opt_ir_op(argument_core) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
            intrinsic_slice_from_raw_parts(argument_operands.a);
        indirect_slice_value =
            (argument_core.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u &&
            !x86_direct_array_pair(argument_core);
    }
    bool array_value =
        (argument.value_metadata & SEMANTIC_LIR_VALUE_ARRAY_PAIR) != 0u ||
        direct_slice_intrinsic;
    operands.metadata = (argument_type & 0xffu) |
        (native_c ? X86_LIR_METADATA_NATIVE_C : 0u) |
        ((argument.value_metadata & SEMANTIC_LIR_VALUE_AGGREGATE) != 0u
            ? X86_LIR_METADATA_AGGREGATE : 0u) |
        (string_value &&
         component == 0u
            ? X86_LIR_METADATA_WIDE :
         string_value &&
         component == 1u
            ? X86_LIR_METADATA_STRING_LEN : 0u);
    if (array_value)
        operands.metadata |= X86_LIR_METADATA_ARRAY_PAIR |
            (component == 1u ? X86_LIR_METADATA_ARRAY_LEN
                             : X86_LIR_METADATA_WIDE);
    // The value's checked representation decides whether this is a descriptor
    // address. A fixed-array field also uses FIELD_LOAD, but already yields
    // its data address; dereferencing it as a slice would pass element zero
    // as the callee's pointer. VALUE_GET slices expose three direct slots.
    if (array_value && argument.value_instruction < semantic_count &&
        (direct_slice_intrinsic || indirect_slice_value))
        operands.metadata |= X86_LIR_METADATA_INDIRECT_ARRAY_PAIR;
    if (scalar_uses_64bit_gpr(argument_type))
        operands.metadata |= X86_LIR_METADATA_WIDE;
    // Narrow scalar spill slots contain only four initialized bytes. A
    // dword ABI move zero-extends into the machine-word argument register;
    // reading eight bytes would pass stale stack data as its high half.
    // Pointer and aggregate components retain their explicit width above.
    // Unclassified producers can still be aggregate addresses; do not narrow
    // those until semantic projection supplies their concrete type metadata.
    if (argument_type == 0u)
        operands.metadata |= X86_LIR_METADATA_WIDE;
    uint immediate = 0u;
    bool encoded_array_length = array_value && component == 1u &&
        argument.array_length != SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME &&
        argument.array_length != INVALID;
    uint array_stride = 0u;
    bool encoded_array_stride = false;
    bool supported_array_storage = true;
    if (array_value && component == NATIVE_SLICE_STRIDE &&
        argument.value_instruction < semantic_count && !direct_slice_intrinsic &&
        !x86_direct_array_pair(opt_ir_core[argument.value_instruction]) && !indirect_slice_value)
    {
        OptIrNodeCore value = opt_ir_core[argument.value_instruction];
        uint storage = x86_array_storage_kind(value,
            direct_packed_i32_array(argument.value_instruction, semantic_count));
        supported_array_storage = argument.array_length != INVALID &&
            argument.array_length != SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME &&
            x86_fixed_array_stride(storage,
                x86_aggregate_value_word_count(value, opt_ir_operands[argument.value_instruction]),
                argument.array_length, array_stride);
        encoded_array_stride = supported_array_storage;
    }
    bool encoded_immediate = encoded_array_length || encoded_array_stride || (!string_value && !array_value &&
        (argument.value_metadata & SEMANTIC_LIR_VALUE_AGGREGATE) == 0u &&
        x86_scalar_immediate_type(argument_type) &&
        direct_i32_constant(
            argument.value_instruction, semantic_count, immediate));
    if (encoded_immediate)
    {
        operands.a = encoded_array_length ? argument.array_length : encoded_array_stride ? array_stride : immediate;
        operands.metadata |= X86_LIR_METADATA_IMMEDIATE;
    }
    target_lir_core[page_row] = core;
    target_lir_operands[page_row] = operands;
    target_semantic_origin[page_row] = semantic_row;
    bool matching_call = argument.call_instruction < gParams.semantic_capacity &&
        opt_ir_source_hir[argument.call_instruction] == source_hir &&
        opt_ir_op(opt_ir_core[argument.call_instruction]) == opt_ir_op(source);
    target_lir_flags[page_row] = matching_call &&
        argument.value_instruction < gParams.semantic_capacity && supported_array_storage
        ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
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
    uint source_hir = opt_ir_source_hir[semantic_row];
    uint target_start = target_lir_offset[scheduled_row];
    OptIrNodeCore source = opt_ir_core[semantic_row];
    // Call-argument rows are an ABI expansion of call instructions only. A
    // loop or control row may share a HIR-indexed workspace slot with a prior
    // call, so do not let stale/non-call metadata manufacture CALL_ARG rows.
    bool is_call = semantic_lir_is_call(opt_ir_op(source));
    uint argument_count = is_call
        ? semantic_lir_call_arg_count_by_hir[source_hir] : 0u;
    uint argument_start = semantic_lir_call_arg_start_by_hir[source_hir];
    uint argument_rows = call_abi_argument_count(argument_start, argument_count);
    OptIrNodeOperands args = opt_ir_operands[semantic_row];
    uint function_count = min(gParams.semantic_capacity, semantic_lir_function_total[0u]);
    X86InlineInfo inline_info;
    inline_info.return_value = INVALID;
    inline_info.body_row_count = 0u;
    inline_info.schedule_start = INVALID;
    inline_info.schedule_end = INVALID;
    if (opt_ir_op(source) == SEMANTIC_LIR_OP_CALL &&
        args.a < function_count)
        inline_info = x86_inline_info_by_function[args.a];
    bool inline_call = inline_info.return_value != INVALID;
    uint call_result_words = opt_ir_op(source) == SEMANTIC_LIR_OP_CALL &&
        args.a < function_count ? semantic_lir_functions[args.a].result_word_count :
        opt_ir_op(source) == SEMANTIC_LIR_OP_CALL_SYMBOL
            ? x86_imported_call_result_words(source) :
        opt_ir_op(source) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
        intrinsic_slice_from_raw_parts(args.a) ? NATIVE_SLICE_WORDS : 0u;
    // A call expands to argument-move rows followed by the value-producing
    // call row. Semantic operands name values, so their target projection must
    // point at the producer rather than the beginning of the expansion.
    semantic_to_target_start[semantic_row] = inline_call
        ? target_start + argument_rows + inline_info.body_row_count
        : target_start + argument_rows;
    uint local_row = row - target_start;
    if (local_row < argument_rows)
    {
        write_call_arg(page_row, row, semantic_row, source_hir, local_row, source,
            argument_start, argument_count, call_result_words, semantic_count);
        return;
    }

    bool inline_clone = false;
    if (inline_call)
    {
        uint inline_row = local_row - argument_rows;
        if (inline_row >= inline_info.body_row_count)
        {
            X86LirCore core;
            core.source_hir = source_hir;
            core.local_ordinal = 0u;
            core.op = X86_LIR_OP_INLINE_RESULT;
            core.result_or_target = row;
            X86LirOperands operands;
            operands.a = inline_info.return_value;
            operands.b = 0u;
            operands.c = 0u;
            operands.metadata = source.type_id & 0xffu;
            target_lir_core[page_row] = core;
            target_lir_operands[page_row] = operands;
            target_semantic_origin[page_row] = semantic_row;
            target_lir_flags[page_row] = 0u;
            return;
        }
        uint cloned_row = inline_body_semantic_row(inline_info, inline_row,
            semantic_count);
        if (cloned_row >= semantic_count)
        {
            X86LirCore invalid_core;
            invalid_core.source_hir = source_hir;
            invalid_core.local_ordinal = inline_row;
            invalid_core.op = X86_LIR_OP_INLINE_RESULT;
            invalid_core.result_or_target = INVALID;
            X86LirOperands invalid_operands;
            invalid_operands.a = inline_info.body_row_count;
            invalid_operands.b = inline_info.schedule_start;
            invalid_operands.c = inline_info.schedule_end;
            invalid_operands.metadata = 0u;
            target_lir_core[page_row] = invalid_core;
            target_lir_operands[page_row] = invalid_operands;
            target_semantic_origin[page_row] = semantic_row;
            target_lir_flags[page_row] = TARGET_LIR_FLAG_UNSUPPORTED;
            return;
        }
        semantic_row = cloned_row;
        // Keep the target instruction attributed to the call site.  Its
        // callee-side value identity remains available independently through
        // target_semantic_origin, which location resolution consumes below.
        // Machine-function layout must use the containing caller, not a
        // removed standalone copy of the callee.
        source = opt_ir_core[semantic_row];
        args = opt_ir_operands[semantic_row];
        target_start = row;
        local_row = 0u;
        argument_rows = 0u;
        call_result_words = 0u;
        inline_clone = true;
        semantic_to_target_start[semantic_row] = row;
    }

    uint operation_row = local_row - argument_rows;
    bool packed_i32_array = direct_packed_i32_array(
        semantic_row, semantic_count);
    if (call_result_words != 0u && operation_row != 0u)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row - 1u;
        core.op = X86_LIR_OP_AGGREGATE_RESULT_SLOT;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = target_start + argument_rows;
        operands.b = operation_row - 1u;
        operands.c = call_result_words;
        operands.metadata = source.type_id;
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = 0u;
        return;
    }
    uint owner = semantic_function_id_by_hir[opt_ir_source_hir[semantic_row]];
    uint return_words = opt_ir_op(source) == SEMANTIC_LIR_OP_RETURN && owner < function_count
        ? semantic_lir_functions[owner].result_type == SEMANTIC_LIR_TY_STRING
            ? 2u : semantic_lir_functions[owner].result_word_count
        : 0u;
    if (return_words != 0u && operation_row < return_words)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row;
        core.op = X86_LIR_OP_AGGREGATE_RETURN_WORD;
        core.result_or_target = INVALID;
        X86LirOperands operands;
        operands.a = args.a;
        operands.b = operation_row;
        operands.c = return_words;
        operands.metadata = source.type_id >= 128u
            ? SEMANTIC_LIR_TY_POINTER | X86_LIR_METADATA_AGGREGATE
            : source.type_id;
        if (args.a < gParams.semantic_capacity &&
            x86_direct_array_pair(opt_ir_core[args.a]))
            operands.metadata |= X86_LIR_METADATA_ARRAY_PAIR;
        if (packed_i32_array_source(args.a, semantic_count))
            operands.metadata |= X86_LIR_METADATA_PACKED_I32_ARRAY;
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = args.a < gParams.semantic_capacity
            ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    if (opt_ir_op(source) == SEMANTIC_LIR_OP_AGGREGATE_COPY)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row == 0u ? 0u : operation_row - 1u;
        core.op = operation_row == 0u ? X86_LIR_OP_AGGREGATE_ADDR
            : X86_LIR_OP_AGGREGATE_COPY_WORD;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = args.a;
        operands.b = operation_row == 0u ? 0u : operation_row - 1u;
        operands.c = source.value_word_count;
        bool descriptor = (source.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u;
        bool packed_destination = source.type_id == 131u && !descriptor &&
            (source.flags & SEMANTIC_LIR_FLAG_NATIVE_PLACE) == 0u;
        bool packed_source = packed_i32_array_source(args.a, semantic_count) ||
            (args.a < semantic_count &&
             opt_ir_core[args.a].type_id == 131u &&
             x86_direct_array_pair(opt_ir_core[args.a]));
        operands.metadata = source.type_id |
            (packed_destination ? X86_LIR_METADATA_PACKED_I32_ARRAY : 0u) |
            (packed_destination && !packed_source ? X86_LIR_METADATA_AGGREGATE : 0u);
        bool view = descriptor && (source.flags & SEMANTIC_LIR_FLAG_PLACE_VIEW) != 0u &&
            args.a < semantic_count;
        bool valid_view = true;
        if (operation_row != 0u && view)
        {
            // Array-to-slice view: the array's aggregate address, then its
            // static element count and element stride, as for slice fields.
            uint word = operation_row - 1u;
            uint length = semantic_lir_layout_word_offset[semantic_row];
            core.op = X86_LIR_OP_AGGREGATE_INIT;
            operands.a = args.a;
            operands.b = word;
            operands.metadata = SEMANTIC_LIR_TY_POINTER;
            if (word == NATIVE_SLICE_LENGTH)
            {
                operands.a = length;
                operands.metadata |= X86_LIR_METADATA_IMMEDIATE;
            }
            else if (word == NATIVE_SLICE_STRIDE)
            {
                OptIrNodeCore value = opt_ir_core[args.a];
                uint stride = 0u;
                valid_view = x86_fixed_array_stride(x86_array_storage_kind(value,
                        direct_packed_i32_array(args.a, semantic_count)),
                    x86_aggregate_value_word_count(value, opt_ir_operands[args.a]),
                    length, stride);
                operands.a = stride;
                operands.metadata |= X86_LIR_METADATA_IMMEDIATE | X86_LIR_METADATA_ARRAY_PAIR;
            }
        }
        else if (operation_row != 0u && descriptor && args.a < semantic_count &&
            x86_direct_array_pair(opt_ir_core[args.a]))
        {
            // VALUE_GET exposes direct descriptor slots; projections and
            // call results expose an address to three native descriptor words.
            core.op = X86_LIR_OP_AGGREGATE_INIT;
            operands.metadata = SEMANTIC_LIR_TY_POINTER | X86_LIR_METADATA_ARRAY_PAIR;
        }
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = args.a < semantic_count && valid_view &&
            operation_row <= source.value_word_count ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    uint op = x86_lir_opcode(source);
    uint copy_words = 0u;
    bool zero_source = false;
    bool store_array_pair = false;
    bool store_direct_array_pair = false;
    // Match count.slang: only declaration stores expand into aggregate-copy
    // rows. In a field/index STORE, args.b is not the stored value.
    if (x86_lir_opcode(source) == X86_LIR_OP_STORE_LOCAL &&
        args.b < semantic_count)
    {
        OptIrNodeCore value_core = opt_ir_core[args.b];
        OptIrNodeOperands value_operands = opt_ir_operands[args.b];
        store_array_pair =
            (value_core.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u ||
            (opt_ir_op(value_core) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
             intrinsic_slice_from_raw_parts(value_operands.a));
        store_direct_array_pair = x86_direct_array_pair(value_core);
        uint call_words = opt_ir_op(value_core) == SEMANTIC_LIR_OP_CALL &&
            value_operands.a < function_count
            ? semantic_lir_functions[value_operands.a].result_word_count : 0u;
        uint value_words = max(call_words,
            x86_aggregate_value_word_count(value_core, value_operands));
        if (!store_direct_array_pair &&
            (x86_semantic_type_is_aggregate(source) || value_words != 0u))
            copy_words = max(source.value_word_count, value_words);
        zero_source = copy_words != 0u && x86_zero_aggregate(value_core, value_operands);
    }
    uint index_copy_words = 0u;
    bool index_direct_array_pair = false;
    if (op == X86_LIR_OP_INDEX_STORE &&
        x86_semantic_type_is_aggregate(source) && args.c < semantic_count)
    {
        OptIrNodeCore value_core = opt_ir_core[args.c];
        OptIrNodeOperands value_operands = opt_ir_operands[args.c];
        uint call_words = opt_ir_op(value_core) == SEMANTIC_LIR_OP_CALL &&
            value_operands.a < function_count
            ? semantic_lir_functions[value_operands.a].result_word_count : 0u;
        index_direct_array_pair = x86_direct_array_pair(value_core);
        if (!index_direct_array_pair)
            index_copy_words = max(source.value_word_count,
                max(call_words, x86_aggregate_value_word_count(
                    value_core, value_operands)));
    }
    if (zero_source && operation_row != 0u)
    {
        // The source is all zero: zero the destination's storage in place.
        write_fill(page_row, row, semantic_row, source_hir, copy_words,
            operation_row == 1u);
        return;
    }
    if (copy_words != 0u && operation_row != 0u)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row - 1u;
        core.op = X86_LIR_OP_AGGREGATE_COPY_WORD;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = args.b;
        operands.b = operation_row - 1u;
        operands.c = copy_words;
        bool packed_destination = !store_array_pair && source.type_id == 131u;
        bool packed_source = packed_i32_array_source(args.b, semantic_count);
        operands.metadata = source.type_id |
            (packed_destination || packed_source ? X86_LIR_METADATA_PACKED_I32_ARRAY : 0u) |
            (packed_destination && !packed_source ? X86_LIR_METADATA_AGGREGATE : 0u);
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = args.b < gParams.semantic_capacity &&
            operation_row <= copy_words ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    if (x86_zero_aggregate(source, args) && operation_row != 0u)
    {
        write_fill(page_row, row, semantic_row, source_hir,
            source.value_word_count, operation_row == 1u);
        return;
    }
    if (opt_ir_op(source) == SEMANTIC_LIR_OP_AGGREGATE_NEW && operation_row != 0u)
    {
        uint word = operation_row - 1u;
        bool enum_discriminant =
            (args.c & SEMANTIC_LIR_AGGREGATE_ENUM) != 0u && word == 0u;
        bool enum_padding =
            (args.c & SEMANTIC_LIR_AGGREGATE_ENUM) != 0u && word != 0u;
        SemanticLirAggregateElement element;
        element.aggregate_instruction = INVALID;
        element.value_instruction = INVALID;
        element.ordinal = INVALID;
        element.name_token = INVALID;
        element.value_metadata = 0u;
        element.word_offset = INVALID;
        element.word_count = 0u;
        element.slice_array_length = INVALID;
        uint element_total = semantic_lir_aggregate_element_total[0u];
        // `[value; count]`: every element is the one value element. Word
        // `word` is word `word % width` of the element starting at
        // `word - word % width`.
        bool repeat = args.c == SEMANTIC_LIR_AGGREGATE_REPEAT;
        if (repeat && args.b == 1u && args.a < element_total)
        {
            SemanticLirAggregateElement value_element = semantic_lir_aggregate_elements[args.a];
            if (value_element.word_offset == 0u && value_element.word_count != 0u &&
                value_element.word_count != INVALID)
            {
                element = value_element;
                element.word_offset = word - word % value_element.word_count;
            }
        }
        for (uint element_i = 0u; !repeat && element_i < args.b; element_i += 1u)
        {
            uint element_row = args.a + element_i;
            if (element_row < args.a || element_row >= element_total)
            {
                enum_padding = false;
                break;
            }
            SemanticLirAggregateElement candidate =
                semantic_lir_aggregate_elements[element_row];
            // Tagged-union padding is only valid after all payload words.
            // A malformed element range or a gap before a later element must
            // still fail closed instead of being silently zero-filled.
            if (candidate.aggregate_instruction != semantic_row ||
                candidate.word_offset == INVALID ||
                candidate.word_count == INVALID ||
                candidate.word_offset > INVALID - candidate.word_count ||
                candidate.word_offset + candidate.word_count > word)
                enum_padding = false;
            if (word >= candidate.word_offset &&
                word - candidate.word_offset < candidate.word_count)
            {
                element = candidate;
                break;
            }
        }
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row;
        core.op = X86_LIR_OP_AGGREGATE_INIT;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = element.value_instruction;
        operands.b = word - element.word_offset;
        operands.c = packed_i32_array
            ? source.value_word_count : target_start + 1u + word;
        bool valid_view_storage = true;
        uint element_type = element.value_instruction <
            gParams.semantic_capacity
                ? opt_ir_core[element.value_instruction].type_id
                : source.type_id;
        bool aggregate_value =
            (element.value_metadata & SEMANTIC_LIR_VALUE_AGGREGATE) != 0u;
        if (element.value_instruction < gParams.semantic_capacity)
        {
            OptIrNodeCore value = opt_ir_core[element.value_instruction];
            OptIrNodeOperands value_operands =
                opt_ir_operands[element.value_instruction];
            // A checked call can return an aggregate even when its HIR
            // expression reference has no nominal type payload. Use the
            // resolved callee's result ABI to copy from the returned address.
            // Other producers' value_word_count can describe a containing
            // aggregate rather than this scalar element, so do not use it
            // to classify every struct/array initializer.
            aggregate_value |= opt_ir_op(value) == SEMANTIC_LIR_OP_AGGREGATE_NEW &&
                value.value_word_count != 0u;
            aggregate_value |= opt_ir_op(value) == SEMANTIC_LIR_OP_CALL &&
                value_operands.a < function_count &&
                semantic_lir_functions[value_operands.a].result_word_count != 0u;
            // A raw-parts slice intrinsic returns three descriptor words
            // in aggregate storage. A struct field must copy all components,
            // not store the address of that pair in each field word.
            aggregate_value |= opt_ir_op(value) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
                intrinsic_slice_from_raw_parts(value_operands.a);
        }
        operands.metadata = element_type |
            (aggregate_value
                ? X86_LIR_METADATA_AGGREGATE : 0u) |
            (packed_i32_array
                ? X86_LIR_METADATA_PACKED_I32_ARRAY : 0u);
        // Inline array fields use native words. Copy a packed local source
        // element by element into that existing representation.
        if (aggregate_value && packed_i32_array_source(element.value_instruction, semantic_count))
            operands.metadata |= X86_LIR_METADATA_PACKED_I32_ARRAY;
        if ((element.value_metadata & SEMANTIC_LIR_VALUE_STRING) != 0u)
        {
            // Strings use direct adjacent value slots. Copy their descriptor
            // components rather than dereferencing the text bytes.
            operands.metadata &= ~X86_LIR_METADATA_AGGREGATE;
            operands.metadata |= X86_LIR_METADATA_STRING_PAIR;
        }
        if (element.value_instruction < gParams.semantic_capacity)
        {
            OptIrNodeCore value = opt_ir_core[element.value_instruction];
            if (x86_direct_array_pair(value))
                operands.metadata |= X86_LIR_METADATA_ARRAY_PAIR;
        }
        if (element.slice_array_length != INVALID)
        {
            // A fixed array is an aggregate address; a slice field stores
            // that address followed by the array's static element count.
            operands.metadata = SEMANTIC_LIR_TY_POINTER;
            if (operands.b == NATIVE_SLICE_LENGTH)
            {
                operands.a = element.slice_array_length;
                operands.metadata |= X86_LIR_METADATA_IMMEDIATE;
            }
            else if (operands.b == NATIVE_SLICE_STRIDE)
            {
                OptIrNodeCore value = opt_ir_core[element.value_instruction];
                uint stride = 0u;
                if (!x86_fixed_array_stride(x86_array_storage_kind(value,
                        direct_packed_i32_array(element.value_instruction, semantic_count)),
                        x86_aggregate_value_word_count(value, opt_ir_operands[element.value_instruction]),
                        element.slice_array_length, stride))
                    valid_view_storage = false;
                operands.a = stride;
                operands.metadata |= X86_LIR_METADATA_IMMEDIATE | X86_LIR_METADATA_ARRAY_PAIR;
            }
        }
        if (enum_discriminant)
        {
            operands.a = args.c & SEMANTIC_LIR_AGGREGATE_TAG_MASK;
            operands.b = 0u;
            operands.metadata = source.type_id | X86_LIR_METADATA_IMMEDIATE;
        }
        else if (enum_padding && element.aggregate_instruction == INVALID)
        {
            operands.a = 0u;
            operands.b = 0u;
            operands.metadata = source.type_id | X86_LIR_METADATA_IMMEDIATE;
        }
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = enum_discriminant ||
            (enum_padding && element.aggregate_instruction == INVALID) ? 0u :
            valid_view_storage && element.aggregate_instruction == semantic_row &&
            element.value_instruction < gParams.semantic_capacity &&
            element.word_offset != INVALID && word >= element.word_offset &&
            word - element.word_offset < element.word_count
                ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    if (opt_ir_op(source) == SEMANTIC_LIR_OP_CONST_STRING)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row;
        core.op = operation_row == 0u ? X86_LIR_OP_STRING_ADDR : X86_LIR_OP_STRING_LEN;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = args.a;
        operands.b = 0u;
        operands.c = 0u;
        operands.metadata = source.type_id;
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = args.a < semantic_lir_string_total[0u]
            ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    if (opt_ir_op(source) == SEMANTIC_LIR_OP_VALUE_GET &&
        source.type_id == SEMANTIC_LIR_TY_STRING)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row;
        core.op = X86_LIR_OP_ALIAS;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = args.a;
        operands.b = 0u;
        operands.c = operation_row;
        operands.metadata = source.type_id | X86_LIR_METADATA_STRING_PAIR |
            (operation_row == 1u ? X86_LIR_METADATA_STRING_LEN : 0u);
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = operation_row < 2u
            ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    if (opt_ir_op(source) == SEMANTIC_LIR_OP_VALUE_GET &&
        (source.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row;
        core.op = X86_LIR_OP_ALIAS;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = args.a;
        operands.b = 0u;
        operands.c = operation_row;
        operands.metadata = source.type_id | X86_LIR_METADATA_ARRAY_PAIR |
            (operation_row == 1u ? X86_LIR_METADATA_ARRAY_LEN
                                 : X86_LIR_METADATA_WIDE);
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = operation_row < NATIVE_SLICE_WORDS
            ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    uint result = args.result;
    uint a = args.a;
    uint b = args.b;
    uint c = args.c;
    uint local_ordinal = 0u;
    uint flags = x86_lir_supported(source) ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
    if ((source.flags & (SEMANTIC_LIR_FLAG_UNSUPPORTED |
                         SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE)) != 0u)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if ((opt_ir_op(source) == SEMANTIC_LIR_OP_VALUE_SET ||
         opt_ir_op(source) == SEMANTIC_LIR_OP_STORE) &&
        x86_semantic_type_is_aggregate(source) &&
        source.value_word_count != 0u && copy_words == 0u &&
        !store_direct_array_pair &&
        !index_direct_array_pair &&
        x86_lir_opcode(source) != X86_LIR_OP_FIELD_STORE &&
        index_copy_words == 0u)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if (op == X86_LIR_OP_INDEX_STORE &&
        x86_semantic_type_is_aggregate(source) &&
        !index_direct_array_pair &&
        ((index_copy_words == 0u && source.value_word_count != 0u) ||
         index_copy_words > 0x0fffffffu))
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if (opt_ir_op(source) == SEMANTIC_LIR_OP_CALL_HOST &&
        (args.a == HOST_SERVICE_I32_TO_F32 || x86_runtime_service_supported(args.a)))
        flags = 0u;
    if (opt_ir_op(source) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
        // 1 is print and 2 is assert; remaining tags below are view helpers.
        args.a != 1u && args.a != 2u &&
        args.a != INTRINSIC_I32_ARRAY_DATA_PTR &&
        args.a != INTRINSIC_I32_SLICE_DATA_PTR &&
        args.a != INTRINSIC_STRING_DATA_PTR &&
        args.a != INTRINSIC_SLICE_STRIDE &&
        !intrinsic_slice_from_raw_parts(args.a))
        flags = TARGET_LIR_FLAG_UNSUPPORTED;
    // Imported calls can carry a canonical aggregate width after their
    // nominal type reference has been compacted away. Scalar call rows may
    // also carry an enclosing aggregate's width, so retain the scalar type
    // classification before using that width as a result-shape fallback.
    bool imported_aggregate_result = op == X86_LIR_OP_CALL_SYMBOL &&
        x86_imported_call_result_words(source) != 0u;
    bool local_aggregate_result = op == X86_LIR_OP_CALL &&
        call_result_words != 0u;
    uint metadata = (source.type_id >= 128u ? SEMANTIC_LIR_TY_POINTER
        : source.type_id & 0xffu) | ((source.flags & ~(SEMANTIC_LIR_FLAG_NATIVE_PLACE |
            SEMANTIC_LIR_FLAG_PLACE_VIEW | SEMANTIC_LIR_FLAG_ARRAY_PAIR |
            SEMANTIC_LIR_FLAG_NATIVE_C_CALL)) << 8u) |
        ((source.flags & SEMANTIC_LIR_FLAG_NATIVE_C_CALL) != 0u ? X86_LIR_METADATA_NATIVE_C : 0u) |
        (x86_semantic_type_is_aggregate(source) || copy_words != 0u ||
         imported_aggregate_result || local_aggregate_result
            ? X86_LIR_METADATA_AGGREGATE : 0u);
    // Alias width follows the checked type/pair metadata. Narrow local stores
    // initialize four bytes even though their stack homes occupy eight bytes.
    // Preserve full width for still-unclassified aggregate aliases.
    if (opt_ir_op(source) == SEMANTIC_LIR_OP_VALUE_GET && source.type_id == 0u)
        metadata |= X86_LIR_METADATA_WIDE;
    if ((opt_ir_op(source) == SEMANTIC_LIR_OP_VALUE_SET ||
         opt_ir_op(source) == SEMANTIC_LIR_OP_STORE) &&
        source.type_id == SEMANTIC_LIR_TY_STRING)
        metadata |= X86_LIR_METADATA_STRING_PAIR;
    if (store_array_pair)
    {
        metadata = (metadata & ~X86_LIR_METADATA_AGGREGATE) | X86_LIR_METADATA_ARRAY_PAIR;
        if (!store_direct_array_pair) metadata |= X86_LIR_METADATA_INDIRECT_ARRAY_PAIR;
    }
    if (index_copy_words != 0u || (op == X86_LIR_OP_INDEX_STORE &&
        source.value_word_count == 0u && x86_semantic_type_is_aggregate(source) &&
        !index_direct_array_pair))
        metadata |= X86_LIR_METADATA_INDEX_AGGREGATE_COPY;
    if (index_direct_array_pair)
        metadata = (metadata & ~(X86_LIR_METADATA_AGGREGATE | 0xffu)) |
            SEMANTIC_LIR_TY_POINTER | X86_LIR_METADATA_ARRAY_PAIR;
    if ((op == X86_LIR_OP_INDEX_LOAD || op == X86_LIR_OP_INDEX_STORE || op == X86_LIR_OP_INDEX_ADDRESS) &&
        semantic_lir_layout_word_offset[semantic_row] ==
            SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME && args.a < semantic_count)
    {
        OptIrNodeCore base = opt_ir_core[args.a];
        // VALUE_GET of a slice reads the direct declaration pair. Other
        // slice-producing expressions yield an address of pair storage.
        if (!x86_direct_array_pair(base))
            metadata |= X86_LIR_METADATA_INDIRECT_ARRAY_PAIR;
    }

    bool select_store =
        x86_live_by_semantic[semantic_row] == X86_SEMANTIC_SELECT;
    uint propagated_value = 0u;
    bool propagated_constant = direct_i32_constant(
        semantic_row, semantic_count, propagated_value);
    if (select_store)
    {
        X86SelectInfo info = x86_select_by_semantic[semantic_row];
        if (info.condition >= semantic_count ||
            info.true_value >= semantic_count ||
            info.declaration == INVALID)
        {
            flags |= TARGET_LIR_FLAG_UNSUPPORTED;
        }
        else
        {
            OptIrNodeCore compare_core = opt_ir_core[info.condition];
            OptIrNodeOperands compare = opt_ir_operands[info.condition];
            bool aggregate_compare = x86_semantic_type_is_aggregate(compare_core);
            if (aggregate_compare &&
                (compare_core.value_word_count > 1u ||
                 !single_word_compare_operands(compare.a, compare.b,
                     semantic_count)))
                flags |= TARGET_LIR_FLAG_UNSUPPORTED;
            uint left = 0u;
            uint immediate = 0u;
            bool left_constant = direct_i32_constant(
                compare.a, semantic_count, left);
            bool right_constant = direct_i32_constant(
                compare.b, semantic_count, immediate);
            bool immediate_compare = !aggregate_compare &&
                (right_constant || left_constant) &&
                x86_integer_immediate_operation(
                    SEMANTIC_LIR_OP_COMPARE, compare_core.type_id,
                    right_constant ? immediate : left);
            op = X86_LIR_OP_SELECT_STORE;
            result = info.declaration;
            a = immediate_compare && left_constant
                ? compare.b : compare.a;
            b = immediate_compare
                ? (right_constant ? immediate : left) : compare.b;
            c = info.true_value;
            metadata = (compare_core.type_id & 0xffu) |
                (aggregate_compare ? X86_LIR_METADATA_AGGREGATE : 0u);
            if (immediate_compare)
                metadata |= X86_LIR_METADATA_IMMEDIATE;
            local_ordinal = immediate_compare && left_constant
                ? x86_swapped_compare_predicate(compare.c) : compare.c;
        }
    }
    else if (propagated_constant)
    {
        op = X86_LIR_OP_IMM_I32;
        a = propagated_value;
        b = 0u;
        c = 0u;
    }
    else if (opt_ir_op(source) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
             (args.a == INTRINSIC_I32_ARRAY_DATA_PTR ||
              args.a == INTRINSIC_I32_SLICE_DATA_PTR ||
              args.a == INTRINSIC_STRING_DATA_PTR ||
              args.a == INTRINSIC_SLICE_STRIDE))
    {
        // The argument's words arrive in RDI, RSI and RDX. The data
        // pointers are the first word; a view's byte stride is the third,
        // which operand a = 2 selects.
        op = X86_LIR_OP_INTRINSIC_IDENTITY;
        a = args.a == INTRINSIC_SLICE_STRIDE ? 2u : 0u; b = 0u; c = 0u;
    }
    else if (opt_ir_op(source) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
             intrinsic_slice_from_raw_parts(args.a))
    {
        op = X86_LIR_OP_INTRINSIC_SLICE_FROM_RAW_PARTS;
        a = semantic_lir_layout_word_offset[semantic_row]; b = 0u; c = NATIVE_SLICE_WORDS;
        if (a == INVALID) flags |= TARGET_LIR_FLAG_UNSUPPORTED;
        metadata |= X86_LIR_METADATA_AGGREGATE |
            X86_LIR_METADATA_ARRAY_PAIR;
    }
    else if (op == X86_LIR_OP_AGGREGATE_ADDR)
    {
        a = target_start + 1u;
        b = args.b;
        c = packed_i32_array ? source.value_word_count : 0u;
        if (packed_i32_array)
            metadata |= X86_LIR_METADATA_PACKED_I32_ARRAY;
    }
    else if (op == X86_LIR_OP_DECL_ADDRESS)
    {
        // Only the checked declaration identity crosses this operand edge.
        a = args.a; b = 0u; c = 0u;
        metadata = SEMANTIC_LIR_TY_POINTER | X86_LIR_METADATA_WIDE;
    }
    else if (op == X86_LIR_OP_FIELD_ADDRESS)
    {
        a = args.a; b = semantic_lir_layout_word_offset[semantic_row]; c = 0u;
        metadata = SEMANTIC_LIR_TY_POINTER | X86_LIR_METADATA_WIDE;
        if (b == INVALID) flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    }
    else if (op == X86_LIR_OP_PLACE_LOAD || op == X86_LIR_OP_PLACE_STORE)
    {
        a = args.a; b = args.b; c = source.value_word_count;
        // Target metadata cannot retain semantic flags by shifting them:
        // NATIVE_PLACE overlaps existing target metadata. Publish only shape.
        metadata = (source.type_id >= 128u ? SEMANTIC_LIR_TY_POINTER : source.type_id & 0xffu);
        if ((source.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u)
            metadata |= X86_LIR_METADATA_ARRAY_PAIR;
        else if (source.type_id == SEMANTIC_LIR_TY_STRING)
            metadata |= X86_LIR_METADATA_STRING_PAIR;
        else if (x86_semantic_type_is_aggregate(source))
            metadata |= X86_LIR_METADATA_AGGREGATE;
        if (op == X86_LIR_OP_PLACE_STORE && b < semantic_count)
        {
            if ((metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u &&
                !x86_direct_array_pair(opt_ir_core[b]))
                metadata |= X86_LIR_METADATA_INDIRECT_ARRAY_PAIR;
            // An unpromoted fixed i32-array parameter keeps its by-value
            // packed backing behind direct descriptor slots. Its slot zero
            // is already the data pointer, but the copy still needs +4 reads.
            // Checked owned-aggregate stores cannot take a runtime slice;
            // slice assignment uses the descriptor branch above instead.
            if ((metadata & X86_LIR_METADATA_AGGREGATE) != 0u &&
                (packed_i32_array_source(b, semantic_count) ||
                 (opt_ir_core[b].type_id == 131u &&
                  x86_direct_array_pair(opt_ir_core[b]))))
                metadata |= X86_LIR_METADATA_PACKED_I32_ARRAY;
        }
        if (c == INVALID || c > 0x0fffffffu) flags |= TARGET_LIR_FLAG_UNSUPPORTED;
        if (op == X86_LIR_OP_PLACE_LOAD && (source.flags & SEMANTIC_LIR_FLAG_PLACE_VIEW) != 0u &&
            (metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        {
            op = X86_LIR_OP_FIELD_ADDRESS; b = 0u; c = 0u;
            metadata = SEMANTIC_LIR_TY_POINTER | X86_LIR_METADATA_WIDE;
        }
    }
    else if (op == X86_LIR_OP_INDEX_LOAD || op == X86_LIR_OP_INDEX_ADDRESS)
    {
        a = args.a;
        b = args.b;
        c = op == X86_LIR_OP_INDEX_ADDRESS ? source.value_word_count :
            x86_semantic_type_is_aggregate(source)
            ? source.value_word_count : max(source.value_word_count, 1u);
        if ((source.type_id == 3u || op == X86_LIR_OP_INDEX_ADDRESS) &&
            (packed_i32_array_source(args.a, semantic_count) ||
             semantic_lir_layout_word_offset[semantic_row] == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME))
            metadata |= X86_LIR_METADATA_PACKED_I32_ARRAY;
    }
    else if (op == X86_LIR_OP_FIELD_LOAD)
    {
        a = args.a;
        b = semantic_lir_layout_word_offset[semantic_row];
        c = args.c;
        if (a < semantic_count && b <= 1u &&
            x86_direct_array_pair(opt_ir_core[a]))
        {
            // A direct slice value already occupies adjacent value slots.
            // Its descriptor fields must not dereference the data pointer.
            op = X86_LIR_OP_INLINE_RESULT;
            metadata &= ~X86_LIR_METADATA_AGGREGATE;
            metadata |= b == 1u ? X86_LIR_METADATA_ARRAY_LEN
                               : X86_LIR_METADATA_WIDE;
        }
        if (source.type_id == SEMANTIC_LIR_TY_STRING)
        {
            b += operation_row;
            metadata |= X86_LIR_METADATA_STRING_PAIR;
            if (operation_row == 1u) metadata |= X86_LIR_METADATA_STRING_LEN;
        }
    }
    else if (op == X86_LIR_OP_INDEX_STORE)
    {
        a = args.a;
        b = args.b;
        c = args.c;
        // The checked lvalue element type selects packed i32 storage. A cast
        // expression can retain its input type on the value row even when its
        // result is u8; using that row would store at the wrong byte stride.
        if (index_copy_words == 0u && source.type_id == 3u &&
            (packed_i32_array_source(args.a, semantic_count) ||
             semantic_lir_layout_word_offset[semantic_row] == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME))
        {
            metadata = (metadata & 0xffffff00u) | 3u |
                X86_LIR_METADATA_PACKED_I32_ARRAY;
        }
    }
    else if (op == X86_LIR_OP_FIELD_STORE)
    {
        a = args.a;
        b = semantic_lir_layout_word_offset[semantic_row] + operation_row;
        c = args.c;
        local_ordinal = operation_row;
        bool aggregate_field =
            (metadata & X86_LIR_METADATA_AGGREGATE) != 0u;
        bool direct_field_pair = source.type_id == SEMANTIC_LIR_TY_STRING;
        if (args.c < semantic_count)
        {
            OptIrNodeCore field_value = opt_ir_core[args.c];
            OptIrNodeOperands field_operands = opt_ir_operands[args.c];
            if (x86_direct_array_pair(field_value))
            {
                direct_field_pair = true;
                metadata |= X86_LIR_METADATA_ARRAY_PAIR;
            }
            uint call_words = opt_ir_op(field_value) == SEMANTIC_LIR_OP_CALL &&
                field_operands.a < function_count
                ? semantic_lir_functions[field_operands.a].result_word_count : 0u;
            aggregate_field |= max(call_words,
                x86_aggregate_value_word_count(field_value,
                    field_operands)) != 0u;
        }
        metadata = (metadata & 0x00ffffffu) | (8u << 24u);
        if (direct_field_pair)
        {
            // The stride occupied this metadata byte before descriptor stores
            // were supported. Preserve the descriptor tag; FIELD_STORE always
            // addresses native eight-byte words regardless of those flags.
            metadata |= source.type_id == SEMANTIC_LIR_TY_STRING
                ? X86_LIR_METADATA_STRING_PAIR : X86_LIR_METADATA_ARRAY_PAIR;
            if (operation_row >= (source.type_id == SEMANTIC_LIR_TY_STRING ? 2u : NATIVE_SLICE_WORDS))
                flags |= TARGET_LIR_FLAG_UNSUPPORTED;
        }
        else if (aggregate_field)
        {
            metadata |= X86_LIR_METADATA_FIELD_AGGREGATE_WORD;
            if (packed_i32_array_source(args.c, semantic_count))
                metadata |= X86_LIR_METADATA_PACKED_I32_ARRAY;
        }
        else if (operation_row != 0u)
            flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    }
    else if (op == X86_LIR_OP_BINARY)
    {
        uint semantic_op = opt_ir_op(source);
        uint left = 0u;
        uint immediate = 0u;
        uint folded = 0u;
        c = args.b;
        b = args.a;
        a = x86_binary_payload(source);
        bool left_constant = direct_i32_constant(
            args.a, semantic_count, left);
        bool right_constant = direct_i32_constant(
            args.b, semantic_count, immediate);
        if (left_constant && right_constant &&
            x86_fold_integer_binary(semantic_op, source.type_id, args.c,
                left, immediate, folded))
        {
            op = X86_LIR_OP_IMM_I32;
            a = folded;
            b = 0u;
            c = 0u;
        }
        uint divisor_kind = op != X86_LIR_OP_IMM_I32 && right_constant
                ? x86_constant_divisor_kind(
                    semantic_op, source.type_id, immediate)
                : X86_CONSTANT_DIVISOR_NONE;
        if (divisor_kind == X86_CONSTANT_DIVISOR_POWER_OF_TWO)
        {
            a = semantic_op == SEMANTIC_LIR_OP_DIV
                ? X86_LIR_BINARY_DIV_CONST_POW2_I32
                : X86_LIR_BINARY_REM_CONST_POW2_I32;
            c = immediate;
        }
        else if (divisor_kind == X86_CONSTANT_DIVISOR_SIGNED)
        {
            a = semantic_op == SEMANTIC_LIR_OP_DIV
                ? X86_LIR_BINARY_DIV_CONST_I32
                : X86_LIR_BINARY_REM_CONST_I32;
            c = immediate;
        }
        else if (op != X86_LIR_OP_IMM_I32 &&
                 ((right_constant && x86_integer_immediate_operation(
                     semantic_op, source.type_id, immediate)) ||
                  (left_constant &&
                   x86_integer_immediate_commutative(semantic_op) &&
                   x86_integer_immediate_operation(
                       semantic_op, source.type_id, left))))
        {
            bool swap = !right_constant;
            b = swap ? args.b : args.a;
            c = swap ? left : immediate;
            metadata |= X86_LIR_METADATA_IMMEDIATE;
        }
    }
    else if (op == X86_LIR_OP_COMPARE)
    {
        bool aggregate_compare = x86_semantic_type_is_aggregate(source);
        if (aggregate_compare &&
            (source.value_word_count > 1u ||
             !single_word_compare_operands(args.a, args.b, semantic_count)))
            flags |= TARGET_LIR_FLAG_UNSUPPORTED;
        c = args.b; b = args.a; a = args.c;
        uint left = 0u;
        uint immediate = 0u;
        uint folded = 0u;
        bool left_constant = direct_i32_constant(
            args.a, semantic_count, left);
        bool right_constant = direct_i32_constant(
            args.b, semantic_count, immediate);
        if (!aggregate_compare && left_constant && right_constant &&
            x86_fold_integer_binary(SEMANTIC_LIR_OP_COMPARE, source.type_id,
                args.c, left, immediate, folded))
        {
            op = X86_LIR_OP_IMM_I32;
            a = folded;
            b = 0u;
            c = 0u;
        }
        else if (!aggregate_compare && (right_constant || left_constant) &&
            x86_integer_immediate_operation(
                SEMANTIC_LIR_OP_COMPARE, source.type_id,
                right_constant ? immediate : left))
        {
            bool swap = !right_constant;
            a = swap ? x86_swapped_compare_predicate(args.c) : args.c;
            b = swap ? args.b : args.a;
            c = swap ? left : immediate;
            metadata |= X86_LIR_METADATA_IMMEDIATE;
        }
        if (source.type_id == SEMANTIC_LIR_TY_POINTER && args.b < gParams.semantic_capacity &&
            !scalar_uses_64bit_gpr(opt_ir_core[args.b].type_id))
            metadata |= X86_LIR_METADATA_RHS_NARROW;
    }
    else if (op == X86_LIR_OP_UNARY)
    {
        uint folded;
        uint input;
        if (direct_i32_constant(args.a, semantic_count, input) &&
            x86_fold_integer_unary(
                opt_ir_op(source), source.type_id, input, folded))
        {
            op = X86_LIR_OP_IMM_I32;
            a = folded; b = 0u; c = 0u;
        }
        else
        {
            bool convert = opt_ir_op(source) == SEMANTIC_LIR_OP_CONVERT;
            a = opt_ir_op(source) == SEMANTIC_LIR_OP_LOGICAL_NOT ? X86_LIR_UNARY_NOT_BOOL
                : convert ? X86_LIR_UNARY_CONVERT
                : scalar_is_float(source.type_id) ? X86_LIR_UNARY_NEG_FLOAT
                : X86_LIR_UNARY_NEG_I32;
            // A conversion's semantic metadata operand is its source's
            // checked scalar type. Locations never read operand c of UNARY.
            b = args.a; c = convert ? args.b : 0u;
            if (convert && !x86_convert_supported(c, source.type_id))
                flags |= TARGET_LIR_FLAG_UNSUPPORTED;
        }
    }
    else if (op == X86_LIR_OP_RETURN)
    {
        result = INVALID; a = return_words == 0u ? args.a : INVALID;
        b = 0u; c = return_words;
        if (a == INVALID) op = X86_LIR_OP_RETURN_VOID;
        if (return_words != 0u) op = X86_LIR_OP_RETURN;
    }
    else if (op == X86_LIR_OP_TRAP)
    {
        result = INVALID; a = INVALID; b = INVALID; c = INVALID;
    }
    else if (op == X86_LIR_OP_BRANCH)
    {
        result = INVALID;
        bool conditional = opt_ir_op(source) == SEMANTIC_LIR_OP_IF_BEGIN ||
            opt_ir_op(source) == SEMANTIC_LIR_OP_BRANCH_IF;
        uint condition = conditional ? args.a : INVALID;
        uint comparison = condition;
        if (x86_live_by_semantic[semantic_row] ==
            X86_SEMANTIC_COMPARE_ALIAS_BRANCH)
            comparison = x86_select_by_semantic[semantic_row].condition;
        bool fused_compare = comparison < semantic_count &&
            x86_live_by_semantic[comparison] == 0u &&
            opt_ir_op(opt_ir_core[comparison]) ==
                SEMANTIC_LIR_OP_COMPARE;
        if (fused_compare)
        {
            OptIrNodeCore compare_core = opt_ir_core[comparison];
            OptIrNodeOperands compare = opt_ir_operands[comparison];
            bool aggregate_compare = x86_semantic_type_is_aggregate(compare_core);
            if (aggregate_compare &&
                (compare_core.value_word_count > 1u ||
                 !single_word_compare_operands(compare.a, compare.b,
                     semantic_count)))
                flags |= TARGET_LIR_FLAG_UNSUPPORTED;
            uint left = 0u;
            uint immediate = 0u;
            bool left_constant = direct_i32_constant(
                compare.a, semantic_count, left);
            bool right_constant = direct_i32_constant(
                compare.b, semantic_count, immediate);
            bool immediate_compare = !aggregate_compare &&
                (right_constant || left_constant) &&
                x86_integer_immediate_operation(
                    SEMANTIC_LIR_OP_COMPARE, compare_core.type_id,
                    right_constant ? immediate : left);
            op = X86_LIR_OP_COMPARE_BRANCH_FALSE;
            a = immediate_compare && left_constant
                ? compare.b : compare.a;
            b = immediate_compare
                ? (right_constant ? immediate : left) : compare.b;
            c = opt_ir_op(source) == SEMANTIC_LIR_OP_IF_BEGIN
                ? args.c : 0u;
            metadata = (compare_core.type_id & 0xffu) |
                (aggregate_compare ? X86_LIR_METADATA_AGGREGATE : 0u);
            if (immediate_compare)
                metadata |= X86_LIR_METADATA_IMMEDIATE;
            local_ordinal = immediate_compare && left_constant
                ? x86_swapped_compare_predicate(compare.c) : compare.c;
            if (compare_core.type_id == SEMANTIC_LIR_TY_POINTER &&
                compare.b < semantic_count &&
                opt_ir_core[compare.b].type_id !=
                    SEMANTIC_LIR_TY_POINTER)
                metadata |= X86_LIR_METADATA_RHS_NARROW;
            result = opt_ir_op(source) == SEMANTIC_LIR_OP_IF_BEGIN
                ? args.b : args.c;
        }
        else if (opt_ir_op(source) == SEMANTIC_LIR_OP_IF_BEGIN) { a = args.a; b = args.b; c = args.c; }
        else if (opt_ir_op(source) == SEMANTIC_LIR_OP_BRANCH_IF) { a = args.a; b = args.c; c = 0u; }
        else { a = INVALID; b = args.a; c = 0u; }
    }
    else if (op == X86_LIR_OP_LABEL)
    {
        result = INVALID; a = 0u; b = 0u; c = 0u;
    }
    if (op == X86_LIR_OP_STORE_LOCAL && copy_words != 0u &&
        !store_array_pair && (source.type_id == 131u ||
            packed_i32_array_source(args.b, semantic_count)))
    {
        c = copy_words;
        metadata |= X86_LIR_METADATA_PACKED_I32_ARRAY;
    }
    if ((op == X86_LIR_OP_CALL || op == X86_LIR_OP_CALL_HOST ||
         op == X86_LIR_OP_PRINT_I32) && args.a == INVALID)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    // A local call's c is its result width, zero included: the emitter
    // passes a hidden result address above two words, and the default
    // (the semantic row's c) would make a three-argument call returning
    // an empty record look like one.
    if (op == X86_LIR_OP_CALL)
        c = call_result_words;
    if ((op == X86_LIR_OP_CALL || op == X86_LIR_OP_CALL_SYMBOL) &&
             call_result_words == 0u &&
             source.value_word_count != 0u &&
             (metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if ((op == X86_LIR_OP_BRANCH && b == INVALID) ||
        (op == X86_LIR_OP_COMPARE_BRANCH_FALSE && result == INVALID))
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;

    // RHS_NARROW describes the actual count/index operand, independent of
    // the operation result width. Guards inspect all64 bits when absent.
    uint checked_rhs = op == X86_LIR_OP_INDEX_LOAD || op == X86_LIR_OP_INDEX_STORE ||
        op == X86_LIR_OP_INDEX_ADDRESS ? args.b :
        op == X86_LIR_OP_BINARY && (opt_ir_op(source) == SEMANTIC_LIR_OP_SHIFT_LEFT ||
            opt_ir_op(source) == SEMANTIC_LIR_OP_SHIFT_RIGHT) ? args.b : INVALID;
    if (checked_rhs < semantic_count && !scalar_is_wide_integer(opt_ir_core[checked_rhs].type_id))
        metadata |= X86_LIR_METADATA_RHS_NARROW;
    X86LirCore core;
    core.source_hir = source_hir;
    uint stack_words = (source.flags & SEMANTIC_LIR_FLAG_NATIVE_C_CALL) != 0u
        ? native_c_stack_words(argument_start, argument_count)
        : argument_rows + (call_result_words > 2u ? 1u : 0u) > 6u
        ? argument_rows + (call_result_words > 2u ? 1u : 0u) - 6u : 0u;
    uint aligned_stack_words = (stack_words + 1u) & ~1u;
    core.local_ordinal = op == X86_LIR_OP_COMPARE_BRANCH_FALSE ||
        op == X86_LIR_OP_SELECT_STORE || op == X86_LIR_OP_FIELD_STORE
        ? local_ordinal
        : (op == X86_LIR_OP_INDEX_LOAD || op == X86_LIR_OP_INDEX_STORE || op == X86_LIR_OP_INDEX_ADDRESS)
        ? semantic_lir_layout_word_offset[semantic_row]
        : op == X86_LIR_OP_BINARY && source.type_id == SEMANTIC_LIR_TY_POINTER && args.b < semantic_count
        ? opt_ir_core[args.b].type_id
        : op == X86_LIR_OP_CALL_SYMBOL
        ? x86_symbol_call_layout(call_result_words, aligned_stack_words)
        : op == X86_LIR_OP_CALL && stack_words != 0u
        ? aligned_stack_words * 8u
        : 0u;
    core.op = op;
    if (op == X86_LIR_OP_CALL_SYMBOL &&
        (call_result_words > 0xffffu || aligned_stack_words > 0xffffu))
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    // `result` is a semantic instruction identity. The target stream may
    // have inserted CALL_ARG rows before this operation, so machine emission
    // must address the concrete target row for the result value and any
    // caller-owned aggregate storage derived from it.
    core.result_or_target = op == X86_LIR_OP_PLACE_STORE ? INVALID :
        (metadata & X86_LIR_METADATA_INDEX_AGGREGATE_COPY) != 0u
        ? index_copy_words
        : op == X86_LIR_OP_COMPARE_BRANCH_FALSE ||
        op == X86_LIR_OP_SELECT_STORE
        ? result : result == INVALID ? INVALID : row;
    X86LirOperands operands;
    operands.a = a;
    operands.b = b;
    operands.c = c;
    operands.metadata = metadata;
    target_lir_core[page_row] = core;
    target_lir_operands[page_row] = operands;
    target_semantic_origin[page_row] = semantic_row;
    target_lir_flags[page_row] = flags |
        (inline_clone ? TARGET_LIR_FLAG_INLINE_CLONE : 0u);
}
