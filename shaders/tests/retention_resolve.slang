// Acceptance probe for program retention: reads only the build store.
//
// Lanes [0, uses) take one committed use each. A use whose callee another
// (library, unit) defines and whose environment is closed is an instance
// request. Lanes [uses, uses + requests) take one explicit request each from
// rt_test_requests: (callee DeclId, type argument count, argument 0,
// argument 1), arguments being scalar terms, so a template can be
// instantiated at an environment no use of the build names.
//
// For each instance the lane substitutes the environment into the callee's
// declared result and parameters and into every typed row, annotation,
// constant and use environment of its body segment; validates every
// relative reference by its class (row, token, side index, context), the
// side records, the uses and the token records; checks each value binding
// (a local binding names a token with the same spelling), each member's
// field against the substituted struct schema, each constant parameter
// value; and hashes the substituted rows and facts. Results go to
// rt_test_out (RT_PROBE_WORDS per lane).
import primitive_types;
import type_checker.retention.retention_store;
import type_checker.retention.retention_subst;
import type_checker.retention.row_classes;

RWStructuredBuffer<uint> rt_test_out;
StructuredBuffer<uint4> rt_test_requests;
StructuredBuffer<uint> rt_test_meta; // [0] request count

static const uint RT_PROBE_WORDS = 40u;
static const uint LANE_WORDS = 256u;

static const uint P_ELIGIBLE = 0u;      // 1 eligible; 2+ reasons it is not
static const uint P_CALLEE = 1u;
static const uint P_RESULT = 2u;        // substituted declared result
static const uint P_EXPECTED = 3u;      // the use's own checked result
static const uint P_RESULT_STATUS = 4u;
static const uint P_ROWS = 5u;          // segment rows
static const uint P_TYPED = 6u;         // typed rows substituted to closed terms
static const uint P_FAILED = 7u;        // typed rows whose substitution failed
static const uint P_FIRST_FAILURE = 8u; // status of the first failure
static const uint P_BAD_REFS = 9u;      // references outside their domain
static const uint P_USES = 10u;         // the callee body's uses
static const uint P_USES_CLOSED = 11u;  // ... whose environments substitute to closed terms
static const uint P_HASH = 12u;         // + 2: structural hash of substituted rows and facts
static const uint P_PARAMS_CLOSED = 14u;
static const uint P_NESTED_CALLEE = 15u; // callee DeclId of the body's first ordinary call
static const uint P_DIR_FLAGS = 16u;
static const uint P_EXPECTED_CLOSED = 17u;
static const uint P_PARAM_COUNT = 18u;
static const uint P_REJECTION_CHECKS = 19u;
static const uint P_MISSING = 20u;      // VALUE/TYPE rows without a resolved term
static const uint P_BINDINGS = 21u;     // value bindings checked
static const uint P_BINDINGS_BAD = 22u;
static const uint P_MEMBERS = 23u;      // member rows checked against the struct schema
static const uint P_MEMBERS_BAD = 24u;
static const uint P_CONSTS = 25u;       // constant facts checked
static const uint P_CONSTS_BAD = 26u;
static const uint P_ANNOTATIONS = 27u;  // type rows substituted to closed terms
static const uint P_TOKENS = 28u;       // token records checked
static const uint P_TOKENS_BAD = 29u;
static const uint P_TEXT_HASH = 30u;    // FNV-1a of the body text
static const uint P_SYMBOLIC = 31u;     // template rows whose term is not closed
static const uint P_ARG_ROWS = 32u;     // rows substituted to exactly the first argument
static const uint P_FN_REFS = 33u;      // function-reference uses of the body
static const uint P_RECORDS = 34u;      // struct-literal uses of the body
static const uint P_VARIANTS = 35u;     // unit-variant and payload-constructor uses of the body
static const uint P_ARG_MODES = 36u;    // rows with a nonzero argument mode
static const uint P_ITERABLES = 37u;    // rows with a nonzero iterable kind
static const uint P_TEXT_BYTES = 38u;
static const uint P_SIDE_RECORDS = 39u;

static const uint FORM_CONSTRUCTOR = 4u;
static const uint FORM_RECORD = 3u;
static const uint FORM_CALL = 1u;
static const uint FORM_FN_REF = 8u;

static uint g_out;
static uint g_scratch;

void put(uint word, uint value) { rt_test_out[g_out + word] = value; }
void bump(uint word) { rt_test_out[g_out + word] += 1u; }

bool rel_ok(uint word, uint limit)
{
    if (word == 0xffffffffu) return true;
    return word != 0xc0000000u && word <= limit;
}

struct Segment
{
    uint index;
    uint4 s0;
    uint4 s1;
    uint4 s2;
    uint4 s4;
    uint4 s5;
};

uint side_len(Segment g, uint k)
{
    if (k < 4u) return k == 0u ? g.s1.x : (k == 1u ? g.s1.y : (k == 2u ? g.s1.z : g.s1.w));
    return k == 4u ? g.s2.x : (k == 5u ? g.s2.y : g.s2.z);
}

uint side_offset(Segment g, uint k)
{
    uint offset = 0u;
    for (uint j = 0u; j < k; j++) offset += side_len(g, j);
    return offset;
}

uint4 side_record(Segment g, uint k, uint index, uint part)
{
    return rt_seg_side[g.s0.w + 2u * (side_offset(g, k) + index) + part];
}

uint4 seg_row(Segment g, uint row, uint word) { return rt_seg_rows[(g.s0.y + row) * RT_ROW_WORDS + word]; }

uint token_hash(Segment g, uint token)
{
    return token < g.s2.w && g.s4.w != RT_INVALID ? rt_seg_tokens[g.s4.w + token].w : 0u;
}

// Whether a payload word of class `cls` is inside its domain.
bool word_ok(Segment g, uint cls, uint word)
{
    uint rows = g.s0.z;
    if (cls == RT_CLASS_ROW) return word == 0xffffffffu || word < rows;
    if (cls == RT_CLASS_TOKEN) return rel_ok(word, g.s2.w);
    if (cls == RT_CLASS_CONTEXT)
    {
        uint id = word & 0x7fffffffu;
        return id == 0x7fffffffu || id < rows;
    }
    if (cls >= RT_CLASS_SIDE) return rel_ok(word, side_len(g, cls - RT_CLASS_SIDE));
    return true;
}

// Whether a parameter row of the body has name token `token`.
bool param_named_by(Segment g, uint token)
{
    for (uint r = 0u; r < g.s0.z; r++)
        if (seg_row(g, r, 0u).x == RT_HIR_PARAM && seg_row(g, r, 2u).z == token) return true;
    return false;
}

uint2 subst(RtBinding b, uint term) { return rt_subst(b, term, g_scratch, LANE_WORDS); }

// The environment that binds struct `decl`'s parameters to the operands of
// the closed NAMED term `named`, interned in the store; 0 when none.
uint nominal_env(uint decl, uint named)
{
    uint arity = rt_term_arity(named);
    uint const_mask = rt_term_head[named].z;
    uint types = 0u; uint consts = 0u;
    // Type operands first, then constant operands, each in operand order.
    for (uint pass = 0u; pass < 2u; pass++)
        for (uint i = 0u; i < arity; i++)
        {
            bool constant = ((const_mask >> i) & 1u) != 0u;
            if (constant != (pass == 1u)) continue;
            rt_s_stack[g_scratch + types + consts] = rt_term_arg(named, i);
            if (constant) consts++; else types++;
        }
    uint type_mask = types == 0u ? 0u : (types >= 32u ? 0xffffffffu : (1u << types) - 1u);
    uint cmask = consts == 0u ? 0u : (consts >= 32u ? 0xffffffffu : (1u << consts) - 1u);
    RtTermKey key = rt_key_begin(RT_KIND_ENV, types + consts, types, uint3(decl, type_mask, cmask));
    RtScratchArgs args;
    args.base = g_scratch;
    for (uint i = 0u; i < types + consts; i++) rt_key_fold(key, args.arg(i));
    uint env = rt_intern_term(key, args);
    return rt_is_stored_term(env) ? env : 0u;
}

// The field `ordinal` of the struct the substituted receiver `receiver`
// names: its schema term, and the binding that substitutes it (the
// struct's parameters bound to the receiver's operands). `ready` is false
// when the field term is already the answer (a nongeneric struct).
bool member_field(uint2 receiver, uint ordinal, inout RtBinding field_binding, inout uint field_term, out bool ready)
{
    ready = false;
    if (receiver.y != RT_SUBST_OK) return false;
    uint named = receiver.x;
    for (uint step = 0u; step < 8u && rt_term_kind(named) == RT_KIND_REF; step++) named = rt_term_arg(named, 0u);
    if (rt_term_kind(named) != RT_KIND_NAMED) return false;
    uint decl = rt_term_head[named].y;
    uint def = rt_decl_def[decl];
    if (def == 0u) return false;
    uint entry = def - 1u;
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    if (rt_dir[entry * RT_DIR_WORDS].y != 5u || ordinal >= d2.z) return false;
    uint4 field = rt_schema[d2.y + ordinal];
    if ((field.y & 0xffu) != RT_SCHEMA_FIELD || (field.y >> 8u) != ordinal) return false;
    field_term = field.w;
    if (rt_term_arity(named) == 0u) return rt_term_closed(field.w);
    uint env = nominal_env(decl, named);
    if (env == 0u) return false;
    field_binding = rt_binding(entry, env);
    ready = true;
    return true;
}

void check_side(Segment g, inout uint bad)
{
    uint rows = g.s0.z;
    uint side = 0u;
    for (uint k = 0u; k < 7u; k++)
        for (uint i = 0u; i < side_len(g, k); i++)
        {
            uint4 r = side_record(g, k, i, 0u);
            uint4 e = side_record(g, k, i, 1u);
            side++;
            bool ok = true;
            if (k == 0u || k == 4u) ok = r.x < rows && r.y < rows;
            else if (k == 1u) ok = r.x < rows && rel_ok(r.y, g.s2.w) && (r.z == 0xffffffffu || r.z < rows);
            else if (k == 2u) ok = r.x < rows && (r.y == 0xffffffffu || r.y < rows) && (r.z == 0xffffffffu || r.z < rows) &&
                (e.y == 0u || (e.x != 0xffffffffu && e.x + e.y <= side_len(g, 3u)));
            else if (k == 3u) ok = r.x < side_len(g, 2u) && r.y < rows && (r.w == 0xffffffffu || r.w < rows);
            else if (k == 5u) ok = r.x < rows;
            else ok = r.x < rows && rel_ok(r.y, g.s2.w) && (r.z == 0xffffffffu || r.z < rows);
            if (!ok) bad++;
        }
    put(P_SIDE_RECORDS, side);
}

// Every substitution of an instance goes through one of three call sites:
// the declared signature (with the rejection terms), the per-row checks
// and the uses. Each site is a loop over its candidate terms.
void check_instance(uint entry, uint env, uint caller, uint first_arg)
{
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS + 0u];
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    uint4 d3 = rt_dir[entry * RT_DIR_WORDS + 3u];
    put(P_DIR_FLAGS, d3.w);
    put(P_PARAM_COUNT, d1.w);
    if (d3.w != 0u) return;
    RtBinding b = rt_binding(entry, env);

    uint rejected = 0u;
    // Keep the entry, masks, arity and all arguments identical. Only changing
    // the environment owner can distinguish this from the valid binding.
    uint owner = caller != 0u && caller != d0.x ? caller : d0.x + 1u;
    uint4 original_env = rt_term_head[env];
    RtTermKey other_key = rt_key_begin(RT_KIND_ENV, rt_term_arity(env), original_env.x >> 16u,
        uint3(owner, original_env.z, original_env.w));
    RtStoredArgs other_args;
    other_args.base = rt_term_meta[env].x;
    for (uint i = 0u; i < rt_term_arity(env); i++) rt_key_fold(other_key, other_args.arg(i));
    uint other_env = rt_intern_term(other_key, other_args);
    if (rt_is_stored_term(other_env) && rt_binding(entry, other_env).status == RT_SUBST_ENV) rejected |= 16u;

    // Failure results on the actual environment (neither unresolved
    // references may look valid), then the declared result and parameters.
    uint params_closed = 0u;
    for (uint i = 0u; i < 5u + d1.w; i++)
    {
        uint term = i == 0u ? 0u : (i == 1u ? RT_UNKNOWN : (i == 2u ? RT_NONE :
            (i == 3u ? RT_FIT_FAILED : rt_sigs[d1.z + i - 4u])));
        uint2 t = subst(b, term);
        if (i < 4u)
        {
            uint wanted = i == 3u ? RT_SUBST_FIT_FAILED : RT_SUBST_UNRESOLVED;
            if (t.y == wanted) rejected |= 1u << i;
        }
        else if (i == 4u) { put(P_RESULT, t.x); put(P_RESULT_STATUS, t.y); }
        else if (t.y == RT_SUBST_OK && rt_term_closed(t.x)) params_closed++;
    }
    put(P_REJECTION_CHECKS, rejected);
    put(P_PARAMS_CLOSED, params_closed);

    if (d2.x == RT_INVALID) return;
    Segment g;
    g.index = d2.x;
    g.s0 = rt_segments[g.index * RT_SEG_WORDS + 0u];
    g.s1 = rt_segments[g.index * RT_SEG_WORDS + 1u];
    g.s2 = rt_segments[g.index * RT_SEG_WORDS + 2u];
    g.s4 = rt_segments[g.index * RT_SEG_WORDS + 4u];
    g.s5 = rt_segments[g.index * RT_SEG_WORDS + 5u];
    uint rows = g.s0.z;
    uint tokens = g.s2.w;
    put(P_ROWS, rows);

    // Source provenance: token records ascend inside the text.
    uint tokens_bad = 0u;
    uint previous = 0u;
    for (uint t = 0u; t < tokens; t++)
    {
        uint4 rec = rt_seg_tokens[g.s4.w + t];
        if (rec.y + rec.z > g.s4.z || rec.y < previous || (t == 0u && rec.y != 0u)) tokens_bad++;
        previous = rec.y;
    }
    put(P_TOKENS, tokens);
    put(P_TOKENS_BAD, tokens_bad);
    uint text = 0x811c9dc5u;
    for (uint at = 0u; at < g.s4.z; at++)
        text = (text ^ ((rt_seg_bytes[g.s5.x + (at >> 2u)] >> ((at & 3u) * 8u)) & 0xffu)) * 0x01000193u;
    put(P_TEXT_HASH, text);
    put(P_TEXT_BYTES, g.s4.z);

    uint typed = 0u; uint failed = 0u; uint first = 0u; uint bad = 0u; uint missing = 0u;
    uint bindings = 0u; uint bindings_bad = 0u; uint members = 0u; uint members_bad = 0u;
    uint consts = 0u; uint consts_bad = 0u; uint annotations = 0u; uint symbolic = 0u;
    uint arg_rows = 0u; uint modes = 0u; uint iterables = 0u;
    uint2 hash = uint2(0x9e3779b9u, 0x7f4a7c15u);
    for (uint r = 0u; r < rows; r++)
    {
        uint4 r0 = seg_row(g, r, 0u);
        uint4 r1 = seg_row(g, r, 1u);
        uint4 r2 = seg_row(g, r, 2u);
        uint4 r3 = seg_row(g, r, 3u);
        uint4 r4 = seg_row(g, r, 4u);
        uint4 r5 = seg_row(g, r, 5u);
        uint4 r6 = seg_row(g, r, 6u);
        // Every reference by its domain.
        if (!rel_ok(r0.y, rows - 1u) || !rel_ok(r0.z, tokens) || !rel_ok(r0.w, tokens) ||
            !rel_ok(r1.x, rows - 1u) || !rel_ok(r1.y, rows - 1u) || !rel_ok(r1.z, rows)) bad++;
        uint classes = rt_payload_classes(r0.x, r2.x, r == 0u);
        for (uint w = 0u; w < 4u; w++)
        {
            uint word = w == 0u ? r2.x : (w == 1u ? r2.y : (w == 2u ? r2.z : r2.w));
            if (!word_ok(g, rt_word_class(classes, w), word)) bad++;
        }
        if (!rel_ok(r4.x, rows - 1u) || !rel_ok(r4.y, rows - 1u)) bad++;
        if (r4.w != 0u && (r4.z == 0xffffffffu || r4.z + r4.w > side_len(g, 4u))) bad++;
        if (r3.y != RT_NONE && r3.y >= d3.x) bad++;
        if ((r3.w & 4u) != 0u || ((r3.z == RT_ROLE_VALUE || r3.z == RT_ROLE_TYPE) && !rt_is_resolved(r3.x))) missing++;
        if ((r6.x & 0xffu) != 0u) modes++;
        if ((r6.x >> 8u) != 0u) iterables++;

        // The row's substitutions: 0 its term, 1 its parameter binding,
        // 2 its symbolic constant, 3 a member's receiver, 4 the member's
        // field under the receiver's struct binding.
        bool member = r0.x == RT_HIR_MEMBER_EXPR && r5.w != 0xffffffffu && r3.z == RT_ROLE_VALUE;
        bool member_found = false;
        bool field_pending = false;
        RtBinding field_binding = b;
        uint field_term = RT_NONE;
        uint2 own = uint2(r3.x, RT_SUBST_UNRESOLVED);
        uint2 bound = uint2(0u, RT_SUBST_UNRESOLVED);
        uint2 value = uint2(0u, RT_SUBST_UNRESOLVED);
        uint2 field = uint2(RT_NONE, RT_SUBST_UNRESOLVED);
        for (uint j = 0u; j < 5u; j++)
        {
            RtBinding with = b;
            uint term = RT_NONE;
            if (j == 0u) { if (!rt_is_resolved(r3.x)) continue; term = r3.x; }
            else if (j == 1u) { if (r5.x != RT_BIND_PARAM) continue; term = r5.y; }
            else if (j == 2u) { if (r6.y == 0u || (r6.y & RT_CONST_SYMBOLIC) == 0u) continue; term = r6.z; }
            else if (j == 3u) { if (!member || r2.y >= rows) continue; term = seg_row(g, r2.y, 3u).x; }
            else { if (!field_pending) continue; with = field_binding; term = field_term; }
            uint2 t = subst(with, term);
            if (j == 0u) own = t;
            else if (j == 1u) bound = t;
            else if (j == 2u) value = t;
            else if (j == 3u)
            {
                member_found = member_field(t, r5.w, field_binding, field_term, field_pending);
                if (member_found && !field_pending) field = uint2(field_term, RT_SUBST_OK);
            }
            else field = t;
        }

        if (rt_is_resolved(r3.x))
        {
            if (!rt_term_closed(r3.x)) symbolic++;
            if (own.y == RT_SUBST_OK && rt_term_closed(own.x))
            {
                typed++;
                if (r3.z == RT_ROLE_TYPE) annotations++;
                if (own.x == first_arg) arg_rows++;
                uint2 h = rt_ref_hash(own.x);
                hash = rt_mix2(rt_mix2(rt_mix2(hash, r), h.x), h.y);
            }
            else
            {
                if (failed == 0u) first = own.y == RT_SUBST_OK ? 0xffu : own.y;
                failed++;
            }
        }

        // The exact binding.
        if (r5.x != RT_BIND_NONE)
        {
            bindings++;
            bool ok = true;
            if (r5.x == RT_BIND_LOCAL)
            {
                ok = r5.y < tokens;
                // A name row's own spelling is its binding's spelling, or
                // the binding is a parameter row's name token (a receiver
                // `&self` is named by its first token).
                if (ok && r0.x == RT_HIR_NAME_EXPR && r2.w < tokens && token_hash(g, r2.w) != token_hash(g, r5.y))
                    ok = param_named_by(g, r5.y);
            }
            else if (r5.x == RT_BIND_DECL) ok = r5.y != 0u && r5.y < rt_counts[RT_A_DECLS] && rt_decl_def[r5.y] != 0u;
            else if (r5.x == RT_BIND_VARIANT)
            {
                uint def = r5.y < rt_counts[RT_A_DECLS] ? rt_decl_def[r5.y] : 0u;
                ok = def != 0u && r5.z < rt_dir[(def - 1u) * RT_DIR_WORDS + 1u].w;
            }
            else if (r5.x == RT_BIND_PARAM) ok = bound.y == RT_SUBST_OK && rt_term_closed(bound.x);
            else ok = false;
            if (!ok) bindings_bad++;
            // Structural identities only: DeclIds and TermIds depend on
            // allocation order.
            uint2 identity = uint2(r5.y, r5.z);
            if (r5.x == RT_BIND_PARAM) identity = rt_ref_hash(bound.x);
            else if ((r5.x == RT_BIND_DECL || r5.x == RT_BIND_VARIANT) && r5.y < rt_counts[RT_A_DECLS])
            {
                uint4 key = rt_decl_key[r5.y];
                identity = uint2(key.x ^ (key.z << 24u) ^ (r5.z << 16u), key.w ^ (key.y << 8u));
            }
            hash = rt_mix2(rt_mix2(rt_mix2(hash, r5.x), identity.x), identity.y);
        }
        // The member's field against the substituted struct schema.
        if (member)
        {
            members++;
            if (!member_found || field.y != RT_SUBST_OK || own.y != RT_SUBST_OK || field.x != own.x) members_bad++;
            hash = rt_mix2(hash, r5.w);
        }
        // Constants: a symbolic value is a constant parameter leaf.
        if (r6.y != 0u)
        {
            consts++;
            if ((r6.y & RT_CONST_SYMBOLIC) != 0u)
            {
                if (value.y != RT_SUBST_OK || !rt_term_closed(value.x)) consts_bad++;
                uint2 h = rt_ref_hash(value.x);
                hash = rt_mix2(rt_mix2(hash, h.x), h.y);
            }
            else hash = rt_mix2(rt_mix2(hash, r6.z), r6.w);
        }
    }
    check_side(g, bad);
    put(P_TYPED, typed);
    put(P_FAILED, failed);
    put(P_FIRST_FAILURE, first);
    put(P_MISSING, missing);
    put(P_BINDINGS, bindings);
    put(P_BINDINGS_BAD, bindings_bad);
    put(P_MEMBERS, members);
    put(P_MEMBERS_BAD, members_bad);
    put(P_CONSTS, consts);
    put(P_CONSTS_BAD, consts_bad);
    put(P_ANNOTATIONS, annotations);
    put(P_SYMBOLIC, symbolic);
    put(P_ARG_ROWS, arg_rows);
    put(P_ARG_MODES, modes);
    put(P_ITERABLES, iterables);

    uint closed = 0u; uint fn_refs = 0u; uint records = 0u; uint variants = 0u;
    for (uint k = 0u; k < d3.x; k++)
    {
        uint inner = d2.w + k;
        uint4 i0 = rt_uses[inner * RT_USE_WORDS + 0u];
        uint4 i1 = rt_uses[inner * RT_USE_WORDS + 1u];
        uint4 i2 = rt_uses[inner * RT_USE_WORDS + 2u];
        uint form = i0.z & 0xffu;
        if (form == FORM_CALL && rt_test_out[g_out + P_NESTED_CALLEE] == 0u) put(P_NESTED_CALLEE, i0.w);
        if (i0.y >= rows || !rel_ok(i2.w, tokens) || seg_row(g, i0.y, 3u).y != k) bad++;
        if (form == FORM_FN_REF) fn_refs++;
        if (form == FORM_RECORD) records++;
        if (form == FORM_CONSTRUCTOR) variants++;
        // A use without an environment (a function reference, a nongeneric
        // callee) still substitutes its result.
        bool env_use = rt_is_resolved(i1.x);
        if (!env_use && i1.x != RT_NONE) continue;
        uint2 t = subst(b, env_use ? i1.x : i1.y);
        if (t.y == RT_SUBST_OK && rt_term_closed(t.x))
        {
            closed++;
            if (env_use)
            {
                uint2 h = rt_ref_hash(t.x);
                hash = rt_mix2(rt_mix2(hash, h.x), h.y);
            }
        }
    }
    put(P_USES, d3.x);
    put(P_USES_CLOSED, closed);
    put(P_FN_REFS, fn_refs);
    put(P_RECORDS, records);
    put(P_VARIANTS, variants);
    put(P_BAD_REFS, bad);
    put(P_HASH, hash.x);
    put(P_HASH + 1u, hash.y);
}

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x;
    uint uses = rt_counts[RT_A_USES];
    uint requests = rt_test_meta[0u];
    if (lane >= uses + requests) return;
    g_out = lane * RT_PROBE_WORDS;
    g_scratch = lane * LANE_WORDS;
    for (uint i = 0u; i < RT_PROBE_WORDS; i++) rt_test_out[g_out + i] = 0u;
    uint callee; uint env; uint caller; uint first_arg = 0u;
    if (lane < uses)
    {
        uint4 u0 = rt_uses[lane * RT_USE_WORDS + 0u];
        uint4 u1 = rt_uses[lane * RT_USE_WORDS + 1u];
        callee = u0.w;
        env = u1.x;
        caller = u0.x;
        put(P_EXPECTED, u1.y);
        put(P_CALLEE, callee);
        if (callee == 0u) { put(P_ELIGIBLE, 2u); return; }
        if (rt_decl_def[callee] == 0u) { put(P_ELIGIBLE, 3u); return; }
        if (rt_counts[RT_C_READY] == 0u)
        {
            // rt_binding itself must refuse an unready build.
            put(P_RESULT_STATUS, rt_binding(rt_decl_def[callee] - 1u, env).status);
            put(P_ELIGIBLE, 6u);
            return;
        }
        if (all(rt_decl_key[callee].xy == rt_decl_key[u0.x].xy)) { put(P_ELIGIBLE, 4u); return; }
        if (!rt_term_closed(env)) { put(P_ELIGIBLE, 5u); return; }
        put(P_EXPECTED_CLOSED, rt_is_resolved(u1.y) && rt_term_closed(u1.y) ? 1u : 0u);
    }
    else
    {
        uint4 request = rt_test_requests[lane - uses];
        callee = request.x;
        caller = 0u;
        put(P_CALLEE, callee);
        if (callee == 0u || callee >= rt_counts[RT_A_DECLS] || rt_decl_def[callee] == 0u) { put(P_ELIGIBLE, 3u); return; }
        uint count = min(request.y, 2u);
        rt_s_stack[g_scratch] = request.z;
        rt_s_stack[g_scratch + 1u] = request.w;
        first_arg = request.z;
        uint mask = count == 0u ? 0u : (1u << count) - 1u;
        RtTermKey key = rt_key_begin(RT_KIND_ENV, count, count, uint3(callee, mask, 0u));
        RtScratchArgs args;
        args.base = g_scratch;
        for (uint i = 0u; i < count; i++) rt_key_fold(key, args.arg(i));
        env = rt_intern_term(key, args);
        if (!rt_is_stored_term(env)) { put(P_ELIGIBLE, 7u); return; }
        if (rt_counts[RT_C_READY] == 0u)
        {
            put(P_RESULT_STATUS, rt_binding(rt_decl_def[callee] - 1u, env).status);
            put(P_ELIGIBLE, 6u);
            return;
        }
        put(P_EXPECTED_CLOSED, 1u);
    }
    put(P_ELIGIBLE, 1u);
    check_instance(rt_decl_def[callee] - 1u, env, caller, first_arg);
}
