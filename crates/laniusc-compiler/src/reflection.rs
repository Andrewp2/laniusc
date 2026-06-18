use std::{collections::HashMap, fs, path::Path};

use serde::{Deserialize, Serialize};

/// Root of the Slang JSON reflection payload consumed by GPU pass loading.
///
/// The compiler uses this structure to derive bind group layouts, dynamic
/// uniform-buffer offsets, texture formats, and compute thread-group sizes from
/// `.reflect.json` files generated alongside SPIR-V artifacts.
#[derive(Serialize, Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct SlangReflection {
    /// Top-level reflected shader parameters.
    #[serde(default)]
    pub parameters: Vec<ParameterReflection>,
    /// Reflected entry points, including compute stage metadata.
    #[serde(default)]
    pub entry_points: Vec<EntryPointReflection>,
    /// Named type layouts emitted by Slang for user-defined types.
    #[serde(default)]
    pub type_layouts: HashMap<String, TypeLayout>,
}

/// Custom Slang attribute attached to a reflected parameter.
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UserAttribute {
    /// Attribute name without arguments.
    pub name: String,

    /// Raw string arguments supplied to the attribute.
    #[serde(default)]
    pub arguments: Vec<String>,
}

/// Reflected shader parameter that may become a wgpu binding entry.
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ParameterReflection {
    /// Source-level parameter name.
    pub name: String,
    /// Descriptor binding metadata.
    pub binding: BindingInfo,
    /// Reflected Slang type layout for this parameter.
    #[serde(rename = "type")]
    pub ty: TypeLayout,

    /// Custom attributes used to fill gaps in Slang's reflected type data.
    #[serde(default)]
    pub user_attribs: Vec<UserAttribute>,
}

/// Descriptor binding information emitted by Slang reflection.
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct BindingInfo {
    /// Slang binding category, such as `descriptorTableSlot`.
    pub kind: String,
    /// Binding index inside the reflected set.
    #[serde(default)]
    pub index: Option<u32>,
    /// Byte offset for aggregate binding records when Slang provides one.
    #[serde(default)]
    pub offset: Option<u32>,
    /// Reflected binding size in bytes when available.
    #[serde(default)]
    pub size: Option<u32>,
}

/// Reflected shader entry point.
#[derive(Serialize, Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct EntryPointReflection {
    /// Entry point name.
    pub name: Option<String>,
    /// Shader stage name, expected to be `compute` for compiler passes.
    pub stage: Option<String>,
    /// Entry point parameters that are not represented as descriptor sets.
    #[serde(default)]
    pub parameters: Vec<EntryPointParameterReflection>,
    /// Program layout containing reflected descriptor sets.
    #[serde(default, rename = "layout")]
    pub program_layout: Option<ProgramLayoutReflection>,
    /// Workgroup size declared on the compute entry point.
    pub thread_group_size: Option<[u32; 3]>,
}

/// Reflected non-descriptor entry point parameter.
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct EntryPointParameterReflection {
    /// Parameter name.
    pub name: String,
    /// Semantic name, when Slang emits one.
    pub semantic_name: Option<String>,
    /// Semantic index, when Slang emits one.
    pub semantic_index: Option<u32>,
    /// Reflected Slang type layout.
    #[serde(rename = "type")]
    pub ty: TypeLayout,
}

/// Program layout containing descriptor-set parameter lists.
#[derive(Serialize, Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct ProgramLayoutReflection {
    /// Reflected descriptor sets, indexed by `space`.
    #[serde(default)]
    pub parameters: Vec<ParameterSetReflection>,
}

/// Reflected descriptor-set contents for one Slang parameter space.
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ParameterSetReflection {
    /// Parameters in the reflected binding order for this space.
    #[serde(default)]
    pub parameters: Vec<ParameterReflection>,
    /// Slang parameter space, mapped to the wgpu bind-group index.
    #[serde(default)]
    pub space: u32,
}

/// Reflected Slang type layout used to classify wgpu binding types.
#[derive(Serialize, Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct TypeLayout {
    /// Slang type kind, such as `resource` or `constantBuffer`.
    pub kind: Option<String>,
    /// Resource base shape, such as `structuredBuffer` or `texture2D`.
    pub base_shape: Option<String>,
    /// Whether the type is an array resource.
    pub array: Option<bool>,
    /// Whether a constant buffer should be treated as a uniform buffer.
    #[serde(default, rename = "uniformScale")]
    pub uniform_scale: bool,
    /// Element type for arrays or aggregate resources.
    pub element_type: Option<Box<TypeLayout>>,
    /// Field layouts for aggregate types.
    pub fields: Option<Vec<FieldLayout>>,
    /// Reflected size in bytes.
    pub size_in_bytes: Option<usize>,
    /// Static array element count when Slang emits it.
    pub array_element_count: Option<usize>,
    /// Resource access mode, such as `Read`, `Write`, or `ReadWrite`.
    pub access: Option<String>,
    /// Texture format string, when Slang emits one.
    pub format: Option<String>,
    /// Result type used by some Slang resource wrappers.
    pub result_type: Option<Box<TypeLayout>>,
}

/// Reflected field inside an aggregate Slang type.
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct FieldLayout {
    /// Field name.
    pub name: String,
    /// Field type layout.
    #[serde(rename = "type")]
    pub ty: TypeLayout,
    /// Binding metadata for fields that carry resource bindings.
    pub binding: Option<BindingInfo>,
}

#[cfg(not(target_arch = "wasm32"))]
/// Parses a Slang reflection JSON file from disk.
pub fn parse_reflection_from_file(path: impl AsRef<Path>) -> Result<SlangReflection, String> {
    let path_ref = path.as_ref();
    log::debug!("Parsing reflection from: {}", path_ref.display());
    let file_content = fs::read_to_string(path_ref)
        .map_err(|e| format!("Failed to read reflection file {path_ref:?}: {e}"))?;
    serde_json::from_str(&file_content)
        .map_err(|e| format!("Failed to parse reflection JSON {path_ref:?}: {e}"))
}

/// Parses embedded or externally loaded Slang reflection JSON bytes.
pub fn parse_reflection_from_bytes(data: &[u8]) -> Result<SlangReflection, String> {
    log::debug!("Parsing reflection from embedded bytes");
    serde_json::from_slice(data)
        .map_err(|e| format!("Failed to parse reflection JSON from bytes: {e}"))
}

/// Converts one reflected Slang parameter/type pair to a wgpu binding type.
///
/// The conversion encodes the compiler's shader ABI: storage buffers are
/// storage bindings, uniform-scale constant buffers are uniform bindings, and
/// select uniforms use dynamic offsets when reflected or known by fallback name.
pub fn slang_category_and_type_to_wgpu(
    param_info: &ParameterReflection,
    type_layout: &TypeLayout,
) -> Option<wgpu::BindingType> {
    let kind = type_layout.kind.as_deref().unwrap_or("");
    let base_shape = type_layout.base_shape.as_deref().unwrap_or("");
    let access = type_layout.access.as_deref().unwrap_or("Read");
    let array = type_layout.array.unwrap_or(false);
    let format_str = type_layout.format.as_deref().unwrap_or("");
    let is_uniform_buffer = type_layout.uniform_scale;
    let has_dynamic_offset = param_info
        .user_attribs
        .iter()
        .any(|attr| attr.name == "DynamicOffset")
        // Slang's JSON reflection currently omits the custom attribute for
        // these global constant buffers, but the shader source still carries
        // the attribute as the intended ABI marker.
        || matches!(
            param_info.name.as_str(),
            "gRegalloc" | "gNextCallScan" | "gFuncOwnerBlockScan" | "gNodeInstBlockScan"
        );

    // param_info
    // 							.user_attribs
    // 							.iter()
    // 							.find(|attr| attr.name == "CustomFormat")
    // 							.and_then(|attr| attr.arguments.first())
    // 							.and_then(|fmt_str_from_attr| {
    // 								log::debug!(
    // 									"Found CustomFormat attribute for '{}': {}",
    // 									param_info.name,
    // 									fmt_str_from_attr
    // 								);
    // 								slang_format_to_wgpu(fmt_str_from_attr)
    // 							})

    match kind {
        "resource" => {
            match base_shape {
                "constantBuffer" | "parameterBlock" if is_uniform_buffer => {
                    //let attribute = param_info.user_attribs.iter().find(|attr| attr.name == "DynamicOffset");
                    //let has_dynamic_offset = attribute.is_some();
                    // let binding_size_multiplier = attribute
                    // 	.and_then(|attr| attr.arguments.first().and_then(|arg| arg.parse::<u64>().ok()))
                    // 	.unwrap_or(1);
                    Some(wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset,
                        min_binding_size: type_layout
                            .size_in_bytes
                            .or_else(|| {
                                type_layout
                                    .result_type
                                    .as_ref()
                                    .and_then(|rt| rt.size_in_bytes)
                            })
                            .map(|s| s as u64)
                            .and_then(wgpu::BufferSize::new),
                    })
                }
                "structuredBuffer" | "buffer" | "byteAddressBuffer" => {
                    let read_only = access == "read" || access == "Read";
                    Some(wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    })
                }
                "texture1D" | "texture2D" | "texture3D" | "textureCube" | "texture2DArray"
                | "texture1DArray" | "textureCubeArray" | "textureBuffer" => {
                    if access == "read" || access == "Read" {
                        // If this is any sampled texture with CustomFormat rgba32f, set filterable: false
                        let custom_format = param_info
                            .user_attribs
                            .iter()
                            .find(|attr| attr.name == "CustomFormat")
                            .and_then(|attr| attr.arguments.first());
                        if let Some(fmt) = custom_format {
                            let filterable = fmt != "rgba32f";
                            Some(wgpu::BindingType::Texture {
                                sample_type: wgpu::TextureSampleType::Float { filterable },
                                view_dimension: slang_shape_to_wgpu_dimension(base_shape, array)
                                    .unwrap_or(wgpu::TextureViewDimension::D2),
                                multisampled: false,
                            })
                        } else {
                            Some(wgpu::BindingType::Texture {
                                sample_type: wgpu::TextureSampleType::Float { filterable: true },
                                view_dimension: slang_shape_to_wgpu_dimension(base_shape, array)
                                    .unwrap_or(wgpu::TextureViewDimension::D2),
                                multisampled: false,
                            })
                        }
                    } else {
                        let storage_access = match access {
                            "readWrite" | "ReadWrite" => wgpu::StorageTextureAccess::ReadWrite,
                            "write" | "Write" => wgpu::StorageTextureAccess::WriteOnly,
                            "read" | "Read" => wgpu::StorageTextureAccess::ReadOnly,
                            _ => {
                                log::warn!(
                                    "Unknown texture access '{}' for {}, assuming ReadWrite storage",
                                    access,
                                    param_info.name
                                );
                                wgpu::StorageTextureAccess::ReadWrite
                            }
                        };

                        let wgpu_format = slang_format_to_wgpu(format_str).or_else(|| {
                            param_info
                                .user_attribs
                                .iter()
                                .find(|attr| attr.name == "CustomFormat")
                                .and_then(|attr| attr.arguments.first())
                                .and_then(|fmt_str_from_attr| {
                                    log::debug!(
                                        "Found CustomFormat attribute for '{}': {}",
                                        param_info.name,
                                        fmt_str_from_attr
                                    );
                                    slang_format_to_wgpu(fmt_str_from_attr)
                                })
                        });
                        match wgpu_format {
                            Some(format) => Some(wgpu::BindingType::StorageTexture {
                                access: storage_access,
                                format,
                                view_dimension: slang_shape_to_wgpu_dimension(base_shape, array)
                                    .unwrap_or(wgpu::TextureViewDimension::D2),
                            }),
                            None => {
                                log::error!(
                                    "Could not determine storage texture format for parameter '{}'. Checked type.format ('{}') and CustomFormat attribute.",
                                    param_info.name,
                                    format_str
                                );
                                None
                            }
                        }
                    }
                }
                "samplerState" => {
                    if param_info.name == "s_diffuse" {
                        Some(wgpu::BindingType::Sampler(
                            wgpu::SamplerBindingType::Filtering,
                        ))
                    } else {
                        Some(wgpu::BindingType::Sampler(
                            wgpu::SamplerBindingType::NonFiltering,
                        ))
                    }
                }

                "samplerComparisonState" => Some(wgpu::BindingType::Sampler(
                    wgpu::SamplerBindingType::Comparison,
                )),
                _ => {
                    log::warn!(
                        "Unhandled resource baseShape '{}' for parameter '{}'",
                        base_shape,
                        param_info.name
                    );
                    None
                }
            }
        }
        "samplerState" => Some(wgpu::BindingType::Sampler(
            wgpu::SamplerBindingType::Filtering,
        )),
        "samplerComparisonState" => Some(wgpu::BindingType::Sampler(
            wgpu::SamplerBindingType::Comparison,
        )),
        "constantBuffer" => Some(wgpu::BindingType::Buffer {
            ty: wgpu::BufferBindingType::Uniform,
            has_dynamic_offset,
            min_binding_size: type_layout
                .size_in_bytes
                .or_else(|| {
                    type_layout
                        .result_type
                        .as_ref()
                        .and_then(|rt| rt.size_in_bytes)
                })
                .map(|s| s as u64)
                .and_then(wgpu::BufferSize::new),
        }),
        _ => {
            log::warn!(
                "Unhandled parameter kind '{}' for parameter '{}'",
                kind,
                param_info.name
            );
            None
        }
    }
}

fn slang_shape_to_wgpu_dimension(shape: &str, array: bool) -> Option<wgpu::TextureViewDimension> {
    let shape_lower = shape.to_lowercase();
    match shape_lower.as_str() {
        sh if sh.contains("texture1darray") => Some(wgpu::TextureViewDimension::D1),
        sh if sh.contains("texture1d") => Some(wgpu::TextureViewDimension::D1),
        sh if sh.contains("texture2darray") => Some(wgpu::TextureViewDimension::D2Array),
        sh if sh.contains("texture2dmsarray") => Some(wgpu::TextureViewDimension::D2Array),
        sh if sh.contains("texture2dms") => Some(wgpu::TextureViewDimension::D2),
        sh if sh.contains("texture2d") => match array {
            true => Some(wgpu::TextureViewDimension::D2Array),
            false => Some(wgpu::TextureViewDimension::D2),
        },
        sh if sh.contains("texture3d") => Some(wgpu::TextureViewDimension::D3),
        sh if sh.contains("texturecubearray") => Some(wgpu::TextureViewDimension::CubeArray),
        sh if sh.contains("texturecube") => Some(wgpu::TextureViewDimension::Cube),
        sh if sh.contains("texturebuffer") => {
            log::warn!("TextureBuffer view dimension mapping might need adjustment");
            Some(wgpu::TextureViewDimension::D1)
        }
        _ => {
            log::warn!("Unknown texture shape for view dimension mapping: {shape}");
            None
        }
    }
}

fn slang_format_to_wgpu(format_str: &str) -> Option<wgpu::TextureFormat> {
    match format_str {
        "RGBA8UNorm" | "rgba8unorm" => Some(wgpu::TextureFormat::Rgba8Unorm),
        "BGRA8UNorm" | "bgra8unorm" => Some(wgpu::TextureFormat::Bgra8Unorm),
        "R8UNorm" | "r8unorm" => Some(wgpu::TextureFormat::R8Unorm),
        "RG8UNorm" | "rg8unorm" => Some(wgpu::TextureFormat::Rg8Unorm),
        "RGBA8" | "rgba8" => Some(wgpu::TextureFormat::Rgba8Unorm),

        "RGBA8SNorm" | "rgba8snorm" => Some(wgpu::TextureFormat::Rgba8Snorm),

        "R32UInt" | "r32ui" | "uint" => Some(wgpu::TextureFormat::R32Uint),
        "RG32UInt" | "rg32ui" | "uint2" => Some(wgpu::TextureFormat::Rg32Uint),
        "RGBA32UInt" | "rgba32ui" | "uint4" => Some(wgpu::TextureFormat::Rgba32Uint),

        "R32SInt" | "r32i" | "int" => Some(wgpu::TextureFormat::R32Sint),

        "R32Float" | "r32f" | "float" => Some(wgpu::TextureFormat::R32Float),
        "RG32Float" | "rg32f" | "float2" => Some(wgpu::TextureFormat::Rg32Float),
        "RGBA32Float" | "rgba32f" | "float4" => Some(wgpu::TextureFormat::Rgba32Float),
        "R16Float" | "r16f" | "half" => Some(wgpu::TextureFormat::R16Float),
        "RG16Float" | "rg16f" | "half2" => Some(wgpu::TextureFormat::Rg16Float),
        "RGBA16Float" | "rgba16f" | "half4" => Some(wgpu::TextureFormat::Rgba16Float),

        "Depth32Float" | "d32f" => Some(wgpu::TextureFormat::Depth32Float),
        "Depth24PlusStencil8" | "d24s8" => Some(wgpu::TextureFormat::Depth24PlusStencil8),

        "unknown" | "" => None,
        _ => {
            log::warn!("Unknown or unhandled Slang texture format string: '{format_str}'");
            None
        }
    }
}

/// Returns the compute entry point thread-group size from reflection metadata.
pub fn get_thread_group_size(reflection: &SlangReflection) -> Option<[u32; 3]> {
    reflection
        .entry_points
        .iter()
        .find(|ep| ep.stage.as_deref() == Some("compute"))
        .and_then(|ep| ep.thread_group_size)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn uniform_param(name: &str, user_attribs: Vec<UserAttribute>) -> ParameterReflection {
        ParameterReflection {
            name: name.to_string(),
            binding: BindingInfo {
                kind: "descriptorTableSlot".to_string(),
                index: Some(1),
                offset: None,
                size: None,
            },
            ty: TypeLayout {
                kind: Some("resource".to_string()),
                base_shape: Some("constantBuffer".to_string()),
                uniform_scale: true,
                size_in_bytes: Some(16),
                ..TypeLayout::default()
            },
            user_attribs,
        }
    }

    #[test]
    fn dynamic_offset_attribute_marks_uniform_binding_dynamic() {
        let param = uniform_param(
            "gRegalloc",
            vec![UserAttribute {
                name: "DynamicOffset".to_string(),
                arguments: Vec::new(),
            }],
        );

        let Some(wgpu::BindingType::Buffer {
            ty: wgpu::BufferBindingType::Uniform,
            has_dynamic_offset,
            min_binding_size,
        }) = slang_category_and_type_to_wgpu(&param, &param.ty)
        else {
            panic!("expected uniform buffer binding");
        };

        assert!(has_dynamic_offset);
        assert_eq!(min_binding_size.map(|size| size.get()), Some(16));
    }

    #[test]
    fn ordinary_uniform_binding_is_not_dynamic() {
        let param = uniform_param("gParams", Vec::new());

        let Some(wgpu::BindingType::Buffer {
            ty: wgpu::BufferBindingType::Uniform,
            has_dynamic_offset,
            ..
        }) = slang_category_and_type_to_wgpu(&param, &param.ty)
        else {
            panic!("expected uniform buffer binding");
        };

        assert!(!has_dynamic_offset);
    }

    #[test]
    fn x86_regalloc_uniform_uses_dynamic_offset_reflection_fallback() {
        let param = uniform_param("gRegalloc", Vec::new());

        let Some(wgpu::BindingType::Buffer {
            ty: wgpu::BufferBindingType::Uniform,
            has_dynamic_offset,
            ..
        }) = slang_category_and_type_to_wgpu(&param, &param.ty)
        else {
            panic!("expected uniform buffer binding");
        };

        assert!(has_dynamic_offset);
    }

    #[test]
    fn x86_next_call_scan_uniform_uses_dynamic_offset_reflection_fallback() {
        let param = uniform_param("gNextCallScan", Vec::new());

        let Some(wgpu::BindingType::Buffer {
            ty: wgpu::BufferBindingType::Uniform,
            has_dynamic_offset,
            ..
        }) = slang_category_and_type_to_wgpu(&param, &param.ty)
        else {
            panic!("expected uniform buffer binding");
        };

        assert!(has_dynamic_offset);
    }

    #[test]
    fn x86_scan_block_uniforms_use_dynamic_offset_reflection_fallback() {
        for name in ["gFuncOwnerBlockScan", "gNodeInstBlockScan"] {
            let param = uniform_param(name, Vec::new());

            let Some(wgpu::BindingType::Buffer {
                ty: wgpu::BufferBindingType::Uniform,
                has_dynamic_offset,
                ..
            }) = slang_category_and_type_to_wgpu(&param, &param.ty)
            else {
                panic!("expected uniform buffer binding for {name}");
            };

            assert!(has_dynamic_offset, "{name} should use dynamic offsets");
        }
    }
}
