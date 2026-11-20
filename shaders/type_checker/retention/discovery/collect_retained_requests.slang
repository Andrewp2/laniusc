import shared.collectives.step_program;
import shared.collectives.program_prefix_scan;
import type_checker.retention.retention_launch;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.collect_discovery_requests_step;
import type_checker.retention.discovery.discovery_request_status;

StructuredBuffer<uint> dg_receipt;
RWStructuredBuffer<uint> dg_scan_total;

uint use_count(uint instance)
{
    uint decl = dg_instances[2u * instance].x;
    uint entry = dg_entry(decl);
    return entry == RT_INVALID ? 0u : rt_dir[entry * RT_DIR_WORDS + 3u].x;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    if (dg_status[29] != 0u)
    {
        if (program.leader)
            InterlockedOr(step_program_sync[program.sync_base + STEP_SYNC_FAILED], 1u);
        return;
    }

    uint root = dg_config[4];
    if (program.lane == 0u)
    {
        sb_request_count[0] = 0u;
        dg_status[7] = 0u;
    }

    uint uses = 0u;
    if (root != 0u)
    {
        // The source catalog's receipt was copied before this program.
        if (dg_config[10] == 0u || (dg_receipt[0] == 1u && dg_receipt[1] == 0u))
            uses = max(1u, rt_counts[RT_A_USES]);
        if (!step_barrier(program)) return;
    }
    else
    {
        uint lo = dg_config[1];
        uint count = dg_config[2] - lo;
        uint edge_base = dg_config[3];
        for (uint row = program.lane; row < count; row += program.lanes)
            dg_scan_b[row] = use_count(lo + row);
        if (!step_barrier(program)) return;

        if (!step_program_prefix_scan(
                program, count, dg_scan_b, dg_scan_a, dg_scan_total, dg_scan_blocks))
            return;
        if (!step_barrier(program)) return;

        uint total = dg_scan_total[0];
        uint capacity; uint stride;
        dg_edges.GetDimensions(capacity, stride);
        for (uint row = program.lane; row < count; row += program.lanes)
        {
            uint instance = lo + row;
            uint start = dg_scan_a[row];
            uint degree = dg_scan_b[row];
            dg_scan_a[row] = start + degree;
            uint4 old = dg_instances[2u * instance + 1u];
            dg_instances[2u * instance + 1u] = uint4(edge_base + start, degree, old.z, 0u);
        }
        if (program.lane == 0u && count != 0u)
        {
            uint demand = edge_base + total;
            dg_status[2] = demand;
            dg_status[5] = demand;
            if (demand > capacity) InterlockedOr(dg_status[3], 2u);
        }
        uses = edge_base + total > capacity ? 0u : total;
        if (!step_barrier(program)) return;
    }

    for (uint row = program.lane; row < uses; row += program.lanes)
        collect_discovery_requests(row);
    if (!step_barrier(program)) return;
    if (program.lane == 0u) finish_discovery_requests();
    step_program_end(program);
}
