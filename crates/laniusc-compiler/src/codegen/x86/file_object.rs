//! Private storage for native objects whose opaque section bytes stay on disk.
//!
//! Admission and specialization retain the ordinary symbol metadata. Only the
//! payload moves; neither spilling nor exporting interprets instructions.

use std::{
    fs::{self, File},
    io::{Read, Seek, SeekFrom, Write},
    path::PathBuf,
    sync::Arc,
};

use super::{
    GPU_X86_CRT_MAIN_BRIDGE_BYTES,
    GPU_X86_OBJECT_HEADER_BYTES,
    GpuX86ObjectSymbolRecord,
    GpuX86RelocatableObject,
    GpuX86RelocatableObjectLayout,
    GpuX86RelocationRecord,
    object::validate_link_object_columns,
};

/// Metadata may change during checked specialization; payload bytes are frozen.
/// Clones share a guarded file while owning independent metadata columns.
#[derive(Clone, Debug)]
pub(crate) struct GpuX86FileObject {
    pub layout: GpuX86RelocatableObjectLayout,
    pub relocations: Vec<GpuX86RelocationRecord>,
    pub symbols: Vec<GpuX86ObjectSymbolRecord>,
    pub identity_bytes: Vec<u8>,
    payload: Arc<FilePayload>,
}

// Equality preserves the identity of the frozen payload; it does not read code.
impl PartialEq for GpuX86FileObject {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.payload, &other.payload)
            && self.layout == other.layout
            && self.relocations == other.relocations
            && self.symbols == other.symbols
            && self.identity_bytes == other.identity_bytes
    }
}
impl Eq for GpuX86FileObject {}

#[derive(Debug)]
struct FilePayload {
    directory: PrivateDirectory,
    text_len: u32,
    rodata_len: u32,
    original_entry_offset: Option<u32>,
}

#[derive(Debug)]
struct PrivateDirectory(PathBuf);

impl PrivateDirectory {
    fn create() -> Result<Self, String> {
        let parent = fs::canonicalize(std::env::temp_dir())
            .map_err(|error| format!("resolve native object temporary directory: {error}"))?;
        for _ in 0..16 {
            let path = parent.join(format!(
                "lanius-native-object-{}-{:032x}",
                std::process::id(),
                rand::random::<u128>(),
            ));
            let mut builder = fs::DirBuilder::new();
            #[cfg(unix)]
            {
                use std::os::unix::fs::DirBuilderExt;
                builder.mode(0o700);
            }
            match builder.create(&path) {
                Ok(()) => return Ok(Self(path)),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(format!("create native object directory: {error}")),
            }
        }
        Err("could not create a unique native object directory".into())
    }
}

impl Drop for PrivateDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

impl GpuX86FileObject {
    /// Consumes one accepted object and releases both section vectors after
    /// writing them once. No serialized copy of the complete object is built.
    pub(crate) fn spill(object: GpuX86RelocatableObject) -> Result<Self, String> {
        object.validate()?;
        let text_len = object.text.len() as u32;
        let rodata_len = object.rodata.len() as u32;
        let directory = PrivateDirectory::create()?;
        let path = directory.0.join("payload");
        let mut options = fs::OpenOptions::new();
        options.read(true).write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options
            .open(&path)
            .map_err(|error| format!("create private native object payload: {error}"))?;
        file.write_all(&object.text)
            .and_then(|()| file.write_all(&object.rodata))
            .map_err(|error| format!("spill native object payload: {error}"))?;
        // Close the writer before retention. Opening only the current payload
        // during export avoids keeping one descriptor per program object.
        let mut permissions = file
            .metadata()
            .map_err(|error| format!("stat spilled native object: {error}"))?
            .permissions();
        permissions.set_readonly(true);
        file.set_permissions(permissions)
            .map_err(|error| format!("protect native object payload: {error}"))?;
        drop(file);
        let mut stored = Self {
            layout: GpuX86RelocatableObjectLayout {
                version: object.version,
                library_id: object.library_id,
                unit_id: object.unit_id,
                entry_offset: object.entry_offset,
                text_byte_len: text_len,
                rodata_byte_len: rodata_len,
                relocation_count: 0,
                symbol_count: 0,
                identity_byte_len: 0,
                serialized_byte_len: 0,
            },
            relocations: object.relocations,
            symbols: object.symbols,
            identity_bytes: object.identity_bytes,
            payload: Arc::new(FilePayload {
                directory,
                text_len,
                rodata_len,
                original_entry_offset: object.entry_offset,
            }),
        };
        stored.refresh_layout()?;
        Ok(stored)
    }

    /// Refresh counts after specialization changes identities or definitions.
    pub(crate) fn refresh_layout(&mut self) -> Result<(), String> {
        self.layout.relocation_count = u32::try_from(self.relocations.len())
            .map_err(|_| "native relocation count exceeds u32")?;
        self.layout.symbol_count =
            u32::try_from(self.symbols.len()).map_err(|_| "native symbol count exceeds u32")?;
        self.layout.identity_byte_len = u32::try_from(self.identity_bytes.len())
            .map_err(|_| "native identity bytes exceed u32")?;
        self.layout.serialized_byte_len = GPU_X86_OBJECT_HEADER_BYTES as u64
            + u64::from(self.layout.text_byte_len)
            + u64::from(self.layout.rodata_byte_len)
            + u64::from(self.layout.relocation_count) * 32
            + u64::from(self.layout.symbol_count) * 32
            + u64::from(self.layout.identity_byte_len);
        Ok(())
    }

    pub(crate) fn validate(&self) -> Result<(), String> {
        if self.layout.entry_offset.is_some()
            && self.layout.entry_offset != self.payload.original_entry_offset
        {
            return Err(
                "native file object cannot promote or replace its original entry receipt".into(),
            );
        }
        if self.layout.text_byte_len != self.payload.text_len
            || self.layout.rodata_byte_len != self.payload.rodata_len
            || self.layout.relocation_count as usize != self.relocations.len()
            || self.layout.symbol_count as usize != self.symbols.len()
            || self.layout.identity_byte_len as usize != self.identity_bytes.len()
            || self.layout.serialized_byte_len
                != GPU_X86_OBJECT_HEADER_BYTES as u64
                    + u64::from(self.layout.text_byte_len)
                    + u64::from(self.layout.rodata_byte_len)
                    + self.relocations.len() as u64 * 32
                    + self.symbols.len() as u64 * 32
                    + self.identity_bytes.len() as u64
        {
            return Err(
                "native file object metadata disagrees with its frozen payload/layout".into(),
            );
        }
        validate_link_object_columns(
            self.layout.version,
            self.layout.entry_offset,
            self.layout.text_byte_len as usize,
            self.layout.rodata_byte_len as usize,
            &self.relocations,
            &self.symbols,
            &self.identity_bytes,
        )?;
        let actual = fs::metadata(self.payload.directory.0.join("payload"))
            .map_err(|error| format!("stat native object payload: {error}"))?
            .len();
        if actual != u64::from(self.payload.text_len) + u64::from(self.payload.rodata_len) {
            return Err("native object payload length changed after spilling".into());
        }
        Ok(())
    }

    pub(crate) fn crt_main_bridge_range(&self) -> Result<Option<std::ops::Range<u32>>, String> {
        self.validate()?;
        if self.layout.entry_offset.is_none() {
            return Ok(None);
        }
        let end = self.layout.text_byte_len;
        let start = end
            .checked_sub(GPU_X86_CRT_MAIN_BRIDGE_BYTES)
            .ok_or("x86 object is too short for its CRT main bridge")?;
        Ok(Some(start..end))
    }

    pub(crate) fn copy_text_to<W: Write>(&self, output: &mut W) -> Result<u64, String> {
        self.copy_range(0, self.payload.text_len, output)
    }

    pub(crate) fn copy_rodata_to<W: Write>(&self, output: &mut W) -> Result<u64, String> {
        self.copy_range(
            u64::from(self.payload.text_len),
            self.payload.rodata_len,
            output,
        )
    }

    fn copy_range<W: Write>(&self, start: u64, len: u32, output: &mut W) -> Result<u64, String> {
        let mut file = File::open(self.payload.directory.0.join("payload"))
            .map_err(|error| format!("open native object payload: {error}"))?;
        file.seek(SeekFrom::Start(start))
            .map_err(|error| format!("seek native object payload: {error}"))?;
        let copied = std::io::copy(&mut file.take(u64::from(len)), output)
            .map_err(|error| format!("copy native object payload: {error}"))?;
        if copied != u64::from(len) {
            return Err("native object payload was truncated".into());
        }
        Ok(copied)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::codegen::x86::{GPU_X86_OBJECT_VERSION, GpuX86ObjectSection};

    fn object() -> GpuX86RelocatableObject {
        let identity_bytes = [7u32, 11, 13]
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect::<Vec<_>>();
        let (identity_hash_lo, identity_hash_hi) =
            crate::compiler::stable_name_hash(&identity_bytes);
        GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: 7,
            unit_id: 11,
            entry_offset: None,
            text: vec![0, 255, 0x90, 0xc3],
            rodata: vec![0, 128, 255, 0],
            relocations: vec![],
            symbols: vec![GpuX86ObjectSymbolRecord {
                identity_hash_lo,
                identity_hash_hi,
                identity_byte_start: 0,
                identity_byte_len: 12,
                section: GpuX86ObjectSection::Text,
                offset: 0,
                size: 4,
                flags: 0,
            }],
            identity_bytes,
        }
    }

    #[test]
    fn spill_preserves_opaque_sections_and_clone_lifetime() {
        let stored = GpuX86FileObject::spill(object()).unwrap();
        let directory = stored.payload.directory.0.clone();
        let mut cloned = stored.clone();
        drop(stored);
        cloned.layout.unit_id = 99;
        cloned.validate().unwrap();
        let mut text = Vec::new();
        let mut rodata = Vec::new();
        cloned.copy_text_to(&mut text).unwrap();
        cloned.copy_rodata_to(&mut rodata).unwrap();
        assert_eq!(text, [0, 255, 0x90, 0xc3]);
        assert_eq!(rodata, [0, 128, 255, 0]);
        assert!(directory.is_dir());
        drop(cloned);
        assert!(!directory.exists());
    }

    #[test]
    fn file_storage_cannot_promote_an_object_to_entry_or_change_the_entry() {
        let mut stored = GpuX86FileObject::spill(object()).unwrap();
        stored.layout.entry_offset = Some(0);
        assert!(stored.validate().unwrap_err().contains("entry receipt"));
        let mut entry = object();
        entry.entry_offset = Some(0);
        let mut stored = GpuX86FileObject::spill(entry).unwrap();
        stored.layout.entry_offset = Some(1);
        assert!(stored.validate().unwrap_err().contains("entry receipt"));
        stored.layout.entry_offset = None;
        stored.validate().unwrap();
    }

    #[test]
    fn spilled_payload_truncation_and_forged_layout_reject() {
        let mut stored = GpuX86FileObject::spill(object()).unwrap();
        stored.layout.text_byte_len += 1;
        assert!(stored.validate().unwrap_err().contains("frozen payload"));
        stored.layout.text_byte_len -= 1;
        let path = stored.payload.directory.0.join("payload");
        let mut permissions = fs::metadata(&path).unwrap().permissions();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            permissions.set_mode(0o600);
        }
        #[cfg(not(unix))]
        permissions.set_readonly(false);
        fs::set_permissions(&path, permissions).unwrap();
        fs::OpenOptions::new()
            .write(true)
            .open(path)
            .unwrap()
            .set_len(2)
            .unwrap();
        assert!(stored.validate().unwrap_err().contains("length changed"));
        assert!(
            stored
                .copy_text_to(&mut Vec::new())
                .unwrap_err()
                .contains("truncated")
        );
    }
}
