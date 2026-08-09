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
};
