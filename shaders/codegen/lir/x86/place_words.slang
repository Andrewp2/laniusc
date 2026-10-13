import codegen.lowering_ir;
import gpu_index;
struct Params { uint token_capacity; uint parameter_capacity; uint local_capacity; uint function_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_local_total;
StructuredBuffer<SemanticLirLocal> semantic_lir_locals;
StructuredBuffer<uint4> semantic_place_storage_by_token;
RWStructuredBuffer<uint> x86_place_words_by_local;
static const uint DISPATCH_X_STRIDE = 16776960u;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.local_capacity) return;
    uint words = 0u;
    if (row < min(gParams.local_capacity, semantic_lir_local_total[0u]))
    {
        uint token = semantic_lir_locals[row].declaration_id;
        uint4 storage = token < gParams.token_capacity
            ? semantic_place_storage_by_token[token] : uint4(0u, 0u, 0u, 0u);
        // Empty addressable objects still have a unique, stable anchor.
        if (storage.x == 3u) words = max(storage.y, 1u);
    }
    x86_place_words_by_local[row] = words;
}
