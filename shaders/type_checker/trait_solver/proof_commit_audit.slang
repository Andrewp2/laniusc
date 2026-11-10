// Shared words of the grid-wide commit audits. A commit stage runs as audit
// lanes, one per owner row over the whole grid, and then one thread that
// reads their verdict here and publishes or reports the failure.
//
// Protocol. The header's verdict words are zero when a stage's first audit
// lane runs: the host zeroes the header before a solver attempt, and every
// committing thread resets them, whether or not it commits. A stage's
// dispatches are recorded together, so no other stage's lanes run between its
// audit and its commit.
//
// Claims. An exact cover needs every destination row owned once. Each owner
// stamps its rows with the audit's tag, one claim word per row. A row that
// already carries the tag has a second owner, and that owner's lane records
// the row. The committing thread advances the tag, so claim words are never
// cleared. A tag belongs to one stage's lanes: they and their thread run in
// one submission, a new buffer is zeroed, and the tag is never zero.
//
// Verdict. Owner spans that stay inside a table's pending suffix, claim no row
// twice and number its rows cover the suffix exactly once. The lanes record
// what breaks this, each record independent of lane order: the lowest owner
// whose own rows are invalid, the lowest row of each table with two owners,
// and the rows claimed in each table.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;

public RWStructuredBuffer<uint> trait_solver_commit_audit;

public static const uint PCA_EPOCH = 0u;      // the tag is this plus one
public static const uint PCA_FAILED = 1u;     // complement of the lowest invalid owner row
public static const uint PCA_AUDITED = 2u;    // owner rows the lanes audited
public static const uint PCA_LIMIT = 3u;      // PCA_LIMIT_* flags
public static const uint PCA_PUBLISHED = 4u;  // the phase whose commit let its later lanes run
public static const uint PCA_TOTALS = 5u;     // rows claimed in each of five tables
public static const uint PCA_CONFLICTS = 10u; // complement of each table's lowest row with two owners
public static const uint PCA_HEADER = 16u;    // claim words follow

static const uint PCA_LIMIT_TOTAL = 1u;       // a count passed 32 bits
static const uint PCA_LIMIT_CLAIMS = 2u;      // a row has no claim word

public uint pca_word(uint word) { return trait_solver_commit_audit[word]; }
public uint pca_tag() { return trait_solver_commit_audit[PCA_EPOCH] + 1u; }
// Records an owner whose own rows are invalid. Complements make the lowest
// row the largest word and leave zero for none.
public void pca_fail_owner(uint owner)
{ InterlockedMax(trait_solver_commit_audit[PCA_FAILED], ~owner); }
public void pca_add(uint word, uint count)
{
    if (count == 0u) return;
    uint previous;
    InterlockedAdd(trait_solver_commit_audit[word], count, previous);
    if (count > TS_INVALID - previous) InterlockedOr(trait_solver_commit_audit[PCA_LIMIT], PCA_LIMIT_TOTAL);
}
// The committing thread's reset, after it has read the verdict.
public void pca_reset()
{
    trait_solver_commit_audit[PCA_EPOCH] = trait_solver_commit_audit[PCA_EPOCH] + 1u;
    [loop]
    for (uint word = PCA_FAILED; word < PCA_HEADER; word++) trait_solver_commit_audit[word] = 0u;
}
// Whether an owner's span is canonical for the table described by
// `descriptor`: empty at zero, or wholly inside the pending suffix.
public bool pca_pending_span(uint4 descriptor, uint first, uint count)
{
    if (count == 0u) return first == 0u;
    return first >= descriptor.w && first < descriptor.y && count <= descriptor.y - first;
}
// Claims one owner's span of `table`, the stage's table `slot`. The caller
// has checked the span with pca_pending_span. Every row is claimed, so the
// rows with two owners do not depend on which owner claimed first.
//
// Every claimed table has rows at least two words wide, so halving a row's
// first word address in the proof arena gives each row its own claim word.
public void pca_claim(uint slot, uint table, uint4 descriptor, uint span_first, uint span_count, uint tag)
{
    if (span_count == 0u) return;
    uint words; uint stride;
    trait_solver_commit_audit.GetDimensions(words, stride);
    uint width = pps_width(table);
    if (width < 2u || PCA_HEADER + ((descriptor.x + (span_first + span_count - 1u) * width) >> 1u) >= words)
    {
        InterlockedOr(trait_solver_commit_audit[PCA_LIMIT], PCA_LIMIT_CLAIMS);
        return;
    }
    [loop]
    for (uint index = 0u; index < span_count; index++)
    {
        uint row = span_first + index;
        uint claim = PCA_HEADER + ((descriptor.x + row * width) >> 1u);
        uint seen = trait_solver_commit_audit[claim];
        uint previous = seen;
        // Compare-exchange, not exchange: Slang 2026.2 mislowers
        // InterlockedExchange's original-value operand. Only this tag is
        // written during the stage, so a lost exchange met another owner.
        if (seen != tag)
            InterlockedCompareExchange(trait_solver_commit_audit[claim], seen, tag, previous);
        if (seen == tag || previous != seen)
            InterlockedMax(trait_solver_commit_audit[PCA_CONFLICTS + slot], ~row);
    }
}
// The lanes' verdict on everything but the tables: `owners` owner rows were
// to be audited.
public SolverStatus pca_audit_verdict(uint owners)
{
    uint limit = pca_word(PCA_LIMIT); uint audited = pca_word(PCA_AUDITED);
    if ((limit & PCA_LIMIT_TOTAL) != 0u) return ts_limit(64u, PPS_WORK, TS_INVALID, TS_INVALID - 1u);
    if ((limit & PCA_LIMIT_CLAIMS) != 0u) return ts_invalid(66u, TS_INVALID, limit);
    return audited == owners ? ts_ok() : ts_invalid(66u, audited, owners);
}
// The lanes' verdict on the stage's table `slot`, whose pending suffix has
// `pending` rows: a row with two owners, or claimed rows that do not number
// the suffix, reported with `detail`.
public SolverStatus pca_cover_verdict(uint slot, uint table, uint pending, uint detail)
{
    uint conflict = pca_word(PCA_CONFLICTS + slot); uint total = pca_word(PCA_TOTALS + slot);
    if (conflict != 0u) return ts_invalid(66u, table, ~conflict);
    return total == pending ? ts_ok() : ts_invalid(detail, table, total);
}
