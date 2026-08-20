use std::{collections::HashMap, sync::Arc};

use super::{
    GpuCompiler,
    GpuSemanticInterfaceArtifact,
    SourcePackArtifactTarget,
    typecheck::{CompiledSourcePackObject, CompiledSourcePackUnit},
};
use crate::compiler::{
    ExplicitSourcePathFile,
    SourcePackJob,
    read_explicit_source_path_files,
    source_pack_artifact_store_error,
};

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

    /// Reuses the identity already established for a filesystem-backed unit.
    ///
    /// Path-backed cache hits trust this identity before source contents are
    /// read. Reusing it after a miss avoids hashing every loaded source and
    /// serializing the same dependency interfaces a second time.
    pub(super) fn from_hint(hint: &CompiledUnitCacheHintKey) -> Self {
        Self {
            target: hint.target,
            library_id: hint.library_id,
            unit_id: hint.unit_id,
            content_hash: hint.content_hash,
        }
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
    value: Arc<CompiledSourcePackUnit>,
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

pub(super) struct CachedCompiledSourcePackUnit {
    pub value: Arc<CompiledSourcePackUnit>,
    pub cache_hit: bool,
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
    fn clear(&mut self) {
        self.entries.clear();
        self.hints.clear();
        self.resident_bytes = 0;
    }

    fn clear_except_library(&mut self, retained_library_id: u32) {
        self.entries
            .retain(|key, _| key.library_id == retained_library_id);
        self.hints.retain(|_, key| self.entries.contains_key(key));
        self.resident_bytes = self
            .entries
            .values()
            .map(|entry| entry.resident_bytes)
            .sum();
    }

    fn get(&mut self, key: &CompiledUnitCacheKey) -> Option<Arc<CompiledSourcePackUnit>> {
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

    fn insert(&mut self, key: CompiledUnitCacheKey, value: impl Into<Arc<CompiledSourcePackUnit>>) {
        let value = value.into();
        self.clock = self.clock.wrapping_add(1);
        let resident_bytes =
            std::mem::size_of::<CompiledUnitCacheKey>().saturating_add(value.resident_byte_len());
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

    fn get_by_hint(
        &mut self,
        hint: &CompiledUnitCacheHintKey,
    ) -> Option<Arc<CompiledSourcePackUnit>> {
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
    fn resident_byte_len(&self) -> usize {
        let mut bytes = std::mem::size_of::<Self>()
            .saturating_add(vector_resident_bytes(&self.interface.modules))
            .saturating_add(vector_resident_bytes(&self.interface.module_segments))
            .saturating_add(vector_resident_bytes(&self.interface.declarations))
            .saturating_add(vector_resident_bytes(&self.interface.types))
            .saturating_add(vector_resident_bytes(&self.interface.type_edges))
            .saturating_add(vector_resident_bytes(&self.interface.members))
            .saturating_add(vector_resident_bytes(&self.interface.name_bytes));
        bytes = match &self.object {
            CompiledSourcePackObject::X86_64(object) => bytes
                .saturating_add(vector_resident_bytes(&object.text))
                .saturating_add(vector_resident_bytes(&object.rodata))
                .saturating_add(vector_resident_bytes(&object.relocations))
                .saturating_add(vector_resident_bytes(&object.symbols))
                .saturating_add(vector_resident_bytes(&object.identity_bytes)),
            CompiledSourcePackObject::Wasm(object) => bytes
                .saturating_add(vector_resident_bytes(&object.functions))
                .saturating_add(vector_resident_bytes(&object.type_bytes))
                .saturating_add(vector_resident_bytes(&object.body_bytes))
                .saturating_add(vector_resident_bytes(&object.data_bytes))
                .saturating_add(vector_resident_bytes(&object.relocations))
                .saturating_add(vector_resident_bytes(&object.symbols))
                .saturating_add(vector_resident_bytes(&object.identity_bytes)),
        };
        bytes
    }
}

fn vector_resident_bytes<T>(values: &Vec<T>) -> usize {
    values.capacity().saturating_mul(std::mem::size_of::<T>())
}

impl GpuCompiler<'_> {
    /// Compiles or reuses one concrete path-backed source-pack unit.
    ///
    /// Both resident and file-backed project executors use this boundary so
    /// filesystem identity, dependency hashing, and cache ownership cannot
    /// diverge between the two storage policies.
    pub(super) async fn compile_cached_path_source_pack_unit(
        &self,
        target: SourcePackArtifactTarget,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_pages: &[Vec<GpuSemanticInterfaceArtifact>],
    ) -> Result<CachedCompiledSourcePackUnit, super::CompileError> {
        debug_assert_ne!(target, SourcePackArtifactTarget::Generic);
        let unit_id = u32::try_from(job.phase_unit_index).map_err(|_| {
            source_pack_artifact_store_error(format!(
                "source-pack semantic-interface job {} phase-unit index {} exceeds u32",
                job.job_index, job.phase_unit_index
            ))
        })?;
        let cache_hint = CompiledUnitCacheHintKey::new(
            target,
            job.library_id,
            unit_id,
            source_files,
            dependency_pages,
        )
        .map_err(source_pack_artifact_store_error)?;
        if let Some(value) = cache_hint
            .as_ref()
            .and_then(|hint| self.cached_compiled_unit_by_hint(hint))
        {
            return Ok(CachedCompiledSourcePackUnit {
                value,
                cache_hit: true,
            });
        }

        let sources =
            read_explicit_source_path_files("source-pack library-interface job", source_files)?;
        let cache_key = if let Some(hint) = cache_hint.as_ref() {
            CompiledUnitCacheKey::from_hint(hint)
        } else {
            CompiledUnitCacheKey::new(target, job.library_id, unit_id, &sources, dependency_pages)
                .map_err(source_pack_artifact_store_error)?
        };
        if let Some(value) = self.cached_compiled_unit(&cache_key) {
            return Ok(CachedCompiledSourcePackUnit {
                value,
                cache_hit: true,
            });
        }

        let value = Arc::new(
            self.compile_source_pack_unit_with_dependency_pages(
                &sources,
                job.library_id,
                unit_id,
                dependency_pages,
                target,
            )
            .await?,
        );
        self.cache_compiled_unit(cache_hint, cache_key, Arc::clone(&value));
        Ok(CachedCompiledSourcePackUnit {
            value,
            cache_hit: false,
        })
    }

    /// Drops compiled source-unit results without releasing GPU job capacity.
    ///
    /// This is intentionally separate from `release_resident_job_buffers`: a
    /// benchmark or daemon client can force a complete recompilation while
    /// retaining the workspace and bind groups established by an earlier job.
    pub(crate) fn clear_compiled_unit_cache(&self) {
        self.compiled_unit_cache
            .lock()
            .expect("compiled-unit cache mutex poisoned")
            .clear();
    }

    /// Drops project results while retaining the daemon entry loader's
    /// standard-library artifacts. That loader assigns library 0 to stdlib and
    /// library 1 to user sources; this operation is therefore daemon-specific
    /// and deliberately separate from the unconditional cache clear above.
    pub(crate) fn clear_project_compiled_unit_cache(&self) {
        self.compiled_unit_cache
            .lock()
            .expect("compiled-unit cache mutex poisoned")
            .clear_except_library(0);
    }

    pub(super) fn cached_compiled_unit_by_hint(
        &self,
        hint: &CompiledUnitCacheHintKey,
    ) -> Option<Arc<CompiledSourcePackUnit>> {
        self.compiled_unit_cache
            .lock()
            .expect("compiled-unit cache mutex poisoned")
            .get_by_hint(hint)
    }

    pub(super) fn cached_compiled_unit(
        &self,
        key: &CompiledUnitCacheKey,
    ) -> Option<Arc<CompiledSourcePackUnit>> {
        self.compiled_unit_cache
            .lock()
            .expect("compiled-unit cache mutex poisoned")
            .get(key)
    }

    pub(super) fn cache_compiled_unit(
        &self,
        hint: Option<CompiledUnitCacheHintKey>,
        key: CompiledUnitCacheKey,
        value: Arc<CompiledSourcePackUnit>,
    ) {
        let mut cache = self
            .compiled_unit_cache
            .lock()
            .expect("compiled-unit cache mutex poisoned");
        cache.insert(key.clone(), value);
        if let Some(hint) = hint {
            cache.insert_hint(hint, key);
        }
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
    fn filesystem_cache_key_reuses_the_complete_hint_identity() {
        let file = ExplicitSourcePathFile {
            library_id: 7,
            path: PathBuf::from("src/value.lani"),
            byte_len: 31,
            modified_unix_nanos: Some(100),
            line_count: None,
        };
        let hint =
            CompiledUnitCacheHintKey::new(SourcePackArtifactTarget::X86_64, 7, 2, &[file], &[])
                .unwrap()
                .unwrap();
        let key = CompiledUnitCacheKey::from_hint(&hint);

        assert_eq!(key.target, hint.target);
        assert_eq!(key.library_id, hint.library_id);
        assert_eq!(key.unit_id, hint.unit_id);
        assert_eq!(key.content_hash, hint.content_hash);
    }

    #[test]
    fn clearing_cache_preserves_counters_but_removes_resident_results() {
        let mut cache = CompiledUnitCache::default();
        let key = CompiledUnitCacheKey::new(
            SourcePackArtifactTarget::X86_64,
            1,
            2,
            &["fn value() -> i32 { return 1; }".into()],
            &[],
        )
        .unwrap();
        cache.misses = 3;
        cache.hints.insert(
            CompiledUnitCacheHintKey {
                target: key.target,
                library_id: key.library_id,
                unit_id: key.unit_id,
                content_hash: key.content_hash,
            },
            key,
        );
        cache.resident_bytes = 17;

        cache.clear();

        assert!(cache.entries.is_empty());
        assert!(cache.hints.is_empty());
        assert_eq!(cache.resident_bytes, 0);
        assert_eq!(cache.misses, 3);
    }

    #[test]
    fn project_cache_clear_retains_only_standard_library_results_and_hints() {
        fn unit(library_id: u32) -> CompiledSourcePackUnit {
            CompiledSourcePackUnit {
                interface: GpuSemanticInterfaceArtifact {
                    version: crate::compiler::GPU_SEMANTIC_INTERFACE_VERSION,
                    library_id,
                    unit_id: 0,
                    modules: Vec::new(),
                    module_segments: Vec::new(),
                    declarations: Vec::new(),
                    types: Vec::new(),
                    type_edges: Vec::new(),
                    members: Vec::new(),
                    name_bytes: Vec::new(),
                },
                object: CompiledSourcePackObject::X86_64(
                    crate::codegen::x86::GpuX86RelocatableObject {
                        version: crate::codegen::x86::GPU_X86_OBJECT_VERSION,
                        library_id,
                        unit_id: 0,
                        entry_offset: None,
                        text: Vec::new(),
                        rodata: Vec::new(),
                        relocations: Vec::new(),
                        symbols: Vec::new(),
                        identity_bytes: Vec::new(),
                    },
                ),
            }
        }

        let mut cache = CompiledUnitCache::default();
        let stdlib = CompiledUnitCacheKey::new(
            SourcePackArtifactTarget::X86_64,
            0,
            0,
            &["module core;".into()],
            &[],
        )
        .unwrap();
        let project = CompiledUnitCacheKey::new(
            SourcePackArtifactTarget::X86_64,
            1,
            0,
            &["module app;".into()],
            &[],
        )
        .unwrap();
        cache.insert(stdlib.clone(), unit(0));
        cache.insert(project.clone(), unit(1));
        cache.insert_hint(
            CompiledUnitCacheHintKey {
                target: stdlib.target,
                library_id: stdlib.library_id,
                unit_id: stdlib.unit_id,
                content_hash: stdlib.content_hash,
            },
            stdlib.clone(),
        );
        cache.insert_hint(
            CompiledUnitCacheHintKey {
                target: project.target,
                library_id: project.library_id,
                unit_id: project.unit_id,
                content_hash: project.content_hash,
            },
            project.clone(),
        );

        cache.clear_except_library(0);

        assert!(cache.entries.contains_key(&stdlib));
        assert!(!cache.entries.contains_key(&project));
        assert_eq!(cache.hints.len(), 1);
        assert!(cache.resident_bytes > 0);
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
