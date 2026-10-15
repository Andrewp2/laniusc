//! Compiler-wide reflected compute-kernel registry.
//!
//! A kernel is identified by its generated shader-artifact key.  Compiler
//! phases refer to that identity through graph nodes and high-level operations;
//! they do not own one Rust field or loader call per pipeline.

use std::collections::HashMap;
#[cfg(test)]
use std::sync::Arc;

use anyhow::{Context, Result};

use super::passes_core::{
    PassData,
    make_pass_data_from_shader_key,
    make_pass_data_from_shader_key_with_dynamic_uniforms,
};
use crate::reflection::SlangReflection;
#[cfg(test)]
use crate::reflection::parse_reflection_from_bytes;

/// Reflection lookup used by graph construction before physical resources
/// and pipelines exist.
pub(crate) trait KernelReflections {
    fn reflection(&self, key: &str) -> Result<&SlangReflection, String>;
}

/// Reflection-only generated kernel catalog.
#[cfg(test)]
pub(crate) struct KernelCatalog {
    reflections: HashMap<String, Arc<SlangReflection>>,
}

#[cfg(test)]
impl KernelCatalog {
    pub(crate) fn load_prefixes(prefixes: &[&str]) -> Result<Self> {
        let mut reflections = HashMap::new();
        for prefix in prefixes {
            let keys = crate::shader_artifacts::shader_keys(prefix)
                .with_context(|| format!("discover generated GPU kernels below `{prefix}`"))?;
            for key in keys {
                let path = crate::shader_artifacts::artifact_path(&format!("{key}.reflect.json"));
                let bytes = std::fs::read(&path)
                    .with_context(|| format!("read GPU kernel reflection {}", path.display()))?;
                let reflection = parse_reflection_from_bytes(&bytes).map_err(anyhow::Error::msg)?;
                reflections.insert(key, Arc::new(reflection));
            }
        }
        Ok(Self { reflections })
    }
}

#[cfg(test)]
impl KernelReflections for KernelCatalog {
    fn reflection(&self, key: &str) -> Result<&SlangReflection, String> {
        self.reflections
            .get(key)
            .map(AsRef::as_ref)
            .ok_or_else(|| format!("GPU kernel `{key}` has no generated reflection"))
    }
}

/// Kernels that need the most per-thread local memory on the development GPU,
/// largest first, one artifact key per line. `tools/local_memory_report.py
/// --write-order` regenerates the list from a memory probe.
const LARGEST_LOCAL_MEMORY_KERNELS: &str = include_str!("largest_local_memory_kernels.txt");

/// Creates the listed largest-local-memory kernels that `include` accepts,
/// in list order. Returns how many pipelines were created.
///
/// A resident compiler calls this before it creates any other pipeline. When
/// a new pipeline needs a larger local-memory reservation, the NVIDIA driver
/// allocates the new size and keeps the previous reservation as well. Created
/// in arbitrary order, the 1 MB daemon held 1959 MiB + 2219 MiB. With the
/// largest first, every later pipeline fits and the driver allocates only
/// once. A stale list costs device memory, never correctness, and listed
/// kernels that no longer exist are skipped.
pub(crate) fn prepare_largest_local_memory_kernels(
    device: &wgpu::Device,
    include: impl Fn(&str) -> bool,
) -> Result<usize> {
    let mut created = 0;
    for key in LARGEST_LOCAL_MEMORY_KERNELS
        .lines()
        .filter_map(|line| line.split('#').next().map(str::trim))
        .filter(|key| !key.is_empty() && include(key))
    {
        if !crate::shader_artifacts::artifact_path(&format!("{key}.reflect.json")).exists() {
            continue;
        }
        if super::passes_core::prepare_main_shader_kernel(device, key)
            .with_context(|| format!("prepare GPU kernel `{key}`"))?
        {
            created += 1;
        }
    }
    Ok(created)
}

/// Creates the `main` pipeline of every generated kernel that `include`
/// accepts and is not prepared yet, retaining each one for later on-demand
/// loads. Returns how many pipelines were created.
///
/// A resident compiler calls this before its first job. The NVIDIA driver sizes
/// one device-wide local-memory (scratch) reservation when a pipeline is
/// created: the largest per-thread local memory of any pipeline times the
/// resident threads. A large-frame pipeline first created during a job grows
/// that reservation while the job's buffers fill device memory, so the growth
/// lands in system memory and every kernel with local memory then runs its
/// stack over PCIe for the rest of the daemon's life. Creating all pipelines
/// first places the reservation before any buffer exists.
pub(crate) fn prepare_remaining_kernels(
    device: &wgpu::Device,
    include: impl Fn(&str) -> bool,
) -> Result<usize> {
    let keys = crate::shader_artifacts::shader_keys("")
        .context("discover generated GPU kernels")?;
    let mut created = 0;
    for key in keys.iter().filter(|key| include(key)) {
        if super::passes_core::prepare_main_shader_kernel(device, key)
            .with_context(|| format!("prepare GPU kernel `{key}`"))?
        {
            created += 1;
        }
    }
    Ok(created)
}

/// Pipelines prepared before a compilation job begins.
pub(crate) struct KernelRegistry {
    kernels: HashMap<String, PassData>,
    dynamic_uniform_kernels: HashMap<(String, String), PassData>,
}

impl KernelRegistry {
    /// Prepares the selected generated kernels in deterministic artifact order.
    pub(crate) fn prepare<I, S>(device: &wgpu::Device, keys: I) -> Result<Self>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        let mut keys = keys
            .into_iter()
            .map(|key| key.as_ref().to_owned())
            .collect::<Vec<_>>();
        keys.sort_unstable();
        keys.dedup();

        let mut kernels = HashMap::with_capacity(keys.len());
        let mut dynamic_uniform_kernels = HashMap::new();
        for key in keys {
            let kernel = make_pass_data_from_shader_key(device, &key, "main", &key)
                .with_context(|| format!("prepare GPU kernel `{key}`"))?;
            if super::operations::uses_dynamic_uniform_kernel(&kernel.reflection) {
                let dynamic = make_pass_data_from_shader_key_with_dynamic_uniforms(
                    device,
                    &key,
                    "main",
                    &key,
                    &["gParams"],
                )
                .with_context(|| format!("prepare dynamic-uniform GPU kernel `{key}`"))?;
                dynamic_uniform_kernels.insert((key.clone(), "gParams".to_owned()), dynamic);
            }
            kernels.insert(key, kernel);
        }
        Ok(Self {
            kernels,
            dynamic_uniform_kernels,
        })
    }

    /// Prepares the union of several generated-kernel namespaces. Shared GPU
    /// operations therefore live outside any compiler phase without forcing
    /// phase registries to load one pipeline at a time.
    pub(crate) fn prepare_prefixes(
        device: &wgpu::Device,
        prefixes: &[&str],
        include: impl Fn(&str) -> bool,
    ) -> Result<Self> {
        let mut keys = Vec::new();
        for prefix in prefixes {
            keys.extend(
                crate::shader_artifacts::shader_keys(prefix)
                    .with_context(|| format!("discover generated GPU kernels below `{prefix}`"))?
                    .into_iter()
                    .filter(|key| include(key)),
            );
        }
        Self::prepare(device, keys)
    }

    /// Returns a pipeline which daemon preparation promised to create.
    pub(crate) fn kernel(&self, key: &str) -> &PassData {
        self.kernels
            .get(key)
            .unwrap_or_else(|| panic!("GPU kernel `{key}` was not prepared before compilation"))
    }

    /// Returns a capability-dependent pipeline when it was prepared.
    pub(crate) fn optional(&self, key: &str) -> Option<&PassData> {
        self.kernels.get(key)
    }

    /// Returns the startup-prepared layout variant for an operation whose
    /// repeated invocations select rows from one dynamic-uniform table.
    pub(crate) fn dynamic_uniform_kernel(&self, key: &str, uniform: &str) -> &PassData {
        self.dynamic_uniform_kernels
            .get(&(key.to_owned(), uniform.to_owned()))
            .unwrap_or_else(|| {
                panic!("GPU kernel `{key}` has no prepared dynamic-uniform variant for `{uniform}`")
            })
    }
}

impl KernelReflections for KernelRegistry {
    fn reflection(&self, key: &str) -> Result<&SlangReflection, String> {
        self.kernels
            .get(key)
            .map(|kernel| kernel.reflection.as_ref())
            .ok_or_else(|| format!("GPU kernel `{key}` was not prepared before compilation"))
    }
}

impl super::operations::ComputeKernels for KernelRegistry {
    fn kernel(&self, key: &str) -> &PassData {
        self.kernel(key)
    }
}
