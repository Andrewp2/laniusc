import prefix_scan;
import canonical_hir_identity;
struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> family_flag;
StructuredBuffer<uint> family_local_prefix;
StructuredBuffer<uint> family_block_prefix;
StructuredBuffer<uint> raw_to_hir;
StructuredBuffer<uint> canonical_anchor_owner;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> decl_owner;
StructuredBuffer<uint> decl_ordinal;
StructuredBuffer<uint> decl_type;
StructuredBuffer<uint> literal_owner;
StructuredBuffer<uint> literal_ordinal;
StructuredBuffer<uint> literal_value;
StructuredBuffer<uint> expr_result_root;
StructuredBuffer<uint> hir_call_callee_node;
RWStructuredBuffer<uint> family_count;
RWStructuredBuffer<HirField> hir_fields;
RWStructuredBuffer<uint> hir_payload_words;
RWStructuredBuffer<uint> canonical_status;
static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_FILE = 1u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint block_count() { return (gCanonical.raw_capacity + 255u) / 256u; }
uint semantic_anchor(uint raw)
{
    uint kind = hir_kind[raw];
    uint callee = hir_call_callee_node[raw];
    uint open = callee < gCanonical.raw_capacity ? hir_token_end[callee] : INVALID;
    uint right = hir_expr_record[raw * 4u + 2u];
    uint right_start = right < gCanonical.raw_capacity ? hir_token_pos[right] : INVALID;
    uint operator_token = canonical_hir_operator_anchor(
        kind, right_start, gCanonical.canonical_capacity);
    uint value_token = hir_expr_record[raw * 4u + 3u];
    return canonical_hir_anchor(kind, hir_token_pos[raw], hir_token_end[raw], open, value_token,
                                operator_token, gCanonical.canonical_capacity);
}
uint mapped(uint raw)
{
    if (raw >= gCanonical.raw_capacity) return INVALID;
    uint direct = raw_to_hir[raw];
    if (direct != INVALID) return direct;
    uint anchor = semantic_anchor(raw);
    if (anchor >= gCanonical.canonical_capacity) return INVALID;
    uint winner_plus_one = canonical_anchor_owner[anchor] & 0x0fffffffu;
    return winner_plus_one == 0u ? INVALID : raw_to_hir[winner_plus_one - 1u];
}
uint mapped_expression(uint raw)
{
    if (raw >= gCanonical.raw_capacity) return INVALID;
    uint root = expr_result_root[raw];
    uint dense = mapped(root);
    return dense != INVALID ? dense : mapped(raw);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    uint total = inclusive_scan_total(block_count(), family_block_prefix);
    if (raw == 0u) family_count[0u] = total;
    if (raw >= gCanonical.raw_capacity || family_flag[raw] == 0u) return;
    uint block = raw / 256u;
    uint base = block == 0u ? 0u : family_block_prefix[block - 1u];
    uint row = base + family_local_prefix[raw];
    if (row >= gCanonical.canonical_capacity)
    {
        uint ignored;
        InterlockedMax(canonical_status[0u], 3u, ignored);
        InterlockedMax(canonical_status[3u], raw + 1u, ignored);
        return;
    }
    bool declaration = decl_owner[raw] != INVALID;
    HirField field;
    field.owner = mapped(declaration ? decl_owner[raw] : literal_owner[raw]);
    field.name_token = hir_token_pos[raw];
    uint raw_value = declaration ? decl_type[raw] : literal_value[raw];
    field.value = declaration ? mapped(raw_value) : mapped_expression(raw_value);
    field.ordinal = declaration ? decl_ordinal[raw] : literal_ordinal[raw];
    hir_fields[row] = field;
    if (!declaration && field.owner != INVALID &&
        field.owner < gCanonical.canonical_capacity && field.ordinal != INVALID)
    {
        uint ignored;
        InterlockedMin(hir_payload_words[field.owner * 4u + 1u], row, ignored);
        InterlockedMax(hir_payload_words[field.owner * 4u + 2u], field.ordinal + 1u, ignored);
    }
    if (declaration && field.value == INVALID)
    {
        uint original;
        InterlockedCompareExchange(canonical_status[9u], 0u, raw + 1u, original);
        if (original == 0u)
        {
            uint anchor = raw_value < gCanonical.raw_capacity ? semantic_anchor(raw_value) : INVALID;
            uint winner = anchor < gCanonical.canonical_capacity
                ? canonical_anchor_owner[anchor] & 0x0fffffffu
                : 0u;
            canonical_status[10u] = raw_value + 1u;
            canonical_status[11u] = anchor + 1u;
            canonical_status[12u] = winner;
        }
    }
}
