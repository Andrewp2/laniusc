// Copies the used rows of up to sixteen job tables into the program
// retention snapshot (program_retention.rs `record_job_snapshot`). A table's
// row count is a word the job wrote on the GPU (compact_hir_count, or a side
// table's count), so the host knows only the table's capacity. The export
// kernels read a table only below that count (retention_job.slang
// `valid_row`, side_tables.slang `side_rows`), so rows past it are never
// read and are not copied.

struct SnapshotRowsParams
{
    // The grid's lane count, and the tables in use.
    uint lanes;
    uint tables;
    uint reserved0;
    uint reserved1;
    // Per table: x the source word offset, y words per row, z the table's
    // words, w the word of its row count in sr_countN.
    uint4 table[16];
};

ConstantBuffer<SnapshotRowsParams> gSR;
StructuredBuffer<uint> sr_src0;
StructuredBuffer<uint> sr_src1;
StructuredBuffer<uint> sr_src2;
StructuredBuffer<uint> sr_src3;
StructuredBuffer<uint> sr_src4;
StructuredBuffer<uint> sr_src5;
StructuredBuffer<uint> sr_src6;
StructuredBuffer<uint> sr_src7;
StructuredBuffer<uint> sr_src8;
StructuredBuffer<uint> sr_src9;
StructuredBuffer<uint> sr_src10;
StructuredBuffer<uint> sr_src11;
StructuredBuffer<uint> sr_src12;
StructuredBuffer<uint> sr_src13;
StructuredBuffer<uint> sr_src14;
StructuredBuffer<uint> sr_src15;
StructuredBuffer<uint> sr_count0;
StructuredBuffer<uint> sr_count1;
StructuredBuffer<uint> sr_count2;
StructuredBuffer<uint> sr_count3;
StructuredBuffer<uint> sr_count4;
StructuredBuffer<uint> sr_count5;
StructuredBuffer<uint> sr_count6;
StructuredBuffer<uint> sr_count7;
StructuredBuffer<uint> sr_count8;
StructuredBuffer<uint> sr_count9;
StructuredBuffer<uint> sr_count10;
StructuredBuffer<uint> sr_count11;
StructuredBuffer<uint> sr_count12;
StructuredBuffer<uint> sr_count13;
StructuredBuffer<uint> sr_count14;
StructuredBuffer<uint> sr_count15;
RWStructuredBuffer<uint> sr_dst0;
RWStructuredBuffer<uint> sr_dst1;
RWStructuredBuffer<uint> sr_dst2;
RWStructuredBuffer<uint> sr_dst3;
RWStructuredBuffer<uint> sr_dst4;
RWStructuredBuffer<uint> sr_dst5;
RWStructuredBuffer<uint> sr_dst6;
RWStructuredBuffer<uint> sr_dst7;
RWStructuredBuffer<uint> sr_dst8;
RWStructuredBuffer<uint> sr_dst9;
RWStructuredBuffer<uint> sr_dst10;
RWStructuredBuffer<uint> sr_dst11;
RWStructuredBuffer<uint> sr_dst12;
RWStructuredBuffer<uint> sr_dst13;
RWStructuredBuffer<uint> sr_dst14;
RWStructuredBuffer<uint> sr_dst15;

// Copies the words of table `t` that hold its counted rows.
void copy_rows(uint t, StructuredBuffer<uint> src, StructuredBuffer<uint> count, RWStructuredBuffer<uint> dst, uint lane)
{
    if (t >= gSR.tables) return;
    uint4 table = gSR.table[t];
    uint rows = count[table.w];
    uint words = rows >= table.z / table.y ? table.z : rows * table.y;
    for (uint i = lane; i < words; i += gSR.lanes)
        dst[i] = src[table.x + i];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint lane = tid.x;
    copy_rows(0u, sr_src0, sr_count0, sr_dst0, lane);
    copy_rows(1u, sr_src1, sr_count1, sr_dst1, lane);
    copy_rows(2u, sr_src2, sr_count2, sr_dst2, lane);
    copy_rows(3u, sr_src3, sr_count3, sr_dst3, lane);
    copy_rows(4u, sr_src4, sr_count4, sr_dst4, lane);
    copy_rows(5u, sr_src5, sr_count5, sr_dst5, lane);
    copy_rows(6u, sr_src6, sr_count6, sr_dst6, lane);
    copy_rows(7u, sr_src7, sr_count7, sr_dst7, lane);
    copy_rows(8u, sr_src8, sr_count8, sr_dst8, lane);
    copy_rows(9u, sr_src9, sr_count9, sr_dst9, lane);
    copy_rows(10u, sr_src10, sr_count10, sr_dst10, lane);
    copy_rows(11u, sr_src11, sr_count11, sr_dst11, lane);
    copy_rows(12u, sr_src12, sr_count12, sr_dst12, lane);
    copy_rows(13u, sr_src13, sr_count13, sr_dst13, lane);
    copy_rows(14u, sr_src14, sr_count14, sr_dst14, lane);
    copy_rows(15u, sr_src15, sr_count15, sr_dst15, lane);
}
