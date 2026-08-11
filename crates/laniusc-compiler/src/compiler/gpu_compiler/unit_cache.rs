use std::collections::HashMap;

use super::{
    GpuCompiler,
    GpuSemanticInterfaceArtifact,
    SourcePackArtifactTarget,
    typecheck::{CompiledSourcePackObject, CompiledSourcePackUnit},
};
use crate::compiler::ExplicitSourcePathFile;

const DEFAULT_COMPILED_UNIT_CACHE_BYTES: usize = 256 * 1024 * 1024;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub(super) struct CompiledUnitCacheKey {
    target: u8,
    library_id: u32,
    unit_id: u32,
    content_hash: blake3::Hash,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub(super) struct CompiledUnitCacheHintKey {
    target: u8,
    library_id: u32,
    unit_id: u32,
    content_hash: blake3::Hash,
}

impl CompiledUnitCacheKey {
    pub(super) fn new(
        target: SourcePackArtifactTarget,
        library_id: u32,
        unit_id: u32,
        sources: &[String],
        dependency_interfaces: &[Vec<GpuSemanticInterfaceArtifact>],
    ) -> Result<Self, String> {
        let target = target_tag(target);
        let mut content = blake3::Hasher::new();
        content.update(b"laniusc-compiled-unit-cache-key-v1");
        hash_len(&mut content, sources.len());
        for source in sources {
            hash_bytes(&mut content, source.as_bytes());
        }
        hash_dependency_interfaces(&mut content, dependency_interfaces)?;
        Ok(Self {
            target,
            library_id,
            unit_id,
            content_hash: content.finalize(),
        })
    }
}

impl CompiledUnitCacheHintKey {
    pub(super) fn new(
        target: SourcePackArtifactTarget,
        library_id: u32,
        unit_id: u32,
        source_files: &[ExplicitSourcePathFile],
        dependency_interfaces: &[Vec<GpuSemanticInterfaceArtifact>],
    ) -> Result<Option<Self>, String> {
        let target = target_tag(target);
        let mut content = blake3::Hasher::new();
        content.update(b"laniusc-compiled-unit-cache-hint-v1");
        hash_len(&mut content, source_files.len());
        for file in source_files {
            let Some(modified_unix_nanos) = file.modified_unix_nanos else {
                return Ok(None);
            };
            hash_bytes(&mut content, file.path.as_os_str().as_encoded_bytes());
            let byte_len = u64::try_from(file.byte_len)
                .map_err(|_| "source-file byte length does not fit cache hint".to_string())?;
            content.update(&byte_len.to_le_bytes());
            content.update(&modified_unix_nanos.to_le_bytes());
        }
        hash_dependency_interfaces(&mut content, dependency_interfaces)?;
        Ok(Some(Self {
            target,
            library_id,
            unit_id,
            content_hash: content.finalize(),
        }))
    }
}

fn target_tag(target: SourcePackArtifactTarget) -> u8 {
    match target {
        SourcePackArtifactTarget::Generic => 0,
        SourcePackArtifactTarget::Wasm => 1,
        SourcePackArtifactTarget::X86_64 => 2,
    }
}

fn hash_dependency_interfaces(
    content: &mut blake3::Hasher,
    dependency_interfaces: &[Vec<GpuSemanticInterfaceArtifact>],
) -> Result<(), String> {
    hash_len(content, dependency_interfaces.len());
    for page in dependency_interfaces {
        hash_len(content, page.len());
        for interface in page {
            hash_bytes(content, &interface.to_bytes()?);
        }
    }
    Ok(())
}

fn hash_len(hasher: &mut blake3::Hasher, len: usize) {
    hasher.update(&(len as u64).to_le_bytes());
}

fn hash_bytes(hasher: &mut blake3::Hasher, bytes: &[u8]) {
    hash_len(hasher, bytes.len());
    hasher.update(bytes);
}

#[derive(Clone)]
struct CachedCompiledUnit {
    value: CompiledSourcePackUnit,
    resident_bytes: usize,
    last_used: u64,
}

pub(super) struct CompiledUnitCache {
    entries: HashMap<CompiledUnitCacheKey, CachedCompiledUnit>,
    hints: HashMap<CompiledUnitCacheHintKey, CompiledUnitCacheKey>,
    resident_bytes: usize,
    maximum_bytes: usize,
    clock: u64,
    hits: u64,
    misses: u64,
    evictions: u64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct CompiledUnitCacheStats {
    pub hits: u64,
    pub misses: u64,
    pub evictions: u64,
    pub entries: usize,
    pub resident_bytes: usize,
}

impl Default for CompiledUnitCache {
    fn default() -> Self {
        Self {
            entries: HashMap::new(),
            hints: HashMap::new(),
            resident_bytes: 0,
            maximum_bytes: DEFAULT_COMPILED_UNIT_CACHE_BYTES,
            clock: 0,
            hits: 0,
            misses: 0,
            evictions: 0,
        }
    }
}

impl CompiledUnitCache {
    fn get(&mut self, key: &CompiledUnitCacheKey) -> Option<CompiledSourcePackUnit> {
        self.clock = self.clock.wrapping_add(1);
        let entry = self.entries.get_mut(key);
        let Some(entry) = entry else {
            self.misses = self.misses.saturating_add(1);
            return None;
        };
        self.hits = self.hits.saturating_add(1);
        entry.last_used = self.clock;
        Some(entry.value.clone())
    }

    fn insert(&mut self, key: CompiledUnitCacheKey, value: CompiledSourcePackUnit) {
        self.clock = self.clock.wrapping_add(1);
        let resident_bytes =
            std::mem::size_of::<CompiledUnitCacheKey>().saturating_add(value.byte_len());
        if let Some(entry) = self.entries.get_mut(&key) {
            self.resident_bytes = self.resident_bytes.saturating_sub(entry.resident_bytes);
            *entry = CachedCompiledUnit {
                value,
                resident_bytes,
                last_used: self.clock,
            };
        } else {
            self.entries.insert(
                key,
                CachedCompiledUnit {
                    value,
                    resident_bytes,
                    last_used: self.clock,
                },
            );
        }
        self.resident_bytes = self.resident_bytes.saturating_add(resident_bytes);
        self.evict_to_budget();
    }

    fn get_by_hint(&mut self, hint: &CompiledUnitCacheHintKey) -> Option<CompiledSourcePackUnit> {
        let Some(key) = self.hints.get(hint).cloned() else {
            return None;
        };
        self.get(&key)
    }

    fn insert_hint(&mut self, hint: CompiledUnitCacheHintKey, key: CompiledUnitCacheKey) {
        self.hints.insert(hint, key);
    }

    fn evict_to_budget(&mut self) {
        while self.resident_bytes > self.maximum_bytes {
            let oldest = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.last_used)
                .map(|(key, entry)| (key.clone(), entry.last_used));
            let Some((key, _)) = oldest else {
                self.resident_bytes = 0;
                break;
            };
            let removed = self
                .entries
                .remove(&key)
                .expect("cache eviction selected a missing entry");
            self.resident_bytes = self.resident_bytes.saturating_sub(removed.resident_bytes);
            self.hints.retain(|_, cached_key| cached_key != &key);
            self.evictions = self.evictions.saturating_add(1);
        }
    }

    fn stats(&self) -> CompiledUnitCacheStats {
        CompiledUnitCacheStats {
            hits: self.hits,
            misses: self.misses,
            evictions: self.evictions,
            entries: self.entries.len(),
            resident_bytes: self.resident_bytes,
        }
    }
}

impl CompiledSourcePackUnit {
    fn byte_len(&self) -> usize {
        let interface = self.interface.to_bytes().map_or(0, |bytes| bytes.len());
        let object = match &self.object {
            CompiledSourcePackObject::X86_64(object) => {
                object.to_bytes().map_or(0, |bytes| bytes.len())
            }
            CompiledSourcePackObject::Wasm(object) => {
                object.to_bytes().map_or(0, |bytes| bytes.len())
            }
        };
        interface.saturating_add(object)
    }
}

impl GpuCompiler<'_> {
    pub(super) fn cached_compiled_unit_by_hint(
        &self,
        hint: &CompiledUnitCacheHintKey,
    ) -> Option<CompiledSourcePackUnit> {
        self.compiled_unit_cache
            .lock()
            .expect("compiled-unit cache mutex poisoned")
            .get_by_hint(hint)
    }

    pub(super) fn cached_compiled_unit(
        &self,
        key: &CompiledUnitCacheKey,
    ) -> Option<CompiledSourcePackUnit> {
        self.compiled_unit_cache
            .lock()
            .expect("compiled-unit cache mutex poisoned")
            .get(key)
    }

    pub(super) fn cache_compiled_unit(
        &self,
        hint: CompiledUnitCacheHintKey,
        key: CompiledUnitCacheKey,
        value: CompiledSourcePackUnit,
    ) {
        let mut cache = self
            .compiled_unit_cache
            .lock()
            .expect("compiled-unit cache mutex poisoned");
        cache.insert(key.clone(), value);
        cache.insert_hint(hint, key);
    }

    pub(crate) fn compiled_unit_cache_stats(&self) -> CompiledUnitCacheStats {
        self.compiled_unit_cache
            .lock()
            .expect("compiled-unit cache mutex poisoned")
            .stats()
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    #[test]
    fn cache_key_uses_source_and_dependency_contents() {
        let base = CompiledUnitCacheKey::new(
            SourcePackArtifactTarget::X86_64,
            1,
            2,
            &["fn value() -> i32 { return 1; }".into()],
            &[],
        )
        .unwrap();
        let changed = CompiledUnitCacheKey::new(
            SourcePackArtifactTarget::X86_64,
            1,
            2,
            &["fn value() -> i32 { return 2; }".into()],
            &[],
        )
        .unwrap();
        assert_ne!(base, changed);
        assert_ne!(base.content_hash, changed.content_hash);
    }

    #[test]
    fn cache_hint_tracks_path_length_and_modification_identity() {
        let file = ExplicitSourcePathFile {
            library_id: 7,
            path: PathBuf::from("src/value.lani"),
            byte_len: 31,
            modified_unix_nanos: Some(100),
            line_count: None,
        };
        let base = CompiledUnitCacheHintKey::new(
            SourcePackArtifactTarget::X86_64,
            7,
            2,
            std::slice::from_ref(&file),
            &[],
        )
        .unwrap()
        .unwrap();
        let mut changed = file.clone();
        changed.modified_unix_nanos = Some(101);
        let changed =
            CompiledUnitCacheHintKey::new(SourcePackArtifactTarget::X86_64, 7, 2, &[changed], &[])
                .unwrap()
                .unwrap();
        assert_ne!(base, changed);
    }

    #[test]
    fn cache_hint_is_disabled_without_reliable_modification_time() {
        let file = ExplicitSourcePathFile {
            library_id: 1,
            path: PathBuf::from("src/value.lani"),
            byte_len: 31,
            modified_unix_nanos: None,
            line_count: None,
        };
        assert!(
            CompiledUnitCacheHintKey::new(SourcePackArtifactTarget::Wasm, 1, 0, &[file], &[],)
                .unwrap()
                .is_none()
        );
    }
}
