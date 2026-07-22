//! Bounds-checked, flat input model for the GPU Wasm linker.
//!
//! The host performs container validation and upload marshaling only. Symbol
//! resolution, module byte emission, body movement, and relocation are GPU
//! passes in `link/executable.rs`.

mod executable;
mod paged;
mod symbol_partitions;
mod symbol_resolution;

use std::path::PathBuf;

use super::{
    GpuWasmRelocatableObject,
    GpuWasmRelocatableObjectLayout,
    GpuWasmRelocationTargetKind,
    GpuWasmSymbolKind,
};
use crate::codegen::GpuLinkByteSource;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct GpuWasmLinkRelocationRecord {
    pub body_offset: u32,
    pub target_kind: GpuWasmRelocationTargetKind,
    pub target_index: u32,
    pub target_identity: [u32; 3],
    pub addend: i32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct GpuWasmLinkSymbolRecord {
    pub identity: [u32; 3],
    pub function_index: u32,
    pub flags: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct GpuWasmLinkInput {
    pub(super) function_count: usize,
    type_bytes: GpuLinkByteSource,
    body_bytes: GpuLinkByteSource,
    pub(super) relocations: Vec<GpuWasmLinkRelocationRecord>,
    pub(super) symbols: Vec<GpuWasmLinkSymbolRecord>,
    pub(super) entry_function: u32,
}

impl GpuWasmLinkInput {
    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn for_executable(objects: &[GpuWasmRelocatableObject]) -> Result<Self, String> {
        if objects.is_empty() {
            return Err("Wasm link requires at least one object".into());
        }
        let mut result = Self::empty(
            GpuLinkByteSource::resident("Wasm link type bytes", Vec::new()),
            GpuLinkByteSource::resident("Wasm link body bytes", Vec::new()),
        );
        for (object_index, object) in objects.iter().enumerate() {
            result.append_object(object_index, object)?;
            result.type_bytes.extend_resident(&object.type_bytes);
            result.body_bytes.extend_resident(&object.body_bytes);
            checked_u32("type byte", result.type_byte_len())?;
            checked_u32("body byte", result.body_byte_len())?;
        }
        result.finish_validation()?;
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            eprintln!(
                "[laniusc][wasm-link] objects={} functions={} body_bytes={} relocations={}",
                objects.len(),
                result.function_count,
                result.body_byte_len(),
                result.relocations.len()
            );
            for (index, relocation) in result.relocations.iter().enumerate() {
                let site = relocation.body_offset as usize;
                let start = site.saturating_sub(1);
                let end = site.saturating_add(5).min(result.body_byte_len());
                let bytes = result.body_bytes.read_range(start..end)?;
                let bytes = bytes
                    .iter()
                    .map(|byte| format!("{byte:02x}"))
                    .collect::<Vec<_>>()
                    .join(" ");
                eprintln!(
                    "[laniusc][wasm-link] relocation={index} site={site} target={:?}:{} identity={:?} bytes=[{bytes}]",
                    relocation.target_kind, relocation.target_index, relocation.target_identity
                );
            }
        }
        Ok(result)
    }

    /// Builds link metadata one object at a time while retaining large type and
    /// body columns as file ranges. Peak host payload memory is therefore one
    /// compilation unit rather than the complete project.
    pub(crate) fn for_executable_files(
        files: impl IntoIterator<Item = (PathBuf, GpuWasmRelocatableObjectLayout)>,
    ) -> Result<Self, String> {
        let mut result = Self::empty(
            GpuLinkByteSource::file_segments("Wasm link type bytes"),
            GpuLinkByteSource::file_segments("Wasm link body bytes"),
        );
        let mut object_count = 0usize;
        for (object_index, (path, layout)) in files.into_iter().enumerate() {
            let object_bytes = std::fs::read(&path)
                .map_err(|err| format!("read Wasm link object {}: {err}", path.display()))?;
            let object = GpuWasmRelocatableObject::from_bytes(&object_bytes)
                .map_err(|reason| format!("parse Wasm link object {}: {reason}", path.display()))?;
            let parsed_layout = GpuWasmRelocatableObjectLayout::from_header_bytes(
                &object_bytes[..super::GPU_WASM_OBJECT_HEADER_BYTES],
            )?;
            if parsed_layout != layout {
                return Err(format!(
                    "Wasm link object {} changed after layout validation",
                    path.display()
                ));
            }
            result.append_object(object_index, &object)?;
            let (type_range, body_range) = layout.payload_byte_ranges()?;
            result
                .type_bytes
                .push_file_segment(path.clone(), type_range)?;
            result.body_bytes.push_file_segment(path, body_range)?;
            checked_u32("type byte", result.type_byte_len())?;
            checked_u32("body byte", result.body_byte_len())?;
            object_count += 1;
        }
        if object_count == 0 {
            return Err("Wasm link requires at least one object".into());
        }
        result.finish_validation()?;
        Ok(result)
    }

    fn empty(type_bytes: GpuLinkByteSource, body_bytes: GpuLinkByteSource) -> Self {
        Self {
            function_count: 0,
            type_bytes,
            body_bytes,
            relocations: Vec::new(),
            symbols: Vec::new(),
            entry_function: u32::MAX,
        }
    }

    fn append_object(
        &mut self,
        object_index: usize,
        object: &GpuWasmRelocatableObject,
    ) -> Result<(), String> {
        object.validate()?;
        let function_base = checked_u32("function", self.function_count)?;
        let body_base = checked_u32("body byte", self.body_byte_len())?;
        if let Some(entry) = object.entry_function {
            if self.entry_function != u32::MAX {
                return Err(format!(
                    "Wasm link has multiple entry objects; second is {object_index}"
                ));
            }
            self.entry_function = function_base
                .checked_add(entry)
                .ok_or_else(|| "Wasm entry function index overflows".to_string())?;
        }
        self.function_count = self
            .function_count
            .checked_add(object.functions.len())
            .ok_or_else(|| "Wasm function count overflows usize".to_string())?;
        for relocation in &object.relocations {
            let (target_index, target_identity) = match relocation.target_kind {
                GpuWasmRelocationTargetKind::LocalFunction => (
                    function_base
                        .checked_add(relocation.target_index)
                        .ok_or_else(|| {
                            "Wasm relocation local function index overflows".to_string()
                        })?,
                    [0; 3],
                ),
                GpuWasmRelocationTargetKind::Symbol => {
                    let symbol = &object.symbols[relocation.target_index as usize];
                    (0, symbol_identity(object, symbol))
                }
            };
            self.relocations.push(GpuWasmLinkRelocationRecord {
                body_offset: body_base
                    .checked_add(relocation.body_byte_offset)
                    .ok_or_else(|| "Wasm relocation offset overflows".to_string())?,
                target_kind: relocation.target_kind,
                target_index,
                target_identity,
                addend: relocation.addend,
            });
        }
        for symbol in &object.symbols {
            if symbol.kind == GpuWasmSymbolKind::Undefined {
                continue;
            }
            self.symbols.push(GpuWasmLinkSymbolRecord {
                identity: symbol_identity(object, symbol),
                function_index: function_base
                    .checked_add(symbol.function_index)
                    .ok_or_else(|| "Wasm symbol function index overflows".to_string())?,
                flags: symbol.flags,
            });
        }
        checked_u32("function", self.function_count)?;
        checked_u32("relocation", self.relocations.len())?;
        checked_u32("symbol", self.symbols.len())?;
        Ok(())
    }

    fn finish_validation(&self) -> Result<(), String> {
        if self.entry_function == u32::MAX {
            return Err("Wasm link has no entry function".into());
        }
        Ok(())
    }

    pub(super) fn type_byte_len(&self) -> usize {
        self.type_bytes.len()
    }

    pub(super) fn body_byte_len(&self) -> usize {
        self.body_bytes.len()
    }

    pub(super) fn read_type_range(&self, range: std::ops::Range<usize>) -> Result<Vec<u8>, String> {
        self.type_bytes.read_range(range)
    }

    pub(super) fn read_body_range(&self, range: std::ops::Range<usize>) -> Result<Vec<u8>, String> {
        self.body_bytes.read_range(range)
    }
}

fn symbol_identity(
    object: &GpuWasmRelocatableObject,
    symbol: &super::GpuWasmObjectSymbolRecord,
) -> [u32; 3] {
    let start = symbol.identity_byte_start as usize;
    let identity = &object.identity_bytes[start..start + 12];
    [
        u32::from_le_bytes(identity[0..4].try_into().unwrap()),
        u32::from_le_bytes(identity[4..8].try_into().unwrap()),
        u32::from_le_bytes(identity[8..12].try_into().unwrap()),
    ]
}

fn checked_u32(label: &str, len: usize) -> Result<u32, String> {
    u32::try_from(len).map_err(|_| format!("Wasm link {label} count {len} exceeds u32"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        codegen::wasm::{
            GPU_WASM_OBJECT_VERSION,
            GpuWasmFunctionRecord,
            GpuWasmLinker,
            GpuWasmObjectSymbolRecord,
            GpuWasmRelocationRecord,
            GpuWasmRelocationTargetKind,
        },
        compiler::stable_name_hash,
    };

    fn object(identity_words: [u32; 3], defined: bool, entry: bool) -> GpuWasmRelocatableObject {
        let identity_bytes: Vec<_> = identity_words
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect();
        let hash = stable_name_hash(&identity_bytes);
        let body_bytes = vec![0x82, 0x80, 0x80, 0x80, 0, 0, 0x0b];
        GpuWasmRelocatableObject {
            version: GPU_WASM_OBJECT_VERSION,
            library_id: identity_words[0],
            unit_id: identity_words[1],
            entry_function: entry.then_some(0),
            functions: if defined {
                vec![GpuWasmFunctionRecord {
                    type_byte_start: 0,
                    type_byte_len: 3,
                    body_byte_start: 0,
                    body_byte_len: 7,
                    symbol_index: 0,
                    flags: 0,
                }]
            } else {
                vec![]
            },
            type_bytes: if defined { vec![0x60, 0, 0] } else { vec![] },
            body_bytes: if defined { body_bytes } else { vec![] },
            relocations: vec![],
            symbols: vec![GpuWasmObjectSymbolRecord {
                identity_hash_lo: hash.0,
                identity_hash_hi: hash.1,
                identity_byte_start: 0,
                identity_byte_len: 12,
                kind: if defined {
                    GpuWasmSymbolKind::Function
                } else {
                    GpuWasmSymbolKind::Undefined
                },
                function_index: if defined { 0 } else { u32::MAX },
                size: if defined { 7 } else { 0 },
                flags: 0,
            }],
            identity_bytes,
        }
    }

    #[test]
    fn flattens_units_without_losing_nominal_identity() {
        let input = GpuWasmLinkInput::for_executable(&[
            object([1, 0, 2], true, false),
            object([1, 1, 2], true, true),
        ])
        .unwrap();
        assert_eq!(input.function_count, 2);
        assert_ne!(input.symbols[0].identity, input.symbols[1].identity);
        assert_eq!(input.entry_function, 1);
    }

    #[test]
    fn gpu_definition_table_omits_undefined_reference_records() {
        let input = GpuWasmLinkInput::for_executable(&[
            object([1, 0, 2], false, false),
            object([1, 0, 2], true, true),
        ])
        .expect("link input");
        assert_eq!(input.symbols.len(), 1);
        assert_eq!(input.symbols[0].identity, [1, 0, 2]);
    }

    #[test]
    fn symbol_relocation_carries_nominal_identity_without_resident_undefined_symbol() {
        let mut caller = object([1, 0, 2], true, true);
        let target_identity: Vec<_> = [9u32, 8, 7]
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect();
        let target_hash = stable_name_hash(&target_identity);
        caller.identity_bytes.extend_from_slice(&target_identity);
        caller.symbols.push(GpuWasmObjectSymbolRecord {
            identity_hash_lo: target_hash.0,
            identity_hash_hi: target_hash.1,
            identity_byte_start: 12,
            identity_byte_len: 12,
            kind: GpuWasmSymbolKind::Undefined,
            function_index: u32::MAX,
            size: 0,
            flags: 0,
        });
        caller.relocations.push(GpuWasmRelocationRecord {
            body_byte_offset: 0,
            target_kind: GpuWasmRelocationTargetKind::Symbol,
            target_index: 1,
            addend: 0,
        });

        let input = GpuWasmLinkInput::for_executable(&[caller]).expect("link input");
        assert_eq!(input.symbols.len(), 1);
        assert_eq!(input.relocations.len(), 1);
        assert_eq!(input.relocations[0].target_identity, [9, 8, 7]);
        assert_eq!(input.relocations[0].target_index, 0);
    }

    #[test]
    fn file_backed_payload_matches_resident_link_input_across_objects() {
        let objects = vec![
            object([1, 0, 2], true, false),
            object([1, 1, 2], true, true),
        ];
        let resident = GpuWasmLinkInput::for_executable(&objects).expect("resident input");
        let root = std::env::temp_dir().join(format!(
            "laniusc-wasm-file-link-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).expect("temporary directory");
        let mut files = Vec::new();
        for (index, object) in objects.iter().enumerate() {
            let bytes = object.to_bytes().expect("serialize object");
            let layout = GpuWasmRelocatableObjectLayout::from_header_bytes(
                &bytes[..crate::codegen::wasm::GPU_WASM_OBJECT_HEADER_BYTES],
            )
            .expect("object layout");
            let path = root.join(format!("{index}.wasmobj"));
            std::fs::write(&path, bytes).expect("write object");
            files.push((path, layout));
        }
        let file_backed = GpuWasmLinkInput::for_executable_files(files).expect("file-backed input");

        assert_eq!(file_backed.function_count, resident.function_count);
        assert_eq!(file_backed.relocations, resident.relocations);
        assert_eq!(file_backed.symbols, resident.symbols);
        assert_eq!(file_backed.entry_function, resident.entry_function);
        assert_eq!(file_backed.type_byte_len(), resident.type_byte_len());
        assert_eq!(file_backed.body_byte_len(), resident.body_byte_len());
        assert_eq!(
            file_backed
                .read_type_range(2..5)
                .expect("cross-object type range"),
            resident.read_type_range(2..5).expect("resident type range")
        );
        assert_eq!(
            file_backed
                .read_body_range(5..9)
                .expect("cross-object body range"),
            resident.read_body_range(5..9).expect("resident body range")
        );

        std::fs::remove_dir_all(root).expect("remove temporary directory");
    }

    fn padded(value: u32) -> [u8; 5] {
        [
            ((value & 0x7f) as u8) | 0x80,
            (((value >> 7) & 0x7f) as u8) | 0x80,
            (((value >> 14) & 0x7f) as u8) | 0x80,
            (((value >> 21) & 0x7f) as u8) | 0x80,
            ((value >> 28) & 0x0f) as u8,
        ]
    }
    fn symbol(
        identity: &[u8],
        kind: GpuWasmSymbolKind,
        function_index: u32,
        size: u32,
        start: u32,
    ) -> GpuWasmObjectSymbolRecord {
        let hash = stable_name_hash(identity);
        GpuWasmObjectSymbolRecord {
            identity_hash_lo: hash.0,
            identity_hash_hi: hash.1,
            identity_byte_start: start,
            identity_byte_len: 12,
            kind,
            function_index,
            size,
            flags: 0,
        }
    }

    #[test]
    fn gpu_links_and_relocates_cross_unit_call() {
        let dep_identity: Vec<u8> = [7u32, 0, 0]
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect();
        let main_identity: Vec<u8> = [8u32, 0, 0]
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect();
        let mut app_body = padded(8).to_vec();
        app_body.extend_from_slice(&[0, 0x10]);
        app_body.extend_from_slice(&padded(0));
        app_body.push(0x0b);
        let mut identities = dep_identity.clone();
        identities.extend_from_slice(&main_identity);
        let app = GpuWasmRelocatableObject {
            version: GPU_WASM_OBJECT_VERSION,
            library_id: 8,
            unit_id: 0,
            entry_function: Some(0),
            functions: vec![GpuWasmFunctionRecord {
                type_byte_start: 0,
                type_byte_len: 4,
                body_byte_start: 0,
                body_byte_len: app_body.len() as u32,
                symbol_index: 1,
                flags: 0,
            }],
            type_bytes: vec![0x60, 0, 1, 0x7f],
            body_bytes: app_body,
            relocations: vec![GpuWasmRelocationRecord {
                body_byte_offset: 7,
                target_kind: GpuWasmRelocationTargetKind::Symbol,
                target_index: 0,
                addend: 0,
            }],
            symbols: vec![
                symbol(&dep_identity, GpuWasmSymbolKind::Undefined, u32::MAX, 0, 0),
                symbol(&main_identity, GpuWasmSymbolKind::Function, 0, 13, 12),
            ],
            identity_bytes: identities,
        };
        let mut dep_body = padded(4).to_vec();
        dep_body.extend_from_slice(&[0, 0x41, 7, 0x0b]);
        let dep = GpuWasmRelocatableObject {
            version: GPU_WASM_OBJECT_VERSION,
            library_id: 7,
            unit_id: 0,
            entry_function: None,
            functions: vec![GpuWasmFunctionRecord {
                type_byte_start: 0,
                type_byte_len: 4,
                body_byte_start: 0,
                body_byte_len: dep_body.len() as u32,
                symbol_index: 0,
                flags: 0,
            }],
            type_bytes: vec![0x60, 0, 1, 0x7f],
            body_bytes: dep_body,
            relocations: vec![],
            symbols: vec![symbol(&dep_identity, GpuWasmSymbolKind::Function, 0, 9, 0)],
            identity_bytes: dep_identity,
        };
        let input = GpuWasmLinkInput::for_executable(&[app, dep]).unwrap();
        let gpu = crate::gpu::device::global();
        let generator = GpuWasmLinker::new_with_device(gpu).expect("Wasm linker");
        let module = generator
            .link_executable(&gpu.device, &gpu.queue, &input)
            .expect("GPU Wasm link");
        assert_eq!(&module[..8], b"\0asm\x01\0\0\0");
        assert!(module.windows(5).any(|bytes| bytes == padded(1)));
        let node = which::which("node").expect("Node runtime for linked Wasm validation");
        let path =
            std::env::temp_dir().join(format!("laniusc-gpu-link-{}.wasm", std::process::id()));
        std::fs::write(&path, &module).expect("write linked Wasm fixture");
        let output = std::process::Command::new(node)
            .args(["-e", "const fs=require('fs'); WebAssembly.instantiate(fs.readFileSync(process.argv[1])).then(x=>process.stdout.write(String(x.instance.exports.main())))", path.to_str().unwrap()])
            .output().expect("run linked Wasm fixture in Node");
        let _ = std::fs::remove_file(&path);
        assert!(
            output.status.success(),
            "Node rejected linked Wasm: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(output.stdout, b"7");
    }
}
