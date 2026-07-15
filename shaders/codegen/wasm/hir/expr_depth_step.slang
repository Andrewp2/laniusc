// Double expression-forest ancestor spans and accumulate their depths.

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;

StructuredBuffer<uint2> expr_depth_state_in;
RWStructuredBuffer<uint2> expr_depth_state_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (node >= gExprRadix.n_items)
        return;

    uint2 state = expr_depth_state_in[node];
    if (state.x == INVALID || state.x >= gExprRadix.n_items || state.x == node)
    {
        expr_depth_state_out[node] = uint2(INVALID, state.y);
        return;
    }

    uint2 ancestor = expr_depth_state_in[state.x];
    expr_depth_state_out[node] = uint2(ancestor.x, state.y + ancestor.y);
}
