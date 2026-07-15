use std::ops::Range;

use super::GpuX86LinkInput;

const ELF_HEADER_AND_PROGRAM_HEADER_BYTES: usize = 0x78;
const SECTION_TEXT: u32 = 1;
const SECTION_RODATA: u32 = 2;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct GpuX86OutputPage {
    pub output_base: u32,
    pub output_len: u32,
    pub text_input: Range<usize>,
    pub rodata_input: Range<usize>,
    pub relocation_indices: Vec<usize>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct GpuX86PagedExecutablePlan {
    pub output_len: usize,
    pub pages: Vec<GpuX86OutputPage>,
}

impl GpuX86PagedExecutablePlan {
    pub(super) fn new(input: &GpuX86LinkInput, max_page_bytes: u64) -> Result<Self, String> {
        let page_capacity =
            usize::try_from(max_page_bytes.min(u32::MAX as u64)).unwrap_or(usize::MAX) & !3usize;
        if page_capacity < 4 {
            return Err(format!(
                "x86 output page limit {max_page_bytes} cannot hold one output word"
            ));
        }
        let text_start = ELF_HEADER_AND_PROGRAM_HEADER_BYTES;
        let rodata_start = text_start
            .checked_add(input.text_len())
            .ok_or_else(|| "x86 text output end overflows".to_string())?;
        let output_len = rodata_start
            .checked_add(input.rodata_len())
            .ok_or_else(|| "x86 output length overflows".to_string())?;
        u32::try_from(output_len)
            .map_err(|_| format!("x86 output length {output_len} exceeds the current u32 model"))?;

        let text_output = text_start..rodata_start;
        let rodata_output = rodata_start..output_len;
        let mut pages = Vec::with_capacity(output_len.div_ceil(page_capacity));
        for output_start in (0..output_len).step_by(page_capacity) {
            let output_end = output_len.min(output_start + page_capacity);
            pages.push(GpuX86OutputPage {
                output_base: output_start as u32,
                output_len: (output_end - output_start) as u32,
                text_input: translated_intersection(output_start..output_end, text_output.clone()),
                rodata_input: translated_intersection(
                    output_start..output_end,
                    rodata_output.clone(),
                ),
                relocation_indices: Vec::new(),
            });
        }

        for (relocation_index, relocation) in input.relocations.iter().enumerate() {
            let object = input
                .objects
                .get(relocation.object_index as usize)
                .ok_or_else(|| format!("x86 relocation {relocation_index} object is invalid"))?;
            let section_start = match relocation.site_section {
                SECTION_TEXT => text_start
                    .checked_add(object.text_input_start as usize)
                    .ok_or_else(|| "x86 relocation text site overflows".to_string())?,
                SECTION_RODATA => rodata_start
                    .checked_add(object.rodata_input_start as usize)
                    .ok_or_else(|| "x86 relocation rodata site overflows".to_string())?,
                section => {
                    return Err(format!(
                        "x86 relocation {relocation_index} has invalid site section {section}"
                    ));
                }
            };
            let site_start = section_start
                .checked_add(relocation.site_offset as usize)
                .ok_or_else(|| format!("x86 relocation {relocation_index} site overflows"))?;
            let site_end = site_start
                .checked_add(4)
                .ok_or_else(|| format!("x86 relocation {relocation_index} end overflows"))?;
            if site_end > output_len {
                return Err(format!(
                    "x86 relocation {relocation_index} site {site_start}..{site_end} exceeds output {output_len}"
                ));
            }
            let first_page = site_start / page_capacity;
            let last_page = (site_end - 1) / page_capacity;
            for page_index in first_page..=last_page {
                pages[page_index].relocation_indices.push(relocation_index);
            }
        }
        Ok(Self { output_len, pages })
    }
}

fn translated_intersection(page: Range<usize>, data: Range<usize>) -> Range<usize> {
    let start = page.start.max(data.start);
    let end = page.end.min(data.end);
    if start >= end {
        return 0..0;
    }
    start - data.start..end - data.start
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::codegen::{
        GpuLinkByteSource,
        x86::link::{GpuX86LinkObjectRecord, GpuX86LinkRelocationRecord},
    };

    fn input(relocation_site: Option<u32>) -> GpuX86LinkInput {
        GpuX86LinkInput {
            objects: vec![GpuX86LinkObjectRecord {
                text_input_start: 0,
                text_len: 40,
                rodata_input_start: 0,
                rodata_len: 12,
                relocation_start: 0,
                relocation_count: usize::from(relocation_site.is_some()) as u32,
                symbol_start: 0,
                symbol_count: 0,
                entry_offset: 0,
            }],
            text: GpuLinkByteSource::resident("test x86 text", vec![0; 40]),
            rodata: GpuLinkByteSource::resident("test x86 rodata", vec![0; 12]),
            relocations: relocation_site
                .map(|site_offset| GpuX86LinkRelocationRecord {
                    object_index: 0,
                    kind: 1,
                    site_section: SECTION_TEXT,
                    site_offset,
                    target_kind: 1,
                    target_index: SECTION_TEXT,
                    target_offset: 0,
                    target_section: 0,
                    addend_lo: 0,
                    addend_hi: 0,
                })
                .into_iter()
                .collect(),
            symbols: Vec::new(),
            entry_object_index: 0,
        }
    }

    #[test]
    fn page_geometry_covers_output_and_reads_only_intersecting_sections() {
        let input = input(None);
        let plan = GpuX86PagedExecutablePlan::new(&input, 32).expect("x86 page plan");
        assert_eq!(plan.output_len, 0x78 + 40 + 12);
        assert_eq!(
            plan.pages.iter().map(|page| page.output_len).sum::<u32>(),
            plan.output_len as u32
        );
        assert_eq!(
            plan.pages
                .iter()
                .map(|page| page.text_input.len())
                .sum::<usize>(),
            40
        );
        assert_eq!(
            plan.pages
                .iter()
                .map(|page| page.rodata_input.len())
                .sum::<usize>(),
            12
        );
    }

    #[test]
    fn relocation_crossing_page_boundary_is_assigned_to_both_pages() {
        // Text starts at 120; site offset 6 starts at 126 and crosses 128.
        let input = input(Some(6));
        let plan = GpuX86PagedExecutablePlan::new(&input, 32).expect("x86 page plan");
        assert_eq!(
            plan.pages
                .iter()
                .filter(|page| page.relocation_indices.contains(&0))
                .count(),
            2
        );
    }
}
