use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex, OnceLock, Weak},
};

use log::warn;

/// Global GPU device/queue resource shared across compiler subsystems.
pub struct GpuDevice {
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
    pub timers_supported: bool,
    pub pipeline_cache: Option<Arc<wgpu::PipelineCache>>,
    pipeline_cache_path: Option<PathBuf>,
}

impl GpuDevice {
    /// Creates a GPU device/queue resource that can be shared across compiler subsystems.
    pub fn new() -> Self {
        create_context()
    }

    pub fn persist_pipeline_cache(&self) {
        let Some(cache) = self.pipeline_cache.as_ref() else {
            return;
        };
        let Some(path) = self.pipeline_cache_path.as_ref() else {
            return;
        };
        let Some(data) = cache.get_data() else {
            return;
        };
        if let Some(parent) = path.parent() {
            if let Err(err) = std::fs::create_dir_all(parent) {
                warn!(
                    "failed to create pipeline cache directory {}: {err}",
                    parent.display()
                );
                return;
            }
        }
        let tmp = path.with_extension("tmp");
        if let Err(err) = std::fs::write(&tmp, data) {
            warn!(
                "failed to write pipeline cache tmp file {}: {err}",
                tmp.display()
            );
            return;
        }
        if let Err(err) = std::fs::rename(&tmp, path) {
            warn!(
                "failed to move pipeline cache {} -> {}: {err}",
                tmp.display(),
                path.display()
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

    let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
        backends,
        ..Default::default()
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
    // Limits tuned from web3d survey; keep in sync across subsystems.
    limits.max_storage_buffers_per_shader_stage =
        adapter_limits.max_storage_buffers_per_shader_stage.min(16);
    limits.max_storage_buffer_binding_size = 2_147_483_644;
    limits.max_buffer_size = 2_147_483_644;

    let adapter_features = adapter.features();

    // Enable SPIRV passthrough always; add timestamp features if supported so timing can be toggled at runtime.
    let mut required_features = wgpu::Features::empty() | wgpu::Features::SPIRV_SHADER_PASSTHROUGH;
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
        memory_hints: wgpu::MemoryHints::default(),
        trace: wgpu::Trace::default(),
    }))
    .expect("failed to create wgpu device");

    device.on_uncaptured_error(Box::new(|e| {
        eprintln!("[wgpu uncaptured] {e:?}");
    }));

    let timers_supported = adapter_features.contains(wgpu::Features::TIMESTAMP_QUERY);
    let (pipeline_cache, pipeline_cache_path) = if pipeline_cache_supported {
        create_pipeline_cache(&device, &adapter_info)
    } else {
        (None, None)
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
    }
}

/// Returns a reference to the global GPU context (created on first use).
pub fn global() -> &'static GpuDevice {
    static CTX: OnceLock<GpuDevice> = OnceLock::new();
    CTX.get_or_init(GpuDevice::new)
}

pub fn persist_pipeline_cache() {
    global().persist_pipeline_cache();
}

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
) -> (Option<wgpu::PipelineCache>, Option<PathBuf>) {
    let Some(filename) = wgpu::util::pipeline_cache_key(adapter_info) else {
        return (None, None);
    };
    let cache_dir = crate::gpu::env::env_path(
        "LANIUS_PIPELINE_CACHE_DIR",
        PathBuf::from("target").join("wgpu-pipeline-cache"),
    );
    let cache_path = cache_dir.join(filename);
    let cache_data = match std::fs::read(&cache_path) {
        Ok(data) => Some(data),
        Err(err) => {
            warn!(
                "failed to read pipeline cache {}: {err}",
                cache_path.display()
            );
            None
        }
    };
    let cache = unsafe {
        device.create_pipeline_cache(&wgpu::PipelineCacheDescriptor {
            label: Some("laniusc_pipeline_cache"),
            data: cache_data.as_deref(),
            // This is only wgpu cache-data recovery when an on-disk pipeline
            // cache is stale. Adapter selection above keeps compiler execution
            // on a real GPU and does not allow a CPU compiler fallback.
            fallback: true,
        })
    };
    (Some(cache), Some(cache_path))
}
