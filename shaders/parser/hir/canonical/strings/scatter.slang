import hir_records;
import canonical_hir_identity;

struct Params {
    uint raw_capacity;
    uint canonical_capacity;
    uint uses_status_count;
    uint local_ancestor_span;
    uint records_use_token_rows;
};

ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> canonical_anchor_owner;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_token_file_id;
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
uint semantic_anchor(uint raw)
{
    uint kind = hir_kind[raw];
    uint expr_form = hir_expr_record[raw * 4u];
    uint identity_kind = canonical_hir_identity_kind(kind, expr_form, false);
    uint callee = hir_call_callee_node[raw];
    uint open = callee < gCanonical.raw_capacity ? hir_token_end[callee] : INVALID;
    uint right = hir_expr_record[raw * 4u + 2u];
    uint right_start = right < gCanonical.raw_capacity ? hir_token_pos[right] : INVALID;
    uint operator_token = canonical_hir_operator_anchor(
        identity_kind, expr_form, right_start, hir_token_end[raw],
        gCanonical.canonical_capacity);
    uint value_token = hir_expr_record[raw * 4u + 3u];
    return canonical_hir_anchor(identity_kind, hir_token_pos[raw], hir_token_end[raw], open, value_token,
                                operator_token, gCanonical.canonical_capacity);
}
uint mapped(uint raw)
{
    return raw < gCanonical.raw_capacity ? raw_to_hir[raw] : INVALID;
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
    string_row.file_id = hir_token_file_id[raw];
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
