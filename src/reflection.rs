use std::{collections::HashMap, fs, path::Path};

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct SlangReflection {
    #[serde(default)]
    pub parameters: Vec<ParameterReflection>,
    #[serde(default)]
    pub entry_points: Vec<EntryPointReflection>,
    #[serde(default)]
    pub type_layouts: HashMap<String, TypeLayout>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct UserAttribute {
    pub name: String,

    #[serde(default)]
    pub arguments: Vec<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ParameterReflection {
    pub name: String,
    pub binding: BindingInfo,
    #[serde(rename = "type")]
    pub ty: TypeLayout,

    #[serde(default)]
    pub user_attribs: Vec<UserAttribute>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct BindingInfo {
    pub kind: String,
    #[serde(default)]
    pub index: Option<u32>,
    #[serde(default)]
    pub offset: Option<u32>,
    #[serde(default)]
    pub size: Option<u32>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct EntryPointReflection {
    pub name: Option<String>,
    pub stage: Option<String>,
    #[serde(default)]
    pub parameters: Vec<EntryPointParameterReflection>,
    #[serde(default, rename = "layout")]
    pub program_layout: Option<ProgramLayoutReflection>,
    pub thread_group_size: Option<[u32; 3]>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct EntryPointParameterReflection {
    pub name: String,
    pub semantic_name: Option<String>,
    pub semantic_index: Option<u32>,
    #[serde(rename = "type")]
    pub ty: TypeLayout,
}

#[derive(Serialize, Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct ProgramLayoutReflection {
    #[serde(default)]
    pub parameters: Vec<ParameterSetReflection>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ParameterSetReflection {
    #[serde(default)]
    pub parameters: Vec<ParameterReflection>,
    #[serde(default)]
    pub space: u32,
}

#[derive(Serialize, Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct TypeLayout {
    pub kind: Option<String>,
    pub base_shape: Option<String>,
    pub array: Option<bool>,
    #[serde(default, rename = "uniformScale")]
    pub uniform_scale: bool,
    pub element_type: Option<Box<TypeLayout>>,
    pub fields: Option<Vec<FieldLayout>>,
    pub size_in_bytes: Option<usize>,
    pub array_element_count: Option<usize>,
    pub access: Option<String>,
    pub format: Option<String>,
    pub result_type: Option<Box<TypeLayout>>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct FieldLayout {
    pub name: String,
    #[serde(rename = "type")]
    pub ty: TypeLayout,
    pub binding: Option<BindingInfo>,
}

#[cfg(not(target_arch = "wasm32"))]
pub fn parse_reflection_from_file(path: impl AsRef<Path>) -> Result<SlangReflection, String> {
    let path_ref = path.as_ref();
    log::debug!("Parsing reflection from: {}", path_ref.display());
    let file_content = fs::read_to_string(path_ref)
        .map_err(|e| format!("Failed to read reflection file {:?}: {}", path_ref, e))?;
    serde_json::from_str(&file_content)
        .map_err(|e| format!("Failed to parse reflection JSON {:?}: {}", path_ref, e))
}

pub fn parse_reflection_from_bytes(data: &[u8]) -> Result<SlangReflection, String> {
    log::debug!("Parsing reflection from embedded bytes");
    serde_json::from_slice(data)
        .map_err(|e| format!("Failed to parse reflection JSON from bytes: {}", e))
}

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
                        has_dynamic_offset: false,
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
            has_dynamic_offset: false,
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
            log::warn!(
                "Unknown texture shape for view dimension mapping: {}",
                shape
            );
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
            log::warn!(
                "Unknown or unhandled Slang texture format string: '{}'",
                format_str
            );
            None
        }
    }
}

pub fn get_thread_group_size(reflection: &SlangReflection) -> Option<[u32; 3]> {
    reflection
        .entry_points
        .iter()
        .find(|ep| ep.stage.as_deref() == Some("compute"))
        .and_then(|ep| ep.thread_group_size)
}
