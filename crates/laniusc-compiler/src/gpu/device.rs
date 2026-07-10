use std::{
    collections::HashMap,
    fs::{self, File},
    io::Write,
    path::PathBuf,
    sync::{Arc, Mutex, OnceLock, Weak},
    time::{Duration, Instant, SystemTime},
};

use log::warn;

const PIPELINE_CACHE_FILE_MAGIC: [u8; 8] = *b"LANIUSPC";
const PIPELINE_CACHE_FILE_VERSION: u32 = 1;
const PIPELINE_CACHE_HEADER_LEN: usize = 8 + 4 + 4 + 8 + 8 + 8;

/// Global GPU device/queue resource shared across compiler subsystems.
pub struct GpuDevice {
    /// Shared wgpu device.
    pub device: Arc<wgpu::Device>,
    /// Shared wgpu queue.
    pub queue: Arc<wgpu::Queue>,
    /// Whether timestamp queries were requested successfully.
    pub timers_supported: bool,
    /// Pipeline cache associated with this device, when supported.
    pub pipeline_cache: Option<Arc<wgpu::PipelineCache>>,
    pipeline_cache_path: Option<PathBuf>,
    pipeline_cache_identity_hash: Option<u64>,
    pipeline_cache_should_persist: bool,
    pipeline_cache_persisted_hash: Mutex<Option<u64>>,
}

impl GpuDevice {
    /// Creates a GPU device/queue resource that can be shared across compiler subsystems.
    pub fn new() -> Self {
        create_context()
    }

    /// Persists the current wgpu pipeline cache to disk when supported.
    pub fn persist_pipeline_cache(&self) {
        let timer = PipelineCachePersistTimer::new();
        let Some(cache) = self.pipeline_cache.as_ref() else {
            return;
        };
        let Some(path) = self.pipeline_cache_path.as_ref() else {
            return;
        };
        let Some(identity_hash) = self.pipeline_cache_identity_hash else {
            return;
        };
        let total_start = Instant::now();
        let start = Instant::now();
        let Some(data) = cache.get_data() else {
            let end = Instant::now();
            timer.span("get_data.empty", start, end);
            timer.span("total.empty", total_start, end);
            return;
        };
        let end = Instant::now();
        timer.span("get_data", start, end);
        timer.bytes("pipeline_cache.persist.bytes", end, data.len());
        let data_hash = stable_hash_u64(&data);
        let force_persist =
            crate::gpu::env::env_bool_truthy("LANIUS_PIPELINE_CACHE_PERSIST_ALWAYS", false);
        let already_persisted = self
            .pipeline_cache_persisted_hash
            .lock()
            .ok()
            .and_then(|hash| *hash)
            == Some(data_hash);
        if !self.pipeline_cache_should_persist && !force_persist && already_persisted {
            timer.span("skipped.unchanged", total_start, end);
            return;
        }
        if let Some(parent) = path.parent() {
            let start = Instant::now();
            if let Err(err) = std::fs::create_dir_all(parent) {
                let end = Instant::now();
                timer.span("create_dir_all.failed", start, end);
                timer.span("total.failed", total_start, end);
                warn!(
                    "failed to create pipeline cache directory {}: {err}",
                    parent.display()
                );
                return;
            }
            timer.span("create_dir_all", start, Instant::now());
        }
        let tmp = pipeline_cache_tmp_path(path);
        let start = Instant::now();
        if let Err(err) = write_pipeline_cache_tmp(&tmp, &data, identity_hash, &timer) {
            let end = Instant::now();
            timer.span("write_tmp.failed", start, end);
            timer.span("total.failed", total_start, end);
            warn!(
                "failed to write pipeline cache tmp file {}: {err}",
                tmp.display()
            );
            return;
        }
        timer.span("write_tmp", start, Instant::now());
        let start = Instant::now();
        if let Err(err) = std::fs::rename(&tmp, path) {
            let end = Instant::now();
            timer.span("rename.failed", start, end);
            timer.span("total.failed", total_start, end);
            warn!(
                "failed to move pipeline cache {} -> {}: {err}",
                tmp.display(),
                path.display()
            );
            return;
        }
        let end = Instant::now();
        timer.span("rename", start, end);
        if let Ok(mut persisted_hash) = self.pipeline_cache_persisted_hash.lock() {
            *persisted_hash = Some(data_hash);
        }
        timer.span("total", total_start, end);
    }

    /// Returns current pipeline-cache payload length, if cache data is available.
    pub fn pipeline_cache_data_len(&self) -> Option<usize> {
        self.pipeline_cache
            .as_ref()
            .and_then(|cache| cache.get_data())
            .map(|data| data.len())
    }
}

fn write_pipeline_cache_tmp(
    path: &std::path::Path,
    data: &[u8],
    identity_hash: u64,
    timer: &PipelineCachePersistTimer,
) -> std::io::Result<()> {
    let start = Instant::now();
    let header = pipeline_cache_file_header(data, identity_hash);
    timer.span("write_tmp.encode_header", start, Instant::now());

    let start = Instant::now();
    let mut file = File::create(path)?;
    timer.span("write_tmp.create_file", start, Instant::now());

    let start = Instant::now();
    file.write_all(&header)?;
    timer.span("write_tmp.write_header", start, Instant::now());

    let start = Instant::now();
    file.write_all(data)?;
    let end = Instant::now();
    timer.span("write_tmp.write_data", start, end);
    timer.bytes(
        "pipeline_cache.persist.file_bytes",
        end,
        PIPELINE_CACHE_HEADER_LEN.saturating_add(data.len()),
    );

    let start = Instant::now();
    file.flush()?;
    timer.span("write_tmp.flush", start, Instant::now());

    let start = Instant::now();
    drop(file);
    timer.span("write_tmp.close", start, Instant::now());

    Ok(())
}

struct PipelineCachePersistTimer {
    print_enabled: bool,
    trace_enabled: bool,
}

impl PipelineCachePersistTimer {
    fn new() -> Self {
        Self {
            print_enabled: crate::gpu::env::env_bool_truthy(
                "LANIUS_GPU_COMPILE_HOST_TIMING",
                false,
            ),
            trace_enabled: crate::gpu::trace::enabled(),
        }
    }

    fn span(&self, stage: &str, start: Instant, end: Instant) {
        self.span_prefixed("persist", stage, start, end);
    }

    fn span_prefixed(&self, prefix: &str, stage: &str, start: Instant, end: Instant) {
        if !self.print_enabled && !self.trace_enabled {
            return;
        }
        let name = format!("pipeline_cache.{prefix}.{stage}");
        if self.print_enabled {
            let dt_ms = end.duration_since(start).as_secs_f64() * 1000.0;
            eprintln!("[gpu_compile_host_timer] {name}: {dt_ms:.3}ms");
        }
        if self.trace_enabled {
            crate::gpu::trace::record_host_span("host.pipeline_cache", &name, start, end);
        }
    }

    fn bytes(&self, name: &str, at: Instant, bytes: usize) {
        self.bytes_prefixed("size", name, at, bytes);
    }

    fn bytes_prefixed(&self, lane_suffix: &str, name: &str, at: Instant, bytes: usize) {
        if self.print_enabled {
            eprintln!("[gpu_compile_host_timer] {name}: {bytes} bytes");
        }
        if self.trace_enabled {
            crate::gpu::trace::record_counter(
                &format!("host.pipeline_cache.{lane_suffix}"),
                name,
                at,
                bytes as f64,
            );
        }
    }
}

fn create_context() -> GpuDevice {
    let backends = crate::gpu::env::env_string("LANIUS_BACKEND", "auto").to_ascii_lowercase();
    let backends = match backends.as_str() {
        "vulkan" | "vk" => wgpu::Backends::VULKAN,
        "dx12" => wgpu::Backends::DX12,
        "metal" | "mtl" => wgpu::Backends::METAL,
        "gl" => wgpu::Backends::GL,
        "auto" => wgpu::Backends::all(),
        other => {
            warn!("unknown LANIUS_BACKEND '{other}'; using default backends");
            wgpu::Backends::all()
        }
    };

    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends,
        ..wgpu::InstanceDescriptor::new_without_display_handle()
    });

    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: None,
        force_fallback_adapter: false,
    }))
    .expect("no suitable GPU adapter");
    let adapter_info = adapter.get_info();

    let adapter_limits = adapter.limits();
    let mut limits = wgpu::Limits::defaults();
    // Native compiler stages use wide GPU record tables; request the adapter's
    // native storage-buffer limit so reflected pass layouts fail only when the
    // selected device genuinely cannot support the compiler's record tables.
    limits.max_storage_buffers_per_shader_stage =
        adapter_limits.max_storage_buffers_per_shader_stage;
    // Native desktop adapters generally expose at least 32 KiB of workgroup
    // storage. Request it when available so bounded cooperative compiler sorts
    // can replace long radix command schedules, while retaining the WebGPU
    // baseline on adapters that only expose the default 16 KiB.
    limits.max_compute_workgroup_storage_size = adapter_limits
        .max_compute_workgroup_storage_size
        .min(32 * 1024);
    limits.max_storage_buffer_binding_size = 2_147_483_644;
    limits.max_buffer_size = 2_147_483_644;

    let adapter_features = adapter.features();

    // Enable SPIR-V passthrough always; add timestamp features if supported so timing can be toggled at runtime.
    let mut required_features = wgpu::Features::empty() | wgpu::Features::PASSTHROUGH_SHADERS;
    if adapter_features.contains(wgpu::Features::TIMESTAMP_QUERY) {
        required_features |= wgpu::Features::TIMESTAMP_QUERY;
        if adapter_features.contains(wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS) {
            required_features |= wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS;
        }
        if adapter_features.contains(wgpu::Features::TIMESTAMP_QUERY_INSIDE_PASSES) {
            required_features |= wgpu::Features::TIMESTAMP_QUERY_INSIDE_PASSES;
        }
    }
    let pipeline_cache_supported = adapter_features.contains(wgpu::Features::PIPELINE_CACHE);
    if pipeline_cache_supported {
        required_features |= wgpu::Features::PIPELINE_CACHE;
    }

    let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
        label: Some("laniusc_device"),
        required_features,
        required_limits: limits,
        // SAFETY: Lanius consumes Slang-produced SPIR-V directly through wgpu's
        // passthrough path so the compiler does not route shaders through Naga.
        experimental_features: unsafe { wgpu::ExperimentalFeatures::enabled() },
        memory_hints: wgpu::MemoryHints::default(),
        trace: wgpu::Trace::default(),
    }))
    .expect("failed to create wgpu device");

    device.on_uncaptured_error(Arc::new(|e| {
        eprintln!("[wgpu uncaptured] {e:?}");
    }));

    let timers_supported = adapter_features.contains(wgpu::Features::TIMESTAMP_QUERY);
    let (
        pipeline_cache,
        pipeline_cache_path,
        pipeline_cache_identity_hash,
        pipeline_cache_should_persist,
        pipeline_cache_persisted_hash,
    ) = if pipeline_cache_supported {
        create_pipeline_cache(&device, &adapter_info)
    } else {
        (None, None, None, false, None)
    };
    let device = Arc::new(device);
    let pipeline_cache = pipeline_cache.map(Arc::new);
    register_pipeline_cache(&device, pipeline_cache.as_ref());

    GpuDevice {
        device,
        queue: Arc::new(queue),
        timers_supported,
        pipeline_cache,
        pipeline_cache_path,
        pipeline_cache_identity_hash,
        pipeline_cache_should_persist,
        pipeline_cache_persisted_hash: Mutex::new(pipeline_cache_persisted_hash),
    }
}

/// Returns a reference to the global GPU context (created on first use).
pub fn global() -> &'static GpuDevice {
    static CTX: OnceLock<GpuDevice> = OnceLock::new();
    CTX.get_or_init(GpuDevice::new)
}

/// Persists the process-global device's pipeline cache.
pub fn persist_pipeline_cache() {
    global().persist_pipeline_cache();
}

/// Persists the process-global cache when `device` is the process-global device.
pub fn persist_pipeline_cache_for_device(device: &wgpu::Device) {
    let global = global();
    if Arc::as_ptr(&global.device) == device as *const wgpu::Device {
        global.persist_pipeline_cache();
    }
}

/// Returns the pipeline cache registered for a wgpu device.
pub fn pipeline_cache_for(device: &wgpu::Device) -> Option<Arc<wgpu::PipelineCache>> {
    let key = device as *const wgpu::Device as usize;
    match pipeline_cache_registry().lock() {
        Ok(caches) => caches.get(&key).cloned().and_then(|cache| cache.upgrade()),
        Err(err) => {
            warn!(
                "failed to lock pipeline cache registry: {err}; proceeding without pipeline cache"
            );
            None
        }
    }
}

fn register_pipeline_cache(device: &Arc<wgpu::Device>, cache: Option<&Arc<wgpu::PipelineCache>>) {
    let Some(cache) = cache else {
        return;
    };
    let key = Arc::as_ptr(device) as usize;
    match pipeline_cache_registry().lock() {
        Ok(mut caches) => {
            caches.insert(key, Arc::downgrade(cache));
        }
        Err(err) => {
            warn!("failed to register pipeline cache due poisoned lock: {err}");
        }
    }
}

fn pipeline_cache_registry() -> &'static Mutex<HashMap<usize, Weak<wgpu::PipelineCache>>> {
    static REGISTRY: OnceLock<Mutex<HashMap<usize, Weak<wgpu::PipelineCache>>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn create_pipeline_cache(
    device: &wgpu::Device,
    adapter_info: &wgpu::AdapterInfo,
) -> (
    Option<wgpu::PipelineCache>,
    Option<PathBuf>,
    Option<u64>,
    bool,
    Option<u64>,
) {
    let timer = PipelineCachePersistTimer::new();
    let total_start = Instant::now();
    let Some(adapter_key) = wgpu::util::pipeline_cache_key(adapter_info) else {
        timer.span_prefixed("create", "unsupported_key", total_start, Instant::now());
        return (None, None, None, false, None);
    };
    let start = Instant::now();
    let cache_dir = crate::gpu::env::env_path(
        "LANIUS_PIPELINE_CACHE_DIR",
        PathBuf::from("target").join("wgpu-pipeline-cache"),
    );
    let (filename, identity_hash) = pipeline_cache_filename(&adapter_key);
    let cache_path = cache_dir.join(filename);
    timer.span_prefixed("create", "path", start, Instant::now());
    let start = Instant::now();
    prune_pipeline_cache_dir(&cache_dir, &cache_path, &adapter_key);
    timer.span_prefixed("create", "prune", start, Instant::now());
    let start = Instant::now();
    let mut should_persist = false;
    let cache_file_data = match fs::read(&cache_path) {
        Ok(file_data) => {
            let end = Instant::now();
            timer.span_prefixed("create", "read", start, end);
            timer.bytes_prefixed(
                "size",
                "pipeline_cache.create.input_file_bytes",
                end,
                file_data.len(),
            );
            Some(file_data)
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            timer.span_prefixed("create", "read.missing", start, Instant::now());
            should_persist = true;
            None
        }
        Err(err) => {
            timer.span_prefixed("create", "read.failed", start, Instant::now());
            warn!(
                "failed to read pipeline cache {}: {err}",
                cache_path.display()
            );
            should_persist = true;
            None
        }
    };
    let mut persisted_hash = None;
    let cache_data = cache_file_data.as_deref().and_then(|file_data| {
        let start = Instant::now();
        match decode_pipeline_cache_file(file_data, identity_hash) {
            Ok(data) => {
                let end = Instant::now();
                timer.span_prefixed("create", "decode", start, end);
                timer.bytes_prefixed(
                    "size",
                    "pipeline_cache.create.input_cache_bytes",
                    end,
                    data.len(),
                );
                persisted_hash = Some(stable_hash_u64(data));
                Some(data)
            }
            Err(err) => {
                timer.span_prefixed("create", "decode.invalid", start, Instant::now());
                warn!("discarding pipeline cache {}: {err}", cache_path.display());
                remove_pipeline_cache_file(&cache_path, "invalid");
                should_persist = true;
                None
            }
        }
    });
    let start = Instant::now();
    let cache = unsafe {
        device.create_pipeline_cache(&wgpu::PipelineCacheDescriptor {
            label: Some("laniusc_pipeline_cache"),
            data: cache_data,
            // This is only wgpu cache-data recovery when an on-disk pipeline
            // cache is stale. Adapter selection above keeps compiler execution
            // on a real GPU and does not allow a CPU compiler fallback.
            fallback: true,
        })
    };
    let end = Instant::now();
    timer.span_prefixed("create", "wgpu_create", start, end);
    timer.span_prefixed("create", "total", total_start, end);
    (
        Some(cache),
        Some(cache_path),
        Some(identity_hash),
        should_persist,
        persisted_hash,
    )
}

fn pipeline_cache_filename(adapter_key: &str) -> (String, u64) {
    let wgpu_version = option_env!("LANIUS_WGPU_VERSION").unwrap_or("unknown");
    // A wgpu pipeline cache is a keyed collection, not a single precompiled
    // shader bundle. Unchanged pipelines remain reusable when one shader or
    // the compiler build changes, while new pipeline descriptors miss and are
    // compiled normally. Key the file only by the opaque-cache compatibility
    // boundary instead of invalidating every pipeline on every shader edit.
    let identity = format!("adapter={adapter_key};wgpu={wgpu_version};format=1");
    let identity_hash = stable_hash_u64(identity.as_bytes());
    let identity_digest = format!("{identity_hash:016x}");
    let filename = format!(
        "{}_laniusc-pipelines-v1_wgpu-{}_key-{}",
        adapter_key,
        sanitize_cache_key_component(wgpu_version),
        identity_digest,
    );
    (filename, identity_hash)
}

fn sanitize_cache_key_component(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '.' | '-' | '_') {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

fn pipeline_cache_tmp_path(path: &std::path::Path) -> PathBuf {
    let filename = path
        .file_name()
        .map(|name| name.to_string_lossy())
        .unwrap_or_else(|| "pipeline_cache".into());
    path.with_file_name(format!("{filename}.tmp"))
}

fn pipeline_cache_file_header(data: &[u8], identity_hash: u64) -> [u8; PIPELINE_CACHE_HEADER_LEN] {
    let mut header = [0u8; PIPELINE_CACHE_HEADER_LEN];
    header[0..8].copy_from_slice(&PIPELINE_CACHE_FILE_MAGIC);
    header[8..12].copy_from_slice(&PIPELINE_CACHE_FILE_VERSION.to_le_bytes());
    header[12..16].copy_from_slice(&(PIPELINE_CACHE_HEADER_LEN as u32).to_le_bytes());
    header[16..24].copy_from_slice(&identity_hash.to_le_bytes());
    header[24..32].copy_from_slice(&(data.len() as u64).to_le_bytes());
    header[32..40].copy_from_slice(&stable_hash_u64(data).to_le_bytes());
    header
}

fn decode_pipeline_cache_file(
    bytes: &[u8],
    expected_identity_hash: u64,
) -> Result<&[u8], PipelineCacheFileError> {
    if bytes.len() < PIPELINE_CACHE_HEADER_LEN {
        return Err(PipelineCacheFileError::TooShort {
            actual: bytes.len(),
        });
    }
    if bytes[0..8] != PIPELINE_CACHE_FILE_MAGIC {
        return Err(PipelineCacheFileError::BadMagic);
    }
    let version = u32::from_le_bytes(bytes[8..12].try_into().expect("u32 version bytes"));
    if version != PIPELINE_CACHE_FILE_VERSION {
        return Err(PipelineCacheFileError::UnsupportedVersion(version));
    }
    let header_len = u32::from_le_bytes(bytes[12..16].try_into().expect("u32 header len bytes"));
    if header_len as usize != PIPELINE_CACHE_HEADER_LEN {
        return Err(PipelineCacheFileError::BadHeaderLen(header_len));
    }
    let actual_identity_hash =
        u64::from_le_bytes(bytes[16..24].try_into().expect("u64 identity hash bytes"));
    if actual_identity_hash != expected_identity_hash {
        return Err(PipelineCacheFileError::IdentityMismatch {
            expected: expected_identity_hash,
            actual: actual_identity_hash,
        });
    }
    let declared_len =
        u64::from_le_bytes(bytes[24..32].try_into().expect("u64 data len bytes")) as usize;
    let data = &bytes[PIPELINE_CACHE_HEADER_LEN..];
    if declared_len != data.len() {
        return Err(PipelineCacheFileError::LengthMismatch {
            declared: declared_len,
            actual: data.len(),
        });
    }
    let expected_hash = u64::from_le_bytes(bytes[32..40].try_into().expect("u64 data hash bytes"));
    let actual_hash = stable_hash_u64(data);
    if actual_hash != expected_hash {
        return Err(PipelineCacheFileError::HashMismatch {
            expected: expected_hash,
            actual: actual_hash,
        });
    }
    Ok(data)
}

#[derive(Debug)]
enum PipelineCacheFileError {
    TooShort { actual: usize },
    BadMagic,
    UnsupportedVersion(u32),
    BadHeaderLen(u32),
    IdentityMismatch { expected: u64, actual: u64 },
    LengthMismatch { declared: usize, actual: usize },
    HashMismatch { expected: u64, actual: u64 },
}

impl std::fmt::Display for PipelineCacheFileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::TooShort { actual } => {
                write!(
                    f,
                    "file is too short for Lanius cache header ({actual} bytes)"
                )
            }
            Self::BadMagic => write!(f, "missing Lanius cache header"),
            Self::UnsupportedVersion(version) => {
                write!(f, "unsupported cache header version {version}")
            }
            Self::BadHeaderLen(header_len) => {
                write!(f, "unexpected cache header length {header_len}")
            }
            Self::IdentityMismatch { expected, actual } => write!(
                f,
                "cache identity mismatch expected={expected:016x} actual={actual:016x}"
            ),
            Self::LengthMismatch { declared, actual } => write!(
                f,
                "cache data length mismatch declared={declared} actual={actual}"
            ),
            Self::HashMismatch { expected, actual } => write!(
                f,
                "cache data hash mismatch expected={expected:016x} actual={actual:016x}"
            ),
        }
    }
}

fn stable_hash_u64(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325u64 ^ (bytes.len() as u64);
    let mut chunks = bytes.chunks_exact(8);
    for chunk in chunks.by_ref() {
        let word = u64::from_le_bytes(chunk.try_into().expect("u64 cache hash chunk"));
        hash ^= word.wrapping_mul(0x9e3779b185ebca87);
        hash = hash.rotate_left(27).wrapping_mul(0x94d049bb133111eb);
    }
    for (idx, byte) in chunks.remainder().iter().enumerate() {
        hash ^= u64::from(*byte) << (idx * 8);
        hash = hash.rotate_left(11).wrapping_mul(0x9e3779b185ebca87);
    }
    hash ^= hash >> 33;
    hash = hash.wrapping_mul(0xff51afd7ed558ccd);
    hash ^= hash >> 33;
    hash = hash.wrapping_mul(0xc4ceb9fe1a85ec53);
    hash ^= hash >> 33;
    hash
}

fn prune_pipeline_cache_dir(
    cache_dir: &std::path::Path,
    current_path: &std::path::Path,
    adapter_key: &str,
) {
    if !crate::gpu::env::env_bool_strict("LANIUS_PIPELINE_CACHE_PRUNE", true) {
        return;
    }
    let max_files = crate::gpu::env::env_u64("LANIUS_PIPELINE_CACHE_MAX_FILES", 8) as usize;
    let max_bytes = crate::gpu::env::env_u64(
        "LANIUS_PIPELINE_CACHE_MAX_BYTES",
        256u64.saturating_mul(1024).saturating_mul(1024),
    );
    let max_age_days = crate::gpu::env::env_u64("LANIUS_PIPELINE_CACHE_MAX_AGE_DAYS", 30);
    let Ok(read_dir) = fs::read_dir(cache_dir) else {
        return;
    };
    let now = SystemTime::now();
    let max_age = Duration::from_secs(max_age_days.saturating_mul(24 * 60 * 60));
    let mut entries = Vec::new();
    for entry in read_dir.flatten() {
        let path = entry.path();
        if path == current_path {
            continue;
        }
        let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        if !name.starts_with(adapter_key) {
            continue;
        }
        let Ok(metadata) = entry.metadata() else {
            continue;
        };
        if !metadata.is_file() {
            continue;
        }
        let modified = metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH);
        let len = metadata.len();
        if now.duration_since(modified).is_ok_and(|age| age > max_age) {
            remove_pipeline_cache_file(&path, "age");
            continue;
        }
        entries.push(PipelineCachePruneEntry {
            path,
            len,
            modified,
        });
    }
    entries.sort_by(|left, right| {
        right
            .modified
            .cmp(&left.modified)
            .then_with(|| right.len.cmp(&left.len))
            .then_with(|| right.path.cmp(&left.path))
    });
    let mut kept_files = 0usize;
    let mut kept_bytes = 0u64;
    for entry in entries {
        let exceeds_files = kept_files >= max_files;
        let exceeds_bytes = kept_bytes.saturating_add(entry.len) > max_bytes;
        if exceeds_files || exceeds_bytes {
            remove_pipeline_cache_file(&entry.path, "budget");
            continue;
        }
        kept_files = kept_files.saturating_add(1);
        kept_bytes = kept_bytes.saturating_add(entry.len);
    }
}

struct PipelineCachePruneEntry {
    path: PathBuf,
    len: u64,
    modified: SystemTime,
}

fn remove_pipeline_cache_file(path: &std::path::Path, reason: &str) {
    if let Err(err) = fs::remove_file(path) {
        warn!(
            "failed to prune pipeline cache file {} for {reason}: {err}",
            path.display()
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pipeline_cache_file_round_trips_opaque_blob() {
        let identity_hash = 0x1234_5678_9abc_def0;
        let blob = b"opaque wgpu cache data";
        let mut file = pipeline_cache_file_header(blob, identity_hash).to_vec();
        file.extend_from_slice(blob);

        let decoded = decode_pipeline_cache_file(&file, identity_hash).unwrap();

        assert_eq!(decoded, blob);
    }

    #[test]
    fn pipeline_cache_file_rejects_wrong_identity() {
        let blob = b"opaque wgpu cache data";
        let mut file = pipeline_cache_file_header(blob, 0x11).to_vec();
        file.extend_from_slice(blob);

        let err = decode_pipeline_cache_file(&file, 0x22).unwrap_err();

        assert!(matches!(
            err,
            PipelineCacheFileError::IdentityMismatch { .. }
        ));
    }

    #[test]
    fn pipeline_cache_file_rejects_partial_write() {
        let identity_hash = 0x1234_5678_9abc_def0;
        let blob = b"opaque wgpu cache data";
        let mut file = pipeline_cache_file_header(blob, identity_hash).to_vec();
        file.extend_from_slice(&blob[..blob.len() - 1]);

        let err = decode_pipeline_cache_file(&file, identity_hash).unwrap_err();

        assert!(matches!(err, PipelineCacheFileError::LengthMismatch { .. }));
    }
}
