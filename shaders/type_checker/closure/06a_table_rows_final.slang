// The final row dispatch of the instance table (table_rows.slang): a row
// still busy fails.
#include "table_rows.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    realize_row(dtid.x + dtid.y * 16776960u, true);
}
