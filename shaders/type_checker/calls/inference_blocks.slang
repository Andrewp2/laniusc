// The rows a listed pass of the inference rounds visits
// (docs/compiler-call-inference-rounds.md, "Listed active blocks").
//
// A listed pass dispatches from inference_hir_list_args or
// inference_token_list_args, which 03m1 writes at the start of each round's
// passes. Word 0 of a block list is 0 when the pass visits every row (outside
// the rounds, in round 1 and after a change without an owning
// function): the dispatch is then the full grid and a lane's row is its own
// linear index. Otherwise the dispatch has one workgroup per listed block of
// 256 rows, a block that holds a row of a function active in the round:
// word 1 is their count and word 2 + w is workgroup w's block. Each lane still
// checks its own item with inference_item_active.
module inference_blocks;
import type_checker.calls.inference_activity;

public StructuredBuffer<uint> inference_hir_blocks;
public StructuredBuffer<uint> inference_token_blocks;

// The HIR row of the lane whose linear index (its kernel's own grid
// linearization) is `linear`.
public uint inference_listed_hir_row(uint linear)
{
    if (call_inference_round[0u] == 0u || inference_hir_blocks[0u] == 0u) return linear;
    return inference_hir_blocks[2u + linear / 256u] * 256u + linear % 256u;
}

// The token of the lane whose linear index is `linear`.
public uint inference_listed_token(uint linear)
{
    if (call_inference_round[0u] == 0u || inference_token_blocks[0u] == 0u) return linear;
    return inference_token_blocks[2u + linear / 256u] * 256u + linear % 256u;
}
