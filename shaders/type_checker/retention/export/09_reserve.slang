// Export step 9 (one lane): reserve the job's blocks of the scan-placed
// arenas (segment rows, uses, directory entries, segments) and publish the
// indirect arguments of the side-table and schema steps. A block that does
// not fit records the arena's overflow and demand; later steps then write
// nothing for it, and step 15 rolls the job back.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;
import type_checker.retention.export.dispatch;
import type_checker.retention.export.side_tables;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint4 total = scan_at(0xffffffffu);
    rt_x_counts[RT_X_BASE + RT_A_SEG_ROWS] = rt_alloc(RT_A_SEG_ROWS, total.x);
    rt_x_counts[RT_X_BASE + RT_A_USES] = rt_alloc(RT_A_USES, total.y);
    rt_x_counts[RT_X_BASE + RT_A_DIR] = rt_alloc(RT_A_DIR, total.z);
    rt_x_counts[RT_X_BASE + RT_A_SEGMENTS] = rt_alloc(RT_A_SEGMENTS, total.w);
    uint side = 0u;
    for (uint k = 0u; k < RT_SIDE_TABLES; k++) side = max(side, side_rows(k));
    set_dispatch(RT_D_SIDE, side);
    set_dispatch(RT_D_SCHEMA, max(max(side_rows(RT_SIDE_PARAMS), side_rows(RT_SIDE_FIELDS)), variant_payload_rows()));
}
