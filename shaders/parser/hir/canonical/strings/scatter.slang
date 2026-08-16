import hir_records;

struct Params {
    uint raw_capacity;
    uint canonical_capacity;
    uint uses_status_count;
    uint local_ancestor_span;
    uint records_use_token_rows;
};

ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> raw_string_count;
StructuredBuffer<uint> raw_string_node;
StructuredBuffer<uint> raw_string_data_offset;
StructuredBuffer<uint> raw_string_decoded_len;
RWStructuredBuffer<HirString> hir_strings;
RWStructuredBuffer<HirPayload> hir_payload;
RWStructuredBuffer<uint> canonical_status;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint mapped(uint raw)
{
    return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID;
}
uint file_for_raw(uint raw)
{
    uint token = raw < gCanonical.raw_capacity ? hir_token_pos[raw] : INVALID;
    return token < gCanonical.canonical_capacity ? token_file_id[token] : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    uint count = min(raw_string_count[0u], gCanonical.canonical_capacity);
    if (row >= count) return;
    uint raw = raw_string_node[row];
    uint literal_row = gCanonical.records_use_token_rows != 0u
        ? hir_token_pos[raw]
        : raw;
    HirString string_row;
    string_row.node = mapped(raw);
    string_row.data_offset = raw_string_data_offset[literal_row];
    string_row.decoded_len = raw_string_decoded_len[literal_row];
    string_row.file_id = file_for_raw(raw);
    hir_strings[row] = string_row;
    if (string_row.node != INVALID)
    {
        HirPayload payload = hir_payload[string_row.node];
        payload.b = row;
        hir_payload[string_row.node] = payload;
    }
    if (string_row.node == INVALID)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
    }
}
