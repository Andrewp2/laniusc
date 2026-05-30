// x86_64 relocation patching.
//
// Encoding writes zero placeholders for rel32 fields. Relocation rows are
// compacted in instruction order; this pass runs over those rows and scatters
// the four displacement bytes into packed output words with atomic OR. That
// keeps adjacent branch immediates from racing when they share an output word.

import gpu_index;
import byte_packing;
import bit_packing;
import atomics;
import status;
struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_inst_kind;
StructuredBuffer<uint> x86_inst_arg0;
StructuredBuffer<uint> x86_inst_arg1;
StructuredBuffer<uint> x86_inst_arg2;
StructuredBuffer<uint> x86_inst_size;
StructuredBuffer<uint> x86_inst_byte_offset;
StructuredBuffer<uint> x86_decl_layout_status;
StructuredBuffer<uint> x86_text_len;
StructuredBuffer<uint> text_status;
StructuredBuffer<uint> encode_status;
StructuredBuffer<uint> x86_reloc_count;
StructuredBuffer<uint> x86_reloc_kind;
StructuredBuffer<uint> x86_reloc_site_inst;
StructuredBuffer<uint> x86_reloc_target_inst;

RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> reloc_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_ENCODE_OK = 1u;
static const uint X86_RELOC_OK = 1u;
static const uint X86_ERR_RELOC = 8u;
static const uint ELF_TEXT_WORD_OFFSET = 0x78u / 4u;

static const uint X86_INST_JCC_FALSE_REL32 = 9u;
static const uint X86_INST_JMP_REL32 = 10u;
static const uint X86_INST_CALL_REL32 = 15u;
static const uint X86_INST_V_BRANCH_ZERO = 56u;
static const uint X86_INST_V_JMP = 57u;
static const uint X86_INST_V_ENTRY_STACK_JMP = 64u;
static const uint X86_INST_V_FOR_ARRAY_BRANCH = 68u;
static const uint X86_INST_V_FOR_ARRAY_INC_JMP = 70u;
static const uint X86_INST_V_CALL_MIXED_DIRECT = 71u;
static const uint X86_INST_V_MATCH_TAG_BRANCH = 77u;
static const uint X86_INST_V_FOR_INTERVAL_BRANCH = 78u;

static const uint X86_RELOC_REL32 = 1u;
static const uint X86_RELOC_CALL_REL32 = 2u;
static const uint X86_ARG_SCALAR = 1u;
static const uint X86_ARG_LOCAL_PTR = 2u;
static const uint X86_ARG_PARAM_PTR = 3u;
static const uint X86_AGG_SOURCE_LOCAL = 1u;
static const uint X86_AGG_SOURCE_PARAM = 2u;
static const uint MAX_X86_LOCAL_SLOTS = 1000000u;
static const uint MIN_X86_STACK_FRAME_BYTES = 16u;
static const uint X86_REG_EAX = 0u;
static const uint X86_REG_ECX = 1u;
static const uint X86_REG_EDX = 2u;
static const uint X86_REG_ESP = 4u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDI = 7u;
static const uint X86_REG_R8D = 8u;
static const uint X86_REG_R9D = 9u;
static const uint X86_REG_R10D = 10u;
static const uint X86_REG_R11D = 11u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool signed_i8_immediate(uint imm)
{
    return imm <= 127u || imm >= 0xffffff80u;
}

bool valid_reg(uint reg)
{
    return reg < 16u;
}

uint rex_for_opcode_reg(uint reg)
{
    return reg >= 8u && reg < 16u ? 1u : 0u;
}

uint rex_for_modrm(uint reg_field, uint rm)
{
    return (reg_field >= 8u && reg_field < 16u) ||
           (rm >= 8u && rm < 16u)
               ? 1u
               : 0u;
}

uint push_pop_reg_size(uint reg)
{
    return valid_reg(reg) ? 1u + rex_for_opcode_reg(reg) : 0u;
}

uint mov_r32_r32_size(uint dst, uint src)
{
    return valid_reg(dst) && valid_reg(src) ? 2u + rex_for_modrm(src, dst) : 0u;
}

uint mov_r64_r64_size(uint dst, uint src)
{
    return valid_reg(dst) && valid_reg(src) ? 3u : 0u;
}

uint local_slot_disp(uint slot)
{
    return (slot + 3u) * 4u;
}

bool valid_local_slot(uint slot)
{
    return slot < MAX_X86_LOCAL_SLOTS;
}

uint cmp_local_imm_size(uint slot, uint imm)
{
    if (!valid_local_slot(slot))
        return 0u;
    uint disp = local_slot_disp(slot);
    if (signed_i8_immediate(imm))
        return disp <= 127u ? 5u : 8u;
    return disp <= 127u ? 8u : 11u;
}

uint cmp_ptr_slot_imm_size(uint base, uint ordinal, uint imm)
{
    uint disp = ordinal * 4u;
    if (!valid_reg(base) || disp > 127u)
        return 0u;
    return (signed_i8_immediate(imm) ? 4u : 7u) + rex_for_modrm(7u, base);
}

uint local_mem_r32_size(uint reg, uint slot)
{
    if (!valid_reg(reg) || !valid_local_slot(slot))
        return 0u;
    uint disp = local_slot_disp(slot);
    return (disp <= 127u ? 4u : 7u) + rex_for_modrm(reg, 4u);
}

uint cmp_local_r32_size(uint slot, uint reg)
{
    return local_mem_r32_size(reg, slot);
}

uint branch_zero_imm_offset(uint cond)
{
    return valid_reg(cond) ? 2u + rex_for_modrm(cond, cond) + 2u : INVALID;
}

uint stack_frame_adjust_size(uint frame_size)
{
    if (frame_size == 0u)
        return 0u;
    return frame_size <= 127u ? 4u : 7u;
}

uint call_save_restore_size(uint save_mask)
{
    uint active = save_mask & 0xffu;
    uint high = active & 0xf0u;
    return countbits(active) + countbits(high);
}

uint call_save_stack_size(uint save_mask)
{
    return countbits(save_mask & 0xffu) * 8u;
}

uint call_frame_size(uint save_stack)
{
    uint local_slots = x86_decl_layout_status[3u];
    uint bytes = max((local_slots + 3u) * 4u, MIN_X86_STACK_FRAME_BYTES);
    bytes = (bytes + 15u) & 0xfffffff0u;
    return (save_stack & 8u) != 0u ? bytes + 8u : bytes;
}

bool call_save_mask_has_slot(uint save_mask, uint slot)
{
    return ((save_mask >> slot) & 1u) != 0u;
}

bool call_saved_reg_slot(uint reg, out uint slot)
{
    slot = INVALID;
    if (reg == X86_REG_ECX) { slot = 0u; return true; }
    if (reg == X86_REG_EDX) { slot = 1u; return true; }
    if (reg == X86_REG_ESI) { slot = 2u; return true; }
    if (reg == X86_REG_EDI) { slot = 3u; return true; }
    if (reg == X86_REG_R8D) { slot = 4u; return true; }
    if (reg == X86_REG_R9D) { slot = 5u; return true; }
    if (reg == X86_REG_R10D) { slot = 6u; return true; }
    if (reg == X86_REG_R11D) { slot = 7u; return true; }
    return false;
}

uint load_saved_call_reg_r32_size(uint dst, uint src, uint save_mask)
{
    uint slot = INVALID;
    if (!valid_reg(dst) || !call_saved_reg_slot(src, slot) ||
        !call_save_mask_has_slot(save_mask, slot))
        return 0u;
    return 4u + rex_for_modrm(dst, 4u);
}

uint lea_arg_local_ptr_size(uint target, uint slot, uint stack_adjust)
{
    if (!valid_reg(target) || !valid_local_slot(slot))
        return 0u;
    uint disp = stack_adjust + local_slot_disp(slot);
    return disp <= 127u ? 5u : 8u;
}

uint mixed_target_reg(uint ordinal, bool aggregate_return)
{
    uint shifted = ordinal + (aggregate_return ? 1u : 0u);
    if (shifted == 0u) return X86_REG_EDI;
    if (shifted == 1u) return X86_REG_ESI;
    if (shifted == 2u) return X86_REG_EDX;
    if (shifted == 3u) return X86_REG_ECX;
    if (shifted == 4u) return X86_REG_R8D;
    if (shifted == 5u) return X86_REG_R9D;
    return INVALID;
}

uint selected_mixed_arg_kind(uint info, uint ordinal)
{
    if (ordinal < 4u)
        return packed_u2_at_offset(info, 24u, ordinal);
    return 0u;
}

uint selected_mixed_arg_payload(uint packed, uint ordinal)
{
    if (ordinal < 4u)
        return packed_u8_at(packed, ordinal);
    return INVALID;
}

uint mixed_arg_move_size(
    uint target,
    uint kind,
    uint payload,
    uint save_mask,
    uint save_stack)
{
    if (kind == X86_ARG_SCALAR)
    {
        if (!valid_reg(payload))
            return 0u;
        if (payload == target)
            return 0u;
        uint saved_load_size = load_saved_call_reg_r32_size(target, payload, save_mask);
        return saved_load_size != 0u ? saved_load_size : mov_r32_r32_size(target, payload);
    }
    if (kind == X86_ARG_LOCAL_PTR)
        return lea_arg_local_ptr_size(target, payload, save_stack);
    if (kind == X86_ARG_PARAM_PTR)
        return payload == target ? 0u : mov_r64_r64_size(target, payload);
    return 0u;
}

uint call_mixed_ordinal_move_size(
    uint info,
    uint packed,
    uint save_mask,
    uint save_stack,
    uint ordinal,
    uint arg_count,
    bool aggregate_return)
{
    if (ordinal >= arg_count)
        return 0u;
    uint target_reg = mixed_target_reg(ordinal, aggregate_return);
    if (!valid_reg(target_reg))
        return INVALID;
    uint payload = selected_mixed_arg_payload(packed, ordinal);
    uint kind = selected_mixed_arg_kind(info, ordinal);
    uint move_size = mixed_arg_move_size(target_reg, kind, payload, save_mask, save_stack);
    if (move_size == 0u &&
        !(kind == X86_ARG_SCALAR && payload == target_reg) &&
        !(kind == X86_ARG_PARAM_PTR && payload == target_reg))
        return INVALID;
    return move_size;
}

uint call_mixed_call_imm_offset(uint info, uint packed, uint save_mask)
{
    bool aggregate_return = (info & 1u) != 0u;
    uint dest = packed_u8_at(info, 1u);
    uint arg_count = packed_u8_at(info, 2u);
    if (arg_count > 4u ||
        (aggregate_return && !valid_local_slot(dest)) ||
        (!aggregate_return && !valid_reg(dest)))
        return INVALID;

    uint save_size = call_save_restore_size(save_mask);
    uint save_stack = call_save_stack_size(save_mask);
    uint offset = save_size;
    if (aggregate_return)
    {
        uint ret_ptr_size = lea_arg_local_ptr_size(X86_REG_EDI, dest, save_stack);
        if (ret_ptr_size == 0u)
            return INVALID;
        offset += ret_ptr_size;
    }

    uint move0 = call_mixed_ordinal_move_size(
        info, packed, save_mask, save_stack, 0u, arg_count, aggregate_return);
    uint move1 = call_mixed_ordinal_move_size(
        info, packed, save_mask, save_stack, 1u, arg_count, aggregate_return);
    uint move2 = call_mixed_ordinal_move_size(
        info, packed, save_mask, save_stack, 2u, arg_count, aggregate_return);
    uint move3 = call_mixed_ordinal_move_size(
        info, packed, save_mask, save_stack, 3u, arg_count, aggregate_return);
    if (move0 == INVALID || move1 == INVALID || move2 == INVALID || move3 == INVALID)
        return INVALID;

    uint frame_adjust_size = stack_frame_adjust_size(call_frame_size(save_stack));
    return offset + move0 + move1 + move2 + move3 + frame_adjust_size + 1u;
}

uint inst_kind_tag(uint inst_i)
{
    return x86_inst_kind[inst_i] & 0xffu;
}

uint inst_call_save_mask(uint inst_i)
{
    return (x86_inst_kind[inst_i] >> 8u) & 0xffu;
}

uint target_offset(uint target)
{
    uint inst_count = text_status[3u];
    if (target == inst_count)
        return x86_text_len[0u];
    return x86_inst_byte_offset[target];
}

uint rel32_to_target(uint site_inst, uint target_inst)
{
    uint source_next = x86_inst_byte_offset[site_inst] + x86_inst_size[site_inst];
    return target_offset(target_inst) - source_next;
}

uint reloc_kind_base(uint packed_kind)
{
    return packed_kind & 0xffu;
}

uint reloc_imm_offset_for_inst(uint inst_i)
{
    uint kind = inst_kind_tag(inst_i);
    if (kind == X86_INST_JCC_FALSE_REL32)
        return 2u;
    if (kind == X86_INST_JMP_REL32 || kind == X86_INST_CALL_REL32)
        return 1u;
    if (kind == X86_INST_V_BRANCH_ZERO)
        return branch_zero_imm_offset(x86_inst_arg0[inst_i]);
    if (kind == X86_INST_V_JMP)
        return 1u;
    if (kind == X86_INST_V_ENTRY_STACK_JMP)
        return stack_frame_adjust_size(x86_inst_arg1[inst_i]) + 1u;
    if (kind == X86_INST_V_FOR_ARRAY_BRANCH)
    {
        uint cmp_size = cmp_local_imm_size(x86_inst_arg0[inst_i], x86_inst_arg1[inst_i]);
        return cmp_size == 0u ? INVALID : cmp_size + 2u;
    }
    if (kind == X86_INST_V_FOR_ARRAY_INC_JMP)
    {
        uint index_slot = x86_inst_arg0[inst_i];
        if (!valid_local_slot(index_slot))
            return INVALID;
        return (local_slot_disp(index_slot) <= 127u ? 5u : 8u) + 1u;
    }
    if (kind == X86_INST_V_CALL_MIXED_DIRECT)
        return call_mixed_call_imm_offset(
            x86_inst_arg1[inst_i],
            x86_inst_arg2[inst_i],
            inst_call_save_mask(inst_i));
    if (kind == X86_INST_V_MATCH_TAG_BRANCH)
    {
        uint source_kind = unpack_u16_pair_low(x86_inst_arg0[inst_i]);
        uint tag = unpack_u16_pair_high(x86_inst_arg0[inst_i]);
        uint cmp_size = 0u;
        if (source_kind == X86_AGG_SOURCE_LOCAL)
            cmp_size = cmp_local_imm_size(x86_inst_arg1[inst_i], tag);
        if (source_kind == X86_AGG_SOURCE_PARAM)
            cmp_size = cmp_ptr_slot_imm_size(x86_inst_arg1[inst_i], 0u, tag);
        return cmp_size == 0u ? INVALID : cmp_size + 2u;
    }
    if (kind == X86_INST_V_FOR_INTERVAL_BRANCH)
    {
        uint load_size = local_mem_r32_size(X86_REG_R11D, x86_inst_arg1[inst_i]);
        uint cmp_size = cmp_local_r32_size(x86_inst_arg0[inst_i], X86_REG_R11D);
        return load_size == 0u || cmp_size == 0u ? INVALID : load_size + cmp_size + 2u;
    }
    return INVALID;
}

uint reloc_target_for_inst(uint inst_i)
{
    uint kind = inst_kind_tag(inst_i);
    if (kind == X86_INST_JCC_FALSE_REL32 ||
        kind == X86_INST_JMP_REL32 ||
        kind == X86_INST_CALL_REL32 ||
        kind == X86_INST_V_JMP ||
        kind == X86_INST_V_ENTRY_STACK_JMP ||
        kind == X86_INST_V_CALL_MIXED_DIRECT)
        return x86_inst_arg0[inst_i];
    if (kind == X86_INST_V_BRANCH_ZERO ||
        kind == X86_INST_V_FOR_ARRAY_INC_JMP)
        return x86_inst_arg1[inst_i];
    if (kind == X86_INST_V_FOR_ARRAY_BRANCH ||
        kind == X86_INST_V_MATCH_TAG_BRANCH ||
        kind == X86_INST_V_FOR_INTERVAL_BRANCH)
        return x86_inst_arg2[inst_i];
    return INVALID;
}

bool reloc_kind_matches_inst(uint reloc_kind, uint inst_kind)
{
    if (reloc_kind == X86_RELOC_REL32)
        return inst_kind == X86_INST_JCC_FALSE_REL32 ||
               inst_kind == X86_INST_JMP_REL32 ||
               inst_kind == X86_INST_V_BRANCH_ZERO ||
               inst_kind == X86_INST_V_JMP ||
               inst_kind == X86_INST_V_ENTRY_STACK_JMP ||
               inst_kind == X86_INST_V_FOR_ARRAY_BRANCH ||
               inst_kind == X86_INST_V_FOR_ARRAY_INC_JMP ||
               inst_kind == X86_INST_V_MATCH_TAG_BRANCH ||
               inst_kind == X86_INST_V_FOR_INTERVAL_BRANCH;
    if (reloc_kind == X86_RELOC_CALL_REL32)
        return inst_kind == X86_INST_CALL_REL32 ||
               inst_kind == X86_INST_V_CALL_MIXED_DIRECT;
    return false;
}

bool valid_reloc_record(uint reloc_i, uint site_inst, uint inst_count)
{
    if (reloc_i >= x86_reloc_count[0u])
        return false;
    uint target = x86_reloc_target_inst[reloc_i];
    if (x86_reloc_site_inst[reloc_i] != site_inst || target > inst_count)
        return false;

    uint site_kind = inst_kind_tag(site_inst);
    uint reloc_kind = reloc_kind_base(x86_reloc_kind[reloc_i]);
    if (!reloc_kind_matches_inst(reloc_kind, site_kind))
        return false;

    uint expected_target = reloc_target_for_inst(site_inst);
    return expected_target == target;
}

void patch_text_byte(uint text_pos, uint value)
{
    uint word_i = ELF_TEXT_WORD_OFFSET + text_pos / 4u;
    uint byte_i = text_pos & 3u;
    uint shifted = (value & 0xffu) << (byte_i * 8u);
    atomic_u32_or(out_words, word_i, shifted);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint reloc_i = linear_dispatch_id(tid);
    bool encode_ok = encode_status[0u] == X86_ENCODE_OK && encode_status[1u] == 0u;
    bool reloc_ok = reloc_status[0u] == X86_RELOC_OK && reloc_status[1u] == 0u;
    bool upstream_ok = encode_ok && reloc_ok &&
                       encode_status[3u] == x86_text_len[0u] &&
                       text_status[3u] <= gParams.out_capacity;
    if (!upstream_ok || reloc_i >= x86_reloc_count[0u])
        return;

    uint inst_count = text_status[3u];
    uint site_inst = x86_reloc_site_inst[reloc_i];
    if (site_inst >= inst_count || !valid_reloc_record(reloc_i, site_inst, inst_count))
    {
        publish_stage_error_min_detail4(reloc_status, X86_ERR_RELOC, reloc_i);
        return;
    }

    uint imm_offset = reloc_imm_offset_for_inst(site_inst);
    uint size = x86_inst_size[site_inst];
    uint inst_offset = x86_inst_byte_offset[site_inst];
    bool in_bounds = imm_offset != INVALID &&
                     imm_offset + 4u <= size &&
                     inst_offset + size <= x86_text_len[0u];
    if (!in_bounds)
    {
        publish_stage_error_min_detail4(reloc_status, X86_ERR_RELOC, reloc_i);
        return;
    }

    uint rel = rel32_to_target(site_inst, x86_reloc_target_inst[reloc_i]);
    uint imm_pos = inst_offset + imm_offset;
    patch_text_byte(imm_pos + 0u, u32_le_byte(rel, 0u));
    patch_text_byte(imm_pos + 1u, u32_le_byte(rel, 1u));
    patch_text_byte(imm_pos + 2u, u32_le_byte(rel, 2u));
    patch_text_byte(imm_pos + 3u, u32_le_byte(rel, 3u));
}
