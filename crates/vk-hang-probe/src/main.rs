//! Replays one captured compute dispatch through raw Vulkan.
//!
//! usage: vk-hang-probe CAPTURE_DIR SHADER.spv SHADER.reflect.json
//!            [--out DIR] [--timeout SECS] [--cache FILE] [--groups-x N]
//!            [--watch NAME[:WORDS]]... [--extra NAME=BYTES]... [--no-dispatch]
//!
//! With `--no-dispatch` only the pipeline is created and its executable
//! properties dumped; CAPTURE_DIR may then be `-` (every binding zero-filled).
//!
//! CAPTURE_DIR is a `LANIUS_DEBUG_CAPTURE_DIR` capture (manifest.json plus one
//! .bin per binding). Every buffer lives in host-visible, host-coherent memory
//! that stays mapped, so `--watch` buffers are printed every second while the
//! dispatch runs, and are still readable if it never finishes. Shader bindings
//! missing from the capture (for example an added breadcrumb buffer) are
//! zero-filled, `--extra` bytes each (default 1 MiB).
//!
//! The pipeline is created with the statistics and internal-representation
//! capture flags of VK_KHR_pipeline_executable_properties, and whatever the
//! driver reports is written to OUT/executables.txt (plus one file per
//! internal representation).
use std::{
    collections::HashMap,
    ffi::CStr,
    fs,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

use anyhow::{Context, Result, anyhow, bail};
use ash::vk;

struct Args {
    capture: PathBuf,
    spirv: PathBuf,
    reflection: PathBuf,
    out: PathBuf,
    timeout: Duration,
    cache: Option<PathBuf>,
    groups_x: Option<u32>,
    watch: Vec<(String, usize)>,
    extra: HashMap<String, u64>,
    no_dispatch: bool,
}

fn parse_args() -> Result<Args> {
    let mut positional = Vec::new();
    let mut out = PathBuf::from("vk-hang-probe-out");
    let mut timeout = Duration::from_secs(10);
    let mut cache = None;
    let mut groups_x = None;
    let mut watch = Vec::new();
    let mut extra = HashMap::new();
    let mut no_dispatch = false;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        let mut value = |flag: &str| args.next().ok_or_else(|| anyhow!("{flag} needs a value"));
        match arg.as_str() {
            "--out" => out = PathBuf::from(value("--out")?),
            "--timeout" => timeout = Duration::from_secs_f64(value("--timeout")?.parse()?),
            "--cache" => cache = Some(PathBuf::from(value("--cache")?)),
            "--no-dispatch" => no_dispatch = true,
            "--groups-x" => groups_x = Some(value("--groups-x")?.parse()?),
            "--watch" => {
                let spec = value("--watch")?;
                let (name, words) = spec.split_once(':').unwrap_or((&spec, "16"));
                watch.push((name.to_owned(), words.parse()?));
            }
            "--extra" => {
                let spec = value("--extra")?;
                let (name, bytes) = spec
                    .split_once('=')
                    .ok_or_else(|| anyhow!("--extra wants NAME=BYTES"))?;
                extra.insert(name.to_owned(), bytes.parse()?);
            }
            _ if arg.starts_with("--") => bail!("unknown flag {arg}"),
            _ => positional.push(PathBuf::from(arg)),
        }
    }
    let [capture, spirv, reflection]: [PathBuf; 3] = positional
        .try_into()
        .map_err(|_| anyhow!("usage: vk-hang-probe CAPTURE_DIR SHADER.spv SHADER.reflect.json [flags]"))?;
    Ok(Args { capture, spirv, reflection, out, timeout, cache, groups_x, watch, extra, no_dispatch })
}

/// One set-0 binding from the Slang reflection JSON.
struct Binding {
    name: String,
    index: u32,
    uniform: bool,
}

fn reflected_bindings(path: &Path) -> Result<Vec<Binding>> {
    let json: serde_json::Value = serde_json::from_slice(&fs::read(path)?)?;
    let mut bindings = Vec::new();
    for parameter in json["parameters"].as_array().ok_or_else(|| anyhow!("no parameters"))? {
        let binding = &parameter["binding"];
        if binding["kind"] != "descriptorTableSlot" || binding["space"].as_u64().unwrap_or(0) != 0 {
            continue;
        }
        bindings.push(Binding {
            name: parameter["name"].as_str().unwrap_or("").to_owned(),
            index: binding["index"].as_u64().ok_or_else(|| anyhow!("binding without index"))? as u32,
            uniform: parameter["type"]["kind"] == "constantBuffer",
        });
    }
    Ok(bindings)
}

struct MappedBuffer {
    name: String,
    buffer: vk::Buffer,
    pointer: *const u32,
    bytes: u64,
}

impl MappedBuffer {
    fn words(&self, count: usize) -> Vec<u32> {
        let available = (self.bytes / 4) as usize;
        // SAFETY: the mapping covers `bytes` and stays mapped until exit.
        // Volatile reads observe device writes through coherent memory.
        (0..count.min(available))
            .map(|i| unsafe { self.pointer.add(i).read_volatile() })
            .collect()
    }
}

fn main() -> Result<()> {
    let args = parse_args()?;
    fs::create_dir_all(&args.out)?;
    let manifest: serde_json::Value = if args.capture == Path::new("-") {
        serde_json::json!({ "groups": [1, 1, 1], "bindings": [] })
    } else {
        serde_json::from_slice(&fs::read(args.capture.join("manifest.json")).context("manifest.json")?)?
    };
    let groups = manifest["groups"]
        .as_array()
        .ok_or_else(|| anyhow!("manifest has no groups"))?
        .iter()
        .map(|v| v.as_u64().unwrap_or(1).max(1) as u32)
        .collect::<Vec<_>>();
    let mut captured = HashMap::new();
    for binding in manifest["bindings"].as_array().ok_or_else(|| anyhow!("manifest has no bindings"))? {
        let name = binding["name"].as_str().unwrap_or("").to_owned();
        let file = args.capture.join(binding["file"].as_str().unwrap_or(""));
        captured.insert(name, fs::read(&file).with_context(|| format!("{}", file.display()))?);
    }
    let bindings = reflected_bindings(&args.reflection)?;
    let spirv = fs::read(&args.spirv)?;
    if spirv.len() % 4 != 0 {
        bail!("{} is not SPIR-V", args.spirv.display());
    }
    let code = spirv
        .chunks_exact(4)
        .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
        .collect::<Vec<_>>();

    // SAFETY: plain Vulkan setup; every handle is used only on this thread
    // and is intentionally leaked at exit (a hung queue cannot be torn down).
    unsafe {
        let entry = ash::Entry::load()?;
        let app = vk::ApplicationInfo::default()
            .application_name(c"vk-hang-probe")
            .api_version(vk::API_VERSION_1_3);
        let instance = entry.create_instance(&vk::InstanceCreateInfo::default().application_info(&app), None)?;
        let physical = instance
            .enumerate_physical_devices()?
            .into_iter()
            .max_by_key(|&device| {
                let properties = instance.get_physical_device_properties(device);
                (properties.device_type == vk::PhysicalDeviceType::DISCRETE_GPU) as u8 * 2
                    + (properties.vendor_id == 0x10de) as u8
            })
            .ok_or_else(|| anyhow!("no Vulkan device"))?;
        let properties = instance.get_physical_device_properties(physical);
        eprintln!(
            "vk-hang-probe: device {:?}, driver version {:#x}",
            CStr::from_ptr(properties.device_name.as_ptr()),
            properties.driver_version
        );
        let mut driver = vk::PhysicalDeviceDriverProperties::default();
        let mut properties2 = vk::PhysicalDeviceProperties2::default().push_next(&mut driver);
        instance.get_physical_device_properties2(physical, &mut properties2);
        eprintln!(
            "vk-hang-probe: driver {:?} {:?}",
            CStr::from_ptr(driver.driver_name.as_ptr()),
            CStr::from_ptr(driver.driver_info.as_ptr())
        );
        let family = instance
            .get_physical_device_queue_family_properties(physical)
            .iter()
            .position(|family| family.queue_flags.contains(vk::QueueFlags::COMPUTE))
            .ok_or_else(|| anyhow!("no compute queue"))? as u32;

        let extension_names = instance
            .enumerate_device_extension_properties(physical)?
            .iter()
            .map(|e| CStr::from_ptr(e.extension_name.as_ptr()).to_owned())
            .collect::<Vec<_>>();
        let executable_properties = extension_names
            .iter()
            .any(|e| e.as_c_str() == ash::khr::pipeline_executable_properties::NAME);
        let mut enabled_extensions = Vec::new();
        if executable_properties {
            enabled_extensions.push(ash::khr::pipeline_executable_properties::NAME.as_ptr());
        }

        // Enable every supported core feature so any capability the shader
        // declares is available.
        let mut v11 = vk::PhysicalDeviceVulkan11Features::default();
        let mut v12 = vk::PhysicalDeviceVulkan12Features::default();
        let mut v13 = vk::PhysicalDeviceVulkan13Features::default();
        let mut executable_features = vk::PhysicalDevicePipelineExecutablePropertiesFeaturesKHR::default();
        let mut features = vk::PhysicalDeviceFeatures2::default()
            .push_next(&mut v11)
            .push_next(&mut v12)
            .push_next(&mut v13);
        if executable_properties {
            features = features.push_next(&mut executable_features);
        }
        instance.get_physical_device_features2(physical, &mut features);
        let priorities = [1.0f32];
        let queue_info = [vk::DeviceQueueCreateInfo::default()
            .queue_family_index(family)
            .queue_priorities(&priorities)];
        let device_info = vk::DeviceCreateInfo::default()
            .queue_create_infos(&queue_info)
            .enabled_extension_names(&enabled_extensions)
            .push_next(&mut features);
        let device = instance.create_device(physical, &device_info, None)?;
        let queue = device.get_device_queue(family, 0);

        let memory = instance.get_physical_device_memory_properties(physical);
        let wanted = vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT;
        let mut buffers = Vec::new();
        for binding in &bindings {
            let data = captured.get(&binding.name);
            let bytes = data
                .map(|d| d.len() as u64)
                .unwrap_or_else(|| *args.extra.get(&binding.name).unwrap_or(&(1 << 20)))
                .max(16)
                .next_multiple_of(16);
            if data.is_none() && !args.no_dispatch {
                eprintln!("vk-hang-probe: {} not captured; zero-filled {bytes} bytes", binding.name);
            }
            let buffer = device.create_buffer(
                &vk::BufferCreateInfo::default().size(bytes).usage(if binding.uniform {
                    vk::BufferUsageFlags::UNIFORM_BUFFER
                } else {
                    vk::BufferUsageFlags::STORAGE_BUFFER
                }),
                None,
            )?;
            let requirements = device.get_buffer_memory_requirements(buffer);
            let memory_type = (0..memory.memory_type_count)
                .find(|&i| {
                    requirements.memory_type_bits & (1 << i) != 0
                        && memory.memory_types[i as usize].property_flags.contains(wanted)
                })
                .ok_or_else(|| anyhow!("no host-coherent memory for {}", binding.name))?;
            let allocation = device.allocate_memory(
                &vk::MemoryAllocateInfo::default()
                    .allocation_size(requirements.size)
                    .memory_type_index(memory_type),
                None,
            )?;
            device.bind_buffer_memory(buffer, allocation, 0)?;
            let pointer = device.map_memory(allocation, 0, vk::WHOLE_SIZE, vk::MemoryMapFlags::empty())?
                as *mut u8;
            std::ptr::write_bytes(pointer, 0, bytes as usize);
            if let Some(data) = data {
                std::ptr::copy_nonoverlapping(data.as_ptr(), pointer, data.len());
            }
            buffers.push((
                binding.index,
                binding.uniform,
                MappedBuffer { name: binding.name.clone(), buffer, pointer: pointer as *const u32, bytes },
            ));
        }

        let layout_bindings = buffers
            .iter()
            .map(|(index, uniform, _)| {
                vk::DescriptorSetLayoutBinding::default()
                    .binding(*index)
                    .descriptor_type(if *uniform {
                        vk::DescriptorType::UNIFORM_BUFFER
                    } else {
                        vk::DescriptorType::STORAGE_BUFFER
                    })
                    .descriptor_count(1)
                    .stage_flags(vk::ShaderStageFlags::COMPUTE)
            })
            .collect::<Vec<_>>();
        let set_layout = device.create_descriptor_set_layout(
            &vk::DescriptorSetLayoutCreateInfo::default().bindings(&layout_bindings),
            None,
        )?;
        let uniform_count = buffers.iter().filter(|(_, uniform, _)| *uniform).count() as u32;
        let storage_count = buffers.len() as u32 - uniform_count;
        let pool_sizes = [
            vk::DescriptorPoolSize { ty: vk::DescriptorType::UNIFORM_BUFFER, descriptor_count: uniform_count.max(1) },
            vk::DescriptorPoolSize { ty: vk::DescriptorType::STORAGE_BUFFER, descriptor_count: storage_count.max(1) },
        ];
        let pool = device.create_descriptor_pool(
            &vk::DescriptorPoolCreateInfo::default().max_sets(1).pool_sizes(&pool_sizes),
            None,
        )?;
        let set_layouts = [set_layout];
        let set = device.allocate_descriptor_sets(
            &vk::DescriptorSetAllocateInfo::default().descriptor_pool(pool).set_layouts(&set_layouts),
        )?[0];
        let infos = buffers
            .iter()
            .map(|(_, _, mapped)| [vk::DescriptorBufferInfo { buffer: mapped.buffer, offset: 0, range: vk::WHOLE_SIZE }])
            .collect::<Vec<_>>();
        let writes = buffers
            .iter()
            .zip(&infos)
            .map(|((index, uniform, _), info)| {
                vk::WriteDescriptorSet::default()
                    .dst_set(set)
                    .dst_binding(*index)
                    .descriptor_type(if *uniform {
                        vk::DescriptorType::UNIFORM_BUFFER
                    } else {
                        vk::DescriptorType::STORAGE_BUFFER
                    })
                    .buffer_info(info)
            })
            .collect::<Vec<_>>();
        device.update_descriptor_sets(&writes, &[]);

        let pipeline_layout = device.create_pipeline_layout(
            &vk::PipelineLayoutCreateInfo::default().set_layouts(&set_layouts),
            None,
        )?;
        let module = device.create_shader_module(&vk::ShaderModuleCreateInfo::default().code(&code), None)?;
        let initial_cache = args.cache.as_ref().and_then(|path| fs::read(path).ok()).unwrap_or_default();
        let cache = device.create_pipeline_cache(
            &vk::PipelineCacheCreateInfo::default().initial_data(&initial_cache),
            None,
        )?;
        let flags = if executable_properties {
            vk::PipelineCreateFlags::CAPTURE_STATISTICS_KHR
                | vk::PipelineCreateFlags::CAPTURE_INTERNAL_REPRESENTATIONS_KHR
        } else {
            vk::PipelineCreateFlags::empty()
        };
        let stage = vk::PipelineShaderStageCreateInfo::default()
            .stage(vk::ShaderStageFlags::COMPUTE)
            .module(module)
            .name(c"main");
        let started = Instant::now();
        let pipeline = device
            .create_compute_pipelines(
                cache,
                &[vk::ComputePipelineCreateInfo::default().flags(flags).stage(stage).layout(pipeline_layout)],
                None,
            )
            .map_err(|(_, err)| anyhow!("create_compute_pipelines: {err}"))?[0];
        eprintln!("vk-hang-probe: pipeline created in {:.1} ms", started.elapsed().as_secs_f64() * 1000.0);
        if let Some(path) = &args.cache {
            fs::write(path, device.get_pipeline_cache_data(cache)?)?;
        }
        if executable_properties {
            dump_executables(&instance, &device, pipeline, &args.out)?;
        }
        if args.no_dispatch {
            std::process::exit(0);
        }

        let command_pool = device.create_command_pool(
            &vk::CommandPoolCreateInfo::default().queue_family_index(family),
            None,
        )?;
        let command = device.allocate_command_buffers(
            &vk::CommandBufferAllocateInfo::default()
                .command_pool(command_pool)
                .level(vk::CommandBufferLevel::PRIMARY)
                .command_buffer_count(1),
        )?[0];
        device.begin_command_buffer(command, &vk::CommandBufferBeginInfo::default())?;
        device.cmd_bind_pipeline(command, vk::PipelineBindPoint::COMPUTE, pipeline);
        device.cmd_bind_descriptor_sets(command, vk::PipelineBindPoint::COMPUTE, pipeline_layout, 0, &[set], &[]);
        let groups_x = args.groups_x.unwrap_or(groups[0]);
        device.cmd_dispatch(command, groups_x, groups[1], groups[2]);
        // Make shader writes visible to the host-coherent mappings.
        let barrier = vk::MemoryBarrier::default()
            .src_access_mask(vk::AccessFlags::SHADER_WRITE)
            .dst_access_mask(vk::AccessFlags::HOST_READ);
        device.cmd_pipeline_barrier(
            command,
            vk::PipelineStageFlags::COMPUTE_SHADER,
            vk::PipelineStageFlags::HOST,
            vk::DependencyFlags::empty(),
            &[barrier],
            &[],
            &[],
        );
        device.end_command_buffer(command)?;
        let fence = device.create_fence(&vk::FenceCreateInfo::default(), None)?;
        let commands = [command];
        let dispatched = Instant::now();
        device.queue_submit(queue, &[vk::SubmitInfo::default().command_buffers(&commands)], fence)?;

        let watched = args
            .watch
            .iter()
            .map(|(name, words)| {
                buffers
                    .iter()
                    .find(|(_, _, mapped)| &mapped.name == name)
                    .map(|(_, _, mapped)| (mapped, *words))
                    .ok_or_else(|| anyhow!("--watch {name}: no such binding"))
            })
            .collect::<Result<Vec<_>>>()?;
        let print_watched = |tag: &str| {
            for (mapped, words) in &watched {
                eprintln!("vk-hang-probe: [{tag}] {} = {:x?}", mapped.name, mapped.words(*words));
            }
        };
        let finished = loop {
            match device.wait_for_fences(&[fence], true, 1_000_000_000) {
                Ok(()) => break true,
                Err(vk::Result::TIMEOUT) => {}
                Err(err) => bail!("wait_for_fences: {err}"),
            }
            print_watched(&format!("{:.0}s", dispatched.elapsed().as_secs_f64()));
            if dispatched.elapsed() >= args.timeout {
                break false;
            }
        };
        let elapsed_ms = dispatched.elapsed().as_secs_f64() * 1000.0;
        print_watched(if finished { "done" } else { "hung" });
        for (_, _, mapped) in &buffers {
            let data = std::slice::from_raw_parts(mapped.pointer as *const u8, mapped.bytes as usize);
            fs::write(args.out.join(format!("{}.bin", mapped.name)), data)?;
        }
        println!(
            "{}",
            serde_json::json!({ "finished": finished, "elapsed_ms": elapsed_ms, "groups": [groups_x, groups[1], groups[2]] })
        );
        // A hung queue cannot be destroyed cleanly, and the driver's exit
        // handlers wait for it; `_exit` skips them so the kernel reclaims it.
        use std::io::Write;
        let _ = std::io::stdout().flush();
        let _ = std::io::stderr().flush();
        libc::_exit(if finished { 0 } else { 2 });
    }
}

/// Writes the driver's pipeline executable statistics and internal
/// representations, if it exposes any.
unsafe fn dump_executables(
    instance: &ash::Instance,
    device: &ash::Device,
    pipeline: vk::Pipeline,
    out: &Path,
) -> Result<()> {
    let loader = ash::khr::pipeline_executable_properties::Device::new(instance, device);
    let mut report = String::new();
    // SAFETY: the caller passes a live pipeline created with capture flags.
    let executables = unsafe { loader.get_pipeline_executable_properties(&vk::PipelineInfoKHR::default().pipeline(pipeline))? };
    for (index, executable) in executables.iter().enumerate() {
        let info = vk::PipelineExecutableInfoKHR::default().pipeline(pipeline).executable_index(index as u32);
        report += &format!(
            "executable {index}: {:?} ({:?}), subgroup size {}\n",
            executable.name_as_c_str().unwrap_or_default(),
            executable.description_as_c_str().unwrap_or_default(),
            executable.subgroup_size
        );
        for statistic in unsafe { loader.get_pipeline_executable_statistics(&info)? } {
            let value = match statistic.format {
                vk::PipelineExecutableStatisticFormatKHR::BOOL32 => unsafe { statistic.value.b32 }.to_string(),
                vk::PipelineExecutableStatisticFormatKHR::INT64 => unsafe { statistic.value.i64 }.to_string(),
                vk::PipelineExecutableStatisticFormatKHR::UINT64 => unsafe { statistic.value.u64 }.to_string(),
                vk::PipelineExecutableStatisticFormatKHR::FLOAT64 => unsafe { statistic.value.f64 }.to_string(),
                _ => "?".into(),
            };
            report += &format!(
                "  {:?} = {value}  ({:?})\n",
                statistic.name_as_c_str().unwrap_or_default(),
                statistic.description_as_c_str().unwrap_or_default()
            );
        }
        // Two-call pattern: sizes first, then storage for the text/binary data.
        let fp = loader.fp();
        let mut count = 0u32;
        unsafe {
            (fp.get_pipeline_executable_internal_representations_khr)(
                device.handle(),
                &info,
                &mut count,
                std::ptr::null_mut(),
            )
        }
        .result()?;
        let mut representations = vec![vk::PipelineExecutableInternalRepresentationKHR::default(); count as usize];
        unsafe {
            (fp.get_pipeline_executable_internal_representations_khr)(
                device.handle(),
                &info,
                &mut count,
                representations.as_mut_ptr(),
            )
        }
        .result()?;
        let mut storage = representations.iter().map(|r| vec![0u8; r.data_size]).collect::<Vec<_>>();
        for (representation, data) in representations.iter_mut().zip(&mut storage) {
            representation.p_data = data.as_mut_ptr().cast();
        }
        unsafe {
            (fp.get_pipeline_executable_internal_representations_khr)(
                device.handle(),
                &info,
                &mut count,
                representations.as_mut_ptr(),
            )
        }
        .result()?;
        for (slot, (representation, data)) in representations.iter().zip(&storage).enumerate() {
            let name = representation.name_as_c_str().unwrap_or_default().to_string_lossy().into_owned();
            let file = format!("ir_{index}_{slot}_{}.{}", name.replace(|c: char| !c.is_alphanumeric(), "_"),
                if representation.is_text == vk::TRUE { "txt" } else { "bin" });
            report += &format!("  internal representation {slot}: {name} ({} bytes) -> {file}\n", data.len());
            let end = if representation.is_text == vk::TRUE {
                data.iter().position(|&b| b == 0).unwrap_or(data.len())
            } else {
                data.len()
            };
            fs::write(out.join(file), &data[..end])?;
        }
        if representations.is_empty() {
            report += "  (driver exposes no internal representations)\n";
        }
    }
    fs::write(out.join("executables.txt"), &report)?;
    eprint!("{report}");
    Ok(())
}
