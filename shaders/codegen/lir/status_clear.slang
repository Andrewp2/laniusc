import codegen.lowering_ir;

RWStructuredBuffer<LoweringStatus> lowering_status;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    LoweringStatus status;
    status.flags = 0u;
    status.first_unsupported_hir = 0xffffffffu;
    status.required_capacity = 0u;
    status.available_capacity = 0xffffffffu;
    lowering_status[0u] = status;
}
