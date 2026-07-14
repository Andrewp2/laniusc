//! Durable relocatable object format produced by the GPU Wasm backend.
//!
//! Function bodies contain maximally padded five-byte LEB immediates at every
//! relocation site. This follows the WebAssembly object-file linking
//! convention and lets the GPU linker renumber calls without moving bytes.

use crate::compiler::stable_name_hash;

pub const GPU_WASM_OBJECT_VERSION: u32 = 2;
const GPU_WASM_OBJECT_MAGIC: [u8; 8] = *b"LNWASMOB";
const HEADER_U32S: usize = 10;
const FUNCTION_U32S: usize = 6;
const RELOCATION_U32S: usize = 4;
const SYMBOL_U32S: usize = 8;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum GpuWasmSymbolKind {
    Undefined = 0,
    Function = 1,
}

impl GpuWasmSymbolKind {
    fn from_u32(value: u32) -> Result<Self, String> {
        match value {
            0 => Ok(Self::Undefined),
            1 => Ok(Self::Function),
            _ => Err(format!("Wasm object symbol kind {value} is invalid")),
        }
    }
}

/// One defined function and its independently encoded signature and body.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuWasmFunctionRecord {
    pub type_byte_start: u32,
    pub type_byte_len: u32,
    pub body_byte_start: u32,
    pub body_byte_len: u32,
    pub symbol_index: u32,
    pub flags: u32,
}

/// Interpretation of an `R_WASM_FUNCTION_INDEX_LEB` target payload.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum GpuWasmRelocationTargetKind {
    LocalFunction = 1,
    Symbol = 2,
}

impl GpuWasmRelocationTargetKind {
    fn from_u32(value: u32) -> Result<Self, String> {
        match value {
            1 => Ok(Self::LocalFunction),
            2 => Ok(Self::Symbol),
            _ => Err(format!(
                "Wasm object relocation target kind {value} is invalid"
            )),
        }
    }
}

/// A standard `R_WASM_FUNCTION_INDEX_LEB` relocation within `body_bytes`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuWasmRelocationRecord {
    pub body_byte_offset: u32,
    pub target_kind: GpuWasmRelocationTargetKind,
    pub target_index: u32,
    pub addend: i32,
}

/// One exact semantic declaration identity, defined or undefined in this unit.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuWasmObjectSymbolRecord {
    pub identity_hash_lo: u32,
    pub identity_hash_hi: u32,
    pub identity_byte_start: u32,
    pub identity_byte_len: u32,
    pub kind: GpuWasmSymbolKind,
    pub function_index: u32,
    pub size: u32,
    pub flags: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GpuWasmRelocatableObject {
    pub version: u32,
    pub library_id: u32,
    pub unit_id: u32,
    pub entry_function: Option<u32>,
    pub functions: Vec<GpuWasmFunctionRecord>,
    pub type_bytes: Vec<u8>,
    pub body_bytes: Vec<u8>,
    pub relocations: Vec<GpuWasmRelocationRecord>,
    pub symbols: Vec<GpuWasmObjectSymbolRecord>,
    pub identity_bytes: Vec<u8>,
}

impl GpuWasmRelocatableObject {
    pub fn validate(&self) -> Result<(), String> {
        if self.version != GPU_WASM_OBJECT_VERSION {
            return Err(format!(
                "Wasm object version {} is unsupported; expected {}",
                self.version, GPU_WASM_OBJECT_VERSION
            ));
        }
        for (label, len) in [
            ("function", self.functions.len()),
            ("type byte", self.type_bytes.len()),
            ("body byte", self.body_bytes.len()),
            ("relocation", self.relocations.len()),
            ("symbol", self.symbols.len()),
            ("identity byte", self.identity_bytes.len()),
        ] {
            u32::try_from(len)
                .map_err(|_| format!("Wasm object {label} count {len} exceeds u32"))?;
        }
        if let Some(entry) = self.entry_function {
            if entry as usize >= self.functions.len() {
                return Err(format!(
                    "Wasm object entry function {entry} is out of range"
                ));
            }
        }
        let mut expected_type_start = 0usize;
        let mut expected_body_start = 0usize;
        for (index, function) in self.functions.iter().enumerate() {
            let ty = checked_range(
                "function type",
                index,
                function.type_byte_start,
                function.type_byte_len,
                self.type_bytes.len(),
            )?;
            if self.type_bytes[ty.start] != 0x60 {
                return Err(format!(
                    "Wasm object function {index} type is not a function type"
                ));
            }
            if ty.start != expected_type_start {
                return Err(format!(
                    "Wasm object function {index} types are not densely ordered"
                ));
            }
            expected_type_start = ty.end;
            let body = checked_range(
                "function body",
                index,
                function.body_byte_start,
                function.body_byte_len,
                self.body_bytes.len(),
            )?;
            if body.len() < 7 {
                return Err(format!("Wasm object function {index} body is too short"));
            }
            if body.start != expected_body_start {
                return Err(format!(
                    "Wasm object function {index} bodies are not densely ordered"
                ));
            }
            expected_body_start = body.end;
            let payload_len = decode_padded_u32(&self.body_bytes[body.start..body.start + 5])?;
            if payload_len as usize + 5 != body.len() {
                return Err(format!(
                    "Wasm object function {index} body size prefix is inconsistent"
                ));
            }
            if function.symbol_index != u32::MAX {
                if function.symbol_index as usize >= self.symbols.len() {
                    return Err(format!(
                        "Wasm object function {index} symbol is out of range"
                    ));
                }
                let symbol = self.symbols[function.symbol_index as usize];
                if symbol.kind != GpuWasmSymbolKind::Function
                    || symbol.function_index != index as u32
                {
                    return Err(format!(
                        "Wasm object function {index} symbol does not define it"
                    ));
                }
            }
        }
        if expected_type_start != self.type_bytes.len()
            || expected_body_start != self.body_bytes.len()
        {
            return Err(format!(
                "Wasm object has unowned bytes: functions own {expected_type_start}/{} type bytes and {expected_body_start}/{} body bytes; records={:?}",
                self.type_bytes.len(),
                self.body_bytes.len(),
                self.functions
            ));
        }
        for (index, relocation) in self.relocations.iter().enumerate() {
            let start = relocation.body_byte_offset as usize;
            let end = start
                .checked_add(5)
                .ok_or_else(|| format!("Wasm object relocation {index} site overflows"))?;
            if end > self.body_bytes.len() {
                return Err(format!(
                    "Wasm object relocation {index} site is out of range"
                ));
            }
            decode_padded_u32(&self.body_bytes[start..end]).map_err(|reason| {
                format!("Wasm object relocation {index} does not target a padded LEB: {reason}")
            })?;
            match relocation.target_kind {
                GpuWasmRelocationTargetKind::LocalFunction => {
                    if relocation.target_index as usize >= self.functions.len() {
                        return Err(format!(
                            "Wasm object relocation {index} local function is out of range"
                        ));
                    }
                }
                GpuWasmRelocationTargetKind::Symbol => {
                    if relocation.target_index as usize >= self.symbols.len() {
                        return Err(format!(
                            "Wasm object relocation {index} symbol is out of range"
                        ));
                    }
                }
            }
        }
        for (index, symbol) in self.symbols.iter().enumerate() {
            let identity = checked_range(
                "symbol identity",
                index,
                symbol.identity_byte_start,
                symbol.identity_byte_len,
                self.identity_bytes.len(),
            )?;
            if identity.len() != 12 {
                return Err(format!(
                    "Wasm object symbol {index} identity has {} bytes; expected 12",
                    identity.len()
                ));
            }
            if stable_name_hash(&self.identity_bytes[identity.clone()])
                != (symbol.identity_hash_lo, symbol.identity_hash_hi)
            {
                return Err(format!(
                    "Wasm object symbol {index} identity hash is inconsistent"
                ));
            }
            match symbol.kind {
                GpuWasmSymbolKind::Undefined => {
                    if symbol.function_index != u32::MAX || symbol.size != 0 {
                        return Err(format!(
                            "Wasm object undefined symbol {index} has a definition"
                        ));
                    }
                }
                GpuWasmSymbolKind::Function => {
                    if symbol.function_index as usize >= self.functions.len() {
                        return Err(format!(
                            "Wasm object symbol {index} function is out of range"
                        ));
                    }
                }
            }
        }
        Ok(())
    }

    pub fn to_bytes(&self) -> Result<Vec<u8>, String> {
        self.validate()?;
        let mut out = Vec::new();
        out.extend_from_slice(&GPU_WASM_OBJECT_MAGIC);
        for word in [
            self.version,
            self.library_id,
            self.unit_id,
            self.entry_function.unwrap_or(u32::MAX),
            self.functions.len() as u32,
            self.type_bytes.len() as u32,
            self.body_bytes.len() as u32,
            self.relocations.len() as u32,
            self.symbols.len() as u32,
            self.identity_bytes.len() as u32,
        ] {
            push_u32(&mut out, word);
        }
        for function in &self.functions {
            for word in [
                function.type_byte_start,
                function.type_byte_len,
                function.body_byte_start,
                function.body_byte_len,
                function.symbol_index,
                function.flags,
            ] {
                push_u32(&mut out, word);
            }
        }
        out.extend_from_slice(&self.type_bytes);
        out.extend_from_slice(&self.body_bytes);
        for relocation in &self.relocations {
            for word in [
                relocation.body_byte_offset,
                relocation.target_kind as u32,
                relocation.target_index,
                relocation.addend as u32,
            ] {
                push_u32(&mut out, word);
            }
        }
        for symbol in &self.symbols {
            for word in [
                symbol.identity_hash_lo,
                symbol.identity_hash_hi,
                symbol.identity_byte_start,
                symbol.identity_byte_len,
                symbol.kind as u32,
                symbol.function_index,
                symbol.size,
                symbol.flags,
            ] {
                push_u32(&mut out, word);
            }
        }
        out.extend_from_slice(&self.identity_bytes);
        Ok(out)
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        if bytes.get(..8) != Some(&GPU_WASM_OBJECT_MAGIC) {
            return Err("Wasm object magic is invalid".into());
        }
        let mut cursor = 8;
        let header: Vec<u32> = (0..HEADER_U32S)
            .map(|_| read_u32(bytes, &mut cursor))
            .collect::<Result<_, _>>()?;
        let mut functions = Vec::with_capacity(header[4] as usize);
        for _ in 0..header[4] {
            let w: Vec<u32> = (0..FUNCTION_U32S)
                .map(|_| read_u32(bytes, &mut cursor))
                .collect::<Result<_, _>>()?;
            functions.push(GpuWasmFunctionRecord {
                type_byte_start: w[0],
                type_byte_len: w[1],
                body_byte_start: w[2],
                body_byte_len: w[3],
                symbol_index: w[4],
                flags: w[5],
            });
        }
        let type_bytes = take_bytes(bytes, &mut cursor, header[5] as usize)?.to_vec();
        let body_bytes = take_bytes(bytes, &mut cursor, header[6] as usize)?.to_vec();
        let mut relocations = Vec::with_capacity(header[7] as usize);
        for _ in 0..header[7] {
            let w: Vec<u32> = (0..RELOCATION_U32S)
                .map(|_| read_u32(bytes, &mut cursor))
                .collect::<Result<_, _>>()?;
            relocations.push(GpuWasmRelocationRecord {
                body_byte_offset: w[0],
                target_kind: GpuWasmRelocationTargetKind::from_u32(w[1])?,
                target_index: w[2],
                addend: w[3] as i32,
            });
        }
        let mut symbols = Vec::with_capacity(header[8] as usize);
        for _ in 0..header[8] {
            let w: Vec<u32> = (0..SYMBOL_U32S)
                .map(|_| read_u32(bytes, &mut cursor))
                .collect::<Result<_, _>>()?;
            symbols.push(GpuWasmObjectSymbolRecord {
                identity_hash_lo: w[0],
                identity_hash_hi: w[1],
                identity_byte_start: w[2],
                identity_byte_len: w[3],
                kind: GpuWasmSymbolKind::from_u32(w[4])?,
                function_index: w[5],
                size: w[6],
                flags: w[7],
            });
        }
        let identity_bytes = take_bytes(bytes, &mut cursor, header[9] as usize)?.to_vec();
        if cursor != bytes.len() {
            return Err("Wasm object has trailing bytes".into());
        }
        let object = Self {
            version: header[0],
            library_id: header[1],
            unit_id: header[2],
            entry_function: (header[3] != u32::MAX).then_some(header[3]),
            functions,
            type_bytes,
            body_bytes,
            relocations,
            symbols,
            identity_bytes,
        };
        object.validate()?;
        Ok(object)
    }
}

fn checked_range(
    label: &str,
    index: usize,
    start: u32,
    len: u32,
    total: usize,
) -> Result<std::ops::Range<usize>, String> {
    let start = start as usize;
    let end = start
        .checked_add(len as usize)
        .ok_or_else(|| format!("Wasm object {label} {index} range overflows"))?;
    if len == 0 || end > total {
        return Err(format!(
            "Wasm object {label} {index} range {start}..{end} is invalid"
        ));
    }
    Ok(start..end)
}

fn decode_padded_u32(bytes: &[u8]) -> Result<u32, String> {
    if bytes.len() != 5
        || bytes[..4].iter().any(|byte| byte & 0x80 == 0)
        || bytes[4] & 0x80 != 0
        || bytes[4] & 0x70 != 0
    {
        return Err("expected a maximally padded five-byte varuint32".into());
    }
    Ok((bytes[0] as u32 & 0x7f)
        | ((bytes[1] as u32 & 0x7f) << 7)
        | ((bytes[2] as u32 & 0x7f) << 14)
        | ((bytes[3] as u32 & 0x7f) << 21)
        | ((bytes[4] as u32 & 0x0f) << 28))
}

fn push_u32(out: &mut Vec<u8>, word: u32) {
    out.extend_from_slice(&word.to_le_bytes());
}
fn read_u32(bytes: &[u8], cursor: &mut usize) -> Result<u32, String> {
    let raw = take_bytes(bytes, cursor, 4)?;
    Ok(u32::from_le_bytes(raw.try_into().expect("four bytes")))
}
fn take_bytes<'a>(bytes: &'a [u8], cursor: &mut usize, len: usize) -> Result<&'a [u8], String> {
    let end = cursor
        .checked_add(len)
        .ok_or_else(|| "Wasm object byte range overflows".to_string())?;
    let result = bytes
        .get(*cursor..end)
        .ok_or_else(|| "Wasm object is truncated".to_string())?;
    *cursor = end;
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn identity(words: [u32; 3]) -> Vec<u8> {
        words.into_iter().flat_map(u32::to_le_bytes).collect()
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

    fn fixture() -> GpuWasmRelocatableObject {
        let identity_bytes = identity([3, 4, 5]);
        let hash = stable_name_hash(&identity_bytes);
        let mut body_bytes = padded(8).to_vec();
        body_bytes.extend_from_slice(&[0, 0x10]);
        body_bytes.extend_from_slice(&padded(0));
        body_bytes.push(0x0b);
        GpuWasmRelocatableObject {
            version: GPU_WASM_OBJECT_VERSION,
            library_id: 3,
            unit_id: 4,
            entry_function: Some(0),
            functions: vec![GpuWasmFunctionRecord {
                type_byte_start: 0,
                type_byte_len: 3,
                body_byte_start: 0,
                body_byte_len: body_bytes.len() as u32,
                symbol_index: 0,
                flags: 0,
            }],
            type_bytes: vec![0x60, 0, 0],
            body_bytes,
            relocations: vec![GpuWasmRelocationRecord {
                body_byte_offset: 7,
                target_kind: GpuWasmRelocationTargetKind::Symbol,
                target_index: 0,
                addend: 0,
            }],
            symbols: vec![GpuWasmObjectSymbolRecord {
                identity_hash_lo: hash.0,
                identity_hash_hi: hash.1,
                identity_byte_start: 0,
                identity_byte_len: 12,
                kind: GpuWasmSymbolKind::Function,
                function_index: 0,
                size: 13,
                flags: 0,
            }],
            identity_bytes,
        }
    }

    #[test]
    fn object_round_trips() {
        let object = fixture();
        let bytes = object.to_bytes().unwrap();
        assert_eq!(
            GpuWasmRelocatableObject::from_bytes(&bytes).unwrap(),
            object
        );
    }

    #[test]
    fn rejects_non_padded_relocation_and_trailing_bytes() {
        let mut object = fixture();
        object.body_bytes[7] = 0;
        assert!(object.validate().unwrap_err().contains("padded LEB"));
        let mut bytes = fixture().to_bytes().unwrap();
        bytes.push(0);
        assert!(
            GpuWasmRelocatableObject::from_bytes(&bytes)
                .unwrap_err()
                .contains("trailing")
        );
    }

    #[test]
    fn private_function_does_not_require_a_persisted_symbol() {
        let mut object = fixture();
        object.functions[0].symbol_index = u32::MAX;
        object.relocations.clear();
        object.symbols.clear();
        object.identity_bytes.clear();
        object.validate().unwrap();
        let bytes = object.to_bytes().unwrap();
        assert_eq!(
            GpuWasmRelocatableObject::from_bytes(&bytes).unwrap(),
            object
        );
    }
}
