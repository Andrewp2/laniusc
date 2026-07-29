//! Compiler-wide reflected compute-kernel registry.
//!
//! A kernel is identified by its generated shader-artifact key.  Compiler
//! phases refer to that identity through graph nodes and high-level operations;
//! they do not own one Rust field or loader call per pipeline.

use std::{collections::HashMap, sync::Arc};

use anyhow::{Context, Result};

use super::passes_core::{PassData, make_pass_data_from_shader_key};
use crate::reflection::{SlangReflection, parse_reflection_from_bytes};

/// Reflection lookup used by graph construction before physical resources
/// and pipelines exist.
pub(crate) trait KernelReflections {
    fn reflection(&self, key: &str) -> Result<&SlangReflection, String>;
}

/// Reflection-only generated kernel catalog.
pub(crate) struct KernelCatalog {
    reflections: HashMap<String, Arc<SlangReflection>>,
}

impl KernelCatalog {
    pub(crate) fn load_prefix(prefix: &str) -> Result<Self> {
        let keys = crate::shader_artifacts::shader_keys(prefix)
            .with_context(|| format!("discover generated GPU kernels below `{prefix}`"))?;
        let mut reflections = HashMap::with_capacity(keys.len());
        for key in keys {
            let path = crate::shader_artifacts::artifact_path(&format!("{key}.reflect.json"));
            let bytes = std::fs::read(&path)
                .with_context(|| format!("read GPU kernel reflection {}", path.display()))?;
            let reflection = parse_reflection_from_bytes(&bytes).map_err(anyhow::Error::msg)?;
            reflections.insert(key, Arc::new(reflection));
        }
        Ok(Self { reflections })
    }
}

impl KernelReflections for KernelCatalog {
    fn reflection(&self, key: &str) -> Result<&SlangReflection, String> {
        self.reflections
            .get(key)
            .map(AsRef::as_ref)
            .ok_or_else(|| format!("GPU kernel `{key}` has no generated reflection"))
    }
}

/// Pipelines prepared before a compilation job begins.
pub(crate) struct KernelRegistry {
    kernels: HashMap<String, PassData>,
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
        for key in keys {
            let kernel = make_pass_data_from_shader_key(device, &key, "main", &key)
                .with_context(|| format!("prepare GPU kernel `{key}`"))?;
            kernels.insert(key, kernel);
        }
        Ok(Self { kernels })
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
}

impl KernelReflections for KernelRegistry {
    fn reflection(&self, key: &str) -> Result<&SlangReflection, String> {
        self.kernels
            .get(key)
            .map(|kernel| kernel.reflection.as_ref())
            .ok_or_else(|| format!("GPU kernel `{key}` was not prepared before compilation"))
    }
}
