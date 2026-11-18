// One lane per relocation capacity row: places the relocation in the linked
// image (link.rs append_object_columns_at, symbol_resolution.rs,
// executable.rs relocation_words, splice.rs) and patches the output bytes
// as relocate.slang does.

import codegen.x86.link.resident.rl_common;
import codegen.x86.link.resident.rl_splice;
import shared.buffers.byte_packing;

static const uint RELOC_REL32 = 1u;
static const uint RELOC_CALL_REL32 = 2u;
static const uint RELOC_ABS32 = 3u;
static const uint RELOC_RAW_REL32 = 4u;
static const uint ELF_BASE_VADDR = 0x400000u;

uint reloc_lane_object(uint lane)
{
    uint low = 0u;
    uint high = gRL.object_count;
    while (high - low > 1u)
    {
        uint middle = low + (high - low) / 2u;
        if (slot_word(middle, 11u) <= lane)
            low = middle;
        else
            high = middle;
    }
    return low;
}

// File offset of (object, section, offset); the import object is
// gRL.object_count and has only text.
uint section_file_offset(uint object, uint section, uint offset, out bool ok)
{
    ok = true;
    if (section == 1u)
    {
        uint base = object == gRL.object_count ? rl_status[ST_TEXT_LEN] : object_word(object, OB_TEXT_OUT);
        return TEXT_OFFSET + base + offset;
    }
    if (section == 2u && object < gRL.object_count)
        return TEXT_OFFSET + gRL.text_len_total + object_word(object, OB_RODATA_OUT) + offset;
    ok = false;
    return 0u;
}

void patch_byte(uint file_pos, uint value)
{
    uint word_i = file_pos >> 2u;
    uint shift = (file_pos & 3u) * 8u;
    atomic_u32_and(rl_out, word_i, ~(0xffu << shift));
    atomic_u32_or(rl_out, word_i, (value & 0xffu) << shift);
}

uint copied_byte(uint object, uint copied_offset)
{
    return object_text_byte(object, object_word(object, OB_COPY_START) + copied_offset);
}

uint copy_len(uint object)
{
    return object_word(object, OB_COPY_END) - object_word(object, OB_COPY_START);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint lane = rl_lane(tid);
    if (lane >= gRL.reloc_cap_total || gRL.object_count == 0u)
        return;
    uint object = reloc_lane_object(lane);
    uint local = lane - slot_word(object, 11u);
    uint reloc_cap = slot_word(object, 1u);
    uint row;
    if (local < reloc_cap)
    {
        if (local >= object_word(object, OB_RELOC_COUNT))
            return;
        row = (slot_word(object, 0u) + local) * RELOC_WORDS;
    }
    else
    {
        uint runtime_local = local - reloc_cap;
        if (runtime_local >= object_word(object, OB_RT_COUNT) || runtime_local >= slot_word(object, 3u))
            return;
        row = (slot_word(object, 2u) + runtime_local) * RELOC_WORDS;
    }
    uint kind = st_reloc[row];
    // The native C entry loads the process vector that the CRT bridge maps,
    // so the jump over that load is left out of a dynamic link.
    if (kind == RELOC_RAW_REL32)
        return;
    uint site_section = st_reloc[row + 1u];
    uint site_offset = st_reloc[row + 2u];
    uint target_kind = st_reloc[row + 3u];
    uint target_index = st_reloc[row + 4u];
    uint target_offset = st_reloc[row + 5u];
    uint addend_lo = st_reloc[row + 6u];
    uint addend_hi = st_reloc[row + 7u];
    uint copy_start = object_word(object, OB_COPY_START);
    uint copy_end = object_word(object, OB_COPY_END);

    uint resolved_kind = target_kind;
    uint target_object = object;
    uint target_section = target_index;
    if (target_kind == 1u && target_index == 1u)
    {
        uint rt_start = object_word(object, OB_RT_START);
        if (object_word(object, OB_HAS_RT) != 0u && target_offset >= rt_start &&
            target_offset < object_word(object, OB_RT_END))
        {
            // The kept runtime's bytes already encode it.
            if (object_word(object, OB_SHARED) == 0u)
                return;
            resolved_kind = 3u;
            target_object = object_word(object, OB_ENTRY_OBJECT);
            target_section = 1u;
            target_offset = object_word(object, OB_ENTRY_RT_START) + (target_offset - rt_start);
        }
        else
        {
            if (target_offset < copy_start || target_offset > copy_end)
            {
                fail_emit(1u);
                return;
            }
            target_offset -= copy_start;
        }
    }
    else if (target_kind == 2u)
    {
        uint symbol_count = object_word(object, OB_UNDEF_COUNT) + object_word(object, OB_DEF_COUNT);
        if (target_index >= symbol_count)
        {
            fail_emit(2u);
            return;
        }
        uint3 identity = symbol_identity(symbol_cap_index(object, target_index));
        uint definition = lookup_definition(identity);
        if (definition != INVALID)
        {
            target_object = rl_symbols[definition * SYMBOL_WORDS];
            target_section = rl_symbols[definition * SYMBOL_WORDS + 4u];
            target_offset += rl_symbols[definition * SYMBOL_WORDS + 5u];
        }
        else
        {
            uint name = lookup_binding(identity);
            if (name == INVALID)
            {
                fail_emit(4u);
                return;
            }
            target_object = gRL.object_count;
            target_section = 1u;
            target_offset += DYN_START_BYTES + rl_import_of_name[name] * DYN_STUB_BYTES;
        }
    }
    else if (target_kind != 1u)
    {
        fail_emit(8u);
        return;
    }
    if (site_section == 1u)
    {
        if (site_offset < copy_start || site_offset + 4u < site_offset || site_offset + 4u > copy_end)
        {
            fail_emit(16u);
            return;
        }
        site_offset -= copy_start;
    }
    bool site_ok;
    bool target_ok;
    uint site_file = section_file_offset(object, site_section, site_offset, site_ok);
    uint target_file = section_file_offset(target_object, target_section, target_offset, target_ok);
    uint file_len = TEXT_OFFSET + gRL.text_len_total + rl_status[ST_RODATA_LEN];
    if (!site_ok || !target_ok || site_file + 4u > file_len)
    {
        fail_emit(32u);
        return;
    }
    uint value;
    if (kind == RELOC_REL32 || kind == RELOC_CALL_REL32)
        value = target_file + addend_lo - site_file;
    else if (kind == RELOC_ABS32)
        value = ELF_BASE_VADDR + target_file + addend_lo;
    else
    {
        fail_emit(64u);
        return;
    }
    if (addend_hi != ((addend_lo & 0x80000000u) == 0u ? 0u : 0xffffffffu))
    {
        fail_emit(128u);
        return;
    }
    if (kind == RELOC_CALL_REL32 && site_section == 1u &&
        (resolved_kind == 2u || resolved_kind == 3u) && target_section == 1u &&
        addend_lo == 0xfffffffcu && site_offset != 0u && target_object < gRL.object_count)
    {
        uint size = small_symbol_size(target_object, target_offset);
        if (size != 0u && target_offset + size <= copy_len(target_object) &&
            site_offset - 1u + SPLICE_SLOT_BYTES <= copy_len(object) &&
            copied_byte(object, site_offset - 1u) == 0xe8u &&
            copied_byte(object, site_offset + 4u) == 0x0fu &&
            copied_byte(object, site_offset + 5u) == 0x1fu &&
            copied_byte(object, site_offset + 6u) == 0x40u &&
            copied_byte(object, site_offset + 7u) == 0x00u)
        {
            if (splice_ok(target_object, target_offset, size))
            {
                if (site_file + 8u > file_len)
                {
                    fail_emit(32u);
                    return;
                }
                for (uint i = 0u; i < SPLICE_SLOT_BYTES; i += 1u)
                    patch_byte(site_file - 1u + i, splice_slot_byte(target_object, target_offset, size - 1u, i));
                return;
            }
        }
    }
    for (uint i = 0u; i < 4u; i += 1u)
        patch_byte(site_file + i, u32_le_byte(value, i));
}
