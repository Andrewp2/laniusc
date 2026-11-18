// Output layout and directory admission over one workgroup: the items of
// ts_admit_output_layout and ts_admit_directories run on all lanes, and the
// first failing item in admission order decides, as in the serial loops.
// One thread checking every pair of tables took about 100 µs.
import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.catalog.catalog_io;

public static const uint TS_ADMISSION_LANES = 256u;
groupshared uint ts_group_first[2];
groupshared SolverStatus ts_group_status[2];

// Every lane of the workgroup calls this (it has barriers). Each lane
// returns the statuses the serial admissions return.
public void ts_admit_group(uint lane, out SolverStatus layout, out SolverStatus directories)
{
    if (lane == 0u) { ts_group_first[0] = TS_INVALID; ts_group_first[1] = TS_INVALID; }
    GroupMemoryBarrierWithGroupSync();
    uint work_rows; uint work_buckets;
    layout = ts_admit_output_layout_globals(work_rows, work_buckets);
    directories = ts_admit_directories_globals();
    uint first0 = TS_INVALID; uint first1 = TS_INVALID;
    SolverStatus status0 = ts_ok(); SolverStatus status1 = ts_ok();
    if (layout.state == TS_VALID)
    {
        [loop]
        for (uint key = lane; key < TS_OUTPUT_TABLES * TS_LAYOUT_ITEMS; key += TS_ADMISSION_LANES)
        {
            SolverStatus item;
            if (ts_output_layout_item(key, work_rows, work_buckets, item)) { first0 = key; status0 = item; break; }
        }
    }
    if (directories.state == TS_VALID)
    {
        [loop]
        for (uint key = lane; key < TS_TABLES * TS_DIRECTORY_ITEMS; key += TS_ADMISSION_LANES)
        {
            SolverStatus item;
            if (ts_directory_item(key, item)) { first1 = key; status1 = item; break; }
        }
    }
    if (first0 != TS_INVALID) InterlockedMin(ts_group_first[0], first0);
    if (first1 != TS_INVALID) InterlockedMin(ts_group_first[1], first1);
    GroupMemoryBarrierWithGroupSync();
    if (first0 != TS_INVALID && first0 == ts_group_first[0]) ts_group_status[0] = status0;
    if (first1 != TS_INVALID && first1 == ts_group_first[1]) ts_group_status[1] = status1;
    GroupMemoryBarrierWithGroupSync();
    if (layout.state == TS_VALID && ts_group_first[0] != TS_INVALID) layout = ts_group_status[0];
    if (directories.state == TS_VALID && ts_group_first[1] != TS_INVALID) directories = ts_group_status[1];
}
