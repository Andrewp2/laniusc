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
};
