use std::ops::Range;

use super::GpuWasmLinkInput;

const WASM_MODULE_HEADER_BYTES: usize = 8;
const WASM_SECTION_PREFIX_BYTES: usize = 11;
const WASM_EXPORT_SECTION_BYTES: usize = 22;
const WASM_PADDED_INDEX_BYTES: usize = 5;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct GpuWasmOutputPage {
    pub output_base: u32,
    pub output_len: u32,
    pub type_input: Range<usize>,
    pub body_input: Range<usize>,
    pub relocation_indices: Vec<usize>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct GpuWasmPagedExecutablePlan {
    pub output_len: usize,
    pub type_data_start: usize,
    pub body_data_start: usize,
    pub pages: Vec<GpuWasmOutputPage>,
}

impl GpuWasmPagedExecutablePlan {
    pub(super) fn new(input: &GpuWasmLinkInput, max_page_bytes: u64) -> Result<Self, String> {
        let page_capacity =
            usize::try_from(max_page_bytes.min(u32::MAX as u64)).unwrap_or(usize::MAX) & !3usize;
        if page_capacity < 4 {
            return Err(format!(
                "Wasm output page limit {max_page_bytes} cannot hold one output word"
            ));
        }

        let function_count = input.function_count;
        let type_data_start = WASM_MODULE_HEADER_BYTES + WASM_SECTION_PREFIX_BYTES;
        let function_section_start = type_data_start
            .checked_add(input.type_byte_len())
            .ok_or_else(|| "Wasm type section end overflows".to_string())?;
        let function_section_len = WASM_SECTION_PREFIX_BYTES
            .checked_add(
                function_count
                    .checked_mul(WASM_PADDED_INDEX_BYTES)
                    .ok_or_else(|| "Wasm function section length overflows".to_string())?,
            )
            .ok_or_else(|| "Wasm function section length overflows".to_string())?;
        let code_section_start = function_section_start
            .checked_add(function_section_len)
            .and_then(|end| end.checked_add(WASM_EXPORT_SECTION_BYTES))
            .ok_or_else(|| "Wasm code section start overflows".to_string())?;
        let body_data_start = code_section_start
            .checked_add(WASM_SECTION_PREFIX_BYTES)
            .ok_or_else(|| "Wasm body start overflows".to_string())?;
        let output_len = body_data_start
            .checked_add(input.body_byte_len())
            .ok_or_else(|| "Wasm output length overflows".to_string())?;
        u32::try_from(output_len)
            .map_err(|_| format!("Wasm output length {output_len} exceeds u32"))?;

        let type_output = type_data_start..function_section_start;
        let body_output = body_data_start..output_len;
        let page_count = output_len.div_ceil(page_capacity);
        let mut pages = Vec::with_capacity(page_count);
        for page_index in 0..page_count {
            let output_start = page_index * page_capacity;
            let output_end = output_len.min(output_start + page_capacity);
            pages.push(GpuWasmOutputPage {
                output_base: output_start as u32,
                output_len: (output_end - output_start) as u32,
                type_input: translated_intersection(output_start..output_end, type_output.clone()),
                body_input: translated_intersection(output_start..output_end, body_output.clone()),
                relocation_indices: Vec::new(),
            });
        }

        for (relocation_index, relocation) in input.relocations.iter().enumerate() {
            let site_start = body_data_start
                .checked_add(relocation.body_offset as usize)
                .ok_or_else(|| {
                    format!("Wasm relocation {relocation_index} output site overflows")
                })?;
            let site_end = site_start.checked_add(5).ok_or_else(|| {
                format!("Wasm relocation {relocation_index} output range overflows")
            })?;
            if site_end > output_len {
                return Err(format!(
                    "Wasm relocation {relocation_index} output range {site_start}..{site_end} exceeds {output_len}"
                ));
            }
            let first_page = site_start / page_capacity;
            let last_page = (site_end - 1) / page_capacity;
            for page_index in first_page..=last_page {
                pages[page_index].relocation_indices.push(relocation_index);
            }
        }

        Ok(Self {
            output_len,
            type_data_start,
            body_data_start,
            pages,
        })
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
    use super::{super::GpuWasmLinkRelocationRecord, *};
    use crate::codegen::wasm::GpuWasmRelocationTargetKind;

    fn input_with_body(body_len: usize, relocation_offsets: &[u32]) -> GpuWasmLinkInput {
        GpuWasmLinkInput {
            function_count: 1,
            type_bytes: crate::codegen::GpuLinkByteSource::resident(
                "test Wasm types",
                vec![0x60, 0, 0],
            ),
            body_bytes: crate::codegen::GpuLinkByteSource::resident(
                "test Wasm bodies",
                vec![0; body_len],
            ),
            relocations: relocation_offsets
                .iter()
                .copied()
                .map(|body_offset| GpuWasmLinkRelocationRecord {
                    body_offset,
                    target_kind: GpuWasmRelocationTargetKind::LocalFunction,
                    target_index: 0,
                    target_identity: [0; 3],
                    addend: 0,
                })
                .collect(),
            symbols: Vec::new(),
            entry_function: 0,
        }
    }

    #[test]
    fn page_geometry_covers_output_once_and_requests_only_intersecting_payloads() {
        let input = input_with_body(40, &[]);
        let plan = GpuWasmPagedExecutablePlan::new(&input, 32).expect("plan pages");
        assert_eq!(plan.output_len, 8 + 11 + 3 + 11 + 5 + 22 + 11 + 40);
        assert_eq!(
            plan.pages.iter().map(|page| page.output_len).sum::<u32>(),
            plan.output_len as u32
        );
        assert_eq!(
            plan.pages
                .iter()
                .map(|page| page.type_input.len())
                .sum::<usize>(),
            input.type_byte_len()
        );
        assert_eq!(
            plan.pages
                .iter()
                .map(|page| page.body_input.len())
                .sum::<usize>(),
            input.body_byte_len()
        );
        assert!(plan.pages.iter().all(|page| page.output_base % 4 == 0));
    }

    #[test]
    fn relocation_crossing_page_boundary_is_assigned_to_both_pages() {
        let base_input = input_with_body(40, &[]);
        let base_plan = GpuWasmPagedExecutablePlan::new(&base_input, 32).expect("base plan");
        let boundary = 32usize
            .checked_sub(base_plan.body_data_start % 32)
            .expect("body boundary") as u32;
        let input = input_with_body(40, &[boundary - 2]);
        let plan = GpuWasmPagedExecutablePlan::new(&input, 32).expect("plan pages");
        let containing_pages = plan
            .pages
            .iter()
            .filter(|page| page.relocation_indices.contains(&0))
            .count();
        assert_eq!(containing_pages, 2);
    }
}
