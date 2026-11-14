// Exclusive uint4 prefix scan of rt_x_flags over rt_x_counts[RT_X_SCAN_N]
// rows (the job's live HIR rows), in three kernels: workgroup prefixes
// (08_scan_local), one workgroup over the block sums (08_scan_blocks), and
// the block offsets (08_scan_apply). Totals land in RT_X_SCAN_TOTAL.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;

public globallycoherent RWStructuredBuffer<uint4> rt_x_blocks;

public uint scan_group(uint3 gid) { return gid.x + gid.y * 65535u; }
