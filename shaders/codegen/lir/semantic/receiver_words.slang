// Included by receiver_layout.slang and place_mark after type_instance_kind,
// type_instance_native_words, semantic_aggregate_hir_by_name_token,
// semantic_struct_word_count_by_hir and compact_hir_core.
uint receiver_kind(uint tag, uint payload)
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return tag == 3u && payload < capacity ? type_instance_kind[payload] : 0u;
}

uint receiver_native_words(uint tag, uint payload, uint hir_count)
{
    uint kind = receiver_kind(tag, payload);
    if (kind == 4u) return 1u;
    if (kind == 3u) return NATIVE_SLICE_WORDS;
    if (kind == 1u || kind == 2u) return type_instance_native_words[payload];
    if (tag == 1u && payload != 0u && payload < 128u) return payload == 7u ? 2u : 1u;
    if (tag == 1u && payload >= 4096u)
    {
        uint token = payload - 4096u;
        uint owner = token < gParams.n_tokens ? semantic_aggregate_hir_by_name_token[token] : LIR_INVALID;
        if (owner < hir_count && compact_hir_core[owner].kind == 27u)
            return semantic_struct_word_count_by_hir[owner];
        token = payload >= 6144u ? payload - 6144u : LIR_INVALID;
        owner = token < gParams.n_tokens ? semantic_aggregate_hir_by_name_token[token] : LIR_INVALID;
        if (owner < hir_count && compact_hir_core[owner].kind == 26u)
            return semantic_struct_word_count_by_hir[owner];
    }
    return LIR_INVALID;
}
