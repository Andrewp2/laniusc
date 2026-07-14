//! Stable relocatable object format produced by the GPU x86 backend.
//!
//! Section bytes and relocation rows are already materialized by shaders. The
//! host only validates and serializes this flat artifact; it does not inspect
//! instructions or reconstruct code-generation decisions.

use crate::compiler::stable_name_hash;

pub const GPU_X86_OBJECT_VERSION: u32 = 2;
const GPU_X86_OBJECT_MAGIC: [u8; 8] = *b"LNX86OBJ";
const HEADER_U32S: usize = 9;
const RELOCATION_U32S: usize = 8;
const SYMBOL_U32S: usize = 8;

/// Section referenced by an x86 object symbol or relocation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum GpuX86ObjectSection {
    Undefined = 0,
    Text = 1,
    Rodata = 2,
}

impl GpuX86ObjectSection {
    fn from_u32(value: u32) -> Result<Self, String> {
        match value {
            0 => Ok(Self::Undefined),
            1 => Ok(Self::Text),
            2 => Ok(Self::Rodata),
            _ => Err(format!("x86 object section tag {value} is invalid")),
        }
    }
}

/// Relocation operation emitted by the GPU backend.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum GpuX86RelocationKind {
    Rel32 = 1,
    CallRel32 = 2,
    Abs32 = 3,
}

impl GpuX86RelocationKind {
    fn from_u32(value: u32) -> Result<Self, String> {
        match value {
            1 => Ok(Self::Rel32),
            2 => Ok(Self::CallRel32),
            3 => Ok(Self::Abs32),
            _ => Err(format!("x86 object relocation kind {value} is invalid")),
        }
    }
}

/// Interpretation of a relocation target payload.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum GpuX86RelocationTargetKind {
    SectionOffset = 1,
    Symbol = 2,
}

impl GpuX86RelocationTargetKind {
    fn from_u32(value: u32) -> Result<Self, String> {
        match value {
            1 => Ok(Self::SectionOffset),
            2 => Ok(Self::Symbol),
            _ => Err(format!(
                "x86 object relocation target kind {value} is invalid"
            )),
        }
    }
}

/// One section-relative relocation. `target_index` is either a section tag or
/// an index into the object's symbol table, according to `target_kind`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuX86RelocationRecord {
    pub kind: GpuX86RelocationKind,
    pub site_section: GpuX86ObjectSection,
    pub site_offset: u32,
    pub target_kind: GpuX86RelocationTargetKind,
    pub target_index: u32,
    pub target_offset: u32,
    pub addend: i64,
}

/// One defined or undefined symbol. Identity bytes encode the complete
/// canonical declaration identity, rather than relying on a hash alone.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuX86ObjectSymbolRecord {
    pub identity_hash_lo: u32,
    pub identity_hash_hi: u32,
    pub identity_byte_start: u32,
    pub identity_byte_len: u32,
    pub section: GpuX86ObjectSection,
    pub offset: u32,
    pub size: u32,
    pub flags: u32,
}

/// Complete durable x86 codegen-unit artifact.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GpuX86RelocatableObject {
    pub version: u32,
    pub library_id: u32,
    pub unit_id: u32,
    pub entry_offset: Option<u32>,
    pub text: Vec<u8>,
    pub rodata: Vec<u8>,
    pub relocations: Vec<GpuX86RelocationRecord>,
    pub symbols: Vec<GpuX86ObjectSymbolRecord>,
    pub identity_bytes: Vec<u8>,
}

impl GpuX86RelocatableObject {
    /// Validates all section ranges, relocation targets, and collision-safe
    /// symbol identities.
    pub fn validate(&self) -> Result<(), String> {
        if self.version != GPU_X86_OBJECT_VERSION {
            return Err(format!(
                "x86 object version {} is unsupported; expected {}",
                self.version, GPU_X86_OBJECT_VERSION
            ));
        }
        checked_u32_len("text byte", self.text.len())?;
        checked_u32_len("rodata byte", self.rodata.len())?;
        checked_u32_len("relocation", self.relocations.len())?;
        checked_u32_len("symbol", self.symbols.len())?;
        checked_u32_len("identity byte", self.identity_bytes.len())?;
        if let Some(entry_offset) = self.entry_offset {
            if entry_offset as usize >= self.text.len() {
                return Err(format!(
                    "x86 object entry offset {entry_offset} exceeds text length {}",
                    self.text.len()
                ));
            }
        }

        for (index, relocation) in self.relocations.iter().enumerate() {
            let site_len = self.section_len(relocation.site_section).ok_or_else(|| {
                format!("x86 object relocation {index} has an undefined site section")
            })?;
            let site = relocation.site_offset as usize;
            if site.checked_add(4).is_none_or(|end| end > site_len) {
                return Err(format!(
                    "x86 object relocation {index} site {}..{} exceeds section length {site_len}",
                    site,
                    site.saturating_add(4)
                ));
            }
            match relocation.target_kind {
                GpuX86RelocationTargetKind::SectionOffset => {
                    let section = GpuX86ObjectSection::from_u32(relocation.target_index)?;
                    let target_len = self.section_len(section).ok_or_else(|| {
                        format!("x86 object relocation {index} targets an undefined section")
                    })?;
                    if relocation.target_offset as usize > target_len {
                        return Err(format!(
                            "x86 object relocation {index} target offset {} exceeds section length {target_len}",
                            relocation.target_offset
                        ));
                    }
                }
                GpuX86RelocationTargetKind::Symbol => {
                    if relocation.target_index as usize >= self.symbols.len() {
                        return Err(format!(
                            "x86 object relocation {index} symbol {} exceeds symbol count {}",
                            relocation.target_index,
                            self.symbols.len()
                        ));
                    }
                    if relocation.target_offset != 0 {
                        return Err(format!(
                            "x86 object relocation {index} symbol target has a nonzero section offset"
                        ));
                    }
                }
            }
        }

        for (index, symbol) in self.symbols.iter().enumerate() {
            let start = symbol.identity_byte_start as usize;
            let len = symbol.identity_byte_len as usize;
            let end = start.checked_add(len).ok_or_else(|| {
                format!("x86 object symbol {index} identity byte range overflows")
            })?;
            if len == 0 || end > self.identity_bytes.len() {
                return Err(format!(
                    "x86 object symbol {index} identity byte range {start}..{end} is invalid"
                ));
            }
            let expected = stable_name_hash(&self.identity_bytes[start..end]);
            if expected != (symbol.identity_hash_lo, symbol.identity_hash_hi) {
                return Err(format!(
                    "x86 object symbol {index} identity hash does not match its canonical bytes"
                ));
            }
            match symbol.section {
                GpuX86ObjectSection::Undefined => {
                    if symbol.offset != 0 || symbol.size != 0 {
                        return Err(format!(
                            "x86 object undefined symbol {index} has a section range"
                        ));
                    }
                }
                section => {
                    let section_len = self.section_len(section).expect("defined section");
                    let start = symbol.offset as usize;
                    let end = start.checked_add(symbol.size as usize).ok_or_else(|| {
                        format!("x86 object symbol {index} section range overflows")
                    })?;
                    if end > section_len {
                        return Err(format!(
                            "x86 object symbol {index} range {start}..{end} exceeds section length {section_len}"
                        ));
                    }
                }
            }
        }
        Ok(())
    }

    /// Serializes this object to the versioned binary artifact format.
    pub fn to_bytes(&self) -> Result<Vec<u8>, String> {
        self.validate()?;
        let capacity = 8usize
            .checked_add(HEADER_U32S * 4)
            .and_then(|n| n.checked_add(self.text.len()))
            .and_then(|n| n.checked_add(self.rodata.len()))
            .and_then(|n| {
                self.relocations
                    .len()
                    .checked_mul(RELOCATION_U32S * 4)
                    .and_then(|bytes| n.checked_add(bytes))
            })
            .and_then(|n| {
                self.symbols
                    .len()
                    .checked_mul(SYMBOL_U32S * 4)
                    .and_then(|bytes| n.checked_add(bytes))
            })
            .and_then(|n| n.checked_add(self.identity_bytes.len()))
            .ok_or_else(|| "x86 object serialized length overflows".to_string())?;
        let mut bytes = Vec::with_capacity(capacity);
        bytes.extend_from_slice(&GPU_X86_OBJECT_MAGIC);
        for word in [
            self.version,
            self.library_id,
            self.unit_id,
            self.entry_offset.unwrap_or(u32::MAX),
            self.text.len() as u32,
            self.rodata.len() as u32,
            self.relocations.len() as u32,
            self.symbols.len() as u32,
            self.identity_bytes.len() as u32,
        ] {
            push_u32(&mut bytes, word);
        }
        bytes.extend_from_slice(&self.text);
        bytes.extend_from_slice(&self.rodata);
        for relocation in &self.relocations {
            for word in [
                relocation.kind as u32,
                relocation.site_section as u32,
                relocation.site_offset,
                relocation.target_kind as u32,
                relocation.target_index,
                relocation.target_offset,
                relocation.addend as u64 as u32,
                ((relocation.addend as u64) >> 32) as u32,
            ] {
                push_u32(&mut bytes, word);
            }
        }
        for symbol in &self.symbols {
            for word in [
                symbol.identity_hash_lo,
                symbol.identity_hash_hi,
                symbol.identity_byte_start,
                symbol.identity_byte_len,
                symbol.section as u32,
                symbol.offset,
                symbol.size,
                symbol.flags,
            ] {
                push_u32(&mut bytes, word);
            }
        }
        bytes.extend_from_slice(&self.identity_bytes);
        Ok(bytes)
    }

    /// Parses and validates one complete binary object artifact.
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() < 8 + HEADER_U32S * 4 || bytes[..8] != GPU_X86_OBJECT_MAGIC {
            return Err("x86 object header is missing or invalid".to_string());
        }
        let mut cursor = 8usize;
        let version = read_u32(bytes, &mut cursor)?;
        let library_id = read_u32(bytes, &mut cursor)?;
        let unit_id = read_u32(bytes, &mut cursor)?;
        let entry_offset = match read_u32(bytes, &mut cursor)? {
            u32::MAX => None,
            offset => Some(offset),
        };
        let text_len = read_count(bytes, &mut cursor, "text byte")?;
        let rodata_len = read_count(bytes, &mut cursor, "rodata byte")?;
        let relocation_count = read_count(bytes, &mut cursor, "relocation")?;
        let symbol_count = read_count(bytes, &mut cursor, "symbol")?;
        let identity_len = read_count(bytes, &mut cursor, "identity byte")?;

        let text = read_bytes(bytes, &mut cursor, text_len, "text")?.to_vec();
        let rodata = read_bytes(bytes, &mut cursor, rodata_len, "rodata")?.to_vec();
        let mut relocations = Vec::with_capacity(relocation_count);
        for _ in 0..relocation_count {
            let kind = GpuX86RelocationKind::from_u32(read_u32(bytes, &mut cursor)?)?;
            let site_section = GpuX86ObjectSection::from_u32(read_u32(bytes, &mut cursor)?)?;
            let site_offset = read_u32(bytes, &mut cursor)?;
            let target_kind = GpuX86RelocationTargetKind::from_u32(read_u32(bytes, &mut cursor)?)?;
            let target_index = read_u32(bytes, &mut cursor)?;
            let target_offset = read_u32(bytes, &mut cursor)?;
            let addend_lo = read_u32(bytes, &mut cursor)? as u64;
            let addend_hi = read_u32(bytes, &mut cursor)? as u64;
            relocations.push(GpuX86RelocationRecord {
                kind,
                site_section,
                site_offset,
                target_kind,
                target_index,
                target_offset,
                addend: ((addend_hi << 32) | addend_lo) as i64,
            });
        }
        let mut symbols = Vec::with_capacity(symbol_count);
        for _ in 0..symbol_count {
            symbols.push(GpuX86ObjectSymbolRecord {
                identity_hash_lo: read_u32(bytes, &mut cursor)?,
                identity_hash_hi: read_u32(bytes, &mut cursor)?,
                identity_byte_start: read_u32(bytes, &mut cursor)?,
                identity_byte_len: read_u32(bytes, &mut cursor)?,
                section: GpuX86ObjectSection::from_u32(read_u32(bytes, &mut cursor)?)?,
                offset: read_u32(bytes, &mut cursor)?,
                size: read_u32(bytes, &mut cursor)?,
                flags: read_u32(bytes, &mut cursor)?,
            });
        }
        let identity_bytes = read_bytes(bytes, &mut cursor, identity_len, "identity")?.to_vec();
        if cursor != bytes.len() {
            return Err(format!(
                "x86 object has {} trailing bytes",
                bytes.len() - cursor
            ));
        }
        let object = Self {
            version,
            library_id,
            unit_id,
            entry_offset,
            text,
            rodata,
            relocations,
            symbols,
            identity_bytes,
        };
        object.validate()?;
        Ok(object)
    }

    fn section_len(&self, section: GpuX86ObjectSection) -> Option<usize> {
        match section {
            GpuX86ObjectSection::Undefined => None,
            GpuX86ObjectSection::Text => Some(self.text.len()),
            GpuX86ObjectSection::Rodata => Some(self.rodata.len()),
        }
    }
}

fn checked_u32_len(label: &str, len: usize) -> Result<(), String> {
    u32::try_from(len)
        .map(|_| ())
        .map_err(|_| format!("x86 object {label} count {len} exceeds u32"))
}

fn push_u32(bytes: &mut Vec<u8>, value: u32) {
    bytes.extend_from_slice(&value.to_le_bytes());
}

fn read_u32(bytes: &[u8], cursor: &mut usize) -> Result<u32, String> {
    let raw = read_bytes(bytes, cursor, 4, "u32")?;
    Ok(u32::from_le_bytes(raw.try_into().expect("four bytes")))
}

fn read_count(bytes: &[u8], cursor: &mut usize, label: &str) -> Result<usize, String> {
    usize::try_from(read_u32(bytes, cursor)?)
        .map_err(|_| format!("x86 object {label} count does not fit usize"))
}

fn read_bytes<'a>(
    bytes: &'a [u8],
    cursor: &mut usize,
    len: usize,
    label: &str,
) -> Result<&'a [u8], String> {
    let end = cursor
        .checked_add(len)
        .ok_or_else(|| format!("x86 object {label} range overflows"))?;
    let slice = bytes
        .get(*cursor..end)
        .ok_or_else(|| format!("x86 object is truncated in {label}"))?;
    *cursor = end;
    Ok(slice)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn object_fixture() -> GpuX86RelocatableObject {
        let identity_bytes = b"library:7/module:math/function:add(i32,i32)->i32".to_vec();
        let (identity_hash_lo, identity_hash_hi) = stable_name_hash(&identity_bytes);
        GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: 7,
            unit_id: 11,
            entry_offset: Some(0),
            text: vec![0xe8, 0, 0, 0, 0, 0xc3],
            rodata: b"hello\0".to_vec(),
            relocations: vec![GpuX86RelocationRecord {
                kind: GpuX86RelocationKind::CallRel32,
                site_section: GpuX86ObjectSection::Text,
                site_offset: 1,
                target_kind: GpuX86RelocationTargetKind::Symbol,
                target_index: 0,
                target_offset: 0,
                addend: -4,
            }],
            symbols: vec![GpuX86ObjectSymbolRecord {
                identity_hash_lo,
                identity_hash_hi,
                identity_byte_start: 0,
                identity_byte_len: identity_bytes.len() as u32,
                section: GpuX86ObjectSection::Undefined,
                offset: 0,
                size: 0,
                flags: 0,
            }],
            identity_bytes,
        }
    }

    #[test]
    fn x86_object_binary_roundtrip_preserves_sections_relocations_and_symbols() {
        let object = object_fixture();
        let bytes = object.to_bytes().expect("serialize object");
        assert_eq!(
            GpuX86RelocatableObject::from_bytes(&bytes).expect("parse object"),
            object
        );
    }

    #[test]
    fn x86_object_validation_rejects_corrupt_ranges_and_identity_hashes() {
        let mut bad_site = object_fixture();
        bad_site.relocations[0].site_offset = bad_site.text.len() as u32;
        assert!(bad_site.validate().is_err());

        let mut bad_symbol = object_fixture();
        bad_symbol.symbols[0].identity_hash_lo ^= 1;
        assert!(bad_symbol.validate().is_err());

        let bytes = object_fixture().to_bytes().expect("serialize object");
        assert!(GpuX86RelocatableObject::from_bytes(&bytes[..bytes.len() - 1]).is_err());
        let mut trailing = bytes;
        trailing.push(0);
        assert!(GpuX86RelocatableObject::from_bytes(&trailing).is_err());
    }
}
