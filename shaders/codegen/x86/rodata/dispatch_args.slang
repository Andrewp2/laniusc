// Build one-workgroup-per-canonical-string indirect dispatch arguments.
StructuredBuffer<uint> compact_string_count;
RWStructuredBuffer<uint> string_dispatch_args;
static const uint MAX_GROUPS_X = 65535u;
[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (any(dtid != uint3(0u))) return;
    uint groups = max(1u, compact_string_count[0]);
    string_dispatch_args[0] = min(groups, MAX_GROUPS_X);
    string_dispatch_args[1] = (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
    string_dispatch_args[2] = 1u;
}
