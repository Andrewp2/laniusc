import type_checker.retention.retained_snapshot_copy;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    copy_snapshot_rows(tid.x);
}
