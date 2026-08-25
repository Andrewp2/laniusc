// Collapses single-predecessor demand chains to local definitions or block
// arguments. A fixed worker pool owns one declaration range at a time; global
// double buffering plus workgroup barriers performs logarithmic pointer
// jumping without host-recorded rounds.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_demand_canonical_lookup;

struct Params
{
    uint block_capacity;
    uint edge_capacity;
    uint access_capacity;
    uint declaration_capacity;
    uint declaration_block_capacity;
    uint demand_capacity;
    uint worker_count;
    uint max_radix_blocks;
    uint incoming_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_access_group_total;
StructuredBuffer<OptIrAccessGroup> opt_ir_access_groups;
RWStructuredBuffer<uint> opt_ir_ssa_demand_resolutions;
RWStructuredBuffer<uint> opt_ir_ssa_demand_resolution_tmp;
RWStructuredBuffer<uint> opt_ir_ssa_worker_next_group;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;

groupshared uint worker_group_id;
groupshared uint worker_declaration;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

OptIrSsaValueRef jump_resolution(
    OptIrSsaValueRef current,
    bool source_is_primary,
    uint range_begin,
    uint range_end)
{
    if (current.kind != OPT_IR_SSA_SOURCE_DEMAND)
        return current;
    if (current.payload < range_begin || current.payload >= range_end)
    {
        current.kind = OPT_IR_SSA_SOURCE_INVALID;
        current.payload = INVALID;
        return current;
    }
    return opt_ir_unpack_ssa_source(source_is_primary
        ? opt_ir_ssa_demand_resolutions[current.payload]
        : opt_ir_ssa_demand_resolution_tmp[current.payload]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint worker_slot = gid.x;
    if (worker_slot >= gParams.worker_count) return;
    uint demand_total = opt_ir_active_ssa_demand_total(
        gParams.demand_capacity);
    uint group_total = min(
        opt_ir_access_group_total[0u], gParams.declaration_capacity);

    for (;;)
    {
        if (ltid.x == 0u)
            InterlockedAdd(
                opt_ir_ssa_worker_next_group[0u], 1u, worker_group_id);
        GroupMemoryBarrierWithGroupSync();
        if (worker_group_id >= group_total) return;
        if (ltid.x == 0u)
            worker_declaration =
                opt_ir_access_groups[worker_group_id].subject;
        GroupMemoryBarrierWithGroupSync();

        uint begin = opt_ir_lower_bound_ssa_demand(
            worker_declaration, 0u, demand_total);
        uint end = worker_declaration == INVALID
            ? demand_total
            : opt_ir_lower_bound_ssa_demand(
                worker_declaration + 1u, 0u, demand_total);
        uint count = end - begin;
        for (uint row = begin + ltid.x; row < end; row += 256u)
            opt_ir_ssa_demand_resolution_tmp[row] =
                opt_ir_ssa_demand_resolutions[row];
        DeviceMemoryBarrierWithGroupSync();

        bool source_is_primary = true;
        uint rounds = count <= 1u
            ? 1u : uint(firstbithigh(count - 1u)) + 1u;
        for (uint round = 0u; round < rounds; ++round)
        {
            for (uint row = begin + ltid.x; row < end; row += 256u)
            {
                OptIrSsaValueRef current = opt_ir_unpack_ssa_source(source_is_primary
                    ? opt_ir_ssa_demand_resolutions[row]
                    : opt_ir_ssa_demand_resolution_tmp[row]);
                OptIrSsaValueRef jumped = jump_resolution(
                    current, source_is_primary, begin, end);
                if (source_is_primary)
                    opt_ir_ssa_demand_resolution_tmp[row] =
                        opt_ir_pack_ssa_source(jumped);
                else
                    opt_ir_ssa_demand_resolutions[row] =
                        opt_ir_pack_ssa_source(jumped);
            }
            DeviceMemoryBarrierWithGroupSync();
            source_is_primary = !source_is_primary;
        }

        for (uint row = begin + ltid.x; row < end; row += 256u)
        {
            OptIrSsaValueRef resolved = opt_ir_unpack_ssa_source(source_is_primary
                ? opt_ir_ssa_demand_resolutions[row]
                : opt_ir_ssa_demand_resolution_tmp[row]);
            opt_ir_ssa_demand_resolutions[row] =
                opt_ir_pack_ssa_source(resolved);
            if (resolved.kind == OPT_IR_SSA_SOURCE_DEMAND)
                report_structure_failure(row);
        }
        DeviceMemoryBarrierWithGroupSync();
    }
}
