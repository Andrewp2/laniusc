// Test fixture for retained substitution (tests/retained_substitution.rs).
// One lane runs a construction script against the store: it interns
// declarations, parameters and terms with the store's own interner, writes
// committed (or staged/incomplete) directory entries with binder maps, and
// appends substitution requests. Expected results are terms the script
// builds directly, so every identity comes from the store.
//
// fx_config: (library, op words...). Registers are fx_out[16 + r].
// fx_out: (store overflow, requests, store terms, script error).
//   0 END
//   1 DECL  dst ns local
//   2 PARAM dst owner domain ordinal scalar
//   3 LEAF  dst param
//   4 MK    dst kind arity type_slots w0 w1 w2 word_registers args...
//   5 ENTRY decl kind parent types consts state incomplete params...
//   6 REQ   decl env term
//   7 SET   dst value
//   8 CLEAR_READY
//   9 FLIP  dst src mask      (dst = src ^ mask)
// Operands named decl/owner/param/parent/env/term/args are registers;
// word_registers has bit k set when word k is a register.
import type_checker.retention.retention_store;

RWStructuredBuffer<uint> fx_config;
RWStructuredBuffer<uint> fx_out;
RWStructuredBuffer<uint4> sb_requests;
RWStructuredBuffer<uint> sb_request_count;

static const uint REG = 16u;

uint reg(uint r) { return fx_out[REG + r]; }
void put(uint r, uint value) { fx_out[REG + r] = value; }
uint op(uint at) { return fx_config[at]; }

struct ScriptArgs : IRtArgs
{
    uint base;
    uint arg(uint index) { return reg(op(base + index)); }
}

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint words; uint stride;
    fx_config.GetDimensions(words, stride);
    uint library = op(0u);
    uint requests = 0u;
    uint capacity; sb_requests.GetDimensions(capacity, stride);
    uint at = 1u;
    uint error = 0u;
    for (uint step = 0u; step < 1000000u && at < words; step++)
    {
        uint code = op(at);
        if (code == 0u) break;
        if (code == 1u)
        {
            put(op(at + 1u), rt_intern_decl(uint4(library, 0u, op(at + 2u), op(at + 3u))));
            at += 4u;
        }
        else if (code == 2u)
        {
            put(op(at + 1u), rt_intern_param(reg(op(at + 2u)), op(at + 3u), op(at + 4u), op(at + 5u)));
            at += 6u;
        }
        else if (code == 3u)
        {
            put(op(at + 1u), rt_param_leaf(reg(op(at + 2u))));
            at += 3u;
        }
        else if (code == 4u)
        {
            uint arity = op(at + 3u);
            uint mask = op(at + 8u);
            uint3 w = uint3(op(at + 5u), op(at + 6u), op(at + 7u));
            if ((mask & 1u) != 0u) w.x = reg(w.x);
            if ((mask & 2u) != 0u) w.y = reg(w.y);
            if ((mask & 4u) != 0u) w.z = reg(w.z);
            RtTermKey key = rt_key_begin(op(at + 2u), arity, op(at + 4u), w);
            ScriptArgs args;
            args.base = at + 9u;
            for (uint i = 0u; i < arity; i++) rt_key_fold(key, args.arg(i));
            uint term = rt_intern_term(key, args);
            if (!rt_is_term(term)) error = at;
            put(op(at + 1u), term);
            at += 9u + arity;
        }
        else if (code == 5u)
        {
            uint d = reg(op(at + 1u));
            uint parent = op(at + 3u) == 0xffffffffu ? 0u : reg(op(at + 3u));
            uint types = op(at + 4u);
            uint consts = op(at + 5u);
            uint state = op(at + 6u);
            uint e = rt_alloc(RT_A_DIR, 1u);
            uint b = rt_alloc(RT_A_BINDERS, max(types + consts, 1u));
            if (e == RT_INVALID || b == RT_INVALID) { error = at; break; }
            for (uint i = 0u; i < types + consts; i++) rt_binders[b + i] = reg(op(at + 8u + i));
            rt_dir[e * RT_DIR_WORDS + 0u] = uint4(d, op(at + 2u), parent, state);
            rt_dir[e * RT_DIR_WORDS + 1u] = uint4(b, types | (consts << 16u), 0u, 0u);
            rt_dir[e * RT_DIR_WORDS + 2u] = uint4(RT_INVALID, 0u, 0u, 0u);
            rt_dir[e * RT_DIR_WORDS + 3u] = uint4(0u, 0u, 0u, op(at + 7u));
            rt_decl_def[d] = state == RT_DIR_COMMITTED ? e + 1u : 0u;
            at += 8u + types + consts;
        }
        else if (code == 6u)
        {
            if (requests < capacity)
                sb_requests[requests] = uint4(reg(op(at + 1u)), reg(op(at + 2u)), reg(op(at + 3u)), requests);
            requests++;
            at += 4u;
        }
        else if (code == 7u)
        {
            put(op(at + 1u), op(at + 2u));
            at += 3u;
        }
        else if (code == 8u)
        {
            rt_counts[RT_C_READY] = 0u;
            at += 1u;
        }
        else if (code == 9u)
        {
            put(op(at + 1u), reg(op(at + 2u)) ^ op(at + 3u));
            at += 4u;
        }
        else { error = at; break; }
    }
    sb_request_count[0u] = requests;
    fx_out[0u] = rt_counts[RT_C_OVERFLOW];
    fx_out[1u] = requests;
    fx_out[2u] = rt_counts[RT_A_TERMS];
    fx_out[3u] = error;
}
