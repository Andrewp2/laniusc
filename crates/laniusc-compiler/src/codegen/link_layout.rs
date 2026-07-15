use super::{wasm::GpuWasmRelocatableObjectLayout, x86::GpuX86RelocatableObjectLayout};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum GpuLinkColumnKind {
    X86Object,
    X86Text,
    X86Rodata,
    WasmFunction,
    WasmType,
    WasmBody,
    Relocation,
    Symbol,
    Identity,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct GpuLinkObjectSegment {
    pub object_index: usize,
    pub element_start: u64,
    pub element_count: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct GpuLinkColumnPage {
    pub segments: Vec<GpuLinkObjectSegment>,
    pub element_count: u64,
    pub byte_len: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct GpuLinkColumnPlan {
    pub kind: GpuLinkColumnKind,
    pub element_stride: u64,
    pub total_elements: u64,
    pub total_bytes: u64,
    pub pages: Vec<GpuLinkColumnPage>,
}

impl GpuLinkColumnPlan {
    fn build(
        kind: GpuLinkColumnKind,
        element_stride: u64,
        object_element_counts: impl IntoIterator<Item = u64>,
        max_page_bytes: u64,
    ) -> Result<Self, String> {
        if element_stride == 0 {
            return Err(format!("{kind:?} link-column stride must be nonzero"));
        }
        let max_page_elements = max_page_bytes / element_stride;
        if max_page_elements == 0 {
            return Err(format!(
                "{kind:?} link-column stride {element_stride} exceeds page limit {max_page_bytes}"
            ));
        }

        let mut pages = Vec::new();
        let mut current_segments = Vec::new();
        let mut current_elements = 0u64;
        let mut total_elements = 0u64;
        for (object_index, object_elements) in object_element_counts.into_iter().enumerate() {
            total_elements = total_elements.checked_add(object_elements).ok_or_else(|| {
                format!("{kind:?} link-column aggregate element count overflows u64")
            })?;
            let mut element_start = 0u64;
            while element_start < object_elements {
                if current_elements == max_page_elements {
                    push_page(
                        &mut pages,
                        &mut current_segments,
                        &mut current_elements,
                        element_stride,
                    );
                }
                let available = max_page_elements - current_elements;
                let element_count = available.min(object_elements - element_start);
                current_segments.push(GpuLinkObjectSegment {
                    object_index,
                    element_start,
                    element_count,
                });
                current_elements += element_count;
                element_start += element_count;
            }
        }
        push_page(
            &mut pages,
            &mut current_segments,
            &mut current_elements,
            element_stride,
        );
        let total_bytes = total_elements
            .checked_mul(element_stride)
            .ok_or_else(|| format!("{kind:?} link-column aggregate byte size overflows u64"))?;
        Ok(Self {
            kind,
            element_stride,
            total_elements,
            total_bytes,
            pages,
        })
    }
}

fn push_page(
    pages: &mut Vec<GpuLinkColumnPage>,
    current_segments: &mut Vec<GpuLinkObjectSegment>,
    current_elements: &mut u64,
    element_stride: u64,
) {
    if *current_elements == 0 {
        return;
    }
    pages.push(GpuLinkColumnPage {
        segments: std::mem::take(current_segments),
        element_count: *current_elements,
        byte_len: *current_elements * element_stride,
    });
    *current_elements = 0;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct GpuLinkLayoutPlan {
    pub columns: Vec<GpuLinkColumnPlan>,
    pub output_byte_len: u64,
    pub max_page_bytes: u64,
}

impl GpuLinkLayoutPlan {
    pub(crate) fn for_x86(
        layouts: &[GpuX86RelocatableObjectLayout],
        max_page_bytes: u64,
    ) -> Result<Self, String> {
        let columns = vec![
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::X86Object,
                16,
                layouts.iter().map(|_| 1),
                max_page_bytes,
            )?,
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::X86Text,
                1,
                layouts.iter().map(|layout| layout.text_byte_len as u64),
                max_page_bytes,
            )?,
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::X86Rodata,
                1,
                layouts.iter().map(|layout| layout.rodata_byte_len as u64),
                max_page_bytes,
            )?,
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::Relocation,
                16,
                layouts.iter().map(|layout| layout.relocation_count as u64),
                max_page_bytes,
            )?,
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::Symbol,
                16,
                layouts.iter().map(|layout| layout.symbol_count as u64),
                max_page_bytes,
            )?,
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::Identity,
                1,
                layouts.iter().map(|layout| layout.identity_byte_len as u64),
                max_page_bytes,
            )?,
        ];
        let text_bytes = sum_u32(layouts.iter().map(|layout| layout.text_byte_len))?;
        let rodata_bytes = sum_u32(layouts.iter().map(|layout| layout.rodata_byte_len))?;
        let output_byte_len = 0x78u64
            .checked_add(text_bytes)
            .and_then(|len| len.checked_add(rodata_bytes))
            .ok_or_else(|| "x86 linked output byte size overflows u64".to_string())?;
        Ok(Self {
            columns,
            output_byte_len,
            max_page_bytes,
        })
    }

    pub(crate) fn for_wasm(
        layouts: &[GpuWasmRelocatableObjectLayout],
        max_page_bytes: u64,
    ) -> Result<Self, String> {
        let columns = vec![
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::WasmFunction,
                24,
                layouts.iter().map(|layout| layout.function_count as u64),
                max_page_bytes,
            )?,
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::WasmType,
                1,
                layouts.iter().map(|layout| layout.type_byte_len as u64),
                max_page_bytes,
            )?,
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::WasmBody,
                1,
                layouts.iter().map(|layout| layout.body_byte_len as u64),
                max_page_bytes,
            )?,
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::Relocation,
                16,
                layouts.iter().map(|layout| layout.relocation_count as u64),
                max_page_bytes,
            )?,
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::Symbol,
                16,
                layouts.iter().map(|layout| layout.symbol_count as u64),
                max_page_bytes,
            )?,
            GpuLinkColumnPlan::build(
                GpuLinkColumnKind::Identity,
                1,
                layouts.iter().map(|layout| layout.identity_byte_len as u64),
                max_page_bytes,
            )?,
        ];
        let function_count = sum_u32(layouts.iter().map(|layout| layout.function_count))?;
        let type_bytes = sum_u32(layouts.iter().map(|layout| layout.type_byte_len))?;
        let body_bytes = sum_u32(layouts.iter().map(|layout| layout.body_byte_len))?;
        let output_byte_len = 8u64
            .checked_add(11 + type_bytes)
            .and_then(|len| len.checked_add(11 + function_count * 5))
            .and_then(|len| len.checked_add(22))
            .and_then(|len| len.checked_add(11 + body_bytes))
            .ok_or_else(|| "Wasm linked output byte size overflows u64".to_string())?;
        Ok(Self {
            columns,
            output_byte_len,
            max_page_bytes,
        })
    }

    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn requires_streaming(&self) -> bool {
        self.output_byte_len > self.max_page_bytes
            || self.columns.iter().any(|column| column.pages.len() > 1)
    }
}

fn sum_u32(values: impl IntoIterator<Item = u32>) -> Result<u64, String> {
    values.into_iter().try_fold(0u64, |sum, value| {
        sum.checked_add(value as u64)
            .ok_or_else(|| "link layout aggregate size overflows u64".to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn column_pages_split_inside_one_object_and_reconstruct_every_element() {
        let plan = GpuLinkColumnPlan::build(GpuLinkColumnKind::X86Text, 1, [3, 15, 0, 4], 8)
            .expect("plan column");
        assert_eq!(plan.total_elements, 22);
        assert_eq!(
            plan.pages
                .iter()
                .map(|page| page.byte_len)
                .collect::<Vec<_>>(),
            [8, 8, 6]
        );
        let mut reconstructed = [0u64; 4];
        for page in &plan.pages {
            assert!(page.byte_len <= 8);
            for segment in &page.segments {
                reconstructed[segment.object_index] += segment.element_count;
            }
        }
        assert_eq!(reconstructed, [3, 15, 0, 4]);
    }

    #[test]
    fn empty_columns_do_not_create_phantom_pages() {
        let plan = GpuLinkColumnPlan::build(GpuLinkColumnKind::Symbol, 16, [0, 0], 64)
            .expect("plan empty column");
        assert_eq!(plan.total_bytes, 0);
        assert!(plan.pages.is_empty());
    }

    #[test]
    fn stride_larger_than_binding_limit_is_rejected() {
        let error = GpuLinkColumnPlan::build(GpuLinkColumnKind::WasmFunction, 24, [1], 16)
            .expect_err("record cannot fit");
        assert!(error.contains("exceeds page limit"));
    }

    #[test]
    fn x86_layout_plan_uses_exact_output_size_and_detects_paged_text() {
        let layouts = [GpuX86RelocatableObjectLayout {
            version: super::super::x86::GPU_X86_OBJECT_VERSION,
            library_id: 1,
            unit_id: 0,
            entry_offset: Some(0),
            text_byte_len: 80,
            rodata_byte_len: 9,
            relocation_count: 2,
            symbol_count: 3,
            identity_byte_len: 36,
            serialized_byte_len: 0,
        }];
        let plan = GpuLinkLayoutPlan::for_x86(&layouts, 64).expect("plan x86 layout");
        assert_eq!(plan.output_byte_len, 0x78 + 80 + 9);
        assert!(plan.requires_streaming());
        let text = plan
            .columns
            .iter()
            .find(|column| column.kind == GpuLinkColumnKind::X86Text)
            .expect("text column");
        assert_eq!(text.pages.len(), 2);
        assert_eq!(text.pages[0].byte_len, 64);
        assert_eq!(text.pages[1].byte_len, 16);
    }

    #[test]
    fn wasm_layout_plan_remains_resident_when_every_column_and_output_fit() {
        let layouts = [GpuWasmRelocatableObjectLayout {
            version: super::super::wasm::GPU_WASM_OBJECT_VERSION,
            library_id: 1,
            unit_id: 0,
            entry_function: Some(0),
            function_count: 2,
            type_byte_len: 6,
            body_byte_len: 20,
            relocation_count: 1,
            symbol_count: 2,
            identity_byte_len: 24,
            serialized_byte_len: 0,
        }];
        let plan = GpuLinkLayoutPlan::for_wasm(&layouts, 1024).expect("plan Wasm layout");
        assert_eq!(plan.output_byte_len, 8 + 17 + 21 + 22 + 31);
        assert!(!plan.requires_streaming());
        assert!(
            plan.columns
                .iter()
                .flat_map(|column| &column.pages)
                .all(|page| page.byte_len <= 1024)
        );
    }
}
