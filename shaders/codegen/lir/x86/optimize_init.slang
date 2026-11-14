// Initializes per-node value facts and declaration-read weights. Large
// functions use existing structured regions to recover loop depth in
// parallel, before their independent allocation segments read the weights.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.x86.common;
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
StructuredBuffer<OptIrNodeControl> opt_ir_control;
StructuredBuffer<uint> opt_ir_region_total;
StructuredBuffer<OptIrRegion> opt_ir_regions;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> x86_position_by_semantic;
StructuredBuffer<uint> x86_function_start;
StructuredBuffer<uint> x86_function_end;
RWStructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
RWStructuredBuffer<X86DeclarationAnalysis> x86_decl_analysis_by_token;
// lir/x86/aggregate_facts.slang: optimize_elements accumulates into these.
RWStructuredBuffer<uint> x86_aggregate_facts;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

uint loop_read_weight(uint row, uint function_id, uint total)
{
    uint position = x86_position_by_semantic[row];
    if (position >= total) return 0u;
    uint region_id = opt_ir_control[row].region_id;
    uint region_capacity;
    uint region_stride;
    opt_ir_regions.GetDimensions(region_capacity, region_stride);
    uint region_total = min(opt_ir_region_total[0u], region_capacity);
    uint depth = 0u;
    while (region_id != INVALID)
    {
        if (region_id >= region_total) return 0u;
        OptIrRegion region = opt_ir_regions[region_id];
        if (region.function_id != function_id ||
            region.position_start > position || region.position_end <= position ||
            region.position_end >= total ||
            (region.parent_region != INVALID && region.parent_region >= region_id))
            return 0u;
        uint opener = semantic_schedule_order[region.position_start];
        if (opener >= total) return 0u;
        uint op = opt_ir_op(opt_ir_core[opener]);
        if (op == SEMANTIC_LIR_OP_LOOP_BEGIN) depth += 1u;
        else if (op != SEMANTIC_LIR_OP_BLOCK_BEGIN && op != SEMANTIC_LIR_OP_IF_BEGIN)
            return 0u;
        // The established weighting saturates at three enclosing loops.
        // Validated parents strictly decrease, so even deeply nested
        // non-loop regions cannot form a cycle here.
        if (depth == 3u) break;
        region_id = region.parent_region;
    }
    return (1u << (3u * depth)) - 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (row >= total) return;
    x86_aggregate_facts[row] = 0u;
    X86ValueAnalysis value;
    value.value = 0u;
    value.known = 0u;
    value.replacement = row;
    OptIrNodeCore core = opt_ir_core[row];
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_I32)
    {
        value.value = opt_ir_operands[row].a;
        value.known = 1u;
    }
    x86_value_by_semantic[row] = value;

    uint op = opt_ir_op(core);
    if (op != SEMANTIC_LIR_OP_VALUE_GET && op != SEMANTIC_LIR_OP_ADDRESS) return;
    uint owner = opt_ir_source_hir[row];
    if (owner >= gParams.function_capacity) return;
    uint function_id = semantic_function_id_by_hir[owner];
    if (function_id >= gParams.function_capacity) return;
    uint start = x86_function_start[function_id];
    uint end = min(x86_function_end[function_id], total);
    // Small functions still add their loop weights in walk_function. This
    // uses exactly the same threshold as the allocator to avoid counting
    // those reads twice.
    if (end <= start || end - start <= X86_ALLOCATION_SERIAL_FUNCTION_LIMIT) return;
    uint declaration = opt_ir_operands[row].a;
    if (declaration >= gParams.token_capacity) return;
    uint weight = loop_read_weight(row, function_id, total);
    if (weight != 0u)
    {
        uint ignored;
        InterlockedAdd(x86_decl_analysis_by_token[declaration].read_count, weight, ignored);
    }
}
