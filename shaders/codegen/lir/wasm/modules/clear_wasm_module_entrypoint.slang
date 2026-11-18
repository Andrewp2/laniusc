RWStructuredBuffer<uint> wasm_module_entrypoint_state;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    wasm_module_entrypoint_state[0u] = 0u;
    wasm_module_entrypoint_state[1u] = 0xffffffffu;
}
