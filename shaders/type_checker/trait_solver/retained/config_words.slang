// rc_config words of the retained trait catalog producer, and the
// producer state words that 00_configure writes. Words 0-8, 9-15, 7 and 37
// come from 00_configure; the host writes the others.
public static const uint RC_CFG_DECLS = 0u;
public static const uint RC_CFG_PARAMS = 1u;
public static const uint RC_CFG_TERMS = 2u;
public static const uint RC_CFG_DIR = 3u;
public static const uint RC_CFG_TRAITS = 4u;
public static const uint RC_CFG_USES = 5u;
public static const uint RC_CFG_JOBS = 6u;
public static const uint RC_CFG_UNIT_SLOTS = 7u;
public static const uint RC_CFG_LANES = 8u;
public static const uint RC_CFG_BASE = 9u;          // + region: first lane of the region
public static const uint RC_CFG_EPOCH = 16u;        // epoch low, epoch high
public static const uint RC_CFG_GENERATION = 18u;   // store build generation (RT_C_GENERATION)
public static const uint RC_CFG_PHASE = 19u;        // fill: 0 catalog tables (0-10), 1 batch tables (11-16)
public static const uint RC_CFG_TABLE = 20u;        // + solver table (0-16): word offset
public static const uint RC_CFG_SORT = 37u;         // bitonic width: a power of two >= trait records
public static const uint RC_CFG_ATOM_IDS = 38u;     // word offset of the atom identity table in rc_routes
public static const uint RC_CFG_ROUTE_USES = 39u;   // word offset of the use map in rc_routes
public static const uint RC_CFG_CLOSURE_WAVES = 40u; // bound on closure waves
// Host bounds the configuration must fit: the most records of each lane
// region (+ region), unit slots and sort keys its buffers hold, the unit
// slots to use (0: twice the jobs, as a power of two) and the bitonic steps
// recorded in rc_stages.
public static const uint RC_CFG_REGION_CAP = 41u;   // + region
public static const uint RC_CFG_UNIT_CAP = 48u;
public static const uint RC_CFG_SORT_CAP = 49u;
public static const uint RC_CFG_UNIT_REQUEST = 50u;
public static const uint RC_CFG_STEPS = 51u;
public static const uint RC_CFG_WORDS = 52u;

// rc_state word set when the counters do not fit the host's bounds or the
// lanes exceed 2^24; nothing ran. The store's counters follow the state
// words (RC_S_WORDS .. + RT_C_WORDS).
public static const uint RC_S_CONFIG_FAULT = 27u;
public static const uint RC_S_WORDS = 28u;
// rc_dispatch entries (three words each): every lane, the closure root
// lanes, the sort keys, then one per recorded bitonic step.
public static const uint RC_D_LANES = 0u;
public static const uint RC_D_ROOTS = 1u;
public static const uint RC_D_SORT = 2u;
public static const uint RC_D_STEP = 3u;
