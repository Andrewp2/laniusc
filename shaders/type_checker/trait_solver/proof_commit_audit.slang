// Shared words of the grid-wide commit audits. A commit stage runs as audit
// lanes, one per owner row over the whole grid, and then one thread that
// reads their verdict here and publishes. The lanes prove success only: when
// the verdict is anything else, the committing thread runs the serial stage
// for its exact result.
//
// Protocol. The header's verdict words are zero when a stage's first audit
// lane runs: the host zeroes the header before a solver attempt, and every
// committing thread resets them, whether or not it commits. A stage's dispatches are recorded together, so no
// other stage's lanes run between its audit and its commit.
//
// Claims. An exact cover needs every destination row owned once. Each owner
// stamps its rows with the audit's tag, one claim word per row, and fails the
// audit when a row already carries the tag. The committing thread advances the
// tag, so claim words are never cleared. Stale or uninitialized claim words can
// only fail an audit, which falls back to the serial stage; they cannot pass
// one, because two owners of one row always meet on its claim word.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_span_coverage;

public RWStructuredBuffer<uint> trait_solver_commit_audit;

public static const uint PCA_EPOCH = 0u;      // the tag is this plus one
public static const uint PCA_FAILED = 1u;     // some lane could not prove its rows
public static const uint PCA_AUDITED = 2u;    // owner rows the lanes audited
public static const uint PCA_TOUCHED = 3u;    // serial bitmap-word charges of the owners
public static const uint PCA_PUBLISHED = 4u;  // the phase whose commit let its later lanes run
public static const uint PCA_SERIAL = 5u;     // commits of this attempt that ran their serial stage
public static const uint PCA_GRID = 6u;       // commits of this attempt the lanes proved
public static const uint PCA_TOTALS = 8u;     // five row totals
public static const uint PCA_HEADER = 16u;    // claim words follow

public uint pca_word(uint word) { return trait_solver_commit_audit[word]; }
public uint pca_tag() { return trait_solver_commit_audit[PCA_EPOCH] + 1u; }
public void pca_fail() { InterlockedOr(trait_solver_commit_audit[PCA_FAILED], 1u); }
// A sum past 32 bits fails the audit, as it fails the serial count.
public void pca_add(uint word, uint count)
{
    if (count == 0u) return;
    uint previous;
    InterlockedAdd(trait_solver_commit_audit[word], count, previous);
    if (count > TS_INVALID - previous) pca_fail();
}
// The committing thread's reset, after it has read the verdict. The
// attempt's two commit counts stay; only the host zeroes them.
public void pca_reset()
{
    trait_solver_commit_audit[PCA_EPOCH] = trait_solver_commit_audit[PCA_EPOCH] + 1u;
    [loop]
    for (uint word = PCA_FAILED; word < PCA_HEADER; word++)
        if (word != PCA_SERIAL && word != PCA_GRID) trait_solver_commit_audit[word] = 0u;
}
// Counts a building commit by how it was decided.
public void pca_count(bool proven)
{
    uint word = proven ? PCA_GRID : PCA_SERIAL;
    trait_solver_commit_audit[word] = trait_solver_commit_audit[word] + 1u;
}
// One owner's span of `table`, whose valid descriptor is `descriptor`: the
// checks pps_check_span_cover makes of it against the pending suffix, its
// serial bitmap-word charge, and a claim on each of its rows.
//
// Every claimed table has rows at least two words wide, so halving a row's
// first word address in the proof arena gives each row its own claim word.
public void pca_cover(uint table, uint4 descriptor, uint span_first, uint span_count, uint tag)
{
    uint first = descriptor.w; uint end = descriptor.y;
    if (span_count == 0u) { if (span_first != 0u) pca_fail(); return; }
    if (span_first < first || span_first >= end || span_count > end - span_first) { pca_fail(); return; }
    pca_add(PCA_TOUCHED, pps_cover_span_words(first, span_first, span_count));
    uint words; uint stride;
    trait_solver_commit_audit.GetDimensions(words, stride);
    uint width = pps_width(table);
    bool clean = width >= 2u;
    [loop]
    for (uint index = 0u; index < span_count && clean; index++)
    {
        uint slot = PCA_HEADER + ((descriptor.x + (span_first + index) * width) >> 1u);
        if (slot >= words) { clean = false; break; }
        uint seen = trait_solver_commit_audit[slot];
        uint previous = seen;
        // Compare-exchange, not exchange: Slang 2026.2 mislowers
        // InterlockedExchange's original-value operand.
        if (seen != tag)
            InterlockedCompareExchange(trait_solver_commit_audit[slot], seen, tag, previous);
        clean = seen != tag && previous == seen;
    }
    if (!clean) pca_fail();
}
