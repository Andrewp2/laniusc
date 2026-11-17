// The route arena of a retained trait publication
// (docs/compiler-retained-trait-catalog.md, "Publication"). The producer,
// the publish kernels and every GPU consumer share these words.

public static const uint RP_MAGIC = 0x52545231u;
public static const uint RP_VERSION = 1u;
public static const uint RP_INVALID = 0xffffffffu;
public static const uint RP_HEADER_WORDS = 64u;

// Header words. The host writes the identity and the locations; the GPU
// writes the status, failures and proof locations.
public static const uint RP_H_MAGIC = 0u;
public static const uint RP_H_VERSION = 1u;
public static const uint RP_H_EPOCH = 2u;          // 2-3: catalog epoch
public static const uint RP_H_ARENA = 4u;          // 4-5: batch arena id
public static const uint RP_H_SERIAL = 6u;
public static const uint RP_H_GENERATION = 7u;     // store build generation
public static const uint RP_H_STATUS = 8u;         // RP_BUILDING / RP_VALID / RP_FAILED, written last
public static const uint RP_H_FAILURES = 9u;
public static const uint RP_H_FIRST_FAILURE = 10u; // min(code << 24 | row)
public static const uint RP_H_USES = 11u;
public static const uint RP_H_OBLIGATIONS = 12u;
public static const uint RP_H_ATOMS = 13u;
public static const uint RP_H_USE_MAP = 14u;       // word offsets in the route arena
public static const uint RP_H_ROUTES = 15u;
public static const uint RP_H_ATOM_IDS = 16u;
public static const uint RP_H_CAT_IMPLS = 17u;     // catalog arena word offsets and rows
public static const uint RP_H_CAT_METHODS = 18u;
public static const uint RP_H_IMPL_ROWS = 19u;
public static const uint RP_H_METHOD_ROWS = 20u;
public static const uint RP_H_PROOF_BINDINGS = 21u; // proof arena offset, admitted rows (GPU)
public static const uint RP_H_PROOF_BINDING_ROWS = 22u;
public static const uint RP_H_PROOF_NODES = 23u;
public static const uint RP_H_PROOF_NODE_ROWS = 24u;
public static const uint RP_H_PROOF_EDGES = 25u;
public static const uint RP_H_PROOF_EDGE_ROWS = 26u;
public static const uint RP_H_CAT_ATOMS = 27u;
public static const uint RP_H_CALLS = 30u;
// A closed publication's producer fault (closed/07_totals.slang): nonzero
// when its batch was left empty and the host must check the wave eagerly.
public static const uint RP_H_PRODUCER = 31u;
// Solver locations, read only by the publish kernels.
public static const uint RP_H_OUT_RESULTS = 32u;   // output table 3
public static const uint RP_H_OUT_CALLS = 33u;     // output table 4
public static const uint RP_H_OUT_EVIDENCE = 34u;  // output table 5
public static const uint RP_H_OUT_RECEIPT = 35u;   // output table 10
public static const uint RP_H_CAT_RECEIPT = 36u;   // output table 0 in the catalog arena
public static const uint RP_H_PROOF_WORDS = 37u;
public static const uint RP_H_CAT_WORDS = 38u;
public static const uint RP_H_OUT_WORDS = 39u;

// Immutable source-store extent. Substitution may append terms, but a new
// exported job invalidates catalog coherence and the use proof map.
public static const uint RP_H_STORE_DIRS = 40u;
public static const uint RP_H_STORE_TRAITS = 41u;
public static const uint RP_H_STORE_JOBS = 42u;
public static const uint RP_H_STORE_DECLS = 43u;
public static const uint RP_H_DIAGNOSTIC_USE = 44u; // smallest hard-refuted use, or INVALID
// The verdict publish_finish requires, copied on the GPU after the solve
// (retained.rs): the solver's stop word (kernels::wave::STOP; DONE when the
// finish point published the batch in the submits recorded), the producer's
// fill faults and the native recipe status. A solve whose state the host
// did not read publishes only when all three hold.
public static const uint RP_H_SOLVE_STOP = 45u;
public static const uint RP_H_FILL_FAULTS = 46u;
public static const uint RP_H_RECIPE_STATUS = 47u;
public static const uint RP_SOLVE_DONE = 2u;
public static const uint RP_H_DIAGNOSTIC_SPAN = 48u; // job, file, byte, length

public static const uint RP_BUILDING = 0u;
public static const uint RP_VALID = 1u;
public static const uint RP_FAILED = 2u;

// Use map, 4 words per retained use: call row + 1 (0: no goal), first
// route, route count, call status word 0.
public static const uint RP_USE_WORDS = 4u;
// Route, 8 words per obligation: result classification (1 closed, 2
// conditional, 3 refuted), predicate atom, impl row (RP_INVALID for an assumption), method
// first, method count, proof binding first, proof binding count, proof row.
public static const uint RP_ROUTE_WORDS = 8u;
// Atom identity, 2 words per catalog atom: kind, retained id.
public static const uint RP_ID_NONE = 0u;
public static const uint RP_ID_DECL = 1u;
public static const uint RP_ID_PARAM = 2u;
public static const uint RP_ID_TERM = 3u;

// Route failure codes.
public static const uint RP_E_RECEIPT = 1u;  // catalog, batch or proof receipt not valid
public static const uint RP_E_RESULT = 2u;   // a result row that names no proof
public static const uint RP_E_PROOF = 3u;    // proof row, substitution or bindings out of the store
public static const uint RP_E_IMPL = 4u;     // proof impl differs from the result's impl
