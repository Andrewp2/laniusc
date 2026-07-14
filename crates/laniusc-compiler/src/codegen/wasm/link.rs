//! Bounds-checked, flat input model for the GPU Wasm linker.
//!
//! The host performs container validation and upload marshaling only. Symbol
//! resolution, module byte emission, body movement, and relocation are GPU
//! passes in `link/executable.rs`.

mod executable;

use super::{GpuWasmRelocatableObject, GpuWasmRelocationTargetKind, GpuWasmSymbolKind};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct GpuWasmLinkFunctionRecord {
    pub type_input_start: u32,
    pub type_len: u32,
    pub body_input_start: u32,
    pub body_len: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct GpuWasmLinkRelocationRecord {
    pub body_offset: u32,
    pub target_kind: GpuWasmRelocationTargetKind,
    pub target_index: u32,
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
    pub(super) functions: Vec<GpuWasmLinkFunctionRecord>,
    pub(super) type_bytes: Vec<u8>,
    pub(super) body_bytes: Vec<u8>,
    pub(super) relocations: Vec<GpuWasmLinkRelocationRecord>,
    pub(super) symbols: Vec<GpuWasmLinkSymbolRecord>,
    pub(super) entry_function: u32,
}

impl GpuWasmLinkInput {
    pub(crate) fn for_executable(objects: &[GpuWasmRelocatableObject]) -> Result<Self, String> {
        if objects.is_empty() {
            return Err("Wasm link requires at least one object".into());
        }
        let mut result = Self {
            functions: Vec::new(),
            type_bytes: Vec::new(),
            body_bytes: Vec::new(),
            relocations: Vec::new(),
            symbols: Vec::new(),
            entry_function: u32::MAX,
        };
        for (object_index, object) in objects.iter().enumerate() {
            object.validate()?;
            let function_base = checked_u32("function", result.functions.len())?;
            let type_base = checked_u32("type byte", result.type_bytes.len())?;
            let body_base = checked_u32("body byte", result.body_bytes.len())?;
            let symbol_base = checked_u32("symbol", result.symbols.len())?;
            if let Some(entry) = object.entry_function {
                if result.entry_function != u32::MAX {
                    return Err(format!(
                        "Wasm link has multiple entry objects; second is {object_index}"
                    ));
                }
                result.entry_function = function_base
                    .checked_add(entry)
                    .ok_or_else(|| "Wasm entry function index overflows".to_string())?;
            }
            result.type_bytes.extend_from_slice(&object.type_bytes);
            result.body_bytes.extend_from_slice(&object.body_bytes);
            for function in &object.functions {
                result.functions.push(GpuWasmLinkFunctionRecord {
                    type_input_start: type_base
                        .checked_add(function.type_byte_start)
                        .ok_or_else(|| "Wasm type offset overflows".to_string())?,
                    type_len: function.type_byte_len,
                    body_input_start: body_base
                        .checked_add(function.body_byte_start)
                        .ok_or_else(|| "Wasm body offset overflows".to_string())?,
                    body_len: function.body_byte_len,
                });
            }
            for relocation in &object.relocations {
                result.relocations.push(GpuWasmLinkRelocationRecord {
                    body_offset: body_base
                        .checked_add(relocation.body_byte_offset)
                        .ok_or_else(|| "Wasm relocation offset overflows".to_string())?,
                    target_kind: relocation.target_kind,
                    target_index: match relocation.target_kind {
                        GpuWasmRelocationTargetKind::LocalFunction => function_base
                            .checked_add(relocation.target_index)
                            .ok_or_else(|| {
                                "Wasm relocation local function index overflows".to_string()
                            })?,
                        GpuWasmRelocationTargetKind::Symbol => symbol_base
                            .checked_add(relocation.target_index)
                            .ok_or_else(|| "Wasm relocation symbol index overflows".to_string())?,
                    },
                    addend: relocation.addend,
                });
            }
            for symbol in &object.symbols {
                let start = symbol.identity_byte_start as usize;
                let identity = &object.identity_bytes[start..start + 12];
                result.symbols.push(GpuWasmLinkSymbolRecord {
                    identity: [
                        u32::from_le_bytes(identity[0..4].try_into().unwrap()),
                        u32::from_le_bytes(identity[4..8].try_into().unwrap()),
                        u32::from_le_bytes(identity[8..12].try_into().unwrap()),
                    ],
                    function_index: match symbol.kind {
                        GpuWasmSymbolKind::Undefined => u32::MAX,
                        GpuWasmSymbolKind::Function => function_base
                            .checked_add(symbol.function_index)
                            .ok_or_else(|| "Wasm symbol function index overflows".to_string())?,
                    },
                    flags: symbol.flags,
                });
            }
            checked_u32("function", result.functions.len())?;
            checked_u32("type byte", result.type_bytes.len())?;
            checked_u32("body byte", result.body_bytes.len())?;
            checked_u32("relocation", result.relocations.len())?;
            checked_u32("symbol", result.symbols.len())?;
        }
        if result.entry_function == u32::MAX {
            return Err("Wasm link has no entry function".into());
        }
        Ok(result)
    }
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
            GpuWasmCodeGenerator,
            GpuWasmFunctionRecord,
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
        assert_eq!(input.functions.len(), 2);
        assert_ne!(input.symbols[0].identity, input.symbols[1].identity);
        assert_eq!(input.entry_function, 1);
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
        let generator = GpuWasmCodeGenerator::new_with_device(gpu).expect("Wasm generator");
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
