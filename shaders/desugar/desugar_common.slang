// Shared layout of the desugaring after the lexer's token build
// (crates/laniusc-compiler/src/compiler/desugar.rs mirrors it).
//
// `sizes` holds the counts of one run, `args` the indirect dispatch sizes
// and `blocks` the parameters of the kernels, one 256-byte uniform block
// each. The plan kernel writes all three from counts on the GPU, so the
// host records every dispatch before it knows a count. A run whose pack
// has no machine gets zero workgroups everywhere.
module desugar_common;

// Sizes.
public static const uint S_TOKENS = 0u;      // tokens the machine kernels read; 0 without a machine
public static const uint S_MACHINES = 1u;
public static const uint S_STATES = 2u;
public static const uint S_TRANSITIONS = 3u;
public static const uint S_LIVE = 4u;        // tokens while the expansion goes on, else 0
public static const uint S_PIECES = 5u;
public static const uint S_REGION = 6u;      // bytes of generated text
public static const uint S_GENERATED = 7u;   // generated tokens
public static const uint S_OUT = 8u;         // tokens after the splice
public static const uint S_REGION_BASE = 9u; // first byte of the region in `in_bytes`
public static const uint S_REGION_CAP = 10u; // bytes the region holds
public static const uint S_PIECE_CAP = 11u;  // pieces the piece buffers hold
public static const uint S_SPLICED = 12u;    // tokens the splice reads; 0 when nothing is spliced
// What a run that did not fit needed; the host sizes the next run from them.
public static const uint S_NEED_TOKENS = 13u;
public static const uint S_NEED_PIECES = 14u;
public static const uint S_NEED_REGION = 15u;
public static const uint S_NEED_OUT = 16u;
public static const uint SIZE_WORDS = 20u;

// Indirect dispatches, three words each.
public static const uint A_TOKENS = 0u;
public static const uint A_TOKEN_SCAN = 1u;
public static const uint A_TOKEN_SCAN_ONE = 2u;
public static const uint A_RECORD_WORDS = 3u;
public static const uint A_LIVE = 4u;
public static const uint A_LIVE_SCAN = 5u;
public static const uint A_LIVE_SCAN_ONE = 6u;
public static const uint A_INFO_WORDS = 7u;
public static const uint A_STATES = 8u;
public static const uint A_STATE_WORDS = 9u;
public static const uint A_WRITE = 10u;      // tokens of the piece writing run
public static const uint A_PIECE_SCAN = 11u;
public static const uint A_PIECE_SCAN_ONE = 12u;
public static const uint A_REGION_WORDS = 13u;
public static const uint A_REGION_BYTES = 14u;
public static const uint A_REGION_SCAN = 15u;
public static const uint A_REGION_SCAN_ONE = 16u;
public static const uint A_SPLICE = 17u;     // source tokens of the splice
public static const uint A_SPLICE_SCAN = 18u;
public static const uint A_SPLICE_SCAN_ONE = 19u;
public static const uint A_GENERATED = 20u;
public static const uint A_OUT = 21u;
public static const uint ARG_TRIPLES = 22u;

// Parameter blocks, 64 words apart (the uniform offset alignment).
public static const uint BLOCK_WORDS = 64u;
public static const uint P_TOKENS = 0u;        // (tokens)
public static const uint P_CLEAR_RECORDS = 1u; // (words)
public static const uint P_SCAN_TOKENS_0 = 2u; // closures/scan: (count, mode, tiles)
public static const uint P_SCAN_TOKENS_1 = 3u;
public static const uint P_SCAN_TOKENS_2 = 4u;
public static const uint P_LIVE = 5u;          // (live tokens)
public static const uint P_LISTS_A = 6u;       // (live, fourth = 0)
public static const uint P_LISTS_B = 7u;       // (live, fourth = 1)
public static const uint P_SCAN_LIVE_0 = 8u;
public static const uint P_SCAN_LIVE_1 = 9u;
public static const uint P_SCAN_LIVE_2 = 10u;
public static const uint P_CLEAR_INFO = 11u;   // (words)
public static const uint P_CLEAR_STATES = 12u; // (words)
public static const uint P_RESOLVE = 13u;      // (live, machines, explain word, explain key)
public static const uint P_CHECK = 14u;        // (live, 0, explain word, explain key)
public static const uint P_STATES = 15u;       // (states)
public static const uint P_STATE_CHECK = 16u;  // (states, 0, explain word, explain key)
public static const uint P_COUNT = 17u;        // pieces: (live, write = 0)
public static const uint P_WRITE = 18u;        // pieces: (write tokens, write = 1)
public static const uint P_SCAN_PIECES_0 = 19u;
public static const uint P_SCAN_PIECES_1 = 20u;
public static const uint P_SCAN_PIECES_2 = 21u;
public static const uint P_EMIT = 22u;         // (region bytes, pieces)
public static const uint P_SCAN_REGION_0 = 23u;
public static const uint P_SCAN_REGION_1 = 24u;
public static const uint P_SCAN_REGION_2 = 25u;
public static const uint P_SCAN_SPLICE_0 = 26u;
public static const uint P_SCAN_SPLICE_1 = 27u;
public static const uint P_SCAN_SPLICE_2 = 28u;
public static const uint BLOCKS = 29u;

// Plan modes, in recording order.
public static const uint PLAN_TOKENS = 0u;
public static const uint PLAN_MACHINES = 1u;
public static const uint PLAN_PIECES = 2u;
public static const uint PLAN_REGION = 3u;
public static const uint PLAN_SPLICE = 4u;
public static const uint PLAN_FINISH = 5u;

// Bits of the lexer's feature word the host reads with the token count.
public static const uint FEATURE_MACHINES = 0x00001000u;
public static const uint DESUGAR_REGION_OVERFLOW = 0x40000000u;
public static const uint DESUGAR_RULE_ERROR = 0x80000000u;

public static const uint DESUGAR_NO_ERROR = 0xffffffffu;
public static const uint DESUGAR_STATUS_WORDS = 4u;

public static const uint DESUGAR_DISPATCH_X_STRIDE = 16776960u;
public static const uint DESUGAR_MAX_GROUPS_X = 65535u;
public static const uint DESUGAR_SCAN_TILE_ROWS = 2048u;
