// Per token: the nesting depth change and whether a closure starts here.
// Count starts directly so closure-free packs need no depth scan.
// Binder roles consume the resulting depth scan in roles.slang, only when
// the source pack contains a closure.
//
// Per file, the kernel also ORs the rewrites the file needs into
// `file_flags` (docs/state-machines-design.md, "Selecting the files to
// rewrite"): SELECT_CLOSURES when
// a closure starts in it, SELECT_MACHINES when it holds a token that only a
// machine or a generator can use, or a name with the reserved prefix. The
// machine pass parses only the files with SELECT_MACHINES.
import gpu_index;
import byte_packing;
import generated_token_ids;
import closure_common;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> token_file_id;
ByteAddressBuffer in_bytes;
RWStructuredBuffer<uint4> marks;
RWStructuredBuffer<uint> summary;
RWStructuredBuffer<uint> file_flags;

static const uint SELECT_CLOSURES = 1u;
static const uint SELECT_MACHINES = 2u;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint kind_in_file(uint i, uint count, uint file)
{
    if (i >= count || token_file_id[i] != file)
        return 0u;
    return tokens_out[i].kind;
}

// A closure starts at `|` or `||` where a binary operator cannot stand.
bool prefix_position(uint previous)
{
    return tk_paren_open(previous) || tk_comma(previous) || tk_assign(previous) || previous == TK_RETURN ||
           previous == TK_COLON || previous == TK_ARROW;
}

// The word `move`, which makes the closure after it an owned value.
bool move_word(uint i)
{
    TokenOut token = tokens_out[i];
    if (token.kind != TK_IDENT || token.len != 4u)
        return false;
    return byte_address_load_u8(in_bytes, token.start) == 109u && byte_address_load_u8(in_bytes, token.start + 1u) == 111u &&
           byte_address_load_u8(in_bytes, token.start + 2u) == 118u && byte_address_load_u8(in_bytes, token.start + 3u) == 101u;
}

// The lexer gives these kinds only to the words of a machine, a transition
// or a generator: `machine` before a name, `state`, `start` and `final` in a
// machine's body, `goto` before a name, `stay` before `with` or after an
// arm's arrow, `gen` before `fn`, and `yield`.
bool machine_kind(uint kind)
{
    return kind == TK_MACHINE || kind == TK_START || kind == TK_STATE || kind == TK_FINAL || kind == TK_GOTO ||
           kind == TK_STAY || kind == TK_GEN || kind == TK_YIELD;
}

// A name that starts with `__lanius_`, the prefix of generated names.
bool reserved_name(uint i)
{
    TokenOut token = tokens_out[i];
    if (token.kind != TK_IDENT || token.len < 9u)
        return false;
    // "__lanius_"
    uint expected[9] = { 95u, 95u, 108u, 97u, 110u, 105u, 117u, 115u, 95u };
    for (uint k = 0u; k < 9u; k += 1u)
    {
        if (byte_address_load_u8(in_bytes, token.start + k) != expected[k])
            return false;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    uint count = token_count[0];
    if (i == 0u)
        summary[0] = count;
    if (i >= count)
        return;

    uint file = token_file_id[i];
    uint kind = tokens_out[i].kind;
    uint previous = i > 0u ? kind_in_file(i - 1u, count, file) : 0u;

    bool bar = kind == TK_PIPE || kind == TK_OROR;
    uint before_previous = i > 1u ? kind_in_file(i - 2u, count, file) : 0u;
    bool moved = bar && previous == TK_IDENT && prefix_position(before_previous) && move_word(i - 1u);
    uint start = bar && (prefix_position(previous) || moved) ? 1u : 0u;
    marks[i] = uint4(tk_depth_delta(kind), start, 0u, 0u);
    uint select = (start != 0u ? SELECT_CLOSURES : 0u) | (machine_kind(kind) || reserved_name(i) ? SELECT_MACHINES : 0u);
    if (select != 0u)
    {
        uint before;
        InterlockedOr(file_flags[file], select, before);
    }
    if (start != 0u)
    {
        uint prior;
        InterlockedAdd(summary[1], 1u, prior);
    }
}
