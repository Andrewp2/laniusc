// Assigns value locations and spill widths for every scheduled OptIR node.
// Small functions use one invocation to linear-scan general-purpose registers
// over the values' [definition, last use] intervals; see walk_function. Large
// functions use independent, bounded schedule segments; see walk_segment.
// Both walks read each position's row facts from gather_x86_register_allocation_inputs.slang, so the
// serial loops wait on one record load per position. Between a small function's
// backward and forward passes, a position's stack-words word holds the
// distances (or, at a loop label, the farthest back-edge position) that the
// forward pass reads before it writes the position's spill width; prepare
// sets every word to INVALID first. The subsequent global
// prefix scan turns the spill widths into function-relative stack offsets.

#include "native_register_allocator.slang"

// Written only by the walks; gather_x86_register_allocation_inputs.slang does not bind them.
RWStructuredBuffer<uint> x86_location_by_semantic;
RWStructuredBuffer<uint> x86_saved_gpr_mask_by_function;

StructuredBuffer<X86AllocationPrepared> x86_allocation_prepared;
StructuredBuffer<uint2> x86_allocation_boundary_masks;

// The record at `position` when it lies in [start, end), otherwise one that no
// function owns. The walks load records two positions ahead of the one they
// process, so a load's latency overlaps the two steps before its use.
X86AllocationPrepared prepared_in(uint position, uint start, uint end)
{
    if (position >= start && position < end) return x86_allocation_prepared[position];
    X86AllocationPrepared none;
    none.row = INVALID;
    none.function_id = INVALID;
    none.flags = 0u;
    none.location = INVALID;
    none.last = 0u;
    none.home = INVALID;
    none.words = 0u;
    none.operand = INVALID;
    return none;
}

uint pending_in(uint position, uint end)
{
    return position < end ? x86_stack_words_by_position[position] : INVALID;
}

void walk_function(uint function_id, uint start, uint end, uint total)
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
    X86AllocationPrepared ahead1 = prepared_in(end - 1u, start, end);
    X86AllocationPrepared ahead2 = prepared_in(end - 2u, start, end);
    for (uint cursor = end; cursor > start; )
    {
        cursor -= 1u;
        X86AllocationPrepared prepared = ahead1;
        ahead1 = ahead2;
        ahead2 = prepared_in(cursor - 2u, start, end);
        if (depth != 0u && cursor < inner)
        {
            inner = middle;
            middle = outer;
            outer = INVALID;
            depth -= 1u;
        }
        if (prepared.function_id != function_id) continue;
        uint row = prepared.row;
        bool reads_declaration = (prepared.flags & PREPARED_READS_DECLARATION) != 0u;
        if (depth != 0u && reads_declaration)
        {
            uint declaration = prepared.operand;
            uint ignored;
            if (declaration < gParams.token_capacity)
                InterlockedAdd(x86_decl_analysis_by_token[declaration].read_count,
                    (1u << (3u * depth)) - 1u, ignored);
        }
        uint target = reads_declaration ? INVALID : prepared.operand;
        if (target < total)
        {
            uint target_position = x86_position_by_semantic[target];
            if (target_position <= cursor)
            {
                if (target_position < start || target_position == cursor ||
                    (prepared.flags & PREPARED_TARGET_LABEL) == 0u)
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
                    uint prior = x86_stack_words_by_position[target_position];
                    x86_stack_words_by_position[target_position] =
                        prior == INVALID ? cursor : max(prior, cursor);
                }
            }
        }
        if ((prepared.flags & PREPARED_CONTROL_LABEL) != 0u)
        {
            // Only a loop with a call in its body makes the values it holds
            // need callee-saved registers.
            uint source = x86_stack_words_by_position[cursor];
            if (source != INVALID && next_call <= source) next_target = cursor;
        }
        else
            x86_stack_words_by_position[cursor] = near_distance(cursor, next_call) |
                (near_distance(cursor, next_target) << 16u);
        if ((prepared.flags & PREPARED_CALL) != 0u) next_call = cursor;
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

    X86AllocationPrepared forward1 = prepared_in(start, start, end);
    X86AllocationPrepared forward2 = prepared_in(start + 1u, start, end);
    uint pending1 = pending_in(start, end);
    uint pending2 = pending_in(start + 1u, end);
    for (uint position = start; position < end; position += 1u)
    {
        X86AllocationPrepared prepared = forward1;
        forward1 = forward2;
        forward2 = prepared_in(position + 2u, start, end);
        uint pending = pending1;
        pending1 = pending2;
        pending2 = pending_in(position + 2u, end);
        if (prepared.function_id != function_id) continue;
        uint row = prepared.row;
        bool label = (prepared.flags & PREPARED_CONTROL_LABEL) != 0u;
        uint location = INVALID;
        uint words = 0u;
        if (label)
        {
            if (pending != INVALID) hold_over_loop(ends, position, pending);
        }
        bool in_place = false;
        if ((prepared.flags & PREPARED_LIVE) != 0u)
        {
            bool gpr = (prepared.flags & PREPARED_GPR) != 0u;
            bool argument = (prepared.flags & PREPARED_ARGUMENT) != 0u;
            location = prepared.location;
            uint last = prepared.last;
            bool across = has_call &&
                (event_inside(position, pending & NEAR_MASK, last, false) ||
                 event_inside(position, pending >> 16u, last, true));
            in_place = gpr && sound && (prepared.flags &
                (across ? PREPARED_IN_PLACE_ACROSS : PREPARED_IN_PLACE)) != 0u;
            uint home = gpr && sound && !in_place && !label
                ? prepared.home : INVALID;
            if (home != INVALID)
            {
                location = X86_LOCATION_DECLARATION | home;
                in_place = true;
            }
            if (gpr && sound && !label && !in_place)
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
                words = prepared.words;
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

// Find the next event in the segment from masks built in parallel by the
// gather. A scan of a segment reads at most nine masks. Check ownership only
// for event positions because a tile can straddle a function boundary.
uint segment_boundary(uint start, uint end, uint function_id, bool label)
{
    uint tile = start >> 5u;
    uint last_tile = (end - 1u) >> 5u;
    uint keep = 0xffffffffu << (start & 31u);
    for (; tile <= last_tile; tile += 1u)
    {
        uint2 masks = x86_allocation_boundary_masks[tile];
        uint bits = (label ? masks.y : masks.x) & keep;
        while (bits != 0u)
        {
            uint position = (tile << 5u) + uint(firstbitlow(bits));
            if (position >= end) return INVALID;
            if (x86_allocation_prepared[position].function_id == function_id)
                return position;
            bits &= bits - 1u;
        }
        keep = 0xffffffffu;
    }
    return INVALID;
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
// seed_x86_value_facts.slang has already published loop-weighted declaration reads. Every
// segment makes the same slice-header decision from immutable function
// analysis, so its three registers stay reserved for the entire function.
void walk_segment(uint function_id, uint start, uint end)
{
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

    X86AllocationPrepared forward1 = prepared_in(start, start, end);
    X86AllocationPrepared forward2 = prepared_in(start + 1u, start, end);
    uint next_call = start;
    uint next_label = start;
    for (uint position = start; position < end; position += 1u)
    {
        X86AllocationPrepared prepared = forward1;
        forward1 = forward2;
        forward2 = prepared_in(position + 2u, start, end);
        if (prepared.function_id != function_id) continue;
        uint row = prepared.row;
        uint location = INVALID;
        uint words = 0u;
        if ((prepared.flags & PREPARED_LIVE) != 0u)
        {
            bool label = (prepared.flags & PREPARED_CONTROL_LABEL) != 0u;
            uint last = prepared.last;
            if (next_label <= position)
                next_label = position + 1u < end
                    ? segment_boundary(position + 1u, end, function_id, true) : INVALID;
            bool contained = last < end &&
                !event_inside(position, near_distance(position, next_label), last, true);
            // Outside this segment, either a call or a loop back edge may
            // reach the parameter's last use. Keep its ordinary stack copy
            // unless convert_x86_branches_to_selects.slang already proved the read a coalesced alias.
            if (has_call && contained && next_call <= position)
                next_call = position + 1u < end
                    ? segment_boundary(position + 1u, end, function_id, false) : INVALID;
            bool across = has_call && (!contained ||
                event_inside(position, near_distance(position, next_call), last, false));
            bool gpr = (prepared.flags & PREPARED_GPR) != 0u;
            bool argument = (prepared.flags & PREPARED_ARGUMENT) != 0u;
            location = prepared.location;
            bool in_place = gpr && (prepared.flags &
                (across ? PREPARED_IN_PLACE_ACROSS : PREPARED_IN_PLACE)) != 0u;
            uint home = gpr && !in_place && !label ? prepared.home : INVALID;
            if (home != INVALID)
            {
                location = X86_LOCATION_DECLARATION | home;
                in_place = true;
            }
            if (gpr && contained && !label && !in_place)
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
                words = prepared.words;
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
    X86AllocationPrepared prepared = x86_allocation_prepared[position];
    uint row = prepared.row;
    uint function_total = min(gParams.function_capacity,
        semantic_lir_function_total[0u]);
    uint function_id = prepared.function_id;
    if (function_id < function_total)
    {
        uint start = x86_function_start[function_id];
        uint end = min(x86_function_end[function_id], total);
        if (end > start && end - start > X86_ALLOCATION_SERIAL_FUNCTION_LIMIT)
        {
            if ((position - start) % X86_ALLOCATION_SEGMENT_SIZE == 0u)
                walk_segment(function_id, position,
                    min(position + X86_ALLOCATION_SEGMENT_SIZE, end));
        }
        else if (start == position && start < end)
            walk_function(function_id, start, end, total);
        return;
    }
    uint words = 0u;
    if ((prepared.flags & PREPARED_LIVE) != 0u)
    {
        if (prepared.location != INVALID)
            x86_location_by_semantic[row] = prepared.location;
        else
            words = prepared.words;
    }
    x86_stack_words_by_position[position] = words;
}
