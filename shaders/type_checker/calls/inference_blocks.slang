// HIR and token lists use one workgroup per tile. The argument list packs
// eight 32-row tiles per workgroup. The final pass, the first round and rounds
// after a global change use the ordinary grid.
module inference_blocks;
import type_checker.calls.inference_activity;

public StructuredBuffer<uint> inference_hir_blocks;
public StructuredBuffer<uint> inference_token_blocks;
public StructuredBuffer<uint> inference_arg_blocks;

uint inference_listed_row(StructuredBuffer<uint> blocks, uint linear, uint tile_rows)
{
    if (call_inference_round[0u] == 0u || blocks[0u] == 0u) return linear;
    uint tile = linear / tile_rows;
    if (tile >= blocks[1u]) return 0xffffffffu;
    return blocks[2u + tile] * tile_rows + linear % tile_rows;
}

public uint inference_listed_hir_row(uint linear)
{
    return inference_listed_row(inference_hir_blocks, linear, 256u);
}

public uint inference_listed_token(uint linear)
{
    return inference_listed_row(inference_token_blocks, linear, 256u);
}

public uint inference_listed_argument(uint linear)
{
    return inference_listed_row(inference_arg_blocks, linear, 32u);
}
