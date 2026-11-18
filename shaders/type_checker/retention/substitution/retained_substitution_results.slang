// The consumer side of a substitution publication
// (docs/compiler-retained-substitution.md, "Publication contract").
//
// A consumer binds the publication's sb_results and sb_counts (read-only),
// the store it substitutes against (rt_counts) and the run number the host
// gave it with the publication (RetainedSubstitution::publication,
// PublicationId.run). It may read a result's TermId only when
// sb_result_current holds:
// - the publication committed (SB_STATE_PUBLISHED) in run `run`, so a
//   buffer left over from another run, an overflowed or request-capacity
//   run, or a run the host abandoned does not match;
// - the publication's store generation is the bound store's current
//   generation, which is unique per build of every store, so results of an
//   earlier build or of another store do not match;
// - the store is READY (a later export or substitution error clears it);
// - the row is below the published request count and carries the same run
//   and generation.
import type_checker.retention.retention_store;
__exported import type_checker.retention.substitution.retained_substitution_layout;

public StructuredBuffer<uint4> sb_results;
public StructuredBuffer<uint> sb_counts;

public bool sb_publication_current(uint run)
{
    return run != 0u && sb_counts[SB_C_STATE] == SB_STATE_PUBLISHED && sb_counts[SB_C_RUN] == run &&
        sb_counts[SB_C_GENERATION] != 0u && sb_counts[SB_C_GENERATION] == rt_counts[RT_C_GENERATION] &&
        rt_counts[RT_C_READY] != 0u;
}

public bool sb_result_current(uint run, uint request)
{
    if (!sb_publication_current(run) || request >= sb_counts[SB_C_REQUESTS]) return false;
    uint4 r1 = sb_results[request * SB_RESULT_WORDS + 1u];
    return r1.z == run && r1.w == sb_counts[SB_C_GENERATION];
}
