import shared.collectives.step_program;
import shared.collectives.program_prefix_scan;
import type_checker.retention.projection.retained_projection_workspace;

RWStructuredBuffer<uint> pj_scan_sums;
RWStructuredBuffer<uint> pj_scan_total;

uint projected_string_words(uint global, uint ranks)
{
    uint rank = pj_rank_of(PJ_C_ROWS, global, 0u, ranks);
    uint row = global - pj_base_at(rank, PJ_C_ROWS);
    uint4 literal = pj_row(rank, row, 2u);
    if (pj_row(rank, row, 0u).x != RT_HIR_LITERAL_EXPR || literal.x != 28u ||
        literal.y >= pj_side_len(rank, PJ_SIDE_STRINGS))
        return 0u;
    uint length = pj_side(rank, PJ_SIDE_STRINGS, literal.y, 0u).z;
    if (length >= 0xfffffffbu)
    {
        pj_row_fail(global, PJ_E_INPUT_CAPACITY, length);
        return 0u;
    }
    return (length + 4u) >> 2u;
}

public bool scan_projected_string_word_counts(inout StepProgram program, uint rows)
{
    if (pj_total(PJ_C_SIDE + PJ_SIDE_STRINGS) == 0u)
    {
        for (uint row = program.lane; row <= rows; row += program.lanes)
            pj_string_offsets[row] = 0u;
        return true;
    }

    if (program.lane == 0u) pj_scan_total[1u] = 0u;
    uint ranks = pj_instance_count();
    for (uint row = program.lane; row <= rows; row += program.lanes)
        pj_string_scratch[row] = row < rows ? projected_string_words(row, ranks) : 0u;
    if (!step_barrier(program)) return false;
    if (!step_program_prefix_scan(program, rows + 1u, pj_string_scratch, pj_string_offsets,
            pj_scan_total, pj_scan_sums)) return false;
    if (!step_barrier(program)) return false;

    // Find crossings even when the total wrapped. The checked scan below
    // reproduces the original capacity diagnostics for those inputs.
    for (uint row = program.lane; row < rows; row += program.lanes)
    {
        uint offset = pj_string_offsets[row];
        if (offset + pj_string_scratch[row] > 0x3fffffffu || offset > 0x3fffffffu)
            InterlockedOr(pj_scan_total[1u], 1u);
    }
    if (!step_barrier(program)) return false;
    if (pj_scan_total[1u] == 0u) return true;

    for (uint i = program.lane; i <= rows; i += program.lanes)
        pj_string_offsets[i] = i != 0u ? pj_string_scratch[i - 1u] : 0u;
    if (!step_barrier(program)) return false;
    bool from_offsets = true;
    for (uint distance = 1u; ; distance *= 2u)
    {
        for (uint i = program.lane; i <= rows; i += program.lanes)
        {
            uint own = from_offsets ? pj_string_offsets[i] : pj_string_scratch[i];
            uint prior = i >= distance ?
                (from_offsets ? pj_string_offsets[i - distance] : pj_string_scratch[i - distance]) : 0u;
            if (own > 0x3fffffffu || prior > 0x3fffffffu - min(own, 0x3fffffffu))
            {
                pj_row_fail(min(i, rows - 1u), PJ_E_INPUT_CAPACITY, own);
                own = prior = 0u;
            }
            if (from_offsets) pj_string_scratch[i] = own + prior;
            else pj_string_offsets[i] = own + prior;
        }
        if (!step_barrier(program)) return false;
        from_offsets = !from_offsets;
        if (distance > rows / 2u) break;
    }
    if (!from_offsets)
        for (uint i = program.lane; i <= rows; i += program.lanes)
            pj_string_offsets[i] = pj_string_scratch[i];
    return true;
}
