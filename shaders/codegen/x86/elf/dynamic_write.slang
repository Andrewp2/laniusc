// Dynamic-link parts of a native C executable for Linux x86-64/glibc.
//
// The section passes place .text at 0x78 and .rodata after it, as for a
// freestanding executable. The last object of a dynamic link is the import
// object: `_start` followed by one eight-byte stub per imported function,
// all zero in its input. This pass writes, one byte per thread:
// - the ELF header (program headers and sections are elsewhere);
// - `_start` and the stubs inside the import object;
// - after .rodata, the program headers, .interp, .hash, .dynsym, .dynstr,
//   .gnu.version, .gnu.version_r and .rela.dyn in the executable segment, a
//   page-aligned writable segment with .dynamic and .got, and the unloaded
//   .symtab, .strtab, .shstrtab and section headers.
//
// The pass derives every offset from counts (dynamic_layout); the host
// mirror in codegen/x86/link/dynamic.rs sizes the output from the same
// formulas and this pass rejects a disagreement. Every GOT entry has an
// R_X86_64_GLOB_DAT relocation and the image asks for eager binding, so a
// stub is `jmp [rip + got]` and never needs lazy-binding support.

import atomics;
import byte_packing;
import gpu_index;

struct Params
{
    uint output_page_base;
    uint output_page_len;
    uint rodata_end;
    uint start_offset;
    uint main_offset;
    uint import_count;
    uint needed_count;
    uint verneed_count;
    uint verneed_libraries;
    uint dynstr_len;
    uint symbol_count;
    uint name_stride;
    uint text_len;
    uint rodata_len;
    uint total_len;
    uint element_count;
    uint import_rows;
    uint needed_rows;
    uint verneed_rows;
    uint symbol_rows;
    uint main_size;
    uint reserved_0;
    uint reserved_1;
    uint reserved_2;
};

ConstantBuffer<Params> gDyn;

// Import rows: (dynstr name offset, version index). Needed rows: (soname
// offset). Version-need rows: (kind | last << 1, count or version index,
// dynstr offset, 0); kind 0 is an Elf64_Verneed, 1 an Elf64_Vernaux. Symbol
// rows: (file offset, size, section 1 text or 2 rodata, identity words 0..2,
// 0, 0).
StructuredBuffer<uint> dynamic_words;
ByteAddressBuffer dynamic_strings;

RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> link_relocation_status;

static const uint BASE = 0x400000u;
static const uint TEXT_OFFSET = 0x78u;
static const uint START_BYTES = 40u;
static const uint START_CODE_BYTES = 34u;
static const uint STUB_BYTES = 8u;
static const uint PROGRAM_HEADERS = 6u;
static const uint SECTIONS = 15u;
static const uint FIXED_DYNAMIC = 15u;
static const uint INTERP_BYTES = 28u;
static const uint STRTAB_PREFIX = 13u;
static const uint SHSTRTAB_BYTES = 123u;
static const uint DYNAMIC_LAYOUT_ERROR = 10u;

static const uint START_WORDS[10] = {
    0x8949ed31u, 0x89485ed1u, 0xe48348e2u, 0x455450f0u, 0xc931c031u,
    0x003d8d48u, 0xff000000u, 0x00000015u, 0xccccf400u, 0xccccccccu,
};
// "/lib64/ld-linux-x86-64.so.2"
static const uint INTERP_WORDS[7] = {
    0x62696c2fu, 0x6c2f3436u, 0x696c2d64u, 0x2d78756eu, 0x2d363878u,
    0x732e3436u, 0x00322e6fu,
};
static const uint SHSTRTAB_WORDS[31] = {
    0x6e692e00u, 0x70726574u, 0x61682e00u, 0x2e006873u, 0x736e7964u,
    0x2e006d79u, 0x736e7964u, 0x2e007274u, 0x2e756e67u, 0x73726576u,
    0x006e6f69u, 0x756e672eu, 0x7265762eu, 0x6e6f6973u, 0x2e00725fu,
    0x616c6572u, 0x6e79642eu, 0x65742e00u, 0x2e007478u, 0x61646f72u,
    0x2e006174u, 0x616e7964u, 0x0063696du, 0x746f672eu, 0x79732e00u,
    0x6261746du, 0x74732e00u, 0x62617472u, 0x68732e00u, 0x74727473u,
    0x00006261u,
};
// "\0main\0_start\0"
static const uint STRTAB_PREFIX_WORDS[4] = {
    0x69616d00u, 0x735f006eu, 0x74726174u, 0x00000000u,
};

struct DynamicLayout
{
    uint tail;
    uint ph;
    uint interp;
    uint hash;
    uint hash_len;
    uint dynsym;
    uint dynstr;
    uint versym;
    uint verneed;
    uint rela;
    uint rx_end;
    uint rw;
    uint dynamic_count;
    uint got;
    uint rw_end;
    uint symtab;
    uint symtab_count;
    uint strtab;
    uint strtab_len;
    uint shstrtab;
    uint sh;
    uint total;
};

uint align_up(uint value, uint alignment)
{
    return (value + alignment - 1u) & ~(alignment - 1u);
}

DynamicLayout dynamic_layout()
{
    uint n = gDyn.import_count;
    DynamicLayout layout;
    layout.tail = align_up(gDyn.rodata_end, 8u);
    layout.ph = layout.tail;
    layout.interp = layout.ph + PROGRAM_HEADERS * 56u;
    layout.hash = align_up(layout.interp + INTERP_BYTES, 8u);
    layout.hash_len = 4u * (n + 4u);
    layout.dynsym = align_up(layout.hash + layout.hash_len, 8u);
    layout.dynstr = layout.dynsym + 24u * (n + 1u);
    layout.versym = align_up(layout.dynstr + gDyn.dynstr_len, 2u);
    layout.verneed = align_up(layout.versym + 2u * (n + 1u), 8u);
    layout.rela = layout.verneed + 16u * gDyn.verneed_count;
    layout.rx_end = layout.rela + 24u * n;
    layout.rw = align_up(layout.rx_end, 4096u);
    layout.dynamic_count = gDyn.needed_count + FIXED_DYNAMIC;
    layout.got = layout.rw + 16u * layout.dynamic_count;
    layout.rw_end = layout.got + 8u * n;
    layout.symtab = align_up(layout.rw_end, 8u);
    layout.symtab_count = 3u + gDyn.symbol_count;
    layout.strtab = layout.symtab + 24u * layout.symtab_count;
    layout.strtab_len = STRTAB_PREFIX + gDyn.symbol_count * gDyn.name_stride;
    layout.shstrtab = layout.strtab + layout.strtab_len;
    layout.sh = align_up(layout.shstrtab + SHSTRTAB_BYTES, 8u);
    layout.total = layout.sh + 64u * SECTIONS;
    return layout;
}

uint word_byte(uint word, uint local)
{
    return packed_u8_at(word, local);
}

uint elf_header_word(uint word, DynamicLayout layout)
{
    switch (word)
    {
    case 0u: return 0x464c457fu;
    case 1u: return 0x00010102u;
    case 4u: return 2u | (62u << 16u);
    case 5u: return 1u;
    case 6u: return BASE + gDyn.start_offset;
    case 8u: return layout.ph;
    case 10u: return layout.sh;
    case 13u: return 64u | (56u << 16u);
    case 14u: return PROGRAM_HEADERS | (64u << 16u);
    case 15u: return SECTIONS | (14u << 16u);
    default: return 0u;
    }
}

// Elf64_Phdr words: type, flags, offset, vaddr, paddr, filesz, memsz, align.
uint program_header_word(uint header, uint word, DynamicLayout layout)
{
    uint kind = 0u;
    uint flags = 0u;
    uint offset = 0u;
    uint size = 0u;
    uint align = 0u;
    bool mapped = true;
    switch (header)
    {
    case 0u: kind = 6u; flags = 4u; offset = layout.ph; size = PROGRAM_HEADERS * 56u; align = 8u; break;
    case 1u: kind = 3u; flags = 4u; offset = layout.interp; size = INTERP_BYTES; align = 1u; break;
    case 2u: kind = 1u; flags = 5u; offset = 0u; size = layout.rx_end; align = 4096u; break;
    case 3u: kind = 1u; flags = 6u; offset = layout.rw; size = layout.rw_end - layout.rw; align = 4096u; break;
    case 4u: kind = 2u; flags = 6u; offset = layout.rw; size = 16u * layout.dynamic_count; align = 8u; break;
    default: kind = 0x6474e551u; flags = 6u; mapped = false; align = 16u; break;
    }
    uint address = mapped ? BASE + offset : 0u;
    switch (word)
    {
    case 0u: return kind;
    case 1u: return flags;
    case 2u: return offset;
    case 4u: return address;
    case 6u: return address;
    case 8u: return size;
    case 10u: return size;
    case 12u: return align;
    default: return 0u;
    }
}

uint dynamic_entry_word(uint entry, uint word, DynamicLayout layout)
{
    uint tag = 0u;
    uint value = 0u;
    uint n = gDyn.import_count;
    if (entry < gDyn.needed_count)
    {
        tag = 1u;
        value = dynamic_words[gDyn.needed_rows + entry];
    }
    else
    {
        switch (entry - gDyn.needed_count)
        {
        case 0u: tag = 4u; value = BASE + layout.hash; break;
        case 1u: tag = 5u; value = BASE + layout.dynstr; break;
        case 2u: tag = 6u; value = BASE + layout.dynsym; break;
        case 3u: tag = 10u; value = gDyn.dynstr_len; break;
        case 4u: tag = 11u; value = 24u; break;
        case 5u: tag = 7u; value = BASE + layout.rela; break;
        case 6u: tag = 8u; value = 24u * n; break;
        case 7u: tag = 9u; value = 24u; break;
        case 8u: tag = 0x6ffffff0u; value = BASE + layout.versym; break;
        case 9u: tag = 0x6ffffffeu; value = BASE + layout.verneed; break;
        case 10u: tag = 0x6fffffffu; value = gDyn.verneed_libraries; break;
        case 11u: tag = 30u; value = 8u; break;          // DT_FLAGS: DF_BIND_NOW
        case 12u: tag = 0x6ffffffbu; value = 1u; break;  // DT_FLAGS_1: DF_1_NOW
        case 13u: tag = 21u; value = 0u; break;          // DT_DEBUG
        default: break;                                  // DT_NULL
        }
    }
    return word == 0u ? tag : (word == 2u ? value : 0u);
}

uint elf_hash(uint offset)
{
    uint hash = 0u;
    for (uint i = 0u; i < 256u; i++)
    {
        uint c = byte_address_load_u8_bounded(dynamic_strings, offset + i, gDyn.dynstr_len);
        if (c == 0u)
            break;
        hash = (hash << 4u) + c;
        uint high = hash & 0xf0000000u;
        if (high != 0u)
            hash ^= high >> 24u;
        hash &= ~high;
    }
    return hash;
}

uint verneed_word(uint record, uint word)
{
    uint row = gDyn.verneed_rows + record * 4u;
    uint kind = dynamic_words[row];
    bool last = (kind & 2u) != 0u;
    uint count_or_index = dynamic_words[row + 1u];
    uint name = dynamic_words[row + 2u];
    if ((kind & 1u) == 0u)
    {
        // Elf64_Verneed: version | count << 16, file, aux, next.
        switch (word)
        {
        case 0u: return 1u | (count_or_index << 16u);
        case 1u: return name;
        case 2u: return 16u;
        default: return last ? 0u : 16u * (count_or_index + 1u);
        }
    }
    // Elf64_Vernaux: hash, flags | other << 16, name, next.
    switch (word)
    {
    case 0u: return elf_hash(name);
    case 1u: return count_or_index << 16u;
    case 2u: return name;
    default: return last ? 0u : 16u;
    }
}

uint decimal_digits(uint value)
{
    uint digits = 1u;
    while (value >= 10u && digits < 10u)
    {
        value /= 10u;
        digits++;
    }
    return digits;
}

uint decimal_digit(uint value, uint digits, uint index)
{
    for (uint i = index + 1u; i < digits; i++)
        value /= 10u;
    return 48u + value % 10u;
}

// "__lanius_A_B_C", then NUL padding to the stride.
uint symbol_name_byte(uint symbol, uint local)
{
    uint row = gDyn.symbol_rows + symbol * 8u;
    if (local < 9u)
        return local == 2u ? 0x6cu : (local == 3u ? 0x61u : (local == 4u ? 0x6eu :
            (local == 5u ? 0x69u : (local == 6u ? 0x75u : (local == 7u ? 0x73u : 0x5fu)))));
    uint at = 9u;
    for (uint part = 0u; part < 3u; part++)
    {
        uint value = dynamic_words[row + 3u + part];
        uint digits = decimal_digits(value);
        if (local < at + digits)
            return decimal_digit(value, digits, local - at);
        at += digits;
        if (part < 2u)
        {
            if (local == at)
                return 0x5fu;
            at++;
        }
    }
    return 0u;
}

// Elf64_Sym words: name, info | other << 8 | shndx << 16, value, size.
uint symtab_word(uint symbol, uint word)
{
    uint name = 0u;
    uint info = 0u;
    uint section = 0u;
    uint value = 0u;
    uint size = 0u;
    if (symbol == 1u)
    {
        name = 6u; info = 0x12u; section = 8u;
        value = BASE + gDyn.start_offset; size = START_CODE_BYTES;
    }
    else if (symbol == 2u)
    {
        name = 1u; info = 0x12u; section = 8u;
        value = BASE + gDyn.main_offset; size = gDyn.main_size;
    }
    else if (symbol >= 3u)
    {
        uint row = gDyn.symbol_rows + (symbol - 3u) * 8u;
        bool text = dynamic_words[row + 2u] == 1u;
        name = STRTAB_PREFIX + (symbol - 3u) * gDyn.name_stride;
        info = text ? 0x12u : 0x11u;
        section = text ? 8u : 9u;
        value = BASE + dynamic_words[row];
        size = dynamic_words[row + 1u];
    }
    switch (word)
    {
    case 0u: return name;
    case 1u: return info | (section << 16u);
    case 2u: return value;
    case 4u: return size;
    default: return 0u;
    }
}

// Elf64_Shdr words: name, type, flags, addr, offset, size, link, info, align,
// entsize.
uint section_header_word(uint section, uint word, DynamicLayout layout)
{
    uint n = gDyn.import_count;
    uint name = 0u;
    uint kind = 0u;
    uint flags = 0u;
    uint offset = 0u;
    uint size = 0u;
    uint link = 0u;
    uint info = 0u;
    uint align = 1u;
    uint entry = 0u;
    bool mapped = true;
    switch (section)
    {
    case 0u: align = 0u; mapped = false; break;
    case 1u: name = 1u; kind = 1u; flags = 2u; offset = layout.interp; size = INTERP_BYTES; break;
    case 2u: name = 9u; kind = 5u; flags = 2u; offset = layout.hash; size = layout.hash_len; link = 3u; align = 8u; entry = 4u; break;
    case 3u: name = 15u; kind = 11u; flags = 2u; offset = layout.dynsym; size = 24u * (n + 1u); link = 4u; info = 1u; align = 8u; entry = 24u; break;
    case 4u: name = 23u; kind = 3u; flags = 2u; offset = layout.dynstr; size = gDyn.dynstr_len; break;
    case 5u: name = 31u; kind = 0x6fffffffu; flags = 2u; offset = layout.versym; size = 2u * (n + 1u); link = 3u; align = 2u; entry = 2u; break;
    case 6u: name = 44u; kind = 0x6ffffffeu; flags = 2u; offset = layout.verneed; size = 16u * gDyn.verneed_count; link = 4u; info = gDyn.verneed_libraries; align = 8u; break;
    case 7u: name = 59u; kind = 4u; flags = 2u; offset = layout.rela; size = 24u * n; link = 3u; align = 8u; entry = 24u; break;
    case 8u: name = 69u; kind = 1u; flags = 6u; offset = TEXT_OFFSET; size = gDyn.text_len; align = 8u; break;
    case 9u: name = 75u; kind = 1u; flags = 2u; offset = TEXT_OFFSET + gDyn.text_len; size = gDyn.rodata_len; break;
    case 10u: name = 83u; kind = 6u; flags = 3u; offset = layout.rw; size = 16u * layout.dynamic_count; link = 4u; align = 8u; entry = 16u; break;
    case 11u: name = 92u; kind = 1u; flags = 3u; offset = layout.got; size = 8u * n; align = 8u; entry = 8u; break;
    case 12u: name = 97u; kind = 2u; mapped = false; offset = layout.symtab; size = 24u * layout.symtab_count; link = 13u; info = 1u; align = 8u; entry = 24u; break;
    case 13u: name = 105u; kind = 3u; mapped = false; offset = layout.strtab; size = layout.strtab_len; break;
    default: name = 113u; kind = 3u; mapped = false; offset = layout.shstrtab; size = SHSTRTAB_BYTES; break;
    }
    switch (word)
    {
    case 0u: return name;
    case 1u: return kind;
    case 2u: return flags;
    case 4u: return mapped ? BASE + offset : 0u;
    case 6u: return section == 0u ? 0u : offset;
    case 8u: return size;
    case 10u: return link;
    case 11u: return info;
    case 12u: return align;
    case 14u: return entry;
    default: return 0u;
    }
}

uint start_byte(uint local, DynamicLayout layout)
{
    // lea rdi, [rip + main]; call [rip + GOT(__libc_start_main)].
    if (local >= 23u && local < 27u)
        return u32_le_byte(gDyn.main_offset - (gDyn.start_offset + 27u), local - 23u);
    if (local >= 29u && local < 33u)
        return u32_le_byte(layout.got - (gDyn.start_offset + 33u), local - 29u);
    return word_byte(START_WORDS[local >> 2u], local);
}

uint stub_byte(uint stub, uint local, DynamicLayout layout)
{
    // jmp [rip + GOT(stub)]; xchg ax, ax.
    uint at = gDyn.start_offset + START_BYTES + stub * STUB_BYTES;
    switch (local)
    {
    case 0u: return 0xffu;
    case 1u: return 0x25u;
    case 6u: return 0x66u;
    case 7u: return 0x90u;
    default: return u32_le_byte(layout.got + stub * 8u - (at + 6u), local - 2u);
    }
}

uint tail_byte(uint pos, DynamicLayout layout)
{
    uint n = gDyn.import_count;
    if (pos < layout.interp)
    {
        uint local = pos - layout.ph;
        return word_byte(program_header_word(local / 56u, (local % 56u) >> 2u, layout), local);
    }
    if (pos < layout.interp + INTERP_BYTES)
    {
        uint local = pos - layout.interp;
        return word_byte(INTERP_WORDS[local >> 2u], local);
    }
    if (pos >= layout.hash && pos < layout.hash + layout.hash_len)
    {
        uint local = pos - layout.hash;
        uint word = local >> 2u;
        return word_byte(word == 0u ? 1u : (word == 1u ? n + 1u : 0u), local);
    }
    if (pos >= layout.dynsym && pos < layout.dynstr)
    {
        uint local = pos - layout.dynsym;
        uint symbol = local / 24u;
        uint word = (local % 24u) >> 2u;
        uint value = 0u;
        if (symbol != 0u && word == 0u)
            value = dynamic_words[gDyn.import_rows + (symbol - 1u) * 2u];
        else if (symbol != 0u && word == 1u)
            value = 0x12u;
        return word_byte(value, local);
    }
    if (pos >= layout.dynstr && pos < layout.dynstr + gDyn.dynstr_len)
        return byte_address_load_u8(dynamic_strings, pos - layout.dynstr);
    if (pos >= layout.versym && pos < layout.versym + 2u * (n + 1u))
    {
        uint local = pos - layout.versym;
        uint symbol = local >> 1u;
        uint version = symbol == 0u ? 0u : dynamic_words[gDyn.import_rows + (symbol - 1u) * 2u + 1u];
        return (version >> ((local & 1u) * 8u)) & 0xffu;
    }
    if (pos >= layout.verneed && pos < layout.rela)
    {
        uint local = pos - layout.verneed;
        return word_byte(verneed_word(local >> 4u, (local & 15u) >> 2u), local);
    }
    if (pos >= layout.rela && pos < layout.rx_end)
    {
        uint local = pos - layout.rela;
        uint relocation = local / 24u;
        uint word = (local % 24u) >> 2u;
        uint value = word == 0u ? BASE + layout.got + relocation * 8u
            : (word == 2u ? 6u : (word == 3u ? relocation + 1u : 0u));
        return word_byte(value, local);
    }
    if (pos >= layout.rw && pos < layout.got)
    {
        uint local = pos - layout.rw;
        return word_byte(dynamic_entry_word(local >> 4u, (local & 15u) >> 2u, layout), local);
    }
    if (pos >= layout.symtab && pos < layout.strtab)
    {
        uint local = pos - layout.symtab;
        return word_byte(symtab_word(local / 24u, (local % 24u) >> 2u), local);
    }
    if (pos >= layout.strtab && pos < layout.shstrtab)
    {
        uint local = pos - layout.strtab;
        if (local < STRTAB_PREFIX)
            return word_byte(STRTAB_PREFIX_WORDS[local >> 2u], local);
        local -= STRTAB_PREFIX;
        return symbol_name_byte(local / gDyn.name_stride, local % gDyn.name_stride);
    }
    if (pos >= layout.shstrtab && pos < layout.shstrtab + SHSTRTAB_BYTES)
    {
        uint local = pos - layout.shstrtab;
        return word_byte(SHSTRTAB_WORDS[local >> 2u], local);
    }
    if (pos >= layout.sh && pos < layout.total)
    {
        uint local = pos - layout.sh;
        return word_byte(section_header_word(local >> 6u, (local & 63u) >> 2u, layout), local);
    }
    // Alignment padding and the GOT, which the dynamic loader fills.
    return 0u;
}

void scatter_byte(uint file_pos, uint value)
{
    if (value == 0u ||
        file_pos < gDyn.output_page_base ||
        file_pos - gDyn.output_page_base >= gDyn.output_page_len)
        return;
    file_pos -= gDyn.output_page_base;
    atomic_u32_or(out_words, file_pos >> 2u, (value & 0xffu) << ((file_pos & 3u) * 8u));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint element = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (element >= gDyn.element_count)
        return;
    DynamicLayout layout = dynamic_layout();
    uint import_text = START_BYTES + STUB_BYTES * gDyn.import_count;
    if (element == 0u &&
        (layout.total != gDyn.total_len ||
         gDyn.element_count != TEXT_OFFSET + import_text + (layout.total - layout.tail)))
    {
        atomic_u32_min(link_relocation_status, 2u, layout.total);
        link_relocation_status[0u] = 0u;
        link_relocation_status[1u] = DYNAMIC_LAYOUT_ERROR;
    }
    if (element < TEXT_OFFSET)
    {
        scatter_byte(element, element < 64u
            ? word_byte(elf_header_word(element >> 2u, layout), element) : 0u);
        return;
    }
    element -= TEXT_OFFSET;
    if (element < import_text)
    {
        uint pos = gDyn.start_offset + element;
        scatter_byte(pos, element < START_BYTES
            ? start_byte(element, layout)
            : stub_byte((element - START_BYTES) / STUB_BYTES, (element - START_BYTES) % STUB_BYTES, layout));
        return;
    }
    uint pos = layout.tail + (element - import_text);
    scatter_byte(pos, tail_byte(pos, layout));
}
