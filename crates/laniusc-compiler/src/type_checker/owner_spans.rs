//! Source byte spans of generic callable declarations (kernel 04_owner_spans).
//! An original compile reads them back once; a concrete replay copies these
//! byte ranges into an instance unit and renames each copy. The host never
//! lexes or inspects the copied text.

use anyhow::{Result, anyhow, ensure};

use crate::gpu::readback::{PagedReadback, ReadbackRegion};

/// Words per GPU record (see 04_owner_spans.slang).
const OWNER_SPAN_WORDS: usize = 11;
const INVALID: u32 = u32::MAX;

/// One copyable generic body: a top-level function, a method of an
/// inherent impl, or a method of a trait impl whose self type names a
/// nominal declaration of the unit. Bytes are global source-pack offsets.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct CheckedOwnerSpan {
    pub function_hir: u32,
    /// First byte of the function's name token.
    pub name_byte: u32,
    /// One past the last byte of the function's body.
    pub end_byte: u32,
    /// The enclosing impl of a method. None for a top-level function.
    pub enclosing_impl: Option<CheckedImplHeader>,
    /// The checked native callable symbol of the function.
    pub native_symbol: u32,
}

/// The header of a method's impl, which a method copy repeats.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct CheckedImplHeader {
    pub hir: u32,
    /// The `impl` keyword byte.
    pub keyword_byte: u32,
    /// The byte after the impl body's opening brace.
    pub brace_end: u32,
    /// For a trait impl, what makes its header an inherent one.
    pub trait_cut: Option<CheckedTraitCut>,
}

/// A trait impl's header bytes `[start, end)`, its trait path and `for`,
/// which an inherent copy of the header leaves out, and the first byte of
/// its self type's declaration name.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct CheckedTraitCut {
    pub start: u32,
    pub end: u32,
    pub self_declaration_byte: u32,
}

impl CheckedOwnerSpan {
    /// The first template byte a copy of this body repeats.
    pub(crate) fn first_byte(&self) -> u32 {
        self.enclosing_impl.map_or(self.name_byte, |header| header.keyword_byte)
    }
}

/// Every copyable generic body of one checked unit.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct CheckedOwnerSpans {
    /// The unit's compact HIR row count. Rows of a body copied after the
    /// unit's text start here.
    pub hir_count: u32,
    /// Sorted by function HIR. A row whose span the GPU could not complete
    /// has no entry: that body replays in its original scope.
    pub spans: Vec<CheckedOwnerSpan>,
}

impl CheckedOwnerSpans {
    pub(crate) fn get(&self, function_hir: u32) -> Option<&CheckedOwnerSpan> {
        self.spans
            .binary_search_by_key(&function_hir, |span| span.function_hir)
            .ok()
            .map(|index| &self.spans[index])
    }

    pub(crate) fn resident_bytes(&self) -> usize {
        self.spans.capacity() * std::mem::size_of::<CheckedOwnerSpan>()
    }

    /// Decode GPU records (any order). Malformed spans are dropped; a
    /// duplicate row is an error.
    pub(crate) fn from_records(hir_count: u32, words: &[u32]) -> Result<Self> {
        ensure!(words.len() % OWNER_SPAN_WORDS == 0, "owner span records are truncated");
        let mut spans = Vec::with_capacity(words.len() / OWNER_SPAN_WORDS);
        for record in words.chunks_exact(OWNER_SPAN_WORDS) {
            let [row, _token, name, end, impl_row, keyword, brace_end, symbol, cut_start, cut_end, declaration] =
                record.try_into().expect("exact chunk");
            ensure!(row < hir_count, "owner span row {row} is outside the unit");
            if name == INVALID || end == INVALID || end <= name || symbol == INVALID {
                continue;
            }
            let enclosing_impl = if impl_row == INVALID {
                None
            } else {
                if keyword == INVALID || brace_end == INVALID || keyword >= brace_end || brace_end > name {
                    continue;
                }
                let trait_cut = match [cut_start, cut_end, declaration] {
                    [INVALID, INVALID, INVALID] => None,
                    [start, stop, declaration] if keyword < start && start < stop && stop < brace_end
                        && declaration != INVALID => Some(CheckedTraitCut {
                            start, end: stop, self_declaration_byte: declaration,
                        }),
                    _ => continue,
                };
                Some(CheckedImplHeader { hir: impl_row, keyword_byte: keyword, brace_end, trait_cut })
            };
            spans.push(CheckedOwnerSpan {
                function_hir: row,
                name_byte: name,
                end_byte: end,
                enclosing_impl,
                native_symbol: symbol,
            });
        }
        spans.sort_by_key(|span| span.function_hir);
        ensure!(
            spans.windows(2).all(|pair| pair[0].function_hir < pair[1].function_hir),
            "owner span rows are not unique"
        );
        Ok(Self { hir_count, spans })
    }
}

impl super::GpuTypeChecker {
    /// Read the owner spans of the last check. None when this check retained
    /// no interface inputs or the record table overflowed (every body then
    /// replays in its original scope).
    pub(crate) fn retained_owner_spans(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
    ) -> Result<Option<CheckedOwnerSpans>> {
        let semantic = self
            .semantic_artifact()
            .ok_or_else(|| anyhow!("checked semantic artifact is unavailable"))?;
        let Some(inputs) = semantic.generic_call_inputs.as_ref() else {
            return Ok(None);
        };
        // The same physical staging page as the unit-fact snapshot, which
        // has completed by now.
        let readback = PagedReadback::from_staging(self.semantic_interface_buffers.buffer(
            device,
            "generic call snapshot",
            64 * 1024,
            64 * 1024,
            wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        ));
        let counts = readback.read_regions(
            device,
            queue,
            &[
                ReadbackRegion::from_buffer(inputs.buffer("retained_owner_span_count"), 0, 4, "owner span count")?,
                ReadbackRegion::from_buffer(inputs.buffer("compact_hir_count"), 0, 4, "HIR count")?,
            ],
            "owner span counts",
        )?;
        let count = super::generic_calls::words(&counts[0])[0] as usize;
        let hir_count = super::generic_calls::words(&counts[1])[0];
        let records = inputs.buffer("retained_owner_spans");
        if count > records.byte_size / 4 / OWNER_SPAN_WORDS {
            return Ok(None);
        }
        if count == 0 {
            return Ok(Some(CheckedOwnerSpans { hir_count, spans: Vec::new() }));
        }
        let bytes = readback.read_regions(
            device,
            queue,
            &[ReadbackRegion::from_buffer(records, 0, count * OWNER_SPAN_WORDS * 4, "owner spans")?],
            "owner spans",
        )?;
        CheckedOwnerSpans::from_records(hir_count, &super::generic_calls::words(&bytes[0])).map(Some)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NO_CUT: [u32; 3] = [INVALID; 3];

    fn record(head: [u32; 8], cut: [u32; 3]) -> Vec<u32> {
        head.into_iter().chain(cut).collect()
    }

    #[test]
    fn records_decode_sorted_and_drop_incomplete_spans() {
        let words = [
            // A method of an inherent impl at row 9.
            record([9, 40, 120, 180, 7, 100, 115, 0x4000_0028], NO_CUT),
            // A top-level function at row 3.
            record([3, 10, 20, 60, INVALID, INVALID, INVALID, 2], NO_CUT),
            // Row 5 has no complete name span.
            record([5, 30, INVALID, INVALID, INVALID, INVALID, INVALID, 4], NO_CUT),
            // Row 6 sits in an impl whose header did not resolve.
            record([6, 31, 70, 90, 2, INVALID, INVALID, 5], NO_CUT),
            // A trait-impl method at row 11: `impl<T> Get<T> for Slot<T> {`
            // loses [208, 220); its self type is declared at byte 150.
            record([11, 50, 230, 260, 10, 200, 228, 6], [208, 220, 150]),
            // Row 12's trait path does not lie inside its header.
            record([12, 51, 330, 360, 10, 300, 328, 7], [290, 320, 150]),
        ].concat();
        let spans = CheckedOwnerSpans::from_records(13, &words).unwrap();
        assert_eq!(spans.hir_count, 13);
        assert_eq!(spans.spans.len(), 3);
        assert_eq!(spans.spans[0].function_hir, 3);
        assert_eq!(spans.spans[0].enclosing_impl, None);
        assert_eq!(spans.spans[0].first_byte(), 20);
        let method = spans.get(9).unwrap();
        assert_eq!(method.enclosing_impl,
            Some(CheckedImplHeader { hir: 7, keyword_byte: 100, brace_end: 115, trait_cut: None }));
        assert_eq!(method.native_symbol, 0x4000_0028);
        assert_eq!(method.first_byte(), 100);
        assert_eq!(spans.get(11).unwrap().enclosing_impl.unwrap().trait_cut,
            Some(CheckedTraitCut { start: 208, end: 220, self_declaration_byte: 150 }));
        assert!(spans.get(5).is_none() && spans.get(6).is_none() && spans.get(12).is_none());
    }

    #[test]
    fn records_reject_duplicate_and_foreign_rows() {
        let one = record([3, 10, 20, 60, INVALID, INVALID, INVALID, 2], NO_CUT);
        let twice = [one.clone(), one.clone()].concat();
        assert!(CheckedOwnerSpans::from_records(12, &twice).is_err());
        assert!(CheckedOwnerSpans::from_records(3, &one).is_err());
        assert!(CheckedOwnerSpans::from_records(12, &one[..10]).is_err());
    }
}
