// Constants of the retained projection (docs/compiler-retained-projection.md).
// The host mirrors them in program_retention/projection.rs.

public static const uint PJ_INSTANCE_WORDS = 2u;
public static const uint PJ_INFO_WORDS = 6u;
public static const uint PJ_FLAG_ENTRY = 1u;
public static const uint PJ_READY_ROUTES = 1u;

// Native identities (codegen/x86/finalize.rs).
public static const uint PJ_NATIVE_LIBRARY = 0xfffffffeu;
public static const uint PJ_NATIVE_NS_INSTANCE = 0xffff0002u;
public static const uint PJ_ROUTE_NONE = 0xffffffffu;

// Side tables of a body segment (export/side_tables.slang order); two
// uint4 per record.
public static const uint PJ_SIDE_CALL_ARGS = 0u;
public static const uint PJ_SIDE_FIELDS = 1u;
public static const uint PJ_SIDE_MATCH_ARMS = 2u;
public static const uint PJ_SIDE_MATCH_PAYLOADS = 3u;
public static const uint PJ_SIDE_ARRAY_ELEMENTS = 4u;
public static const uint PJ_SIDE_STRINGS = 5u;
public static const uint PJ_SIDE_PARAMS = 6u;
public static const uint PJ_SIDE_TABLES = 7u;
public static const uint PJ_SIDE_WORDS = 2u;

// Scan columns.
public static const uint PJ_C_ROWS = 0u;
public static const uint PJ_C_TOKENS = 1u;
public static const uint PJ_C_SIDE = 2u;      // + table (7)
public static const uint PJ_C_REQUESTS = 9u;
public static const uint PJ_COLUMNS = 10u;

// Configuration words (pj_config).
public static const uint PJ_CFG_RUN = 0u;        // substitution publication run
public static const uint PJ_CFG_BATCH_ROWS = 1u; // rows that start a new batch
public static const uint PJ_CFG_BATCH = 2u;      // current batch
public static const uint PJ_CFG_ROUND = 3u;      // layout round
public static const uint PJ_CFG_IDENTITY_MASK = 4u;
public static const uint PJ_CFG_ROW_CAP = 5u;    // batch column capacities
public static const uint PJ_CFG_TOKEN_CAP = 6u;
public static const uint PJ_CFG_SIDE_CAP = 7u;
public static const uint PJ_CFG_WORDS = 8u;

// Status words (pj_status).
public static const uint PJ_S_STATE = 0u;          // PJ_STATE_*
public static const uint PJ_S_ERRORS = 1u;         // rows and ranks with an error
public static const uint PJ_S_ERROR_RANK = 2u;     // smallest rank with a rank error
public static const uint PJ_S_ERROR_ROW = 3u;      // smallest global row with a row error
public static const uint PJ_S_INSTANCES = 4u;
public static const uint PJ_S_GENERATION = 5u;
public static const uint PJ_S_MAX_ROWS = 6u;       // largest instance, in rows
public static const uint PJ_S_MAX_TOKENS = 7u;
public static const uint PJ_S_MAX_SIDE = 8u;
public static const uint PJ_S_BATCHES = 9u;
public static const uint PJ_S_LAYOUT_CHANGED = 10u; // terms laid out in the current round
public static const uint PJ_S_LAYOUT_ROUNDS = 11u;
public static const uint PJ_S_IDENTITY_OVERFLOW = 12u;
public static const uint PJ_S_INPUT_ERROR = 13u;   // header error, even with no ranks
public static const uint PJ_S_INPUT_DETAIL = 14u;
public static const uint PJ_S_TOTALS = 16u;        // + column: totals over all ranks
// The first error (09_report): (code, detail, rank, DeclId, relative row,
// relative token, file id, file-relative byte start).
public static const uint PJ_S_FIRST = 32u;
// Batch figures of the current batch (11_batch_finish).
public static const uint PJ_S_BATCH = 48u;         // (lo, hi, rows, tokens, side 0..6)
// Batch maxima (06_batch_plan): rows (with the root row), tokens, the
// largest side table and the nonempty batches.
public static const uint PJ_S_BATCH_ROWS = 40u;
public static const uint PJ_S_BATCH_TOKENS = 41u;
public static const uint PJ_S_BATCH_SIDE = 42u;
public static const uint PJ_S_BATCH_NONEMPTY = 43u;
public static const uint PJ_S_BATCH_STRING_WORDS = 44u;
public static const uint PJ_STATUS_WORDS = 64u;
public static const uint PJ_BATCH_WORDS = 3u;

public static const uint PJ_STATE_CHECKED = 1u;
public static const uint PJ_STATE_FAILED = 2u;

// Error codes (pj_errors.x, pj_row_errors.x).
public static const uint PJ_E_NONE = 0u;
public static const uint PJ_E_READINESS = 1u;   // readiness flags, generation or counts
public static const uint PJ_E_RECORD = 2u;      // instance record: generation, flags, ENV
public static const uint PJ_E_DECL = 3u;        // callable not a committed complete FREE_FN with a body
public static const uint PJ_E_DUPLICATE = 4u;   // two ranks with one (DeclId, ENV)
public static const uint PJ_E_ROUTES = 5u;      // route range of the record
public static const uint PJ_E_ENTRY = 6u;       // entry instance with parameters, or two entries
public static const uint PJ_E_SUBST = 7u;       // a substitution result is not OK (detail: status)
public static const uint PJ_E_PUBLICATION = 8u; // a result is not current
public static const uint PJ_E_FORM = 9u;        // unsupported row form (detail: kind | form << 8)
public static const uint PJ_E_ROLE = 10u;       // bound or pattern row
public static const uint PJ_E_INCOMPLETE = 11u; // MISSING or FOREIGN row
public static const uint PJ_E_TYPE = 12u;       // unsupported closed type (detail: term kind)
public static const uint PJ_E_LAYOUT = 13u;     // a type without a complete layout
public static const uint PJ_E_USE = 14u;        // unsupported use form (detail: form)
public static const uint PJ_E_ROUTE = 15u;      // a route that does not name the use's target
public static const uint PJ_E_SIGNATURE = 16u;  // argument, arity or result does not match the target
public static const uint PJ_E_RULE = 17u;       // language rule (detail: the diagnostic code, see PJ_D_*)
public static const uint PJ_E_DEPTH = 18u;      // expression or control nesting over the bound
public static const uint PJ_E_FIELD = 19u;      // struct literal or member field
public static const uint PJ_E_INPUT_CAPACITY = 20u; // producer must grow and rerun; never project a prefix

// Rule details: error code << 24 | the checker's detail.
public static const uint PJ_RULE_ASSIGN_MISMATCH = 3u;     // LNC0006
public static const uint PJ_RULE_INTEGER_RANGE = 24u;      // LNC0069
public static const uint PJ_RULE_FLOAT_LITERAL = 25u;      // LNC0070

// Lowering type-reference tags.
public static const uint PJ_REF_SCALAR = 1u;
public static const uint PJ_REF_INSTANCE = 3u;
public static const uint PJ_SCALAR_LINK_NONE = 0x7ffffffu;
public static const uint PJ_IMPORTED_STRUCT = 6u;
public static const uint PJ_IMPORTED_COMPLETE = 0x80000000u;

// Per global row facts (pj_g_facts): (ref tag, ref payload, native words,
// scalar code or 0). pj_g_member: (field word offset, field word count).
public static const uint PJ_EXPR_DEPTH = 256u;
public static const uint PJ_LAYOUT_ROUNDS = 32u;
