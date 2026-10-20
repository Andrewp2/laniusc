// Size the instance table's row dispatches (06_table_rows, 06a): one lane
// per virtual row, none when the table is flagged (the host ignores it).
import type_checker.closure.instance_closure;
import type_checker.closure.instance_table;

RWStructuredBuffer<uint> instance_table_args;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint rows = instance_table_counts[IT_COUNT_FLAGS] != 0u ? 0u
        : min(instance_table_counts[IT_COUNT_ROWS], it_row_capacity());
    uint groups = (rows + 255u) / 256u;
    uint x = min(groups, 65535u);
    instance_table_args[0u] = x;
    instance_table_args[1u] = x == 0u ? 0u : (groups + 65534u) / 65535u;
    instance_table_args[2u] = 1u;
}
