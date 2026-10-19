// Early exit for bounded HIR relation walks.
//
// A walk records a fixed number of ping-pong rounds (enough for the longest
// chain the tree capacity allows). Real chains are short, so after the first
// rounds every further round rewrites the same values. Each round therefore
// reports whether any row it wrote differs from its input. A round whose
// previous round changed nothing returns at once: the two ping-pong buffers
// already hold the same rows, so every later round would be the identity.
//
// `hir_walk_state` holds two words per round region: changed, ran. The host
// binds a uniform record per (walk, round) naming the word index of the
// previous round's region and of this round's. A walk's first round sees a
// region nothing writes (the state is cleared once per HIR run), so it always
// runs. The dispatch's first thread marks the round as ran even when it is
// skipped, so a skipped round also skips the next.

public struct HirWalkRound
{
    public uint previous;
    public uint this_round;
};

// True when the previous round of this walk ran and changed no row. The value
// is uniform over the dispatch: only earlier dispatches write these words.
public bool hir_walk_round_redundant(RWStructuredBuffer<uint> state, HirWalkRound round)
{
    return state[round.previous + 1u] != 0u && state[round.previous] == 0u;
}

public void hir_walk_mark_ran(RWStructuredBuffer<uint> state, HirWalkRound round, uint linear_thread)
{
    if (linear_thread == 0u)
        state[round.this_round + 1u] = 1u;
}

public void hir_walk_mark_changed(RWStructuredBuffer<uint> state, HirWalkRound round)
{
    state[round.this_round] = 1u;
}
