// Copies the used rows of the job tables in one dispatch into the program
// retention snapshot (program_retention.rs `record_job_snapshot`). A table's
// row count is a word the job wrote on the GPU (compact_hir_count, or a side
// table's count), so the host knows only the table's capacity. The export
// kernels read a table only below that count (retention_job.slang
// `valid_row`, retained_body_side_tables.slang `side_rows`), so rows past it are never
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
    uint4 table[45];
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
StructuredBuffer<uint> sr_src16;
StructuredBuffer<uint> sr_src17;
StructuredBuffer<uint> sr_src18;
StructuredBuffer<uint> sr_src19;
StructuredBuffer<uint> sr_src20;
StructuredBuffer<uint> sr_src21;
StructuredBuffer<uint> sr_src22;
StructuredBuffer<uint> sr_src23;
StructuredBuffer<uint> sr_src24;
StructuredBuffer<uint> sr_src25;
StructuredBuffer<uint> sr_src26;
StructuredBuffer<uint> sr_src27;
StructuredBuffer<uint> sr_src28;
StructuredBuffer<uint> sr_src29;
StructuredBuffer<uint> sr_src30;
StructuredBuffer<uint> sr_src31;
StructuredBuffer<uint> sr_src32;
StructuredBuffer<uint> sr_src33;
StructuredBuffer<uint> sr_src34;
StructuredBuffer<uint> sr_src35;
StructuredBuffer<uint> sr_src36;
StructuredBuffer<uint> sr_src37;
StructuredBuffer<uint> sr_src38;
StructuredBuffer<uint> sr_src39;
StructuredBuffer<uint> sr_src40;
StructuredBuffer<uint> sr_src41;
StructuredBuffer<uint> sr_src42;
StructuredBuffer<uint> sr_src43;
StructuredBuffer<uint> sr_src44;
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
StructuredBuffer<uint> sr_count16;
StructuredBuffer<uint> sr_count17;
StructuredBuffer<uint> sr_count18;
StructuredBuffer<uint> sr_count19;
StructuredBuffer<uint> sr_count20;
StructuredBuffer<uint> sr_count21;
StructuredBuffer<uint> sr_count22;
StructuredBuffer<uint> sr_count23;
StructuredBuffer<uint> sr_count24;
StructuredBuffer<uint> sr_count25;
StructuredBuffer<uint> sr_count26;
StructuredBuffer<uint> sr_count27;
StructuredBuffer<uint> sr_count28;
StructuredBuffer<uint> sr_count29;
StructuredBuffer<uint> sr_count30;
StructuredBuffer<uint> sr_count31;
StructuredBuffer<uint> sr_count32;
StructuredBuffer<uint> sr_count33;
StructuredBuffer<uint> sr_count34;
StructuredBuffer<uint> sr_count35;
StructuredBuffer<uint> sr_count36;
StructuredBuffer<uint> sr_count37;
StructuredBuffer<uint> sr_count38;
StructuredBuffer<uint> sr_count39;
StructuredBuffer<uint> sr_count40;
StructuredBuffer<uint> sr_count41;
StructuredBuffer<uint> sr_count42;
StructuredBuffer<uint> sr_count43;
StructuredBuffer<uint> sr_count44;
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
RWStructuredBuffer<uint> sr_dst16;
RWStructuredBuffer<uint> sr_dst17;
RWStructuredBuffer<uint> sr_dst18;
RWStructuredBuffer<uint> sr_dst19;
RWStructuredBuffer<uint> sr_dst20;
RWStructuredBuffer<uint> sr_dst21;
RWStructuredBuffer<uint> sr_dst22;
RWStructuredBuffer<uint> sr_dst23;
RWStructuredBuffer<uint> sr_dst24;
RWStructuredBuffer<uint> sr_dst25;
RWStructuredBuffer<uint> sr_dst26;
RWStructuredBuffer<uint> sr_dst27;
RWStructuredBuffer<uint> sr_dst28;
RWStructuredBuffer<uint> sr_dst29;
RWStructuredBuffer<uint> sr_dst30;
RWStructuredBuffer<uint> sr_dst31;
RWStructuredBuffer<uint> sr_dst32;
RWStructuredBuffer<uint> sr_dst33;
RWStructuredBuffer<uint> sr_dst34;
RWStructuredBuffer<uint> sr_dst35;
RWStructuredBuffer<uint> sr_dst36;
RWStructuredBuffer<uint> sr_dst37;
RWStructuredBuffer<uint> sr_dst38;
RWStructuredBuffer<uint> sr_dst39;
RWStructuredBuffer<uint> sr_dst40;
RWStructuredBuffer<uint> sr_dst41;
RWStructuredBuffer<uint> sr_dst42;
RWStructuredBuffer<uint> sr_dst43;
RWStructuredBuffer<uint> sr_dst44;

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


public void copy_snapshot_rows(uint lane)
{
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

public void copy_snapshot_tables(uint lane)
{
    copy_snapshot_rows(lane);
    copy_rows(16u, sr_src16, sr_count16, sr_dst16, lane);
    copy_rows(17u, sr_src17, sr_count17, sr_dst17, lane);
    copy_rows(18u, sr_src18, sr_count18, sr_dst18, lane);
    copy_rows(19u, sr_src19, sr_count19, sr_dst19, lane);
    copy_rows(20u, sr_src20, sr_count20, sr_dst20, lane);
    copy_rows(21u, sr_src21, sr_count21, sr_dst21, lane);
    copy_rows(22u, sr_src22, sr_count22, sr_dst22, lane);
    copy_rows(23u, sr_src23, sr_count23, sr_dst23, lane);
    copy_rows(24u, sr_src24, sr_count24, sr_dst24, lane);
    copy_rows(25u, sr_src25, sr_count25, sr_dst25, lane);
    copy_rows(26u, sr_src26, sr_count26, sr_dst26, lane);
    copy_rows(27u, sr_src27, sr_count27, sr_dst27, lane);
    copy_rows(28u, sr_src28, sr_count28, sr_dst28, lane);
    copy_rows(29u, sr_src29, sr_count29, sr_dst29, lane);
    copy_rows(30u, sr_src30, sr_count30, sr_dst30, lane);
    copy_rows(31u, sr_src31, sr_count31, sr_dst31, lane);
    copy_rows(32u, sr_src32, sr_count32, sr_dst32, lane);
    copy_rows(33u, sr_src33, sr_count33, sr_dst33, lane);
    copy_rows(34u, sr_src34, sr_count34, sr_dst34, lane);
    copy_rows(35u, sr_src35, sr_count35, sr_dst35, lane);
    copy_rows(36u, sr_src36, sr_count36, sr_dst36, lane);
    copy_rows(37u, sr_src37, sr_count37, sr_dst37, lane);
    copy_rows(38u, sr_src38, sr_count38, sr_dst38, lane);
    copy_rows(39u, sr_src39, sr_count39, sr_dst39, lane);
    copy_rows(40u, sr_src40, sr_count40, sr_dst40, lane);
    copy_rows(41u, sr_src41, sr_count41, sr_dst41, lane);
    copy_rows(42u, sr_src42, sr_count42, sr_dst42, lane);
    copy_rows(43u, sr_src43, sr_count43, sr_dst43, lane);
    copy_rows(44u, sr_src44, sr_count44, sr_dst44, lane);
}
