use std::sync::{Arc, OnceLock};

/// Global GPU device/queue context shared across subsystems.
pub struct GpuDeviceCtx {
    pub device: Arc<wgpu::Device>,
    pub queue: Arc<wgpu::Queue>,
    pub timers_supported: bool,
}

fn create_context() -> GpuDeviceCtx {
    let backends = match std::env::var("LANIUS_BACKEND")
        .unwrap_or_else(|_| "auto".into())
        .to_ascii_lowercase()
        .as_str()
    {
        "vulkan" | "vk" => wgpu::Backends::VULKAN,
        "dx12" => wgpu::Backends::DX12,
        "metal" | "mtl" => wgpu::Backends::METAL,
        "gl" => wgpu::Backends::GL,
        _ => wgpu::Backends::all(),
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

    let mut limits = wgpu::Limits::defaults();
    // Limits tuned from web3d survey; keep in sync across subsystems.
    limits.max_storage_buffers_per_shader_stage = 10;
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

    GpuDeviceCtx {
        device: Arc::new(device),
        queue: Arc::new(queue),
        timers_supported,
    }
}

/// Returns a reference to the global GPU context (created on first use).
pub fn global() -> &'static GpuDeviceCtx {
    static CTX: OnceLock<GpuDeviceCtx> = OnceLock::new();
    CTX.get_or_init(create_context)
}

