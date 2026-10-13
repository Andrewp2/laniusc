// One complete method-selection transaction owns this record. Contributors
// run sequentially across the local inventory and retained dependency pages;
// no contributor publishes a callable signature while gathering candidates.
public static const uint METHOD_CANDIDATE_NO_MATCH = 0u;
public static const uint METHOD_CANDIDATE_UNIQUE = 1u;
public static const uint METHOD_CANDIDATE_AMBIGUOUS = 2u;
public static const uint METHOD_CANDIDATE_INVALID = 3u;
public static const uint METHOD_CALLABLE_LOCAL = 1u;
public static const uint METHOD_CALLABLE_DEPENDENCY = 2u;

public struct MethodCandidate
{
    public uint state;
    public uint deref_count;
    public uint module_preference;
    public uint callable_kind;
    public uint library_id;
    public uint unit_id;
    public uint local_index;
    public uint matched_ref_tag;
    public uint matched_ref_payload;
    public uint receiver_mode;
}

public MethodCandidate method_candidate_empty()
{
    MethodCandidate value;
    value.state = METHOD_CANDIDATE_NO_MATCH;
    value.deref_count = 0xffffffffu;
    value.module_preference = 0xffffffffu;
    value.callable_kind = 0u;
    value.library_id = 0xffffffffu;
    value.unit_id = 0xffffffffu;
    value.local_index = 0xffffffffu;
    value.matched_ref_tag = 0u;
    value.matched_ref_payload = 0xffffffffu;
    value.receiver_mode = 0u;
    return value;
}

// Negative means left is preferred; zero means the same selection rank.
public int method_candidate_rank_compare(MethodCandidate left, MethodCandidate right)
{
    if (left.deref_count != right.deref_count)
        return left.deref_count < right.deref_count ? -1 : 1;
    if (left.module_preference != right.module_preference)
        return left.module_preference < right.module_preference ? -1 : 1;
    return 0;
}

public bool method_candidate_same_callable(MethodCandidate left, MethodCandidate right)
{
    return left.callable_kind == right.callable_kind &&
        left.library_id == right.library_id && left.unit_id == right.unit_id &&
        left.local_index == right.local_index;
}

public void method_candidate_offer(inout MethodCandidate summary, MethodCandidate candidate)
{
    if (summary.state == METHOD_CANDIDATE_INVALID ||
        candidate.state == METHOD_CANDIDATE_NO_MATCH) return;
    if (candidate.state == METHOD_CANDIDATE_INVALID)
    { summary = candidate; return; }
    if (candidate.state != METHOD_CANDIDATE_UNIQUE ||
        candidate.deref_count >= 64u || candidate.module_preference > 1u ||
        (candidate.callable_kind != METHOD_CALLABLE_LOCAL &&
         candidate.callable_kind != METHOD_CALLABLE_DEPENDENCY) ||
        candidate.local_index == 0xffffffffu || candidate.matched_ref_tag < 1u ||
        candidate.matched_ref_tag > 3u || candidate.matched_ref_payload == 0xffffffffu ||
        candidate.receiver_mode > 2u ||
        (candidate.callable_kind == METHOD_CALLABLE_LOCAL &&
         (candidate.library_id != 0xffffffffu || candidate.unit_id != 0xffffffffu)) ||
        (candidate.callable_kind == METHOD_CALLABLE_DEPENDENCY &&
         (candidate.library_id == 0xffffffffu || candidate.unit_id == 0xffffffffu)))
    { summary.state = METHOD_CANDIDATE_INVALID; return; }
    if (summary.state == METHOD_CANDIDATE_NO_MATCH ||
        method_candidate_rank_compare(candidate, summary) < 0)
    { summary = candidate; return; }
    if (method_candidate_rank_compare(candidate, summary) > 0) return;
    if (!method_candidate_same_callable(candidate, summary))
    { summary.state = METHOD_CANDIDATE_AMBIGUOUS; return; }
    // A frozen source graph has exactly one root at each dereference depth.
    // Repeated pages may repeat an identity, but may not disagree about it.
    if (candidate.matched_ref_tag != summary.matched_ref_tag ||
        candidate.matched_ref_payload != summary.matched_ref_payload ||
        candidate.receiver_mode != summary.receiver_mode)
        summary.state = METHOD_CANDIDATE_INVALID;
}

public bool method_candidate_is_winner(MethodCandidate summary,
    uint kind, uint library_id, uint unit_id, uint local_index)
{
    return summary.state == METHOD_CANDIDATE_UNIQUE &&
        summary.callable_kind == kind && summary.library_id == library_id &&
        summary.unit_id == unit_id && summary.local_index == local_index;
}
