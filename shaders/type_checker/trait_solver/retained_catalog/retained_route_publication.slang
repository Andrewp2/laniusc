// Publication of a solved retained trait check
// (docs/compiler-retained-trait-catalog.md, "Publication"). Pass 07 writes
// one route per obligation and one call status per use from the solver's
// own output and proof store. Pass 08 writes the proof locations and then
// the status. Nothing here selects: the routes copy the solver's choice.
import type_checker.trait_solver.retained_catalog.retained_route_abi;
import type_checker.retention.retention_store;

public RWStructuredBuffer<uint> rc_routes;
public RWStructuredBuffer<uint> rp_catalog;
public RWStructuredBuffer<uint> rp_output;
public RWStructuredBuffer<uint> rp_proof;

static const uint PPS_MAGIC = 0x50505332u;
static const uint PPS_DIRECTORY = 12u;
static const uint PROOF_SUBSTITUTIONS = 4u;
static const uint PROOF_BINDINGS = 5u;
static const uint PROOF_PROOFS = 6u;
static const uint PROOF_NODES = 0u;
static const uint PROOF_EDGES = 1u;

public uint header(uint word) { return rc_routes[word]; }
public uint publish_lane(uint3 dtid) { return dtid.x + dtid.y * 16776960u; }

void fault(uint code, uint row)
{
    InterlockedAdd(rc_routes[RP_H_FAILURES], 1u);
    InterlockedMin(rc_routes[RP_H_FIRST_FAILURE], (code << 24u) | min(row, 0xffffffu));
}
uint out_word(uint at) { return at < header(RP_H_OUT_WORDS) ? rp_output[at] : RP_INVALID; }
// (offset, admitted rows) of a proof table, or (RP_INVALID, 0).
uint2 proof_table(uint table, uint width)
{
    uint d = PPS_DIRECTORY + table * 6u;
    if (d + 5u >= header(RP_H_PROOF_WORDS)) return uint2(RP_INVALID, 0u);
    uint offset = rp_proof[d];
    uint logical = rp_proof[d + 1u];
    uint capacity = rp_proof[d + 2u];
    uint admitted = rp_proof[d + 3u];
    if (rp_proof[d + 5u] != width || admitted > logical || logical > capacity) return uint2(RP_INVALID, 0u);
    if (capacity != 0u && offset + capacity * width > header(RP_H_PROOF_WORDS)) return uint2(RP_INVALID, 0u);
    return uint2(offset, admitted);
}
bool proof_row(uint table, uint width, uint row, out uint at)
{
    uint2 t = proof_table(table, width);
    at = t.x + row * width;
    return t.x != RP_INVALID && row < t.y;
}

public void publish_route(uint o)
{
    uint obligations = header(RP_H_OBLIGATIONS);
    if (o >= obligations)
    {
        uint use = o - obligations;
        if (use >= header(RP_H_USES)) return;
        uint at = header(RP_H_USE_MAP) + use * RP_USE_WORDS;
        uint call = rc_routes[at];
        if (call == 0u) return;
        if (call - 1u >= header(RP_H_CALLS)) { fault(RP_E_RESULT, o); return; }
        uint state = out_word(header(RP_H_OUT_CALLS) + (call - 1u) * 8u);
        rc_routes[at + 3u] = state;
        if (state == 3u) InterlockedMin(rc_routes[RP_H_DIAGNOSTIC_USE], use);
        return;
    }
    uint result = header(RP_H_OUT_RESULTS) + o * 8u;
    uint evidence = header(RP_H_OUT_EVIDENCE) + o * 8u;
    uint state = out_word(result);
    uint predicate = out_word(evidence + 1u);
    uint impl_row = RP_INVALID;
    uint4 methods_bindings = uint4(0u, 0u, 0u, 0u);
    uint proof = RP_INVALID;
    if (state == 1u || state == 2u)
    {
        proof = out_word(evidence + 3u);
        uint at;
        if (proof != out_word(result + 3u) || !proof_row(PROOF_PROOFS, 8u, proof, at))
        { fault(RP_E_PROOF, o); return; }
        // Kind (impl/assumption) and classification (closed/conditional)
        // are distinct. An impl whose child proof uses a template bound is
        // kind 1 with classification 2, just as write_proof_rows publishes
        // it. The output result carries the classification.
        uint kind = rp_proof[at];
        if ((kind != 1u && kind != 2u) || rp_proof[at+7u] != state || out_word(evidence) != state)
        { fault(RP_E_RESULT, o); return; }
        if (kind == 1u)
        {
            uint selected = out_word(result + 7u);
            if (selected == 0u || selected - 1u >= header(RP_H_IMPL_ROWS)) { fault(RP_E_RESULT, o); return; }
            impl_row = selected - 1u;
            if (rp_proof[at + 3u] != impl_row) { fault(RP_E_IMPL, o); return; }
            uint substitution = rp_proof[at + 4u];
            uint s;
            if (!proof_row(PROOF_SUBSTITUTIONS, 4u, substitution, s) || rp_proof[s] != impl_row)
            { fault(RP_E_PROOF, o); return; }
            uint2 bindings = proof_table(PROOF_BINDINGS, 8u);
            uint first = rp_proof[s + 1u];
            uint count = rp_proof[s + 2u];
            if (bindings.x == RP_INVALID || first > bindings.y || count > bindings.y - first)
            { fault(RP_E_PROOF, o); return; }
            uint impl_at = header(RP_H_CAT_IMPLS) + impl_row * 12u;
            methods_bindings = uint4(rp_catalog[impl_at + 6u], rp_catalog[impl_at + 7u], first, count);
        }
    }
    else if (state != 3u) { fault(RP_E_RESULT, o); return; }
    uint route = header(RP_H_ROUTES) + o * RP_ROUTE_WORDS;
    rc_routes[route] = state;
    rc_routes[route + 1u] = predicate;
    rc_routes[route + 2u] = impl_row;
    rc_routes[route + 3u] = methods_bindings.x;
    rc_routes[route + 4u] = methods_bindings.y;
    rc_routes[route + 5u] = methods_bindings.z;
    rc_routes[route + 6u] = methods_bindings.w;
    rc_routes[route + 7u] = proof;
}

public void publish_finish()
{
    uint use = header(RP_H_DIAGNOSTIC_USE);
    uint4 span = use < header(RP_H_USES) ? rt_use_spans[use] : uint4(RP_INVALID,RP_INVALID,RP_INVALID,0u);
    for (uint i = 0u; i < 4u; i++) rc_routes[RP_H_DIAGNOSTIC_SPAN+i] = span[i];
    uint receipt = header(RP_H_CAT_RECEIPT);
    bool valid = receipt < header(RP_H_CAT_WORDS) && rp_catalog[receipt] == 1u;
    uint batch = header(RP_H_OUT_RECEIPT);
    valid = valid && out_word(batch) == 1u && out_word(batch + 6u) == header(RP_H_SERIAL) && out_word(batch + 7u) == 0u;
    valid = valid && header(RP_H_PROOF_WORDS) > PPS_DIRECTORY + 16u * 6u && rp_proof[0] == PPS_MAGIC &&
        rp_proof[2] == header(RP_H_EPOCH) && rp_proof[3] == header(RP_H_EPOCH + 1u) &&
        rp_proof[4] == header(RP_H_ARENA) && rp_proof[5] == header(RP_H_ARENA + 1u) &&
        rp_proof[6] == header(RP_H_SERIAL) && rp_proof[11] == 0u;
    uint2 bindings = proof_table(PROOF_BINDINGS, 8u);
    uint2 nodes = proof_table(PROOF_NODES, 8u);
    uint2 edges = proof_table(PROOF_EDGES, 2u);
    valid = valid && bindings.x != RP_INVALID && nodes.x != RP_INVALID && edges.x != RP_INVALID;
    valid = valid && header(RP_H_SOLVE_STOP) == RP_SOLVE_DONE && header(RP_H_FILL_FAULTS) == 0u &&
        header(RP_H_RECIPE_STATUS) == 1u;
    if (!valid) fault(RP_E_RECEIPT, 0u);
    rc_routes[RP_H_PROOF_BINDINGS] = bindings.x;
    rc_routes[RP_H_PROOF_BINDING_ROWS] = bindings.y;
    rc_routes[RP_H_PROOF_NODES] = nodes.x;
    rc_routes[RP_H_PROOF_NODE_ROWS] = nodes.y;
    rc_routes[RP_H_PROOF_EDGES] = edges.x;
    rc_routes[RP_H_PROOF_EDGE_ROWS] = edges.y;
    rc_routes[RP_H_STATUS] = header(RP_H_FAILURES) == 0u ? RP_VALID : RP_FAILED;
}
