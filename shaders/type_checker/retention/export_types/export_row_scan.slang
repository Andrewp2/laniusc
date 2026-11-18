// Exclusive uint4 prefix scan of rt_x_flags over rt_x_counts[RT_X_SCAN_N]
// rows (the job's live HIR rows), in three kernels: workgroup prefixes
// (scan_retained_export_row_counts), one workgroup over the block sums (scan_retained_export_block_totals), and
// the block offsets (apply_retained_export_block_offsets). Totals land in RT_X_SCAN_TOTAL.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;

public globallycoherent RWStructuredBuffer<uint4> rt_x_blocks;

public uint scan_group(uint3 gid) { return gid.x + gid.y * 65535u; }
