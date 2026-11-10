// Seeds exact CFG reachability, one lane per block. A block is dead when it is
// no function entry and every forward predecessor is dead, so each lane counts
// its own forward predecessors and marks its block reachable unless that count
// is zero. The close pass then removes what only dead blocks lead to.
//
// Forward edges ascend in scheduling position and so form an acyclic graph.
// Retreating edges are left out: a retreating edge targets a dominator of its
// source, which a later validator proves, so it reaches nothing new.

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
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<OptIrFunction> opt_ir_functions;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
RWStructuredBuffer<uint> opt_ir_reachable;
RWStructuredBuffer<uint> opt_ir_live_predecessor_count_by_block;
RWStructuredBuffer<uint> opt_ir_dead_claim_by_block;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
// A dead root: the close lane of this block owns the region below it.
static const uint CLAIM_ROOT = 0xffffffffu;
static const uint CLAIM_NONE = 0xfffffffeu;
// Keeps an entry's count from ever reaching the last-predecessor transition.
static const uint ENTRY_BIAS = 0x40000000u;

void report_structure_failure(uint block)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_REACHABILITY_SEED, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u],
        gParams.block_capacity);
    if (block >= block_total) return;
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    uint function_total = min(semantic_function_total[0u],
        gParams.hir_capacity);

    uint function_id = opt_ir_blocks[block].function_id;
    bool valid = function_id < function_total;
    bool entry = valid &&
        opt_ir_functions[function_id].entry_block == block;

    uint begin = opt_ir_predecessor_prefix[block];
    uint end = block + 1u < block_total
        ? opt_ir_predecessor_prefix[block + 1u] : edge_total;
    valid = valid && begin <= end && end <= edge_total;
    uint forward = 0u;
    for (uint row = begin; valid && row < end; ++row)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[row];
        valid = edge_id < edge_total;
        if (!valid) break;
        uint flags = opt_ir_edge_flags(opt_ir_edges[edge_id].packed_target);
        if ((flags & OPT_IR_EDGE_BACK) == 0u) forward += 1u;
    }
    if (!valid) report_structure_failure(block);

    bool root = valid && !entry && forward == 0u;
    opt_ir_live_predecessor_count_by_block[block] =
        entry ? ENTRY_BIAS + forward : forward;
    opt_ir_reachable[block] = root ? 0u : 1u;
    opt_ir_dead_claim_by_block[block] = root ? CLAIM_ROOT : CLAIM_NONE;
}
