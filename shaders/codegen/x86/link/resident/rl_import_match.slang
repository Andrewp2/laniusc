// One lane per exported name of every input: when a candidate C name has
// the same bytes, records the earliest row that defines it, the earliest
// archive row that names it, and an unreadable version.

import codegen.x86.link.resident.rl_cnames;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = cn_lane(tid);
    if (row >= gCN.row_count)
        return;
    uint len = cn_rows[row * 3u + 1u];
    if (len == INVALID)
        return;
    uint offset = input_word(input_of_row(row), 2u) + cn_rows[row * 3u];
    uint code = cn_rows[row * 3u + 2u];
    uint slot = name_hash(offset, len) & gCN.name_mask;
    for (uint probe = 0u; probe <= gCN.name_mask; probe += 1u)
    {
        uint stored = cn_name_hash[slot];
        if (stored == 0u)
            return;
        uint candidate = stored - 1u;
        if (cn_names[candidate * 3u + 1u] == len && bytes_equal(cn_names[candidate * 3u], offset, len))
        {
            if (code == CODE_ERROR)
                cn_match[candidate * 3u + 2u] = 1u;
            else if (code == CODE_ARCHIVE)
                atomic_u32_max(cn_match, candidate * 3u + 1u, INVALID - row);
            else
                atomic_u32_max(cn_match, candidate * 3u, INVALID - row);
            return;
        }
        slot = (slot + 1u) & gCN.name_mask;
    }
}
