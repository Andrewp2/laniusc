// Collapses single-predecessor demand chains to local definitions or block
// arguments. Every demand row has its own lane, which follows its chain for a
// bounded number of hops from the input table and publishes where it stopped.
// The host records two rounds between the two resolution tables; the second
// round hops over the first round's jumps, so a bound of sqrt(capacity) hops
// covers every chain the demand table can hold.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_demand_canonical_lookup;
import gpu_index;

struct Params
{
    uint demand_capacity;
    uint hops_per_round;
    // Set on the round that publishes the final table: a chain that is still
    // unresolved there is a cycle.
    uint final_round;
    uint reserved;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_ssa_demand_resolution_in;
RWStructuredBuffer<uint> opt_ir_ssa_demand_resolution_out;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = opt_ir_active_ssa_demand_total(gParams.demand_capacity);
    if (row >= total) return;

    OptIrSsaValueRef current =
        opt_ir_unpack_ssa_source(opt_ir_ssa_demand_resolution_in[row]);
    if (current.kind == OPT_IR_SSA_SOURCE_DEMAND)
    {
        // A chain stays inside its declaration's contiguous demand rows.
        uint declaration = opt_ir_canonical_ssa_demand(row, total).declaration;
        for (uint hop = 0u;
             hop < gParams.hops_per_round &&
                 current.kind == OPT_IR_SSA_SOURCE_DEMAND;
             ++hop)
        {
            if (opt_ir_canonical_ssa_demand(current.payload, total).declaration
                    != declaration || current.payload >= total)
            {
                current.kind = OPT_IR_SSA_SOURCE_INVALID;
                current.payload = INVALID;
                break;
            }
            current = opt_ir_unpack_ssa_source(
                opt_ir_ssa_demand_resolution_in[current.payload]);
        }
    }
    opt_ir_ssa_demand_resolution_out[row] = opt_ir_pack_ssa_source(current);
    if (gParams.final_round != 0u &&
        current.kind == OPT_IR_SSA_SOURCE_DEMAND)
        report_structure_failure(row);
}
