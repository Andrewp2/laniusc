// One exclusive projection job. Only the successful, exact-current receipt
// authorizes its selected rows; this arena never publishes proof-store rows.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;

public static const uint IAP_MAGIC = 0x49415031u;
public static const uint IAP_VERSION = 1u;
public static const uint IAP_MAX_REQUESTS = 64u;
public static const uint IAP_MAX_ROWS = 4096u;
public static const uint IAP_REQUEST_ROW = 6u;
public static const uint IAP_APP_ROW = 134u;
public static const uint IAP_BINDING_ROW = 326u;
public static const uint IAP_PREREQUISITE_ROW = 12614u;
public static const uint IAP_HOP_ROW = 16710u;
public static const uint IAP_STATUS_ROW = 20806u;
public static const uint IAP_TOTAL_ROWS = 20808u;

// Reuse the existing reflected exclusive-work binding. No recipes are bound.
public RWStructuredBuffer<uint> program_evidence_native_layout_work;

public bool iap_physical_work()
{
    uint actual; uint stride;
    program_evidence_native_layout_work.GetDimensions(actual, stride);
    return program_evidence_params.work_word_count == IAP_TOTAL_ROWS * 4u &&
        actual >= IAP_TOTAL_ROWS * 4u;
}
public uint4 iap_read4(uint row)
{
    // Callers first prove the fixed physical extent. Every row below is a
    // fixed section row plus an index bounded by that section's capacity.
    uint at = row * 4u;
    return uint4(program_evidence_native_layout_work[at],
        program_evidence_native_layout_work[at + 1u],
        program_evidence_native_layout_work[at + 2u],
        program_evidence_native_layout_work[at + 3u]);
}
public void iap_write4(uint row, uint4 value)
{
    uint at = row * 4u;
    program_evidence_native_layout_work[at] = value.x;
    program_evidence_native_layout_work[at + 1u] = value.y;
    program_evidence_native_layout_work[at + 2u] = value.z;
    program_evidence_native_layout_work[at + 3u] = value.w;
}
// Accepted membership is stronger than the admitted reader's ordinary bound.
public bool iap_accepted_span(uint table, uint first, uint count)
{
    uint4 span; uint accepted;
    return table < PPS_PERSISTENT_TABLES && pps_descriptor(table, span, accepted) &&
        first <= accepted && count <= accepted - first;
}
public bool iap_catalog_span(uint table, uint first, uint count)
{
    EvidenceTable span;
    return pev_descriptor(table, span) && first <= span.catalog_count &&
        count <= span.catalog_count - first;
}
public bool iap_header_is_valid()
{
    if (!iap_physical_work() || !pev_catalog_is_valid() || !pps_identity_is_valid()) return false;
    uint4 header = iap_read4(0u); uint4 lineage = iap_read4(1u);
    uint4 limits = iap_read4(2u); uint4 offsets = iap_read4(3u); uint4 tail = iap_read4(4u);
    if (header.x != IAP_MAGIC || header.y != IAP_VERSION ||
        any(header.zw != uint2(proof_store_params.epoch_low, proof_store_params.epoch_high)) ||
        any(header.zw != uint2(program_evidence_catalog[2u], program_evidence_catalog[3u])) ||
        all(header.zw == uint2(0u, 0u)) ||
        any(lineage.xy != uint2(proof_store_params.arena_low, proof_store_params.arena_high)) ||
        all(lineage.xy == uint2(0u, 0u)) || lineage.z != proof_store_params.serial ||
        lineage.w > IAP_MAX_REQUESTS || any(limits.xyz > uint3(IAP_MAX_ROWS)) || limits.w != 0u ||
        any(offsets != uint4(IAP_REQUEST_ROW, IAP_APP_ROW, IAP_BINDING_ROW, IAP_PREREQUISITE_ROW)) ||
        any(tail != uint4(IAP_HOP_ROW, IAP_STATUS_ROW, IAP_TOTAL_ROWS, 0u)) ||
        any(iap_read4(5u) != uint4(0u)) || any(iap_read4(IAP_STATUS_ROW) != uint4(0u)) ||
        any(iap_read4(IAP_STATUS_ROW + 1u) != uint4(0u))) return false;
    uint4 receipt; uint4 extra;
    if (!pev_output_read4(10u, 0u, 0u, receipt) || !pev_output_read4(10u, 0u, 4u, extra) ||
        receipt.x != PEV_VALID || extra.z != proof_store_params.serial || extra.w != 0u ||
        program_evidence_batch[4u] != proof_store_params.serial ||
        program_evidence_proof_store[7u] != proof_store_params.serial ||
        program_evidence_proof_store[10u] != PEV_VALID) return false;
    // A completed submission froze every persistent reserved row as accepted.
    // Even older request roots are read only through these retained prefixes.
    [loop]
    for (uint table = 0u; table < PPS_PERSISTENT_TABLES; table++)
    {
        uint4 span; uint accepted;
        if (!pps_descriptor(table, span, accepted) || accepted != span.w || span.w != span.y) return false;
    }
    return true;
}
public EvidenceStatus iap_reserve(uint pool, uint count, inout uint3 used, out uint first)
{
    first = PEV_INVALID;
    uint4 limits = iap_read4(2u);
    uint available = limits[pool];
    uint prior = used[pool];
    if (prior > available || count > available - prior)
        return pev_limit(201u, pool, count, prior <= available ? available - prior : 0u);
    first = prior; used[pool] = prior + count; return pev_ok();
}
public void iap_status(EvidenceStatus status)
{
    // Single writer, state last. Failed or partial output never has authority.
    uint at = IAP_STATUS_ROW * 4u;
    program_evidence_native_layout_work[at + 1u] = status.detail;
    program_evidence_native_layout_work[at + 2u] = status.subject_row;
    program_evidence_native_layout_work[at + 3u] = status.related_row;
    iap_write4(IAP_STATUS_ROW + 1u, uint4(status.required, status.available, 0u, 0u));
    program_evidence_native_layout_work[at] = status.state;
}
