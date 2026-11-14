// One parallel list-ranking step over the Euler-tour predecessor relation:
// a round follows up to POINTER_JUMP_HOPS input links, so the reach of a
// link grows by that factor per round (`pointer_jump_hop_pairs` in
// lowering_ir.rs).

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
StructuredBuffer<OptIrDominatorTourLink> opt_ir_dominator_tour_link_in;
RWStructuredBuffer<OptIrDominatorTourLink> opt_ir_dominator_tour_link_out;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint POINTER_JUMP_HOPS = 16u;

void report_structure_failure(uint arc)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, arc >> 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint arc = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint arc_total = min(opt_ir_block_total[0u], gParams.block_capacity) * 2u;
    if (arc >= arc_total) return;

    OptIrDominatorTourLink link = opt_ir_dominator_tour_link_in[arc];
    for (uint hop = 0u; hop < POINTER_JUMP_HOPS && link.previous != INVALID; ++hop)
    {
        if (link.previous >= arc_total)
        {
            report_structure_failure(arc);
            link.previous = INVALID;
            break;
        }
        OptIrDominatorTourLink previous =
            opt_ir_dominator_tour_link_in[link.previous];
        link.previous = previous.previous;
        link.down_count += previous.down_count;
    }
    opt_ir_dominator_tour_link_out[arc] = link;
}
