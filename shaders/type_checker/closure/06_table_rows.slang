// A retrying row dispatch of the instance table (table_rows.slang).
#include "table_rows.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    realize_row(dtid.x + dtid.y * 16776960u, false);
}
