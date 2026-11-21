// Constants of the substitution publication and status words
// (docs/compiler-retained-substitution.md). No buffers: a consumer imports
// this module with retained_substitution_results.slang and binds only the publication.

public static const uint SB_RESULT_WORDS = 3u;
public static const uint SB_ROOT_WORDS = 2u;

// Result statuses. Only SB_OK carries a term.
public static const uint SB_OK = 0u;
public static const uint SB_PENDING = 1u;       // internal: not evaluated yet
public static const uint SB_NOT_READY = 2u;     // the store's READY bit is clear
public static const uint SB_DECL = 3u;          // no committed, complete definition
public static const uint SB_ENV = 4u;           // an ENV that does not fit its owner (cause in r2.x)
public static const uint SB_UNRESOLVED = 5u;    // a sentinel or invalid reference
public static const uint SB_PRIOR_FIT = 6u;     // an RT_FIT_FAILED reference in the input
public static const uint SB_FOREIGN = 7u;       // a parameter outside the declaration's binder
public static const uint SB_UNBOUND = 8u;       // a binder parameter the ENV leaves unbound
public static const uint SB_SLOT_PENDING = 9u;  // a dependency-signature slot leaf (needs its binder)
public static const uint SB_FIT_FAILED = 10u;   // a constant projection does not fit its target
public static const uint SB_COUNT = 11u;        // an array length that is not a count
public static const uint SB_UNSUPPORTED = 12u;  // a kind or constant shape the canonical rules reject
public static const uint SB_DEPTH = 13u;        // a type result exceeds the 64-level type graph
public static const uint SB_CAPACITY = 14u;     // the attempt overflowed; never a language result
public static const uint SB_INVARIANT = 15u;    // an inconsistent store record
public static const uint SB_KIND = 16u;         // an operand of the wrong kind (a value where a type is required, ...)
public static const uint SB_LIMIT = 17u;        // a binder domain wider than the 32-slot ENV masks
public static const uint SB_STATUSES = 32u;
public static const uint SB_EDGE_TASK = 0xffffffffu;
// An argument equal to an earlier argument of the same task: (that index, SB_EDGE_SAME).
public static const uint SB_EDGE_SAME = 0xfffffffeu;
// A task whose result is in a term slot built by an earlier evaluation dispatch.
public static const uint SB_TERM_SLOT = 0xfffffffdu;

// ENV causes (r2.x of an SB_ENV result).
public static const uint SB_ENV_NONE = 0u;
public static const uint SB_ENV_NOT_ENV = 1u;      // not a stored, closed ENV term
public static const uint SB_ENV_OWNER = 2u;        // owner word 0, or not the request's declaration
public static const uint SB_ENV_SHAPE = 3u;        // masks beyond the binder, arity or type-slot count wrong
public static const uint SB_ENV_BINDING = 4u;      // a binding of the wrong class or scalar; value = the slot's parameter leaf
public static const uint SB_ENV_EVAL = 5u;         // the closed evaluation of the request ENV failed; r2.y = its status
public static const uint SB_ENV_NONCANONICAL = 6u; // the request ENV is not normalized; value = its normalized form

public static const uint SB_DEAD = 0x80000000u;
public static const uint SB_LEVELS = 256u;
public static const uint SB_MAX_HEIGHT = 64u;
public static const uint SB_ROUND_LOG = 128u;

// Phases.
public static const uint SB_PHASE_EXPAND = 1u;
public static const uint SB_PHASE_EVAL = 3u;
public static const uint SB_PHASE_DONE = 4u;
public static const uint SB_PHASE_OVERFLOW = 5u;
public static const uint SB_PHASE_FINAL = 6u;

// Published states.
public static const uint SB_STATE_OPEN = 1u;
public static const uint SB_STATE_PUBLISHED = 2u;
public static const uint SB_STATE_OVERFLOWED = 3u;
// More requests than the request buffers hold: nothing ran, nothing was
// published, the store is untouched. SB_C_REQUEST_DEMAND holds the count.
public static const uint SB_STATE_REQUEST_CAPACITY = 4u;

// Overflow bits.
public static const uint SB_OVERFLOW_TASKS = 1u;
public static const uint SB_OVERFLOW_EDGES = 2u;
public static const uint SB_OVERFLOW_MEMO = 4u;
public static const uint SB_OVERFLOW_STORE = 8u;

// sb_counts layout.
public static const uint SB_C_PHASE = 0u;
public static const uint SB_C_OVERFLOW = 1u;
public static const uint SB_C_TASKS = 2u;          // allocation counter (keeps the requested end)
public static const uint SB_C_EDGES = 3u;
public static const uint SB_C_DEMAND_TASKS = 4u;
public static const uint SB_C_DEMAND_EDGES = 5u;
public static const uint SB_C_FRONTIER_LO = 6u;
public static const uint SB_C_FRONTIER_HI = 7u;
public static const uint SB_C_NEXT_ARITY = 9u;
public static const uint SB_C_ROUNDS = 10u;        // expansion rounds with a nonempty frontier
public static const uint SB_C_LEVEL = 11u;
public static const uint SB_C_EVAL_ROUNDS = 12u;   // nonempty levels evaluated
public static const uint SB_C_MAX_LEVEL = 13u;
public static const uint SB_C_REQUESTS = 14u;
public static const uint SB_C_SPARE_TASKS = 15u;   // tasks dropped on edge overflow
public static const uint SB_C_EDGE_LANES = 16u;    // expansion lanes dispatched
public static const uint SB_C_EDGES_RESOLVED = 17u;
public static const uint SB_C_MAX_FRONTIER = 18u;
public static const uint SB_C_STATE = 19u;
public static const uint SB_C_RUN = 20u;
public static const uint SB_C_STORE_TERMS_BASE = 21u;
public static const uint SB_C_STORE_ARGS_BASE = 22u;
public static const uint SB_C_STORE_SPARE_TERMS = 23u;
public static const uint SB_C_STORE_SPARE_ARGS = 24u;
public static const uint SB_C_STORE_OVERFLOW_SAVED = 25u;
public static const uint SB_C_STORE_DEMAND_TERMS_SAVED = 26u;
public static const uint SB_C_STORE_DEMAND_ARGS_SAVED = 27u;
public static const uint SB_C_STORE_OVERFLOW = 28u;
public static const uint SB_C_STORE_DEMAND_TERMS = 29u;
public static const uint SB_C_STORE_DEMAND_ARGS = 30u;
public static const uint SB_C_REQUEST_DEMAND = 31u; // the producer's request count when it exceeds the capacity
public static const uint SB_C_STATUS = 32u;        // + status: published results per status
public static const uint SB_C_LEVEL_COUNT = 64u;   // + level: live tasks
public static const uint SB_C_ROUND_LOG = 832u;    // + round: frontier tasks of the round
public static const uint SB_C_EVAL_LANES = 960u;
public static const uint SB_C_MAX_ARITY = 961u;
public static const uint SB_C_STORE_NEW_TERMS = 962u;   // store terms the committed attempt added
public static const uint SB_C_STORE_ROLLED_BACK = 963u; // store terms an overflowed attempt interned and rolled back
public static const uint SB_C_GENERATION = 964u;        // the store's build generation (rt_counts[RT_C_GENERATION])
public static const uint SB_C_REQUEST_CAPACITY = 965u;  // request rows the bound buffers hold
public static const uint SB_WORDS = 1024u;

public static const uint SB_CFG_HASH_MASK = 0u;
public static const uint SB_CFG_RUN = 1u;


// First unused status words, kept across consecutive runs in a chain.
public static const uint SB_C_SYNC_FAILED = 966u;
public static const uint SB_C_ROUND_LANES = 967u;
