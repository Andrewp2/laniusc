// Included helper (not a module): the packed child-slot path of the stackless
// walkers. It records the slot each level descended through, five bits per
// level (a nominal application has at most NOMINAL_APPLICATION_ARGUMENT_LIMIT
// = 32 arguments), six levels per word: 11 words cover the 63 levels below
// DEPTH_LIMIT = 64. The path starts zeroed; a walk uses a level only after
// setting it.
#define SCOPED_TYPE_PATH(name) uint name[11] = {}
#define SCOPED_TYPE_PATH_SLOT(name, d) bitfieldExtract(name[(d) / 6u], (d) % 6u * 5u, 5u)
#define SCOPED_TYPE_PATH_SET(name, d, s) \
    name[(d) / 6u] = bitfieldInsert(name[(d) / 6u], s, (d) % 6u * 5u, 5u)
