// Gather raw statement classification into canonical HIR row order while the
// raw record is still available.

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_flag;
StructuredBuffer<uint> canonical_local_prefix;
StructuredBuffer<uint> canonical_block_prefix;
StructuredBuffer<uint> raw_stmt_record;
StructuredBuffer<uint> raw_expr_record;
RWStructuredBuffer<uint> compact_stmt_record;
RWStructuredBuffer<uint> compact_expr_record;

static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity || canonical_flag[raw] == 0u) return;
    uint block = raw / 256u;
    uint base = block == 0u ? 0u : canonical_block_prefix[block - 1u];
    uint dense = base + canonical_local_prefix[raw];
    if (dense >= gCanonical.canonical_capacity) return;
    compact_stmt_record[dense * 4u] = raw_stmt_record[raw * 4u];
    compact_stmt_record[dense * 4u + 1u] = raw_stmt_record[raw * 4u + 1u];
    compact_stmt_record[dense * 4u + 2u] = raw_stmt_record[raw * 4u + 2u];
    compact_stmt_record[dense * 4u + 3u] = raw_stmt_record[raw * 4u + 3u];
    compact_expr_record[dense * 4u] = raw_expr_record[raw * 4u];
    compact_expr_record[dense * 4u + 1u] = raw_expr_record[raw * 4u + 1u];
    compact_expr_record[dense * 4u + 2u] = raw_expr_record[raw * 4u + 2u];
    compact_expr_record[dense * 4u + 3u] = raw_expr_record[raw * 4u + 3u];
}
