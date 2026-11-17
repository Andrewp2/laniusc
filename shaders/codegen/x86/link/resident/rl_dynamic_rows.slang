// One workgroup: the imports of the link and the dynamic writer's inputs,
// as codegen/x86/native/resolve.rs and codegen/x86/link/dynamic.rs build
// them on the host.
//
// The imports are __libc_start_main, then the referenced C names in byte
// order. A library is needed when it is the first to define an import; the
// needed libraries keep the inputs' order. Version needs group by library
// in needed order, each with its distinct version names in byte order, and
// number from 2. The string table holds a NUL, the sonames, the version
// names in that order and the import names.
//
// It also writes the emit's parameters (gRL words 8 to 15 and the dynamic
// writer's gDyn) and its four indirect dispatches. Any failure leaves the
// dispatches empty and sets a bit the host reads with the plan status; the
// host then links on the host, or records the emit again with the sizes it
// read when only a capacity was short.

import codegen.x86.link.resident.rl_cnames;

public StructuredBuffer<uint> rl_status;
public StructuredBuffer<uint> rl_name_ref;
// Per candidate: import index or INVALID, byte offset among the import
// names. Then one used flag per version (zeroed by the host), then per
// version: rank among the used versions or INVALID, byte offset among the
// version names.
public RWStructuredBuffer<uint> cn_scratch;
public RWStructuredBuffer<uint> cn_import_of_name;
public RWStructuredBuffer<uint> cn_dyn_words;
public RWStructuredBuffer<uint> cn_strings;
public RWStructuredBuffer<uint> cn_out;

static const uint ST_TEXT_LEN = 0u;
static const uint ST_RODATA_LEN = 1u;
static const uint ST_DEF_COUNT = 2u;
static const uint ST_NAME_STRIDE = 3u;
static const uint ST_MAIN_OFFSET = 5u;
static const uint ST_ERRORS = 16u;

// cn_out words.
static const uint CN_RL = 0u;
static const uint CN_DYN = 8u;
static const uint CN_ARGS = 32u;
static const uint CN_BITS = 44u;
static const uint CN_TOTAL = 45u;
static const uint CN_NEED_DYN = 46u;
static const uint CN_NEED_STRINGS = 47u;
static const uint CN_NEED_OUTPUT = 48u;
static const uint CN_IMPORTS = 49u;

static const uint MAX_INPUTS = 64u;
static const uint TEXT_OFFSET = 0x78u;
static const uint DYN_START_BYTES = 40u;
static const uint DYN_STUB_BYTES = 8u;

groupshared uint s_a[256];
groupshared uint s_b[256];
groupshared uint s_bits;
groupshared uint s_used[MAX_INPUTS];
groupshared uint s_vcount[MAX_INPUTS];
groupshared uint s_soname_at[MAX_INPUTS];
groupshared uint s_lib_before[MAX_INPUTS];
groupshared uint s_first_rank[MAX_INPUTS];
groupshared uint s_last_lib;
groupshared uint s_imports;
groupshared uint s_import_bytes;
groupshared uint s_versions;
groupshared uint s_version_bytes;
groupshared uint s_needed;
groupshared uint s_version_at;
groupshared uint s_import_at;

// Exclusive prefix sums of `a` and `b` across the group, and their totals.
void scan2(uint lane, uint a, uint b, out uint prefix_a, out uint prefix_b, out uint total_a, out uint total_b)
{
    s_a[lane] = a;
    s_b[lane] = b;
    GroupMemoryBarrierWithGroupSync();
    for (uint step = 1u; step < 256u; step <<= 1u)
    {
        uint add_a = lane >= step ? s_a[lane - step] : 0u;
        uint add_b = lane >= step ? s_b[lane - step] : 0u;
        GroupMemoryBarrierWithGroupSync();
        s_a[lane] += add_a;
        s_b[lane] += add_b;
        GroupMemoryBarrierWithGroupSync();
    }
    prefix_a = s_a[lane] - a;
    prefix_b = s_b[lane] - b;
    total_a = s_a[255u];
    total_b = s_b[255u];
    GroupMemoryBarrierWithGroupSync();
}

uint version_flag_at() { return gCN.candidate_count * 2u; }
uint version_rank_at() { return gCN.candidate_count * 2u + gCN.version_count; }

void write_byte(uint at, uint value)
{
    if (value != 0u && at < gCN.string_capacity_bytes)
        atomic_u32_or(cn_strings, at >> 2u, value << ((at & 3u) * 8u));
}

void copy_name(uint to, uint from, uint len)
{
    for (uint i = 0u; i < len; i += 1u)
        write_byte(to + i, cn_byte(from + i));
}

void dyn_word(uint index, uint value)
{
    if (index < gCN.dyn_word_capacity)
        cn_dyn_words[index] = value;
}

uint align_up(uint value, uint alignment) { return (value + alignment - 1u) & ~(alignment - 1u); }

void write_groups(uint at, uint lanes, bool run)
{
    uint groups = max((lanes + 255u) / 256u, 1u);
    cn_out[at] = run ? min(groups, 65535u) : 0u;
    cn_out[at + 1u] = run ? (groups + 65534u) / 65535u : 0u;
    cn_out[at + 2u] = run ? 1u : 0u;
}

// The defining row of a referenced candidate.
uint defining_row(uint candidate) { return INVALID - cn_match[candidate * 3u]; }

uint version_of_row(uint row)
{
    uint code = cn_rows[row * 3u + 2u];
    if (code == 0u || code >= CODE_ARCHIVE)
        return INVALID;
    return input_word(input_of_row(row), 3u) + code - 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gtid: SV_GroupThreadID)
{
    uint lane = gtid.x;
    if (lane == 0u)
    {
        s_bits = gCN.gate != GATE_ON || rl_status[ST_ERRORS] != 0u || gCN.input_count > MAX_INPUTS ? BIT_GATE : 0u;
        s_bits |= cn_out[CN_BITS];
    }
    if (lane < MAX_INPUTS)
    {
        s_used[lane] = 0u;
        s_vcount[lane] = 0u;
    }
    GroupMemoryBarrierWithGroupSync();

    // Imports: which candidates the program references, their order and
    // their string bytes, the inputs that define them and their versions.
    uint imports = 0u;
    uint import_bytes = 0u;
    for (uint base = 0u; base < gCN.candidate_count; base += 256u)
    {
        uint candidate = base + lane;
        uint referenced = 0u;
        uint len = 0u;
        uint slot = INVALID;
        if (candidate < gCN.candidate_count)
        {
            len = cn_names[candidate * 3u + 1u];
            slot = cn_names[candidate * 3u + 2u];
            referenced = candidate == 0u || (slot != INVALID && rl_name_ref[slot] != 0u) ? 1u : 0u;
        }
        if (referenced != 0u)
        {
            uint def_key = cn_match[candidate * 3u];
            uint archive_key = cn_match[candidate * 3u + 1u];
            uint bits = 0u;
            if (def_key == 0u)
                bits |= BIT_UNRESOLVED;
            uint row = INVALID - def_key;
            // An archive earlier than the defining library (or any archive
            // when no library defines the name) needs the static linker.
            if (archive_key > def_key || (gCN.wild_row != INVALID && gCN.wild_row < row))
                bits |= BIT_DRIVER;
            if (cn_match[candidate * 3u + 2u] != 0u)
                bits |= BIT_VERSION;
            if (bits != 0u)
                InterlockedOr(s_bits, bits);
            else
            {
                uint input = input_of_row(row);
                if (input < MAX_INPUTS)
                    s_used[input] = 1u;
                uint version = version_of_row(row);
                if (version != INVALID)
                    cn_scratch[version_flag_at() + version] = 1u;
            }
        }
        uint prefix, byte_prefix, total, byte_total;
        scan2(lane, referenced, referenced * (len + 1u), prefix, byte_prefix, total, byte_total);
        if (candidate < gCN.candidate_count)
        {
            uint index = referenced != 0u ? imports + prefix : INVALID;
            cn_scratch[candidate * 2u] = index;
            cn_scratch[candidate * 2u + 1u] = import_bytes + byte_prefix;
            if (slot != INVALID && slot < gCN.name_count)
                cn_import_of_name[slot] = index;
        }
        imports += total;
        import_bytes += byte_total;
    }
    AllMemoryBarrierWithGroupSync();

    // Versions: rank the used ones in (input, name) order.
    uint versions = 0u;
    uint version_bytes = 0u;
    for (uint base = 0u; base < gCN.version_count; base += 256u)
    {
        uint version = base + lane;
        uint used = version < gCN.version_count ? cn_scratch[version_flag_at() + version] : 0u;
        uint len = version < gCN.version_count ? cn_versions[version * 2u + 1u] : 0u;
        uint prefix, byte_prefix, total, byte_total;
        scan2(lane, used, used * (len + 1u), prefix, byte_prefix, total, byte_total);
        if (version < gCN.version_count)
        {
            cn_scratch[version_rank_at() + version * 2u] = used != 0u ? versions + prefix : INVALID;
            cn_scratch[version_rank_at() + version * 2u + 1u] = version_bytes + byte_prefix;
            if (used != 0u)
            {
                uint input = input_of_version(version);
                if (input < MAX_INPUTS)
                    InterlockedAdd(s_vcount[input], 1u);
            }
        }
        versions += total;
        version_bytes += byte_total;
    }
    AllMemoryBarrierWithGroupSync();

    if (lane == 0u)
    {
        uint bits = s_bits;
        if (2u + versions > 0x7fffu)
            bits |= BIT_VERSIONS;
        // Needed libraries and their sonames; version-need libraries.
        uint needed = 0u;
        uint string_at = 1u;
        uint libraries = 0u;
        uint ranks = 0u;
        uint last_lib = INVALID;
        for (uint k = 0u; k < min(gCN.input_count, MAX_INPUTS); k += 1u)
        {
            s_soname_at[k] = 0u;
            s_lib_before[k] = libraries;
            s_first_rank[k] = ranks;
            if (s_used[k] == 0u || input_word(k, 7u) != KIND_SHARED)
                continue;
            s_soname_at[k] = string_at;
            string_at += input_word(k, 6u) + 1u;
            needed += 1u;
            if (s_vcount[k] != 0u)
            {
                libraries += 1u;
                ranks += s_vcount[k];
                last_lib = k;
            }
        }
        uint version_at = string_at;
        uint import_at = version_at + version_bytes;
        uint strings_len = import_at + import_bytes;
        uint n = imports;
        uint verneed_count = libraries + versions;
        uint needed_rows = 2u * n;
        uint verneed_rows = needed_rows + needed;
        uint symbol_rows = verneed_rows + 4u * verneed_count;

        // codegen/x86/link/dynamic.rs `resident_rows` and `layout_for`.
        uint lanius_text = rl_status[ST_TEXT_LEN];
        uint rodata_len = rl_status[ST_RODATA_LEN];
        uint symbols = rl_status[ST_DEF_COUNT];
        uint stride = rl_status[ST_NAME_STRIDE];
        uint import_text = DYN_START_BYTES + DYN_STUB_BYTES * n;
        uint text_len = lanius_text + import_text;
        uint rodata_end = TEXT_OFFSET + text_len + rodata_len;
        uint tail = align_up(rodata_end, 8u);
        uint interp = tail + 6u * 56u;
        uint hash = align_up(interp + 28u, 8u);
        uint dynsym = align_up(hash + 4u * (n + 4u), 8u);
        uint dynstr = dynsym + 24u * (n + 1u);
        uint versym = align_up(dynstr + strings_len, 2u);
        uint verneed = align_up(versym + 2u * (n + 1u), 8u);
        uint rela = verneed + 16u * verneed_count;
        uint rx_end = rela + 24u * n;
        uint rw = align_up(rx_end, 4096u);
        uint got = rw + 16u * (needed + 15u);
        uint symtab = align_up(got + 8u * n, 8u);
        uint strtab = symtab + 24u * (3u + symbols);
        uint shstrtab = strtab + 13u + symbols * stride;
        uint sh = align_up(shstrtab + 123u, 8u);
        uint total = sh + 64u * 15u;
        uint total_words = (total + 3u) / 4u;
        uint element_count = TEXT_OFFSET + import_text + (total - tail);

        uint need_dyn = symbol_rows + symbols * 8u;
        if (need_dyn > gCN.dyn_word_capacity || strings_len > gCN.string_capacity_bytes ||
            total_words > gCN.output_capacity_words)
            bits |= BIT_CAPACITY;
        s_bits = bits;
        s_last_lib = last_lib;
        s_imports = n;
        s_needed = needed;
        s_versions = versions;
        s_version_at = version_at;
        s_import_at = import_at;

        bool run = bits == 0u;
        cn_out[CN_BITS] = bits;
        cn_out[CN_TOTAL] = total;
        cn_out[CN_NEED_DYN] = need_dyn;
        cn_out[CN_NEED_STRINGS] = strings_len;
        cn_out[CN_NEED_OUTPUT] = total_words;
        cn_out[CN_IMPORTS] = n;
        // gRL words 8 to 15.
        cn_out[CN_RL + 0u] = n;
        cn_out[CN_RL + 1u] = text_len;
        cn_out[CN_RL + 2u] = total;
        cn_out[CN_RL + 3u] = symbol_rows;
        cn_out[CN_RL + 4u] = gCN.name_count;
        cn_out[CN_RL + 5u] = 0u;
        cn_out[CN_RL + 6u] = total_words;
        cn_out[CN_RL + 7u] = 0u;
        // gDyn.
        uint d = CN_DYN;
        cn_out[d + 0u] = 0u;
        cn_out[d + 1u] = total;
        cn_out[d + 2u] = rodata_end;
        cn_out[d + 3u] = TEXT_OFFSET + lanius_text;
        cn_out[d + 4u] = TEXT_OFFSET + rl_status[ST_MAIN_OFFSET];
        cn_out[d + 5u] = n;
        cn_out[d + 6u] = needed;
        cn_out[d + 7u] = verneed_count;
        cn_out[d + 8u] = libraries;
        cn_out[d + 9u] = strings_len;
        cn_out[d + 10u] = symbols;
        cn_out[d + 11u] = stride;
        cn_out[d + 12u] = text_len;
        cn_out[d + 13u] = rodata_len;
        cn_out[d + 14u] = total;
        cn_out[d + 15u] = element_count;
        cn_out[d + 16u] = 0u;
        cn_out[d + 17u] = needed_rows;
        cn_out[d + 18u] = verneed_rows;
        cn_out[d + 19u] = symbol_rows;
        cn_out[d + 20u] = gCN.main_bytes;
        cn_out[d + 21u] = 0u;
        cn_out[d + 22u] = 0u;
        cn_out[d + 23u] = 0u;
        write_groups(CN_ARGS, gCN.symbol_cap_total, run);
        write_groups(CN_ARGS + 3u, total_words, run);
        write_groups(CN_ARGS + 6u, element_count, run);
        write_groups(CN_ARGS + 9u, gCN.reloc_cap_total, run);

        if (run)
        {
            // Needed rows and the version-need record of each library.
            uint index = 0u;
            for (uint k = 0u; k < min(gCN.input_count, MAX_INPUTS); k += 1u)
            {
                if (s_soname_at[k] == 0u)
                    continue;
                dyn_word(needed_rows + index, s_soname_at[k]);
                index += 1u;
                if (s_vcount[k] == 0u)
                    continue;
                uint row = verneed_rows + 4u * (s_lib_before[k] + s_first_rank[k]);
                dyn_word(row, k == last_lib ? 2u : 0u);
                dyn_word(row + 1u, s_vcount[k]);
                dyn_word(row + 2u, s_soname_at[k]);
                dyn_word(row + 3u, 0u);
            }
        }
    }
    AllMemoryBarrierWithGroupSync();
    if (s_bits != 0u)
        return;

    uint needed_rows = 2u * s_imports;
    uint verneed_rows = needed_rows + s_needed;
    // Import rows and names.
    for (uint candidate = lane; candidate < gCN.candidate_count; candidate += 256u)
    {
        uint index = cn_scratch[candidate * 2u];
        if (index == INVALID)
            continue;
        uint at = s_import_at + cn_scratch[candidate * 2u + 1u];
        uint version = version_of_row(defining_row(candidate));
        dyn_word(2u * index, at);
        dyn_word(2u * index + 1u, version == INVALID ? 1u : 2u + cn_scratch[version_rank_at() + version * 2u]);
        copy_name(at, cn_names[candidate * 3u], cn_names[candidate * 3u + 1u]);
    }
    // Version-need entries and version names.
    for (uint version = lane; version < gCN.version_count; version += 256u)
    {
        uint rank = cn_scratch[version_rank_at() + version * 2u];
        if (rank == INVALID)
            continue;
        uint input = input_of_version(version);
        uint at = s_version_at + cn_scratch[version_rank_at() + version * 2u + 1u];
        bool last = rank + 1u == s_first_rank[input] + s_vcount[input];
        uint row = verneed_rows + 4u * (s_lib_before[input] + 1u + rank);
        dyn_word(row, 1u | (last ? 2u : 0u));
        dyn_word(row + 1u, 2u + rank);
        dyn_word(row + 2u, at);
        dyn_word(row + 3u, 0u);
        copy_name(at, input_word(input, 2u) + cn_versions[version * 2u], cn_versions[version * 2u + 1u]);
    }
    // Sonames.
    if (lane < min(gCN.input_count, MAX_INPUTS) && s_soname_at[lane] != 0u)
        copy_name(s_soname_at[lane], input_word(lane, 5u), input_word(lane, 6u));
}
