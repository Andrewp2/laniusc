// Export step 15: one lane per declaration row. Copies the statistics the
// body and signature steps accumulated into the staged records: a segment
// keeps (untyped, foreign, ownership, untranslated) in s3, and a directory
// entry whose declaration or body has any nonzero statistic carries
// RT_DIR_INCOMPLETE in d3.w, so a consumer never mistakes a partial body or
// signature for a complete one.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;

public void finalize_retained_export_rows(uint row)
{
    if (row >= hir_count() || rt_x_flags[row].z == 0u) return;
    uint4 info = rt_x_row[row];
    if (info.y == RT_INVALID || rt_x_counts[RT_X_BASE + RT_A_DIR] == RT_INVALID) return;
    uint4 stats = uint4(rt_x_stats[row * 4u + RT_STAT_UNTYPED], rt_x_stats[row * 4u + RT_STAT_FOREIGN],
        rt_x_stats[row * 4u + RT_STAT_OWNERSHIP], rt_x_stats[row * 4u + RT_STAT_UNTRANSLATED]);
    bool incomplete = any(stats != uint4(0u, 0u, 0u, 0u));
    if (incomplete) InterlockedAdd(rt_counts[RT_C_INCOMPLETE], 1u);
    uint4 d3 = rt_dir[info.y * RT_DIR_WORDS + 3u];
    d3.w = incomplete ? RT_DIR_INCOMPLETE : 0u;
    rt_dir[info.y * RT_DIR_WORDS + 3u] = d3;
    if (info.z != RT_INVALID) rt_segments[info.z * RT_SEG_WORDS + 3u] = stats;
}
