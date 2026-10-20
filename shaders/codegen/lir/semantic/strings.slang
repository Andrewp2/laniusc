import hir_records;
import codegen.lowering_ir;
import gpu_index;

struct Params
{
    uint string_capacity;
    uint word_capacity;
    uint n_hir_nodes;
    // An instance-copy replay: its first copy HIR row plus one (0 otherwise).
    uint copy_start;
};

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

// First string row whose node is at or after `copy_row`. String rows, their
// nodes and their pool offsets all follow source order.
uint first_copy_string(uint copy_row, uint string_count)
{
    uint lo = 0u;
    uint hi = string_count;
    while (lo < hi)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (compact_strings[mid].node < copy_row) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

void flag_unsupported()
{
    InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_SEMANTIC);
}

// An instance-copy replay emits only the copies, whose text follows the
// template text, so its rodata is the pool from the first copy string on.
// The template's strings (all of them, or only those outside blanked bodies)
// are dead there, and dropping them makes the object independent of how the
// template was blanked. Ordinary jobs keep the whole pool.
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
    uint first = 0u;
    uint base = 0u;
    if (gParams.copy_start != 0u)
    {
        first = first_copy_string(gParams.copy_start - 1u, string_count);
        base = first < string_count
            ? min(compact_strings[first].data_offset, byte_count) : byte_count;
    }
    uint pool_len = byte_count - base;
    uint word_count = (pool_len + 3u) / 4u;
    if (row == 0u)
    {
        semantic_lir_string_total[0u] = string_count;
        semantic_lir_string_pool_len[0u] = pool_len;
    }
    if (row < string_count)
    {
        HirString source = compact_strings[row];
        SemanticLirString result;
        result.instruction = source.node < gParams.n_hir_nodes &&
            semantic_lir_count[source.node] != 0u
            ? semantic_lir_offset[source.node] : INVALID;
        result.data_offset = source.data_offset;
        if (row < first)
        {
            // A template string: dead in a copy replay, so it has no bytes.
            if (result.instruction != INVALID || source.node >= gParams.copy_start - 1u)
                flag_unsupported();
            result.data_offset = 0u;
        }
        else if (base != 0u)
        {
            if (source.data_offset < base) flag_unsupported();
            result.data_offset = source.data_offset - min(source.data_offset, base);
        }
        result.decoded_len = source.decoded_len;
        result.file_id = source.file_id;
        semantic_lir_strings[row] = result;
    }
    if (row < word_count)
    {
        uint source_words = (byte_count + 3u) / 4u;
        uint word = (base >> 2u) + row;
        uint shift = (base & 3u) * 8u;
        uint low = compact_string_data[word];
        uint high = shift != 0u && word + 1u < source_words ? compact_string_data[word + 1u] : 0u;
        semantic_lir_string_data[row] = shift != 0u ? (low >> shift) | (high << (32u - shift)) : low;
    }
}
