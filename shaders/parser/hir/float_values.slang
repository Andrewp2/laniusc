// Exact decimal candidates, in a separate bounded-worker dispatch. Every
// worker owns one storage workspace and reuses it sequentially for both widths
// and each later token. Ordinary parser lanes never reserve private digit arrays.
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
RWStructuredBuffer<uint4> hir_expr_float_bits;
RWStructuredBuffer<uint> hir_float_workspace;

// Host allocates exactly this many disjoint workspaces and dispatches 8 groups.
static const uint FLOAT_WORKERS = 2048u;
static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint worker = dtid.x;
    if (worker >= FLOAT_WORKERS) return;
    uint active = gHirLiteral.uses_status_count != 0u
        ? min(gHirLiteral.n, tree_count_status[5u]) : gHirLiteral.n;
    uint capacity = gHirLiteral.retain_debug_rows != 0u
        ? gHirLiteral.n : gHirLiteral.token_capacity;
    for (uint node = worker; node < active;)
    {
        uint row = gHirLiteral.retain_debug_rows != 0u ? node : hir_token_pos[node];
        if (row < capacity && hir_expr_record[node * 4u] == 27u)
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
        // Checked subtraction bounds the grid-stride addition near u32::MAX.
        if (active - node <= FLOAT_WORKERS) break;
        node += FLOAT_WORKERS;
    }
}
