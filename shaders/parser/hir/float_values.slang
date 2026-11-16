// Exact decimal candidates. The literal pass claims one dense slot per float
// literal (one lane per HIR node), so each lane pair here owns one claimed
// literal and each lane one storage workspace. Only a job with more literals
// than lane pairs makes a pair take a second literal. Ordinary parser lanes
// never reserve private digit arrays.
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

// Host allocates exactly FLOAT_LANES disjoint workspaces and dispatches
// FLOAT_LANES / FLOAT_GROUP_SIZE groups. Adjacent lanes form a pair: the even
// lane converts a literal to f32, the odd lane converts the same literal to
// f64, and the odd lane publishes both through groupshared memory. Small
// groups spread the lanes over many SMs; each lane is latency bound.
static const uint FLOAT_LANES = 4096u;
static const uint FLOAT_GROUP_SIZE = 64u;
static const uint FLOAT_PAIRS = FLOAT_LANES / 2u;
static const uint HIR_FLOAT_COUNT_SLOT = 3u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint INVALID_ROW = 0xffffffffu;

groupshared uint g_bits32[FLOAT_GROUP_SIZE / 2u];
groupshared uint g_status32[FLOAT_GROUP_SIZE / 2u];

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint lane: SV_GroupIndex)
{
    uint worker = dtid.x;
    uint pair = worker >> 1u;
    uint pair_slot = lane >> 1u;
    bool is_f64 = (worker & 1u) != 0u;
    uint float_capacity;
    uint float_stride;
    hir_float_nodes.GetDimensions(float_capacity, float_stride);
    uint claimed = min(hir_literal_status[HIR_FLOAT_COUNT_SLOT], float_capacity);
    uint active = gHirLiteral.uses_status_count != 0u
        ? min(gHirLiteral.n, tree_count_status[5u]) : gHirLiteral.n;
    uint capacity = gHirLiteral.retain_debug_rows != 0u
        ? gHirLiteral.n : gHirLiteral.token_capacity;
    // Uniform over the dispatch, so every lane reaches every barrier.
    uint rounds = claimed / FLOAT_PAIRS + (claimed % FLOAT_PAIRS != 0u ? 1u : 0u);
    for (uint round = 0u; round < rounds; ++round)
    {
        uint entry = pair + round * FLOAT_PAIRS;
        uint row = INVALID_ROW;
        uint2 bits = uint2(0u, 0u);
        uint status = FLOAT_DECIMAL_INVALID_SPAN;
        if (entry < claimed)
        {
            uint node = hir_float_nodes[entry];
            if (node < active)
                row = gHirLiteral.retain_debug_rows != 0u ? node : hir_token_pos[node];
            if (row < capacity && hir_expr_record[node * 4u] == HIR_EXPR_FLOAT)
            {
                uint token = hir_expr_record[node * 4u + 3u];
                if (token < gHirLiteral.token_capacity)
                {
                    TokenIn span = token_words[token];
                    uint consumed;
                    status = float_decimal_parse_bits(source_bytes, gHirLiteral.source_len,
                        span.start, span.len, is_f64 ? SCALAR_F64 : SCALAR_F32, false,
                        hir_float_workspace, worker * FLOAT_DECIMAL_WORKSPACE_WORDS,
                        bits, consumed);
                }
            }
            else row = INVALID_ROW;
        }
        if (!is_f64)
        {
            g_bits32[pair_slot] = bits.x;
            g_status32[pair_slot] = status;
        }
        GroupMemoryBarrierWithGroupSync();
        if (is_f64 && row != INVALID_ROW)
            hir_expr_float_bits[row] = uint4(g_bits32[pair_slot], bits.x, bits.y,
                g_status32[pair_slot] | (status << 8u));
        GroupMemoryBarrierWithGroupSync();
    }
}
