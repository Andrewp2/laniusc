use std::{
    collections::HashMap,
    fs::{self, File},
    io::Write,
    path::PathBuf,
    sync::{
        Arc,
        Mutex,
        OnceLock,
        Weak,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::{Duration, Instant, SystemTime},
};

use log::warn;

const PIPELINE_CACHE_FILE_MAGIC: [u8; 8] = *b"LANIUSPC";
const PIPELINE_CACHE_FILE_VERSION: u32 = 1;
const PIPELINE_CACHE_HEADER_LEN: usize = 8 + 4 + 4 + 8 + 8 + 8;
/// While pipelines are being created, check the cache at most this often, so
/// a killed or timed-out process keeps most of its driver compiles.
const LAZY_PERSIST_INTERVAL: Duration = Duration::from_secs(10);
/// Pipelines created since the cache was last checked. Creation time cannot
/// tell a cache hit from a compile (the driver's own disk cache serves
/// compiles in a few milliseconds), so a check compares the cache content
/// with what is on disk instead.
static PIPELINES_CREATED_SINCE_PERSIST: AtomicU64 = AtomicU64::new(0);
/// Pipelines created since the cache was loaded. A cache seeded from another
/// kernel set must grow once this set creates its pipelines; if its content
/// still equals the seed, the driver stopped adding pipelines to it.
static PIPELINES_CREATED_SINCE_LOAD: AtomicU64 = AtomicU64::new(0);
/// A seed file larger than this starts the kernel set's cache fresh: the
/// driver stops adding pipelines to a cache near ~130 MiB.
const PIPELINE_CACHE_SEED_MAX_BYTES: u64 = 100 * 1024 * 1024;
/// When the cache was last persisted; None before the first persist.
static LAST_PIPELINE_CACHE_PERSIST: Mutex<Option<Instant>> = Mutex::new(None);
/// Serializes persists: concurrent writers would share one tmp file.
static PIPELINE_CACHE_PERSIST_LOCK: Mutex<()> = Mutex::new(());
static GLOBAL_DEVICE: OnceLock<Result<GpuDevice, GpuDeviceInitializationError>> = OnceLock::new();
/// Global GPU device/queue resource shared across compiler subsystems.
pub struct GpuDevice {
    instance: wgpu::Instance,
    /// Shared wgpu device.
    pub device: Arc<wgpu::Device>,
    /// Shared wgpu queue.
    pub queue: Arc<wgpu::Queue>,
    /// Whether timestamp queries were requested successfully.
    pub timers_supported: bool,
    /// Pipeline cache associated with this device, when supported.
    pipeline_cache: Mutex<Option<Arc<wgpu::PipelineCache>>>,
    pipeline_cache_path: Option<PathBuf>,
    pipeline_cache_identity_hash: Option<u64>,
    pipeline_cache_dirty: Arc<AtomicBool>,
    pipeline_cache_persisted_hash: Mutex<Option<u64>>,
    /// Hash of the blob seeded from another kernel set's file, when this
    /// kernel set had no file of its own.
    pipeline_cache_seed_hash: Option<u64>,
}

/// Failure to select and initialize a GPU-backed wgpu device.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum GpuDeviceInitializationError {
    /// wgpu could not find any adapter for the selected backend.
    NoAdapter,
    /// Adapter discovery selected a CPU software implementation.
    SoftwareAdapter {
        /// Adapter name reported by wgpu.
        name: String,
        /// Backend used by the software adapter.
        backend: wgpu::Backend,
    },
    /// The selected hardware adapter could not create a logical device.
    RequestDevice(String),
}

impl std::fmt::Display for GpuDeviceInitializationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoAdapter => write!(f, "no suitable GPU adapter was found"),
            Self::SoftwareAdapter { name, backend } => write!(
                f,
                "adapter {name:?} on {backend:?} is a CPU software adapter, not a GPU"
            ),
            Self::RequestDevice(detail) => write!(f, "failed to create wgpu device: {detail}"),
        }
    }
}

impl std::error::Error for GpuDeviceInitializationError {}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WgpuRegistryStats {
    pub kept_from_user: usize,
    pub released_from_user: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WgpuResourceStats {
    pub buffers: WgpuRegistryStats,
    pub bind_groups: WgpuRegistryStats,
    pub command_encoders: WgpuRegistryStats,
    pub command_buffers: WgpuRegistryStats,
    pub compute_pipelines: WgpuRegistryStats,
    pub query_sets: WgpuRegistryStats,
}

impl GpuDevice {
    /// Creates a GPU device/queue resource that can be shared across compiler subsystems.
    pub fn new() -> Self {
        Self::try_new().unwrap_or_else(|err| panic!("failed to initialize GPU device: {err}"))
    }

    /// Tries to create a GPU device without accepting a CPU software adapter by default.
    pub fn try_new() -> Result<Self, GpuDeviceInitializationError> {
        create_context()
    }

    /// Returns wgpu-core's current user-owned and dependency-retained resource
    /// counts. This excludes backend-private Vulkan driver allocations.
    pub fn resource_stats(&self) -> Option<WgpuResourceStats> {
        let report = self.instance.generate_report()?;
        let hub = report.hub_report();
        macro_rules! registry_stats {
            ($report:expr) => {
                WgpuRegistryStats {
                    kept_from_user: $report.num_kept_from_user,
                    released_from_user: $report.num_released_from_user,
                }
            };
        }
        Some(WgpuResourceStats {
            buffers: registry_stats!(hub.buffers),
            bind_groups: registry_stats!(hub.bind_groups),
            command_encoders: registry_stats!(hub.command_encoders),
            command_buffers: registry_stats!(hub.command_buffers),
            compute_pipelines: registry_stats!(hub.compute_pipelines),
            query_sets: registry_stats!(hub.query_sets),
        })
    }

    /// Persists the current wgpu pipeline cache to disk when supported.
    pub fn persist_pipeline_cache(&self) {
        let _persist = PIPELINE_CACHE_PERSIST_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        PIPELINES_CREATED_SINCE_PERSIST.store(0, Ordering::Release);
        if let Ok(mut last) = LAST_PIPELINE_CACHE_PERSIST.lock() {
            *last = Some(Instant::now());
        }
        let timer = PipelineCachePersistTimer::new();
        let force_persist =
            crate::gpu::env::env_bool_truthy("LANIUS_PIPELINE_CACHE_PERSIST_ALWAYS", false);
        if !take_pipeline_cache_dirty(&self.pipeline_cache_dirty, force_persist) {
            let now = Instant::now();
            timer.span("skipped.clean", now, now);
            return;
        }
        let Some(cache) = self
            .pipeline_cache
            .lock()
            .ok()
            .and_then(|cache| cache.clone())
        else {
            self.pipeline_cache_dirty.store(true, Ordering::Release);
            return;
        };
        let Some(path) = self.pipeline_cache_path.as_ref() else {
            self.pipeline_cache_dirty.store(true, Ordering::Release);
            return;
        };
        let Some(identity_hash) = self.pipeline_cache_identity_hash else {
            self.pipeline_cache_dirty.store(true, Ordering::Release);
            return;
        };
        let total_start = Instant::now();
        let start = Instant::now();
        let Some(data) = cache.get_data() else {
            let end = Instant::now();
            timer.span("get_data.empty", start, end);
            timer.span("total.empty", total_start, end);
            self.pipeline_cache_dirty.store(true, Ordering::Release);
            return;
        };
        let end = Instant::now();
        timer.span("get_data", start, end);
        timer.bytes("pipeline_cache.persist.bytes", end, data.len());
        let start = Instant::now();
        let mut data_hash = stable_hash_u64(&data);
        timer.span("hash", start, Instant::now());
        let capped = self.pipeline_cache_seed_hash == Some(data_hash)
            && PIPELINES_CREATED_SINCE_LOAD.load(Ordering::Acquire) != 0;
        let data: &[u8] = if capped {
            // Seeded from another kernel set, this set created its pipelines
            // and none was added. Saving the seed again would block this set
            // for good, so save an empty cache: the next start begins fresh.
            let now = Instant::now();
            timer.span("capped", now, now);
            warn!(
                "pipeline cache seeded for {} did not grow after {} pipeline creations; its next start begins fresh",
                path.display(),
                PIPELINES_CREATED_SINCE_LOAD.load(Ordering::Acquire)
            );
            data_hash = stable_hash_u64(&[]);
            &[]
        } else {
            &data
        };
        let already_persisted = self
            .pipeline_cache_persisted_hash
            .lock()
            .ok()
            .and_then(|hash| *hash)
            == Some(data_hash);
        if !force_persist && already_persisted {
            timer.span("skipped.unchanged", total_start, Instant::now());
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
                self.pipeline_cache_dirty.store(true, Ordering::Release);
                return;
            }
            timer.span("create_dir_all", start, Instant::now());
        }
        let tmp = pipeline_cache_tmp_path(path);
        let start = Instant::now();
        if let Err(err) = write_pipeline_cache_tmp(&tmp, data, identity_hash, data_hash, &timer) {
            let end = Instant::now();
            timer.span("write_tmp.failed", start, end);
            timer.span("total.failed", total_start, end);
            warn!(
                "failed to write pipeline cache tmp file {}: {err}",
                tmp.display()
            );
            self.pipeline_cache_dirty.store(true, Ordering::Release);
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
            self.pipeline_cache_dirty.store(true, Ordering::Release);
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
            .lock()
            .ok()
            .and_then(|cache| cache.clone())
            .and_then(|cache| cache.get_data())
            .map(|data| data.len())
    }

    /// Persists and releases the driver cache after eager pipeline creation.
    pub fn persist_and_release_pipeline_cache(&self) {
        self.persist_pipeline_cache();
        unregister_pipeline_cache(&self.device);
        if let Ok(mut cache) = self.pipeline_cache.lock() {
            cache.take();
        }
        let _ = self.device.poll(wgpu::PollType::Poll);
    }
}

fn take_pipeline_cache_dirty(dirty: &AtomicBool, force: bool) -> bool {
    dirty.swap(false, Ordering::AcqRel) || force
}

fn write_pipeline_cache_tmp(
    path: &std::path::Path,
    data: &[u8],
    identity_hash: u64,
    data_hash: u64,
    timer: &PipelineCachePersistTimer,
) -> std::io::Result<()> {
    let start = Instant::now();
    let header = pipeline_cache_file_header(data.len(), identity_hash, data_hash);
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

fn create_context() -> Result<GpuDevice, GpuDeviceInitializationError> {
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
        flags: instance_flags(crate::gpu::env::env_bool_truthy(
            "LANIUS_GPU_DEBUG_LABELS",
            false,
        )),
        ..wgpu::InstanceDescriptor::new_without_display_handle()
    });

    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: None,
        force_fallback_adapter: false,
    }))
    .map_err(|_| GpuDeviceInitializationError::NoAdapter)?;
    let adapter_info = adapter.get_info();
    require_hardware_adapter(
        adapter_info.device_type,
        &adapter_info.name,
        adapter_info.backend,
        crate::gpu::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
    )?;

    let adapter_limits = adapter.limits();
    let limits = compiler_device_limits(&adapter_limits);

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
    .map_err(|err| GpuDeviceInitializationError::RequestDevice(err.to_string()))?;

    device.on_uncaptured_error(Arc::new(|e| {
        eprintln!("[wgpu uncaptured] {e:?}");
    }));
    device.set_device_lost_callback(|reason, message| {
        eprintln!("[wgpu device lost] reason={reason:?} message={message}");
    });

    let timers_supported = adapter_features.contains(wgpu::Features::TIMESTAMP_QUERY);
    let loaded = if pipeline_cache_supported {
        create_pipeline_cache(&device, &adapter_info)
    } else {
        LoadedPipelineCache::default()
    };
    PIPELINES_CREATED_SINCE_LOAD.store(0, Ordering::Release);
    let device = Arc::new(device);
    let pipeline_cache = loaded.cache.map(Arc::new);
    let pipeline_cache_dirty = Arc::new(AtomicBool::new(loaded.should_persist));
    if loaded.should_persist {
        // The cache file is missing or invalid: the next check writes it.
        PIPELINES_CREATED_SINCE_PERSIST.fetch_add(1, Ordering::AcqRel);
    }
    // The loaded file counts as the last persist: a few driver compiles are
    // saved by the persist after their load, not immediately one by one.
    if let Ok(mut last) = LAST_PIPELINE_CACHE_PERSIST.lock() {
        *last = Some(Instant::now());
    }
    register_pipeline_cache(&device, pipeline_cache.as_ref(), &pipeline_cache_dirty);

    Ok(GpuDevice {
        instance,
        device,
        queue: Arc::new(queue),
        timers_supported,
        pipeline_cache: Mutex::new(pipeline_cache),
        pipeline_cache_path: loaded.path,
        pipeline_cache_identity_hash: loaded.identity_hash,
        pipeline_cache_dirty,
        pipeline_cache_persisted_hash: Mutex::new(loaded.persisted_hash),
        pipeline_cache_seed_hash: loaded.seed_hash,
    })
}

fn require_hardware_adapter(
    device_type: wgpu::DeviceType,
    name: &str,
    backend: wgpu::Backend,
    allow_software_adapter: bool,
) -> Result<(), GpuDeviceInitializationError> {
    if device_type != wgpu::DeviceType::Cpu || allow_software_adapter {
        return Ok(());
    }
    Err(GpuDeviceInitializationError::SoftwareAdapter {
        name: name.to_owned(),
        backend,
    })
}

#[cfg(test)]
mod adapter_policy_tests {
    use super::*;

    #[test]
    fn physical_and_hardware_virtualized_adapters_are_accepted() {
        for device_type in [
            wgpu::DeviceType::IntegratedGpu,
            wgpu::DeviceType::DiscreteGpu,
            wgpu::DeviceType::VirtualGpu,
        ] {
            assert!(
                require_hardware_adapter(device_type, "hardware", wgpu::Backend::Vulkan, false)
                    .is_ok()
            );
        }
    }

    #[test]
    fn cpu_software_adapter_requires_explicit_opt_in() {
        let error = require_hardware_adapter(
            wgpu::DeviceType::Cpu,
            "llvmpipe",
            wgpu::Backend::Vulkan,
            false,
        )
        .expect_err("CPU adapters must not satisfy the production GPU contract");
        assert_eq!(
            error,
            GpuDeviceInitializationError::SoftwareAdapter {
                name: "llvmpipe".to_owned(),
                backend: wgpu::Backend::Vulkan,
            }
        );

        assert!(
            require_hardware_adapter(
                wgpu::DeviceType::Cpu,
                "llvmpipe",
                wgpu::Backend::Vulkan,
                true,
            )
            .is_ok()
        );
    }
}

fn compiler_device_limits(adapter_limits: &wgpu::Limits) -> wgpu::Limits {
    let mut limits = wgpu::Limits::defaults();
    // Native compiler stages use wide GPU record tables; request the adapter's
    // native storage-buffer limit so reflected pass layouts fail only when the
    // selected device genuinely cannot support the compiler's record tables.
    limits.max_storage_buffers_per_shader_stage =
        adapter_limits.max_storage_buffers_per_shader_stage;
    // The fast byte-wide radix scatter uses eight 256-bin virtual-warp
    // histograms (plus one digit row), matching the proven renderer sorter in
    // ~/code/game. Request up to 48 KiB when available; adapters below the
    // exact 9 KiB requirement select the prefix-scan fallback pipeline.
    limits.max_compute_workgroup_storage_size = adapter_limits
        .max_compute_workgroup_storage_size
        .min(48 * 1024);
    // WGPU has already applied the selected backend's hardware, driver, and
    // shader-addressing safety limits to the adapter. Keep allocation size and
    // storage-binding size distinct; the workspace arena planner may place
    // several independently bindable ranges in a larger physical buffer.
    limits.max_storage_buffer_binding_size = adapter_limits.max_storage_buffer_binding_size;
    limits.max_buffer_size = adapter_limits.max_buffer_size;
    limits
}

fn instance_flags(debug_labels: bool) -> wgpu::InstanceFlags {
    let mut flags = wgpu::InstanceFlags::from_build_config();
    flags.set(wgpu::InstanceFlags::DEBUG, debug_labels);
    // Debug builds would otherwise enable the Khronos layer whenever it is
    // installed, and no logger receives its messages. Enable it through the
    // Vulkan loader instead (VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation)
    // so it reports through its own log settings.
    flags.remove(wgpu::InstanceFlags::VALIDATION | wgpu::InstanceFlags::GPU_BASED_VALIDATION);
    flags
}

/// Returns a reference to the global GPU context (created on first use).
pub fn global() -> &'static GpuDevice {
    global_result().unwrap_or_else(|err| panic!("failed to initialize GPU device: {err}"))
}

/// Returns the process-global GPU context or its retained initialization error.
pub fn global_result() -> Result<&'static GpuDevice, &'static GpuDeviceInitializationError> {
    match GLOBAL_DEVICE.get_or_init(GpuDevice::try_new) {
        Ok(device) => Ok(device),
        Err(err) => Err(err),
    }
}

/// Persists the process-global device's pipeline cache.
pub fn persist_pipeline_cache() {
    global().persist_pipeline_cache();
}

/// Checks the process-global cache if any pipeline was created since the last
/// check, and writes it when its content differs from the file. Reading the
/// data back costs ~90 ms for the full kernel set, so a process that created
/// nothing skips it. It waits for a background check first, so call it before
/// the process exits.
pub fn persist_created_pipelines() {
    wait_for_background_persist();
    if PIPELINES_CREATED_SINCE_PERSIST.load(Ordering::Acquire) != 0
        || crate::gpu::env::env_bool_truthy("LANIUS_PIPELINE_CACHE_PERSIST_ALWAYS", false)
    {
        persist_pipeline_cache();
    }
}

/// `persist_created_pipelines` on a background thread, for callers that must
/// not wait for the readback: daemon startup and the end of a daemon job.
pub fn persist_created_pipelines_in_background() {
    if let Some(Ok(global)) = GLOBAL_DEVICE.get() {
        spawn_background_persist(global);
    }
}

/// `persist_created_pipelines_in_background` when `device` is the
/// process-global device; for lazy kernel loads inside a job. It never
/// initializes the global device.
pub fn persist_created_pipelines_for_device(device: &wgpu::Device) {
    if let Some(global) = initialized_global_for(device) {
        spawn_background_persist(global);
    }
}

/// Set while a background check runs. Pipelines created after it reset the
/// counter are counted for the next check.
static BACKGROUND_PERSIST_RUNNING: AtomicBool = AtomicBool::new(false);

fn spawn_background_persist(global: &'static GpuDevice) {
    if PIPELINES_CREATED_SINCE_PERSIST.load(Ordering::Acquire) == 0
        && !crate::gpu::env::env_bool_truthy("LANIUS_PIPELINE_CACHE_PERSIST_ALWAYS", false)
    {
        return;
    }
    if BACKGROUND_PERSIST_RUNNING
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return;
    }
    let spawned = std::thread::Builder::new()
        .name("laniusc-pipeline-cache".into())
        .spawn(move || {
            global.persist_pipeline_cache();
            BACKGROUND_PERSIST_RUNNING.store(false, Ordering::Release);
        });
    if spawned.is_err() {
        BACKGROUND_PERSIST_RUNNING.store(false, Ordering::Release);
        global.persist_pipeline_cache();
    }
}

fn wait_for_background_persist() {
    while BACKGROUND_PERSIST_RUNNING.load(Ordering::Acquire) {
        std::thread::sleep(Duration::from_millis(1));
    }
}

/// Records one compute pipeline creation, and checks the cache in the
/// background when the last check was more than `LAZY_PERSIST_INTERVAL` ago.
/// Every creation counts: the driver's disk cache serves compiles in a few
/// milliseconds, so creation time cannot tell a cache hit from a miss.
pub(crate) fn note_pipeline_created(device: &wgpu::Device) {
    PIPELINES_CREATED_SINCE_PERSIST.fetch_add(1, Ordering::AcqRel);
    PIPELINES_CREATED_SINCE_LOAD.fetch_add(1, Ordering::AcqRel);
    let due = LAST_PIPELINE_CACHE_PERSIST
        .lock()
        .map(|last| last.is_none_or(|last| last.elapsed() >= LAZY_PERSIST_INTERVAL))
        .unwrap_or(false);
    if due && let Some(global) = initialized_global_for(device) {
        spawn_background_persist(global);
    }
}

/// Whether `device` is the initialized process-global device. It never
/// initializes the global device.
pub(crate) fn is_global_device(device: &wgpu::Device) -> bool {
    initialized_global_for(device).is_some()
}

fn initialized_global_for(device: &wgpu::Device) -> Option<&'static GpuDevice> {
    // wgpu compares devices by identity, so a cloned handle matches too.
    GLOBAL_DEVICE
        .get()
        .and_then(|global| global.as_ref().ok())
        .filter(|global| *global.device == *device)
}

/// Returns the pipeline cache registered for a wgpu device.
pub fn pipeline_cache_for(device: &wgpu::Device) -> Option<Arc<wgpu::PipelineCache>> {
    let key = device as *const wgpu::Device as usize;
    match pipeline_cache_registry().lock() {
        Ok(caches) => caches.get(&key).and_then(|entry| entry.cache.upgrade()),
        Err(err) => {
            warn!(
                "failed to lock pipeline cache registry: {err}; proceeding without pipeline cache"
            );
            None
        }
    }
}

/// Marks the registered driver cache dirty after creating a compute pipeline.
pub fn mark_pipeline_cache_dirty(device: &wgpu::Device) {
    let key = device as *const wgpu::Device as usize;
    if let Ok(caches) = pipeline_cache_registry().lock()
        && let Some(dirty) = caches.get(&key).and_then(|entry| entry.dirty.upgrade())
    {
        dirty.store(true, Ordering::Release);
    }
}

fn register_pipeline_cache(
    device: &Arc<wgpu::Device>,
    cache: Option<&Arc<wgpu::PipelineCache>>,
    dirty: &Arc<AtomicBool>,
) {
    let Some(cache) = cache else {
        return;
    };
    let key = Arc::as_ptr(device) as usize;
    match pipeline_cache_registry().lock() {
        Ok(mut caches) => {
            caches.insert(
                key,
                RegisteredPipelineCache {
                    cache: Arc::downgrade(cache),
                    dirty: Arc::downgrade(dirty),
                },
            );
        }
        Err(err) => {
            warn!("failed to register pipeline cache due poisoned lock: {err}");
        }
    }
}

fn unregister_pipeline_cache(device: &Arc<wgpu::Device>) {
    let key = Arc::as_ptr(device) as usize;
    if let Ok(mut caches) = pipeline_cache_registry().lock() {
        caches.remove(&key);
    }
}

struct RegisteredPipelineCache {
    cache: Weak<wgpu::PipelineCache>,
    dirty: Weak<AtomicBool>,
}

fn pipeline_cache_registry() -> &'static Mutex<HashMap<usize, RegisteredPipelineCache>> {
    static REGISTRY: OnceLock<Mutex<HashMap<usize, RegisteredPipelineCache>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

/// The pipeline cache loaded at device creation, with what persisting it needs.
#[derive(Default)]
struct LoadedPipelineCache {
    cache: Option<wgpu::PipelineCache>,
    path: Option<PathBuf>,
    identity_hash: Option<u64>,
    should_persist: bool,
    persisted_hash: Option<u64>,
    seed_hash: Option<u64>,
}

fn create_pipeline_cache(
    device: &wgpu::Device,
    adapter_info: &wgpu::AdapterInfo,
) -> LoadedPipelineCache {
    let timer = PipelineCachePersistTimer::new();
    let total_start = Instant::now();
    let Some(adapter_key) = wgpu::util::pipeline_cache_key(adapter_info) else {
        timer.span_prefixed("create", "unsupported_key", total_start, Instant::now());
        return LoadedPipelineCache::default();
    };
    let start = Instant::now();
    let cache_dir = crate::gpu::env::env_path(
        "LANIUS_PIPELINE_CACHE_DIR",
        PathBuf::from("target").join("wgpu-pipeline-cache"),
    );
    let key = PipelineCacheKey::new(
        &adapter_key,
        option_env!("LANIUS_WGPU_VERSION").unwrap_or("unknown"),
        &crate::shader_artifacts::digest(),
    );
    let cache_path = cache_dir.join(&key.filename);
    timer.span_prefixed("create", "path", start, Instant::now());
    let start = Instant::now();
    let others = prune_pipeline_cache_dir(&cache_dir, &cache_path, &adapter_key);
    timer.span_prefixed("create", "prune", start, Instant::now());
    let mut should_persist = false;
    let mut persisted_hash = None;
    let mut seed_hash = None;
    let mut file = match read_pipeline_cache_file(&cache_path, key.identity_hash, "", &timer) {
        Ok(Some(file)) => {
            persisted_hash = Some(pipeline_cache_file_data_hash(&file));
            Some(file)
        }
        Ok(None) => {
            should_persist = true;
            None
        }
        Err(_) => {
            remove_pipeline_cache_file(&cache_path, "invalid");
            should_persist = true;
            None
        }
    };
    if file.is_none() {
        // This kernel set has no file yet: start from the most recently
        // written set's file, so pipelines the shader edit left unchanged
        // stay cache hits.
        let seed_max_bytes = crate::gpu::env::env_u64(
            "LANIUS_PIPELINE_CACHE_SEED_MAX_BYTES",
            PIPELINE_CACHE_SEED_MAX_BYTES,
        );
        let now = Instant::now();
        match choose_pipeline_cache_seed(&others, &key, seed_max_bytes) {
            PipelineCacheSeed::None => timer.span_prefixed("create", "seed.none", now, now),
            PipelineCacheSeed::TooLarge(seed) => {
                timer.span_prefixed("create", "seed.too_large", now, now);
                timer.bytes_prefixed("size", "pipeline_cache.create.seed_file_bytes", now, seed.len as usize);
            }
            PipelineCacheSeed::Use(seed) => {
                match read_pipeline_cache_file(&seed.path, key.identity_hash, "seed.", &timer) {
                    Ok(Some(seed_file)) => {
                        seed_hash = Some(pipeline_cache_file_data_hash(&seed_file));
                        file = Some(seed_file);
                    }
                    Ok(None) => {}
                    Err(_) => remove_pipeline_cache_file(&seed.path, "invalid"),
                }
            }
        }
    }
    // An empty blob is a fresh start, saved after a seed stopped growing.
    let cache_data = file
        .as_deref()
        .map(|file| &file[PIPELINE_CACHE_HEADER_LEN..])
        .filter(|data| !data.is_empty());
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
    LoadedPipelineCache {
        cache: Some(cache),
        path: Some(cache_path),
        identity_hash: Some(key.identity_hash),
        should_persist,
        persisted_hash,
        seed_hash,
    }
}

/// Reads and validates one cache file. `Ok(None)` when it is missing or
/// unreadable; the returned bytes include the header.
fn read_pipeline_cache_file(
    path: &std::path::Path,
    identity_hash: u64,
    stage_prefix: &str,
    timer: &PipelineCachePersistTimer,
) -> Result<Option<Vec<u8>>, PipelineCacheFileError> {
    let start = Instant::now();
    let file = match fs::read(path) {
        Ok(file) => file,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            let stage = format!("{stage_prefix}read.missing");
            timer.span_prefixed("create", &stage, start, Instant::now());
            return Ok(None);
        }
        Err(err) => {
            let stage = format!("{stage_prefix}read.failed");
            timer.span_prefixed("create", &stage, start, Instant::now());
            warn!("failed to read pipeline cache {}: {err}", path.display());
            return Ok(None);
        }
    };
    let end = Instant::now();
    timer.span_prefixed("create", &format!("{stage_prefix}read"), start, end);
    timer.bytes_prefixed(
        "size",
        &format!("pipeline_cache.create.{stage_prefix}input_file_bytes"),
        end,
        file.len(),
    );
    let start = Instant::now();
    match decode_pipeline_cache_file(&file, identity_hash) {
        Ok(_) => {
            timer.span_prefixed("create", &format!("{stage_prefix}decode"), start, Instant::now());
            Ok(Some(file))
        }
        Err(err) => {
            let stage = format!("{stage_prefix}decode.invalid");
            timer.span_prefixed("create", &stage, start, Instant::now());
            warn!("discarding pipeline cache {}: {err}", path.display());
            Err(err)
        }
    }
}

/// The data hash recorded in a validated cache file's header.
fn pipeline_cache_file_data_hash(file: &[u8]) -> u64 {
    u64::from_le_bytes(file[32..40].try_into().expect("u64 data hash bytes"))
}

/// Names one kernel set's pipeline-cache file. Every file for one adapter and
/// wgpu version shares `prefix` and the header identity hash, so a kernel set
/// without a file of its own can seed from another set's.
///
/// A wgpu pipeline cache is a keyed collection, not one precompiled bundle:
/// a seeded cache keeps every unchanged pipeline a hit after a shader edit.
/// One file per kernel set keeps each file to about one set's pipelines; a
/// single shared file grew past the size where the driver stops adding
/// pipelines, and from then on every new pipeline compiled on every start.
#[derive(Clone, Debug, PartialEq, Eq)]
struct PipelineCacheKey {
    prefix: String,
    filename: String,
    identity_hash: u64,
}

impl PipelineCacheKey {
    fn new(adapter_key: &str, wgpu_version: &str, kernel_set_digest: &str) -> Self {
        let identity = format!("adapter={adapter_key};wgpu={wgpu_version};format=1");
        let identity_hash = stable_hash_u64(identity.as_bytes());
        let prefix = format!(
            "{}_laniusc-pipelines-v1_wgpu-{}_key-{identity_hash:016x}",
            adapter_key,
            sanitize_cache_key_component(wgpu_version),
        );
        let kernel_set: String = sanitize_cache_key_component(kernel_set_digest)
            .chars()
            .take(16)
            .collect();
        let filename = format!("{prefix}_set-{kernel_set}");
        Self {
            prefix,
            filename,
            identity_hash,
        }
    }

    /// Whether `name` is another kernel set's file (or the single shared file
    /// older builds wrote) that this kernel set can seed from.
    fn can_seed_from(&self, name: &str) -> bool {
        name != self.filename
            && name.strip_prefix(self.prefix.as_str()).is_some_and(|rest| {
                rest.is_empty() || (rest.starts_with("_set-") && !rest.ends_with(".tmp"))
            })
    }
}

#[derive(Debug, PartialEq, Eq)]
enum PipelineCacheSeed<'a> {
    None,
    Use(&'a PipelineCacheDirEntry),
    TooLarge(&'a PipelineCacheDirEntry),
}

/// The most recently written file this kernel set can seed from. One over
/// `max_bytes` is near the size where the driver stops adding pipelines, so
/// the set starts fresh instead.
fn choose_pipeline_cache_seed<'a>(
    entries: &'a [PipelineCacheDirEntry],
    key: &PipelineCacheKey,
    max_bytes: u64,
) -> PipelineCacheSeed<'a> {
    let newest = entries
        .iter()
        .filter(|entry| key.can_seed_from(&entry.name))
        .max_by(|left, right| {
            left.modified
                .cmp(&right.modified)
                .then_with(|| left.len.cmp(&right.len))
                .then_with(|| left.name.cmp(&right.name))
        });
    match newest {
        None => PipelineCacheSeed::None,
        Some(entry) if entry.len > max_bytes => PipelineCacheSeed::TooLarge(entry),
        Some(entry) => PipelineCacheSeed::Use(entry),
    }
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

fn pipeline_cache_file_header(
    data_len: usize,
    identity_hash: u64,
    data_hash: u64,
) -> [u8; PIPELINE_CACHE_HEADER_LEN] {
    let mut header = [0u8; PIPELINE_CACHE_HEADER_LEN];
    header[0..8].copy_from_slice(&PIPELINE_CACHE_FILE_MAGIC);
    header[8..12].copy_from_slice(&PIPELINE_CACHE_FILE_VERSION.to_le_bytes());
    header[12..16].copy_from_slice(&(PIPELINE_CACHE_HEADER_LEN as u32).to_le_bytes());
    header[16..24].copy_from_slice(&identity_hash.to_le_bytes());
    header[24..32].copy_from_slice(&(data_len as u64).to_le_bytes());
    header[32..40].copy_from_slice(&data_hash.to_le_bytes());
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

/// Lists the adapter's other cache files, prunes them to the budget, and
/// returns the ones kept (seed candidates).
fn prune_pipeline_cache_dir(
    cache_dir: &std::path::Path,
    current_path: &std::path::Path,
    adapter_key: &str,
) -> Vec<PipelineCacheDirEntry> {
    let Ok(read_dir) = fs::read_dir(cache_dir) else {
        return Vec::new();
    };
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
        let name = name.to_string();
        let Ok(metadata) = entry.metadata() else {
            continue;
        };
        if !metadata.is_file() {
            continue;
        }
        entries.push(PipelineCacheDirEntry {
            path,
            name,
            len: metadata.len(),
            modified: metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH),
        });
    }
    if !crate::gpu::env::env_bool_strict("LANIUS_PIPELINE_CACHE_PRUNE", true) {
        return entries;
    }
    let budget = PipelineCacheBudget {
        max_files: crate::gpu::env::env_u64("LANIUS_PIPELINE_CACHE_MAX_FILES", 6) as usize,
        max_bytes: crate::gpu::env::env_u64(
            "LANIUS_PIPELINE_CACHE_MAX_BYTES",
            768u64.saturating_mul(1024).saturating_mul(1024),
        ),
        max_age: Duration::from_secs(
            crate::gpu::env::env_u64("LANIUS_PIPELINE_CACHE_MAX_AGE_DAYS", 30)
                .saturating_mul(24 * 60 * 60),
        ),
    };
    let (kept, removed) = plan_pipeline_cache_prune(entries, &budget, SystemTime::now());
    for (entry, reason) in removed {
        remove_pipeline_cache_file(&entry.path, reason);
    }
    kept
}

struct PipelineCacheBudget {
    /// Files kept per adapter, counting the current kernel set's file.
    max_files: usize,
    /// Bytes kept in the other kernel sets' files.
    max_bytes: u64,
    max_age: Duration,
}

/// Splits the other kernel sets' files into kept and removed (with the
/// reason): the newest are kept while they fit the budget.
fn plan_pipeline_cache_prune(
    mut entries: Vec<PipelineCacheDirEntry>,
    budget: &PipelineCacheBudget,
    now: SystemTime,
) -> (
    Vec<PipelineCacheDirEntry>,
    Vec<(PipelineCacheDirEntry, &'static str)>,
) {
    entries.sort_by(|left, right| {
        right
            .modified
            .cmp(&left.modified)
            .then_with(|| right.len.cmp(&left.len))
            .then_with(|| right.name.cmp(&left.name))
    });
    let max_others = budget.max_files.saturating_sub(1);
    let mut kept = Vec::new();
    let mut removed = Vec::new();
    let mut kept_bytes = 0u64;
    for entry in entries {
        if now
            .duration_since(entry.modified)
            .is_ok_and(|age| age > budget.max_age)
        {
            removed.push((entry, "age"));
            continue;
        }
        if kept.len() >= max_others || kept_bytes.saturating_add(entry.len) > budget.max_bytes {
            removed.push((entry, "budget"));
            continue;
        }
        kept_bytes = kept_bytes.saturating_add(entry.len);
        kept.push(entry);
    }
    (kept, removed)
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct PipelineCacheDirEntry {
    path: PathBuf,
    name: String,
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
    fn profiling_labels_enable_debug_names_without_enabling_validation() {
        let flags = instance_flags(true);

        assert!(flags.contains(wgpu::InstanceFlags::DEBUG));
        assert_eq!(
            flags.contains(wgpu::InstanceFlags::VALIDATION),
            wgpu::InstanceFlags::from_build_config().contains(wgpu::InstanceFlags::VALIDATION)
        );
    }

    #[test]
    fn compiler_buffer_limits_never_exceed_adapter_limits() {
        let mut adapter = wgpu::Limits::defaults();
        adapter.max_storage_buffer_binding_size = 512 * 1024 * 1024;
        adapter.max_buffer_size = 768 * 1024 * 1024;

        let requested = compiler_device_limits(&adapter);

        assert_eq!(
            requested.max_storage_buffer_binding_size,
            adapter.max_storage_buffer_binding_size
        );
        assert_eq!(requested.max_buffer_size, adapter.max_buffer_size);
    }

    #[test]
    fn compiler_buffer_limits_preserve_large_adapter_capabilities() {
        let mut adapter = wgpu::Limits::defaults();
        adapter.max_storage_buffer_binding_size = 3 * 1024 * 1024 * 1024;
        adapter.max_buffer_size = 4 * 1024 * 1024 * 1024;

        let requested = compiler_device_limits(&adapter);

        assert_eq!(
            requested.max_storage_buffer_binding_size,
            adapter.max_storage_buffer_binding_size
        );
        assert_eq!(requested.max_buffer_size, adapter.max_buffer_size);
    }

    #[test]
    fn pipeline_cache_file_round_trips_opaque_blob() {
        let identity_hash = 0x1234_5678_9abc_def0;
        let blob = b"opaque wgpu cache data";
        let mut file =
            pipeline_cache_file_header(blob.len(), identity_hash, stable_hash_u64(blob)).to_vec();
        file.extend_from_slice(blob);

        let decoded = decode_pipeline_cache_file(&file, identity_hash).unwrap();

        assert_eq!(decoded, blob);
    }

    #[test]
    fn pipeline_cache_file_rejects_wrong_identity() {
        let blob = b"opaque wgpu cache data";
        let mut file = pipeline_cache_file_header(blob.len(), 0x11, stable_hash_u64(blob)).to_vec();
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
        let mut file =
            pipeline_cache_file_header(blob.len(), identity_hash, stable_hash_u64(blob)).to_vec();
        file.extend_from_slice(&blob[..blob.len() - 1]);

        let err = decode_pipeline_cache_file(&file, identity_hash).unwrap_err();

        assert!(matches!(err, PipelineCacheFileError::LengthMismatch { .. }));
    }

    #[test]
    fn clean_pipeline_cache_skips_serialization_until_marked_dirty() {
        let dirty = AtomicBool::new(false);

        assert!(!take_pipeline_cache_dirty(&dirty, false));
        dirty.store(true, Ordering::Release);
        assert!(take_pipeline_cache_dirty(&dirty, false));
        assert!(!take_pipeline_cache_dirty(&dirty, false));
    }

    #[test]
    fn forced_pipeline_cache_persistence_consumes_any_dirty_mark() {
        let dirty = AtomicBool::new(true);

        assert!(take_pipeline_cache_dirty(&dirty, true));
        assert!(!dirty.load(Ordering::Acquire));
        assert!(take_pipeline_cache_dirty(&dirty, true));
    }

    fn cache_entry(name: &str, len: u64, age_secs: u64) -> PipelineCacheDirEntry {
        let now = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_000_000);
        PipelineCacheDirEntry {
            path: PathBuf::from("cache").join(name),
            name: name.to_string(),
            len,
            modified: now - Duration::from_secs(age_secs),
        }
    }

    #[test]
    fn pipeline_cache_files_are_keyed_by_kernel_set() {
        let a = PipelineCacheKey::new("nv_1234", "29.0.1", "0123456789abcdef0123");
        let b = PipelineCacheKey::new("nv_1234", "29.0.1", "fedcba9876543210ffff");
        let other_wgpu = PipelineCacheKey::new("nv_1234", "30.0.0", "0123456789abcdef0123");

        assert_ne!(a.filename, b.filename);
        assert!(a.filename.ends_with("_set-0123456789abcdef"));
        assert_eq!(a.prefix, b.prefix);
        assert_eq!(a.identity_hash, b.identity_hash);
        assert_ne!(a.identity_hash, other_wgpu.identity_hash);

        assert!(a.can_seed_from(&b.filename));
        assert!(a.can_seed_from(&a.prefix), "the shared file older builds wrote");
        assert!(!a.can_seed_from(&a.filename));
        assert!(!a.can_seed_from(&format!("{}.tmp", b.filename)));
        assert!(!a.can_seed_from(&format!("{}.tmp", a.prefix)));
        assert!(!a.can_seed_from(&other_wgpu.filename));
    }

    #[test]
    fn pipeline_cache_seeds_from_the_newest_compatible_file() {
        let key = PipelineCacheKey::new("nv_1234", "29.0.1", "aaaaaaaaaaaaaaaa");
        let older = PipelineCacheKey::new("nv_1234", "29.0.1", "bbbbbbbbbbbbbbbb");
        let newer = PipelineCacheKey::new("nv_1234", "29.0.1", "cccccccccccccccc");
        let other_wgpu = PipelineCacheKey::new("nv_1234", "30.0.0", "dddddddddddddddd");
        let entries = vec![
            cache_entry(&older.filename, 60, 300),
            cache_entry(&newer.filename, 70, 200),
            cache_entry(&format!("{}.tmp", key.prefix), 10, 1),
            cache_entry(&other_wgpu.filename, 10, 1),
        ];

        assert_eq!(
            choose_pipeline_cache_seed(&entries, &key, 100),
            PipelineCacheSeed::Use(&entries[1])
        );
        assert_eq!(
            choose_pipeline_cache_seed(&entries, &key, 65),
            PipelineCacheSeed::TooLarge(&entries[1]),
            "a seed over the limit starts fresh instead of falling back"
        );
        assert_eq!(
            choose_pipeline_cache_seed(&entries[2..], &key, 100),
            PipelineCacheSeed::None
        );
    }

    #[test]
    fn pipeline_cache_prune_keeps_the_newest_files() {
        let now = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_000_000);
        let budget = PipelineCacheBudget {
            max_files: 6,
            max_bytes: 1000,
            max_age: Duration::from_secs(10_000),
        };
        let entries: Vec<_> = (0..8)
            .map(|age| cache_entry(&format!("set-{age}"), 10, age * 100))
            .collect();

        let (kept, removed) = plan_pipeline_cache_prune(entries, &budget, now);

        // Five others plus the current kernel set's file make six.
        let kept: Vec<_> = kept.iter().map(|entry| entry.name.as_str()).collect();
        assert_eq!(kept, ["set-0", "set-1", "set-2", "set-3", "set-4"]);
        let removed: Vec<_> = removed
            .iter()
            .map(|(entry, reason)| (entry.name.as_str(), *reason))
            .collect();
        assert_eq!(
            removed,
            [("set-5", "budget"), ("set-6", "budget"), ("set-7", "budget")]
        );

        let entries = vec![
            cache_entry("new", 600, 1),
            cache_entry("big", 600, 2),
            cache_entry("small", 300, 3),
            cache_entry("stale", 1, 20_000),
        ];
        let (kept, removed) = plan_pipeline_cache_prune(entries, &budget, now);
        let kept: Vec<_> = kept.iter().map(|entry| entry.name.as_str()).collect();
        assert_eq!(kept, ["new", "small"]);
        let removed: Vec<_> = removed
            .iter()
            .map(|(entry, reason)| (entry.name.as_str(), *reason))
            .collect();
        assert_eq!(removed, [("big", "budget"), ("stale", "age")]);
    }
}
