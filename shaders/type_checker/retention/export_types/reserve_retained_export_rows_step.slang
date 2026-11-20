// Export step 9 (one lane): reserve the job's blocks of the scan-placed
// arenas (segment rows, uses, directory entries, segments) and publish the
// indirect arguments of the side-table and schema steps. A block that does
// not fit records the arena's overflow and demand; later steps then write
// nothing for it, and step 15 rolls the job back.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export_rows.retained_body_side_tables;

public void reserve_retained_export_rows()
{
    uint4 total = scan_at(0xffffffffu);
    rt_x_counts[RT_X_BASE + RT_A_SEG_ROWS] = rt_alloc(RT_A_SEG_ROWS, total.x);
    rt_x_counts[RT_X_BASE + RT_A_USES] = rt_alloc(RT_A_USES, total.y);
    rt_x_counts[RT_X_BASE + RT_A_DIR] = rt_alloc(RT_A_DIR, total.z);
    rt_x_counts[RT_X_BASE + RT_A_SEGMENTS] = rt_alloc(RT_A_SEGMENTS, total.w);
}
