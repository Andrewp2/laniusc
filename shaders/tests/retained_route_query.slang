// A GPU consumer of a retained trait publication
// (docs/compiler-retained-trait-catalog.md, "Publication"). It is the shape
// discovery and projection use: from a retained use, the k-th obligation
// and a required member symbol, it finds the selected impl, the native
// target method and the exact binding environment in the solver's own
// output. It checks the publication header against the expected identity
// and the live store counters first, and writes nothing when they differ.
import type_checker.trait_solver.retained_catalog.retained_route_abi;

RWStructuredBuffer<uint> rc_routes;
RWStructuredBuffer<uint> rp_catalog;
RWStructuredBuffer<uint> rp_proof;
RWStructuredBuffer<uint> rt_counts;
// [0] request count, [1-2] epoch, [3-4] arena id, [5] serial, [6] generation,
// then 4 words per request: use, obligation ordinal, required symbol, 0.
RWStructuredBuffer<uint> rq_requests;
// 16 words per request: status (1 found; see below), impl DeclId, target
// method DeclId, binding count, then up to 4 bindings of 3 words:
// ParamId, reference tag, value (scalar, or the DeclId of a NAMED node).
RWStructuredBuffer<uint> rq_out;

static const uint RQ_FOUND = 1u;
static const uint RQ_HEADER = 2u;     // header magic, version, status or identity
static const uint RQ_STALE = 3u;      // store not READY or another generation
static const uint RQ_NO_GOAL = 4u;
static const uint RQ_ORDINAL = 5u;
static const uint RQ_NOT_IMPL = 6u;   // the obligation was not proven by an impl
static const uint RQ_NO_MEMBER = 7u;
static const uint RQ_IDENTITY = 8u;   // an atom without the expected retained identity
static const uint RT_C_READY = 77u;
static const uint RT_C_GENERATION = 78u;

uint h(uint word) { return rc_routes[word]; }
// The retained id of a catalog atom of `kind`, or RP_INVALID.
uint atom_id(uint atom, uint kind)
{
    if (atom >= h(RP_H_ATOMS)) return RP_INVALID;
    uint at = h(RP_H_ATOM_IDS) + atom * 2u;
    return rc_routes[at] == kind ? rc_routes[at + 1u] : RP_INVALID;
}
uint answer(uint request)
{
    if (h(RP_H_MAGIC) != RP_MAGIC || h(RP_H_VERSION) != RP_VERSION || h(RP_H_STATUS) != RP_VALID) return RQ_HEADER;
    for (uint i = 0u; i < 5u; i++) if (h(RP_H_EPOCH + i) != rq_requests[1u + i]) return RQ_HEADER;
    if (h(RP_H_GENERATION) != rq_requests[6]) return RQ_HEADER;
    if (rt_counts[RT_C_READY] != 1u || rt_counts[RT_C_GENERATION] != h(RP_H_GENERATION)) return RQ_STALE;
    uint4 q = uint4(rq_requests[8u + request * 4u], rq_requests[9u + request * 4u],
        rq_requests[10u + request * 4u], 0u);
    if (q.x >= h(RP_H_USES)) return RQ_NO_GOAL;
    uint use_at = h(RP_H_USE_MAP) + q.x * RP_USE_WORDS;
    if (rc_routes[use_at] == 0u) return RQ_NO_GOAL;
    if (q.y >= rc_routes[use_at + 2u]) return RQ_ORDINAL;
    uint route = h(RP_H_ROUTES) + (rc_routes[use_at + 1u] + q.y) * RP_ROUTE_WORDS;
    if (rc_routes[route] != 1u) return RQ_NOT_IMPL;
    uint impl_row = rc_routes[route + 2u];
    uint out = request * 16u;
    rq_out[out + 1u] = atom_id(rp_catalog[h(RP_H_CAT_IMPLS) + impl_row * 12u], RP_ID_DECL);
    // The impl's methods are in strictly increasing required symbol.
    uint lo = rc_routes[route + 3u];
    uint hi = lo + rc_routes[route + 4u];
    uint methods = h(RP_H_CAT_METHODS);
    while (lo < hi)
    {
        uint mid = (lo + hi) / 2u;
        if (rp_catalog[methods + mid * 6u + 1u] < q.z) lo = mid + 1u; else hi = mid;
    }
    if (lo >= rc_routes[route + 3u] + rc_routes[route + 4u] || rp_catalog[methods + lo * 6u + 1u] != q.z ||
        rp_catalog[methods + lo * 6u] != impl_row) return RQ_NO_MEMBER;
    rq_out[out + 2u] = atom_id(rp_catalog[methods + lo * 6u + 2u], RP_ID_DECL);
    uint first = rc_routes[route + 5u];
    uint count = rc_routes[route + 6u];
    rq_out[out + 3u] = count;
    for (uint b = 0u; b < count && b < 4u; b++)
    {
        uint at = h(RP_H_PROOF_BINDINGS) + (first + b) * 8u;
        uint tag = rp_proof[at + 2u];
        uint value = rp_proof[at + 3u];
        if (tag == 3u)
        {
            uint node = h(RP_H_PROOF_NODES) + value * 8u;
            if (value >= h(RP_H_PROOF_NODE_ROWS)) return RQ_IDENTITY;
            value = rp_proof[node] == 1u ? atom_id(rp_proof[node + 1u], RP_ID_DECL) : RP_INVALID;
        }
        rq_out[out + 4u + b * 3u] = atom_id(rp_proof[at + 1u], RP_ID_PARAM);
        rq_out[out + 5u + b * 3u] = tag;
        rq_out[out + 6u + b * 3u] = value;
    }
    if (rq_out[out + 1u] == RP_INVALID || rq_out[out + 2u] == RP_INVALID) return RQ_IDENTITY;
    return RQ_FOUND;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint request = dtid.x;
    if (request >= rq_requests[0]) return;
    rq_out[request * 16u] = answer(request);
}
