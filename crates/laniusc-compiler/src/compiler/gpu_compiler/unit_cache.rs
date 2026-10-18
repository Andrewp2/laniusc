use std::{collections::HashMap, sync::Arc};

use super::{
    GpuCompiler,
    GpuSemanticInterfaceArtifact,
    SourcePackArtifactTarget,
    typecheck::{CompiledSourcePackObject, CompiledSourcePackUnit, PendingOriginalUnit, RetainedPendingOriginal},
};
use crate::compiler::{
    ExplicitSourcePathFile,
    SourcePackJob,
    read_explicit_source_path_files,
    source_pack_artifact_store_error,
};

const DEFAULT_COMPILED_UNIT_CACHE_BYTES: usize = 256 * 1024 * 1024;
/// Pending originals of standard-library units (see `PendingOriginalCache`).
const DEFAULT_PENDING_ORIGINAL_CACHE_BYTES: usize = 128 * 1024 * 1024;
/// The daemon entry loader assigns library 0 to the standard library and
/// library 1 to user sources (`clear_project_compiled_unit_cache`).
const STANDARD_LIBRARY_ID: u32 = 0;

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

    // Content-only fallback entries also own diagnostic paths. Include those
    // paths when metadata cannot establish the usual path-backed hint key.
    fn with_source_paths(mut self, source_files: &[ExplicitSourcePathFile]) -> Self {
        let mut content = blake3::Hasher::new();
        content.update(b"laniusc-compiled-unit-cache-path-context-v1");
        content.update(self.content_hash.as_bytes());
        hash_len(&mut content, source_files.len());
        for file in source_files {
            hash_bytes(&mut content, file.path.as_os_str().as_encoded_bytes());
        }
        self.content_hash = content.finalize();
        self
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

/// A value the unit cache can retain, with its resident byte charge.
pub(super) trait CachedUnitValue: Clone {
    fn resident_byte_len(&self) -> usize;
}

impl CachedUnitValue for Arc<CompiledSourcePackUnit> {
    fn resident_byte_len(&self) -> usize {
        CompiledSourcePackUnit::resident_byte_len(self)
    }
}

impl CachedUnitValue for RetainedPendingOriginal {
    fn resident_byte_len(&self) -> usize {
        RetainedPendingOriginal::resident_byte_len(self)
    }
}

#[derive(Clone)]
struct CachedCompiledUnit<V> {
    value: V,
    resident_bytes: usize,
    last_used: u64,
}

/// Released compiled units (strict compilation, any target).
pub(super) type CompiledUnitCache = UnitCache<Arc<CompiledSourcePackUnit>>;

/// Native pending originals of standard-library units, retained across jobs
/// of one compiler. A hit is not a released unit: it re-enters the build as a
/// new `PendingOriginalUnit`, which that build's program admission must
/// release like a fresh compilation (the catalog still admits it every job).
pub(super) type PendingOriginalCache = UnitCache<RetainedPendingOriginal>;

/// A byte-bounded least-recently-used map from unit identity to a value.
pub(super) struct UnitCache<V> {
    entries: HashMap<CompiledUnitCacheKey, CachedCompiledUnit<V>>,
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

impl CompiledUnitCacheStats {
    fn plus(self, other: Self) -> Self {
        Self {
            hits: self.hits.saturating_add(other.hits),
            misses: self.misses.saturating_add(other.misses),
            evictions: self.evictions.saturating_add(other.evictions),
            entries: self.entries.saturating_add(other.entries),
            resident_bytes: self.resident_bytes.saturating_add(other.resident_bytes),
        }
    }
}

impl<V> Default for UnitCache<V> {
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

impl PendingOriginalCache {
    pub(super) fn pending_default() -> Self {
        Self { maximum_bytes: DEFAULT_PENDING_ORIGINAL_CACHE_BYTES, ..Self::default() }
    }
}

impl<V: CachedUnitValue> UnitCache<V> {
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

    fn get(&mut self, key: &CompiledUnitCacheKey) -> Option<V> {
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

    /// A unit compiled without a cache lookup (one the cache never retains).
    fn record_miss(&mut self) {
        self.misses = self.misses.saturating_add(1);
    }

    fn insert(&mut self, key: CompiledUnitCacheKey, value: impl Into<V>) {
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
    ) -> Option<V> {
        let Some(key) = self.hints.get(hint).cloned() else {
            return None;
        };
        self.get(&key)
    }

    fn insert_hint(&mut self, hint: CompiledUnitCacheHintKey, key: CompiledUnitCacheKey) {
        // An oversized unit can be evicted during insert. Its filesystem hint
        // must not remain as an unbounded entry without a resident result.
        if self.entries.contains_key(&key) {
            self.hints.insert(hint, key);
        }
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
    pub(super) fn resident_byte_len(&self) -> usize {
        let mut bytes = std::mem::size_of::<Self>()
            .saturating_add(self.body_native_layouts.as_ref().map_or(0, |entries| entries.iter()
                .map(|widths| widths.len().saturating_mul(4)).fold(0usize, usize::saturating_add)))
            .saturating_add(interface_resident_bytes(&self.interface))
            .saturating_add(
                self.template_sources
                    .len()
                    .saturating_mul(std::mem::size_of::<String>()),
            );
        for source in self.template_sources.iter() {
            bytes = bytes.saturating_add(source.capacity());
        }
        bytes = bytes.saturating_add(self.template_source_paths.len()
            .saturating_mul(std::mem::size_of::<Option<std::path::PathBuf>>()));
        for path in self.template_source_paths.iter().flatten() {
            bytes = bytes.saturating_add(path.capacity());
        }
        bytes = bytes.saturating_add(
            self.generic_calls
                .len()
                .saturating_mul(std::mem::size_of::<crate::type_checker::CheckedGenericCall>()),
        );
        for call in self.generic_calls.iter() {
            bytes = bytes.saturating_add(call.resident_argument_bytes());
        }
        bytes = bytes
            .saturating_add(std::mem::size_of::<crate::type_checker::CheckedUnitContracts>())
            .saturating_add(self.checked_contracts.resident_byte_len())
            .saturating_add(
                self.checked_call_owners
                    .len()
                    .saturating_mul(std::mem::size_of::<crate::type_checker::CheckedCallOwner>()),
            );
        if let Some(spans) = &self.owner_spans {
            bytes = bytes
                .saturating_add(std::mem::size_of::<crate::type_checker::CheckedOwnerSpans>())
                .saturating_add(spans.resident_bytes());
        }
        bytes = bytes.saturating_add(
            self.x86_call_hirs
                .len()
                .saturating_add(self.x86_call_function_hirs.len())
                .saturating_mul(std::mem::size_of::<u32>()),
        );
        bytes = bytes.saturating_add(
            self.template_dependency_pages
                .len()
                .saturating_mul(std::mem::size_of::<Vec<GpuSemanticInterfaceArtifact>>()),
        );
        for page in self.template_dependency_pages.iter() {
            bytes = bytes.saturating_add(vector_resident_bytes(page));
            for interface in page {
                bytes = bytes.saturating_add(interface_resident_bytes(interface));
            }
        }
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

pub(super) fn interface_resident_bytes(interface: &GpuSemanticInterfaceArtifact) -> usize {
    vector_resident_bytes(&interface.modules)
        .saturating_add(vector_resident_bytes(&interface.module_segments))
        .saturating_add(vector_resident_bytes(&interface.declarations))
        .saturating_add(vector_resident_bytes(&interface.types))
        .saturating_add(vector_resident_bytes(&interface.type_edges))
        .saturating_add(vector_resident_bytes(&interface.members))
        .saturating_add(vector_resident_bytes(&interface.predicates))
        .saturating_add(vector_resident_bytes(&interface.predicate_arguments))
        .saturating_add(vector_resident_bytes(&interface.implementations))
        .saturating_add(vector_resident_bytes(&interface.implementation_arguments))
        .saturating_add(vector_resident_bytes(
            &interface.implementation_method_bindings,
        ))
        .saturating_add(vector_resident_bytes(&interface.name_bytes))
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
        dependency_pages: Arc<[Vec<GpuSemanticInterfaceArtifact>]>,
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
            dependency_pages.as_ref(),
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
            CompiledUnitCacheKey::new(
                target,
                job.library_id,
                unit_id,
                &sources,
                dependency_pages.as_ref(),
            )
            .map_err(source_pack_artifact_store_error)?
            .with_source_paths(source_files)
        };
        if let Some(value) = self.cached_compiled_unit(&cache_key) {
            return Ok(CachedCompiledSourcePackUnit {
                value,
                cache_hit: true,
            });
        }

        let source_paths = source_files.iter()
            .map(|file| Some(file.path.clone())).collect::<Vec<_>>();
        let value = Arc::new(
            self.compile_source_pack_unit_with_dependency_pages_and_paths(
                sources.into(),
                job.library_id,
                unit_id,
                dependency_pages,
                target,
                Some(&source_paths),
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
        self.pending_original_cache
            .lock()
            .expect("pending-original cache mutex poisoned")
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
            .clear_except_library(STANDARD_LIBRARY_ID);
        self.pending_original_cache
            .lock()
            .expect("pending-original cache mutex poisoned")
            .clear_except_library(STANDARD_LIBRARY_ID);
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

    /// Both caches: released units and standard-library pending originals.
    pub(crate) fn compiled_unit_cache_stats(&self) -> CompiledUnitCacheStats {
        let compiled = self.compiled_unit_cache
            .lock()
            .expect("compiled-unit cache mutex poisoned")
            .stats();
        compiled.plus(self.pending_original_cache
            .lock()
            .expect("pending-original cache mutex poisoned")
            .stats())
    }

    /// Compiles one path-backed native unit as a pending original, or reuses
    /// a standard-library unit's pending original from an earlier job with
    /// the same identity: target, library, unit, source paths, lengths and
    /// modification times (or contents), and dependency interfaces.
    ///
    /// A reused original is not released: program admission checks its facts
    /// and original calls on every job, as for a fresh compilation. Project
    /// units (library != 0) are compiled on every job and count as misses.
    /// `LANIUS_PENDING_ORIGINAL_CACHE=0` disables reuse.
    pub(super) async fn compile_cached_pending_original_unit(
        &self,
        job: &SourcePackJob,
        source_files: &[ExplicitSourcePathFile],
        dependency_pages: Arc<[Vec<GpuSemanticInterfaceArtifact>]>,
    ) -> Result<PendingOriginalUnit, super::CompileError> {
        let unit_id = u32::try_from(job.phase_unit_index).map_err(|_| {
            source_pack_artifact_store_error("pending native source-unit index exceeds u32")
        })?;
        let cacheable = job.library_id == STANDARD_LIBRARY_ID && pending_original_cache_enabled();
        let cache_hint = if cacheable {
            CompiledUnitCacheHintKey::new(
                SourcePackArtifactTarget::X86_64, job.library_id, unit_id, source_files,
                dependency_pages.as_ref(),
            ).map_err(source_pack_artifact_store_error)?
        } else {
            None
        };
        if let Some(hit) = cache_hint.as_ref().and_then(|hint| self.pending_original_cache
            .lock().expect("pending-original cache mutex poisoned").get_by_hint(hint))
        {
            return Ok(hit.pending());
        }
        let sources = read_explicit_source_path_files(
            "pending native library-interface job", source_files)?;
        let cache_key = match (&cache_hint, cacheable) {
            (Some(hint), _) => Some(CompiledUnitCacheKey::from_hint(hint)),
            (None, true) => Some(CompiledUnitCacheKey::new(
                SourcePackArtifactTarget::X86_64, job.library_id, unit_id, &sources,
                dependency_pages.as_ref(),
            ).map_err(source_pack_artifact_store_error)?.with_source_paths(source_files)),
            (None, false) => None,
        };
        {
            let mut cache = self.pending_original_cache
                .lock().expect("pending-original cache mutex poisoned");
            match &cache_key {
                Some(key) => if let Some(hit) = cache.get(key) {
                    return Ok(hit.pending());
                },
                None => cache.record_miss(),
            }
        }
        let source_paths = source_files.iter()
            .map(|file| Some(file.path.clone())).collect::<Vec<_>>();
        let pending = self.compile_pending_original_source_pack_unit(
            sources.into(), job.library_id, unit_id, dependency_pages, Some(&source_paths),
        ).await?;
        if let Some(key) = cache_key {
            let mut cache = self.pending_original_cache
                .lock().expect("pending-original cache mutex poisoned");
            cache.insert(key.clone(), pending.retain());
            if let Some(hint) = cache_hint {
                cache.insert_hint(hint, key);
            }
        }
        Ok(pending)
    }
}

fn pending_original_cache_enabled() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_PENDING_ORIGINAL_CACHE", true)
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
    fn fallback_cache_keeps_diagnostic_paths_in_its_identity() {
        let sources: Vec<String> = vec!["module first;".into(), "module second;".into()];
        let files = [
            ExplicitSourcePathFile {
                library_id: 7,
                path: PathBuf::from("src/first.lani"),
                byte_len: sources[0].len(),
                modified_unix_nanos: Some(100),
                line_count: None,
            },
            ExplicitSourcePathFile {
                library_id: 7,
                path: PathBuf::from("src/second.lani"),
                byte_len: sources[1].len(),
                modified_unix_nanos: None,
                line_count: None,
            },
        ];
        let mut relocated = files.clone();
        relocated[1].path = PathBuf::from("other/second.lani");

        // Missing metadata selects the content-based fallback for both inputs.
        for paths in [&files, &relocated] {
            assert!(
                CompiledUnitCacheHintKey::new(SourcePackArtifactTarget::X86_64, 7, 0, paths, &[])
                    .unwrap()
                    .is_none()
            );
        }
        let key_for = |paths: &[ExplicitSourcePathFile]| {
            CompiledUnitCacheKey::new(SourcePackArtifactTarget::X86_64, 7, 0, &sources, &[])
                .unwrap()
                .with_source_paths(paths)
        };
        let original_key = key_for(&files);
        let repeated_key = key_for(&files);
        let relocated_key = key_for(&relocated);
        assert_eq!(original_key, repeated_key);
        assert_ne!(original_key, relocated_key);

        let mut original = unit(7);
        original.template_sources = sources.clone().into();
        original.template_source_paths = files
            .iter()
            .map(|file| Some(file.path.clone()))
            .collect::<Vec<_>>()
            .into();
        let original = Arc::new(original);
        let mut cache = CompiledUnitCache::default();
        cache.insert(original_key, Arc::clone(&original));
        assert!(cache.get(&relocated_key).is_none());
        let reused = cache
            .get(&repeated_key)
            .expect("same diagnostic paths reuse the unit");
        assert!(Arc::ptr_eq(&original, &reused));
        assert_eq!(
            reused.template_source_paths[1].as_deref(),
            Some(files[1].path.as_path())
        );
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

    fn unit(library_id: u32) -> CompiledSourcePackUnit {
        CompiledSourcePackUnit {
            body_native_layouts: None,
            owner_spans: None,
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
                predicates: Vec::new(),
                predicate_arguments: Vec::new(),
                implementations: Vec::new(),
                implementation_arguments: Vec::new(),
                implementation_method_bindings: Vec::new(),
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
            template_sources: Vec::<String>::new().into(),
            template_source_paths: Vec::new().into(),
            template_dependency_pages: Vec::<Vec<GpuSemanticInterfaceArtifact>>::new().into(),
            generic_calls: Vec::new().into(),
            checked_contracts: std::sync::Arc::new(Default::default()),
            checked_call_owners: Vec::new().into(),
            x86_call_hirs: Vec::new().into(),
            x86_call_function_hirs: Vec::new().into(),
        }
    }

    #[test]
    fn pending_originals_reenter_as_pending_with_their_original_facts() {
        let pending = PendingOriginalUnit::from_unit_for_test(unit(0));
        let mut cache = PendingOriginalCache::pending_default();
        let key = CompiledUnitCacheKey::new(
            SourcePackArtifactTarget::X86_64, 0, 0, &["module core;".into()], &[],
        ).unwrap();
        cache.insert(key.clone(), pending.retain());
        // Every hit is a new pending wrapper over the same facts snapshot, so
        // each build's admission sees the original compilation's facts.
        for _ in 0..2 {
            let reused = cache.get(&key).expect("retained pending original").pending();
            assert!(reused.facts().same_snapshot(pending.facts()));
        }
        cache.record_miss();
        let stats = cache.stats();
        assert_eq!((stats.hits, stats.misses, stats.entries), (2, 1, 1));
        // The facts snapshot's interface copy is charged with the unit.
        assert_eq!(stats.resident_bytes, std::mem::size_of::<CompiledUnitCacheKey>()
            + unit(0).resident_byte_len() + interface_resident_bytes(&unit(0).interface));
        cache.clear_except_library(STANDARD_LIBRARY_ID);
        assert_eq!(cache.stats().entries, 1);
        cache.clear();
        assert!(cache.get(&key).is_none());
    }

    #[test]
    fn pending_original_cache_evicts_to_its_budget() {
        let mut cache = PendingOriginalCache {
            maximum_bytes: std::mem::size_of::<CompiledUnitCacheKey>() + unit(0).resident_byte_len(),
            ..PendingOriginalCache::pending_default()
        };
        let key = |source: &str| CompiledUnitCacheKey::new(
            SourcePackArtifactTarget::X86_64, 0, 0, &[source.into()], &[],
        ).unwrap();
        cache.insert(key("module a;"), PendingOriginalUnit::from_unit_for_test(unit(0)).retain());
        assert_eq!(cache.stats().entries, 0, "the facts' interface copy exceeds the budget");
        assert_eq!(cache.stats().resident_bytes, 0);
        assert_eq!(cache.stats().evictions, 1);
    }

    #[test]
    fn project_cache_clear_retains_only_standard_library_results_and_hints() {
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
    fn template_sources_are_charged_to_the_cache_budget_without_orphan_hints() {
        let mut value = unit(0);
        // This source alone exceeds the available budget. Ignoring snapshots
        // would incorrectly retain the unit and leak a hint for every such job.
        let mut cache = CompiledUnitCache {
            maximum_bytes: std::mem::size_of::<CompiledUnitCacheKey>()
                + value.resident_byte_len()
                + 2048,
            ..CompiledUnitCache::default()
        };
        value.template_sources = vec!["x".repeat(4096)].into();
        let key = CompiledUnitCacheKey::new(
            SourcePackArtifactTarget::X86_64,
            0,
            0,
            value.template_sources.as_ref(),
            &[],
        )
        .unwrap();
        let hint = CompiledUnitCacheHintKey {
            target: key.target,
            library_id: key.library_id,
            unit_id: key.unit_id,
            content_hash: key.content_hash,
        };
        let active_build = Arc::new(value);
        cache.insert(key.clone(), Arc::clone(&active_build));
        cache.insert_hint(hint.clone(), key);

        assert_eq!(cache.stats().entries, 0);
        assert_eq!(cache.stats().resident_bytes, 0);
        assert_eq!(cache.stats().evictions, 1);
        assert!(cache.hints.is_empty());
        assert!(cache.get_by_hint(&hint).is_none());
        // An active build's ownership survives eviction from the daemon cache.
        assert_eq!(active_build.template_sources[0].len(), 4096);
    }

    #[test]
    fn template_dependency_snapshots_are_charged_to_the_cache_budget() {
        let mut value = unit(0);
        let mut cache = CompiledUnitCache {
            maximum_bytes: std::mem::size_of::<CompiledUnitCacheKey>()
                + value.resident_byte_len()
                + 2048,
            ..CompiledUnitCache::default()
        };
        let mut dependency = unit(7).interface;
        dependency.name_bytes = vec![b'x'; 4096];
        value.template_dependency_pages = vec![vec![], vec![dependency], vec![]].into();
        let key =
            CompiledUnitCacheKey::new(SourcePackArtifactTarget::X86_64, 0, 0, &[], &[]).unwrap();
        let active_build = Arc::new(value);
        cache.insert(key, Arc::clone(&active_build));

        assert_eq!(cache.stats().entries, 0);
        assert_eq!(cache.stats().resident_bytes, 0);
        assert_eq!(cache.stats().evictions, 1);
        assert_eq!(
            active_build.template_dependency_pages[1][0]
                .name_bytes
                .len(),
            4096
        );
    }

    #[test]
    fn generic_call_environments_are_charged_to_the_cache_budget() {
        use crate::type_checker::{CheckedGenericTarget, CheckedGenericType};
        let mut value = unit(0);
        let mut cache = CompiledUnitCache {
            maximum_bytes: std::mem::size_of::<CompiledUnitCacheKey>()
                + value.resident_byte_len()
                + 2048,
            ..CompiledUnitCache::default()
        };
        value.generic_calls = vec![crate::type_checker::CheckedGenericCall {
            call_hir: 7,
            source_span: [0, 1],
            constants: Vec::new(),
            required_constant_parameters: Some(0),
            target: CheckedGenericTarget::Local {
                function_start_token: 3,
                generic_parameter_count: 512,
                native_symbol: 3,
                specialization_symbol: 0x4000_0003,
            },
            required_generic_parameters: Some(512),
            arguments: (0..512)
                .map(|slot| crate::type_checker::CheckedGenericArgument {
                    slot,
                    ty: CheckedGenericType::Scalar(3),
                })
                .collect(),
        }]
        .into();
        let key =
            CompiledUnitCacheKey::new(SourcePackArtifactTarget::X86_64, 0, 0, &[], &[]).unwrap();
        let active_build = Arc::new(value);
        cache.insert(key, Arc::clone(&active_build));
        assert_eq!(cache.stats().entries, 0);
        assert_eq!(cache.stats().resident_bytes, 0);
        assert_eq!(cache.stats().evictions, 1);
        assert_eq!(active_build.generic_calls[0].arguments.len(), 512);
    }

    #[test]
    fn nested_generic_environments_are_charged_to_the_cache_budget() {
        use crate::type_checker::{CheckedGenericCall, CheckedGenericTarget, CheckedGenericType};
        let mut value = unit(0);
        let mut cache = CompiledUnitCache {
            maximum_bytes: std::mem::size_of::<CompiledUnitCacheKey>()
                + value.resident_byte_len()
                + 2048,
            ..CompiledUnitCache::default()
        };
        value.generic_calls = vec![CheckedGenericCall {
            call_hir: 7,
            source_span: [0, 1],
            constants: Vec::new(),
            required_constant_parameters: Some(0),
            target: CheckedGenericTarget::DependencyMethod {
                library_id: 1,
                unit_id: 0,
                method_symbol: 0x8000_0003,
            },
            arguments: vec![crate::type_checker::CheckedGenericArgument {
                slot: 0,
                ty: CheckedGenericType::Nominal {
                    identity: crate::type_checker::CheckedNominalIdentity::Public([1, 0, 0]),
                    arguments: (0..32).map(|_| {
                        crate::type_checker::CheckedGenericApplicationArgument::Type(
                            CheckedGenericType::Nominal {
                                identity: crate::type_checker::CheckedNominalIdentity::Public([1, 0, 1]),
                                arguments: vec![crate::type_checker::CheckedGenericApplicationArgument::Type(
                                    CheckedGenericType::Scalar(3)); 16],
                                words: Some(16), local_replay: None,
                            }
                        )
                    }).collect(),
                    words: Some(512), local_replay: None,
                },
            }],
            required_generic_parameters: Some(1),
        }]
        .into();
        let key =
            CompiledUnitCacheKey::new(SourcePackArtifactTarget::X86_64, 0, 0, &[], &[]).unwrap();
        let active_build = Arc::new(value);
        cache.insert(key, Arc::clone(&active_build));
        assert_eq!(cache.stats().entries, 0);
        assert_eq!(cache.stats().resident_bytes, 0);
        assert_eq!(cache.stats().evictions, 1);
        let CheckedGenericType::Nominal { arguments, .. } = &active_build.generic_calls[0].arguments[0].ty else {
            panic!("retained nominal environment");
        };
        assert_eq!(arguments.len(), 32);
    }

    #[test]
    fn native_call_hir_snapshots_are_charged_to_the_cache_budget() {
        let mut value = unit(0);
        let mut cache = CompiledUnitCache {
            maximum_bytes: std::mem::size_of::<CompiledUnitCacheKey>()
                + value.resident_byte_len()
                + 2048,
            ..CompiledUnitCache::default()
        };
        value.x86_call_hirs = (0..1024).collect::<Vec<_>>().into();
        let key =
            CompiledUnitCacheKey::new(SourcePackArtifactTarget::X86_64, 0, 0, &[], &[]).unwrap();
        let active_build = Arc::new(value);
        cache.insert(key, Arc::clone(&active_build));
        assert_eq!(cache.stats().entries, 0);
        assert_eq!(cache.stats().resident_bytes, 0);
        assert_eq!(cache.stats().evictions, 1);
        assert_eq!(active_build.x86_call_hirs.len(), 1024);
        assert_eq!(active_build.x86_call_hirs[1023], 1023);
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
