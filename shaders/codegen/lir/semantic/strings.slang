import codegen.lowering_ir;
import gpu_index;

struct Params
{
    uint string_capacity;
    uint word_capacity;
    uint n_hir_nodes;
    uint reserved;
};
struct HirString { uint node; uint data_offset; uint decoded_len; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_string_count;
StructuredBuffer<HirString> compact_strings;
StructuredBuffer<uint> compact_string_pool_len;
StructuredBuffer<uint> compact_string_data;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_lir_offset;
RWStructuredBuffer<uint> semantic_lir_string_total;
RWStructuredBuffer<SemanticLirString> semantic_lir_strings;
RWStructuredBuffer<uint> semantic_lir_string_pool_len;
RWStructuredBuffer<uint> semantic_lir_string_data;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint string_count = min(compact_string_count[0u], gParams.string_capacity);
    uint byte_count = min(compact_string_pool_len[0u], gParams.word_capacity * 4u);
    if (row == 0u && (compact_string_count[0u] > gParams.string_capacity ||
                     compact_string_pool_len[0u] > gParams.word_capacity * 4u))
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_STRING_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity,
                       max(compact_string_count[0u], compact_string_pool_len[0u]));
        InterlockedMin(lowering_status[0u].available_capacity,
                       min(gParams.string_capacity, gParams.word_capacity * 4u));
    }
    uint word_count = (byte_count + 3u) / 4u;
    if (row == 0u)
    {
        semantic_lir_string_total[0u] = string_count;
        semantic_lir_string_pool_len[0u] = byte_count;
    }
    if (row < string_count)
    {
        HirString source = compact_strings[row];
        SemanticLirString result;
        result.instruction = source.node < gParams.n_hir_nodes &&
            semantic_lir_count[source.node] != 0u
            ? semantic_lir_offset[source.node] : INVALID;
        result.data_offset = source.data_offset;
        result.decoded_len = source.decoded_len;
        result.file_id = source.file_id;
        semantic_lir_strings[row] = result;
    }
    if (row < word_count)
        semantic_lir_string_data[row] = compact_string_data[row];
}
