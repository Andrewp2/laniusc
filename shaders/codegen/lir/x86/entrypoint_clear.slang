RWStructuredBuffer<uint> x86_entrypoint_state;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    x86_entrypoint_state[0u] = 0u;
    x86_entrypoint_state[1u] = 0xffffffffu;
}
