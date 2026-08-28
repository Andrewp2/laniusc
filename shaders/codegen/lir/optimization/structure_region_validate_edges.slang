// Validates the completed immediate-dominator relation against every CFG
// edge. One invocation independently climbs the compact dominator relation
// from the source block; no invocation owns a function or project-wide walk.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint edge_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<OptIrFunction> opt_ir_functions;
StructuredBuffer<uint> opt_ir_immediate_dominator;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint edge_id, uint reason)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_REGION_VALIDATE_EDGES, ignored);
    // Sort by edge first and subreason second so this detail describes the
    // same earliest edge published through first_unsupported_opt_row.
    InterlockedMin(lowering_status[0u].diagnostic_detail,
        (edge_id << 8u) | (reason & 0xffu));
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, edge_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint edge_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    if (edge_id >= edge_total) return;

    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    OptIrEdge edge = opt_ir_edges[edge_id];
    uint to_block = opt_ir_edge_to_block(edge.packed_target);
    bool valid = edge.from_block < block_total && to_block < block_total;
    if (!valid)
    {
        report_structure_failure(edge_id, 1u);
        return;
    }

    OptIrBlock from = opt_ir_blocks[edge.from_block];
    OptIrBlock to = opt_ir_blocks[to_block];
    uint function_total = min(semantic_function_total[0u], gParams.hir_capacity);
    uint edge_start = opt_ir_block_edge_start(from);
    uint edge_count = opt_ir_block_edge_count(from);
    bool expected_back = to.position_start <= from.position_start;
    valid = from.function_id < function_total &&
        to.function_id == from.function_id &&
        edge_id >= edge_start && edge_id < edge_start + edge_count &&
        expected_back ==
            ((opt_ir_edge_flags(edge.packed_target) &
                OPT_IR_EDGE_BACK) != 0u);

    uint entry = valid ? opt_ir_functions[from.function_id].entry_block : INVALID;
    bool source_unreachable = edge.from_block != entry &&
        opt_ir_immediate_dominator[edge.from_block] ==
            OPT_IR_DOMINATOR_UNREACHABLE;
    // Unreachable blocks remain in the structural IR so source provenance and
    // later dead-code elimination stay exact. Their outgoing edges are valid
    // CFG records, but they impose no dominance obligation on reachable code.
    if (source_unreachable)
        return;

    uint dominator = valid ? opt_ir_immediate_dominator[to_block] : INVALID;
    if (to_block == entry)
    {
        report_structure_failure(edge_id, 2u);
        return;
    }
    if (dominator >= block_total)
    {
        report_structure_failure(edge_id, 3u);
        return;
    }
    if (opt_ir_blocks[dominator].function_id != from.function_id)
    {
        report_structure_failure(edge_id, 4u);
        return;
    }

    uint cursor = edge.from_block;
    uint steps = 0u;
    while (valid && cursor != dominator)
    {
        uint parent = opt_ir_immediate_dominator[cursor];
        valid = parent < block_total && parent != cursor &&
            opt_ir_blocks[parent].function_id == from.function_id;
        cursor = parent;
        steps += 1u;
        valid = valid && steps < block_total;
    }
    if (!valid)
        report_structure_failure(edge_id, 5u);
    else if (cursor != dominator)
        report_structure_failure(edge_id, 6u);
}
