// Publishes the token count and one total of a finished scan for the host.
struct SummaryParams
{
    uint slot;
    uint component;
    uint reserved0;
    uint reserved1;
};

ConstantBuffer<SummaryParams> gSummary;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint4> scan_result;
RWStructuredBuffer<uint> summary;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0u || tid.y != 0u || tid.z != 0u)
        return;
    uint count = token_count[0];
    summary[0] = count;
    uint4 last = uint4(0u, 0u, 0u, 0u);
    if (count > 0u)
        last = scan_result[count - 1u];
    summary[gSummary.slot] = gSummary.component == 0u ? last.x : last.y;
}
