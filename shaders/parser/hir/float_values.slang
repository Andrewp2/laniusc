// Exact decimal candidates. The literal pass claims one dense slot per float
// literal (one lane per HIR node), so each lane here owns one claimed literal
// and one storage workspace. Only a job with more literals than workspaces
// makes a lane take a second literal. Ordinary parser lanes never reserve
// private digit arrays.
import float_decimal;
import primitive_types;

struct Params { uint n; uint source_len; uint uses_status_count;
    uint token_capacity; uint retain_debug_rows; };
ConstantBuffer<Params> gHirLiteral;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<TokenIn> token_words;
ByteAddressBuffer source_bytes;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_literal_status;
StructuredBuffer<uint> hir_float_nodes;
RWStructuredBuffer<uint4> hir_expr_float_bits;
RWStructuredBuffer<uint> hir_float_workspace;

// Host allocates exactly this many disjoint workspaces and dispatches 8 groups.
static const uint FLOAT_WORKERS = 2048u;
static const uint HIR_FLOAT_COUNT_SLOT = 3u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint INVALID_ROW = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint worker = dtid.x;
    if (worker >= FLOAT_WORKERS) return;
    uint float_capacity;
    uint float_stride;
    hir_float_nodes.GetDimensions(float_capacity, float_stride);
    uint claimed = min(hir_literal_status[HIR_FLOAT_COUNT_SLOT], float_capacity);
    uint active = gHirLiteral.uses_status_count != 0u
        ? min(gHirLiteral.n, tree_count_status[5u]) : gHirLiteral.n;
    uint capacity = gHirLiteral.retain_debug_rows != 0u
        ? gHirLiteral.n : gHirLiteral.token_capacity;
    for (uint entry = worker; entry < claimed;)
    {
        uint node = hir_float_nodes[entry];
        uint row = INVALID_ROW;
        if (node < active)
            row = gHirLiteral.retain_debug_rows != 0u ? node : hir_token_pos[node];
        if (row < capacity && hir_expr_record[node * 4u] == HIR_EXPR_FLOAT)
        {
            uint token = hir_expr_record[node * 4u + 3u];
            uint2 bits32 = uint2(0u, 0u); uint2 bits64 = uint2(0u, 0u);
            uint status32 = FLOAT_DECIMAL_INVALID_SPAN;
            uint status64 = FLOAT_DECIMAL_INVALID_SPAN;
            if (token < gHirLiteral.token_capacity)
            {
                TokenIn span = token_words[token];
                uint consumed;
                status32 = float_decimal_parse_bits(source_bytes, gHirLiteral.source_len,
                    span.start, span.len, SCALAR_F32, false, hir_float_workspace,
                    worker * FLOAT_DECIMAL_WORKSPACE_WORDS, bits32, consumed);
                status64 = float_decimal_parse_bits(source_bytes, gHirLiteral.source_len,
                    span.start, span.len, SCALAR_F64, false, hir_float_workspace,
                    worker * FLOAT_DECIMAL_WORKSPACE_WORDS, bits64, consumed);
            }
            hir_expr_float_bits[row] = uint4(bits32.x, bits64.x, bits64.y,
                status32 | (status64 << 8u));
        }
        // Checked subtraction bounds the overflow stride near u32::MAX.
        if (claimed - entry <= FLOAT_WORKERS) break;
        entry += FLOAT_WORKERS;
    }
}
