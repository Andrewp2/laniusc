// Durable checked-call record shared by type checking and target-independent
// lowering. Keep the stable dependency identity explicit: page-local rows may
// never cross this semantic artifact boundary.

struct CheckedCallArtifact
{
    uint target_token;
    uint dependency_library_id;
    uint dependency_unit_id;
    uint dependency_local_index;
    uint dependency_host_service;
    uint intrinsic_tag;
    uint return_type;
    uint receiver_hir;
    uint arg_count;
    uint return_ref_tag;
    uint return_ref_payload;
    // Checked callable classification. This distinguishes ordinary functions
    // from call-shaped language constructs such as enum constructors before
    // target-independent lowering sees the record.
    uint callable_kind;
    // Dense local declaration-family HIR row and declaration-specific
    // ordinal. Both are INVALID when the callable is not a local declaration.
    uint callable_hir;
    uint callable_ordinal;
    // Method lookup owns the adjustment. The source expression retains its
    // original type; these fields describe the accepted receiver parameter.
    // None=0 (no implicit receiver), Value=1, BorrowPlace=2.
    uint receiver_adjustment_kind;
    uint receiver_deref_count;
    uint receiver_matched_ref_tag;
    uint receiver_matched_ref_payload;
    uint receiver_parameter_ref_tag;
    uint receiver_parameter_ref_payload;
};

// `semantic_calls_by_hir` is sparse by HIR kind. Every HIR_CALL_EXPR row is
// initialized in full; no consumer may inspect a row of any other kind.
