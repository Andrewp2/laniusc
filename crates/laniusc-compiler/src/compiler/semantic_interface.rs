//! Stable persisted semantic interface for bounded compilation units.
//!
//! Every identity in this format is canonical across compiler invocations.
//! GPU-local token, HIR, name, declaration, type-instance, and module ids must
//! be translated into these records before a unit can be released.

/// Current binary schema version for GPU semantic-interface artifacts.
pub const GPU_SEMANTIC_INTERFACE_VERSION: u32 = 4;
const GPU_SEMANTIC_INTERFACE_MAGIC: [u8; 8] = *b"LNSIFACE";
const HEADER_U32S: usize = 16;
const MODULE_U32S: usize = 2;
const MODULE_SEGMENT_U32S: usize = 4;
const DECLARATION_U32S: usize = 14;
const TYPE_U32S: usize = 9;
const TYPE_EDGE_U32S: usize = 1;
const MEMBER_U32S: usize = 10;
const INVALID: u32 = u32::MAX;
const MAX_CANONICAL_NAME_BYTES: usize = 64;

pub(crate) mod dependency_batch;

/// Stable kind tag for a typed interface node.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum GpuSemanticInterfaceTypeKind {
    Scalar = 1,
    GenericParameter = 2,
    Declaration = 3,
    Array = 4,
    Slice = 5,
    Reference = 6,
    Function = 7,
    ConstParameter = 8,
}

impl GpuSemanticInterfaceTypeKind {
    fn from_u32(value: u32) -> Option<Self> {
        Some(match value {
            1 => Self::Scalar,
            2 => Self::GenericParameter,
            3 => Self::Declaration,
            4 => Self::Array,
            5 => Self::Slice,
            6 => Self::Reference,
            7 => Self::Function,
            8 => Self::ConstParameter,
            _ => return None,
        })
    }
}

/// Stable role tag for a named declaration member.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum GpuSemanticInterfaceMemberKind {
    Parameter = 1,
    GenericTypeParameter = 2,
    GenericConstParameter = 3,
    Field = 4,
    EnumVariant = 5,
    AssociatedMethod = 6,
}

impl GpuSemanticInterfaceMemberKind {
    fn from_u32(value: u32) -> Option<Self> {
        Some(match value {
            1 => Self::Parameter,
            2 => Self::GenericTypeParameter,
            3 => Self::GenericConstParameter,
            4 => Self::Field,
            5 => Self::EnumVariant,
            6 => Self::AssociatedMethod,
            _ => return None,
        })
    }
}

/// One module path owned by the producing library.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuSemanticInterfaceModuleRecord {
    pub first_segment: u32,
    pub segment_count: u32,
}

/// One canonical UTF-8 module-path segment.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuSemanticInterfaceModuleSegmentRecord {
    pub name_hash_lo: u32,
    pub name_hash_hi: u32,
    pub name_byte_start: u32,
    pub name_byte_len: u32,
}

/// One public declaration exported by the unit.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuSemanticInterfaceDeclarationRecord {
    pub module: u32,
    pub name_hash_lo: u32,
    pub name_hash_hi: u32,
    pub name_byte_start: u32,
    pub name_byte_len: u32,
    pub namespace: u32,
    pub kind: u32,
    pub signature_type: u32,
    pub first_member: u32,
    pub member_count: u32,
    pub owner_declaration: u32,
    pub flags: u32,
    pub value_lo: u32,
    pub value_hi: u32,
}

/// One canonical typed node in an exported declaration signature.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuSemanticInterfaceTypeRecord {
    pub kind: u32,
    /// Kind-specific low payload. Declaration nodes store the defining
    /// library id here; scalar nodes store the language scalar code.
    pub payload_lo: u32,
    /// Kind-specific high payload. Declaration nodes store the persisted
    /// declaration index within the defining unit here.
    pub payload_hi: u32,
    pub first_edge: u32,
    pub edge_count: u32,
    pub length_kind: u32,
    pub length_lo: u32,
    pub length_hi: u32,
    /// Defining frontend unit for declaration nodes. Together with
    /// `payload_lo` and `payload_hi`, this forms the stable nominal identity
    /// `(library_id, unit_id, declaration_index)`. Other kinds store zero.
    pub nominal_unit_id: u32,
}

/// Index of a child type node. Edges encode generic arguments, aggregate
/// elements, and function parameters followed by the return type, without
/// recursive records.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuSemanticInterfaceTypeEdge {
    pub type_index: u32,
}

/// Named declaration member such as a parameter, generic parameter, field,
/// enum variant, or associated method.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuSemanticInterfaceMemberRecord {
    pub owner_declaration: u32,
    pub kind: u32,
    pub ordinal: u32,
    pub name_hash_lo: u32,
    pub name_hash_hi: u32,
    pub name_byte_start: u32,
    pub name_byte_len: u32,
    pub type_index: u32,
    pub value_lo: u32,
    pub value_hi: u32,
}

/// Canonical identity portion emitted before typed signature/member graph
/// materialization. This value is never a valid persisted interface by itself.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GpuSemanticInterfaceIdentityArtifact {
    pub library_id: u32,
    /// Globally unique bounded frontend-unit id within the source-pack build.
    pub unit_id: u32,
    pub modules: Vec<GpuSemanticInterfaceModuleRecord>,
    pub module_segments: Vec<GpuSemanticInterfaceModuleSegmentRecord>,
    pub declarations: Vec<GpuSemanticInterfaceDeclarationRecord>,
    pub name_bytes: Vec<u8>,
}

impl GpuSemanticInterfaceIdentityArtifact {
    /// Validates canonical identities without accepting the partial artifact as
    /// a complete semantic interface.
    pub fn validate(&self) -> Result<(), String> {
        checked_u32_len("module", self.modules.len())?;
        checked_u32_len("module segment", self.module_segments.len())?;
        checked_u32_len("declaration", self.declarations.len())?;
        checked_u32_len("name byte", self.name_bytes.len())?;
        let partial = GpuSemanticInterfaceArtifact {
            version: GPU_SEMANTIC_INTERFACE_VERSION,
            library_id: self.library_id,
            unit_id: self.unit_id,
            modules: self.modules.clone(),
            module_segments: self.module_segments.clone(),
            declarations: self.declarations.clone(),
            types: Vec::new(),
            type_edges: Vec::new(),
            members: Vec::new(),
            name_bytes: self.name_bytes.clone(),
        };
        partial.validate_identities()
    }
}

/// Complete stable interface emitted for one bounded library compilation unit.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GpuSemanticInterfaceArtifact {
    pub version: u32,
    pub library_id: u32,
    /// Globally unique bounded frontend-unit id within the source-pack build.
    pub unit_id: u32,
    pub modules: Vec<GpuSemanticInterfaceModuleRecord>,
    pub module_segments: Vec<GpuSemanticInterfaceModuleSegmentRecord>,
    pub declarations: Vec<GpuSemanticInterfaceDeclarationRecord>,
    pub types: Vec<GpuSemanticInterfaceTypeRecord>,
    pub type_edges: Vec<GpuSemanticInterfaceTypeEdge>,
    pub members: Vec<GpuSemanticInterfaceMemberRecord>,
    pub name_bytes: Vec<u8>,
}

impl GpuSemanticInterfaceArtifact {
    /// Validates all record ranges, canonical names, and typed references.
    pub fn validate(&self) -> Result<(), String> {
        if self.version != GPU_SEMANTIC_INTERFACE_VERSION {
            return Err(format!(
                "semantic-interface version {} is unsupported; expected {}",
                self.version, GPU_SEMANTIC_INTERFACE_VERSION
            ));
        }
        checked_u32_len("module", self.modules.len())?;
        checked_u32_len("module segment", self.module_segments.len())?;
        checked_u32_len("declaration", self.declarations.len())?;
        checked_u32_len("type", self.types.len())?;
        checked_u32_len("type edge", self.type_edges.len())?;
        checked_u32_len("member", self.members.len())?;
        checked_u32_len("name byte", self.name_bytes.len())?;

        self.validate_identities()?;
        if self
            .declarations
            .windows(2)
            .any(|pair| pair[0].module > pair[1].module)
        {
            return Err(
                "semantic-interface declarations are not grouped in canonical module order"
                    .to_string(),
            );
        }
        for (index, declaration) in self.declarations.iter().enumerate() {
            validate_optional_index(
                "declaration signature type",
                index,
                declaration.signature_type,
                self.types.len(),
            )?;
            if declaration.signature_type == INVALID {
                return Err(format!(
                    "semantic-interface declaration record {index} has no typed signature"
                ));
            }
            validate_range(
                "declaration member",
                index,
                declaration.first_member,
                declaration.member_count,
                self.members.len(),
            )?;
            let member_range = checked_range(
                "declaration member",
                index,
                declaration.first_member,
                declaration.member_count,
                self.members.len(),
            )?;
            if self.members[member_range]
                .iter()
                .any(|member| member.owner_declaration as usize != index)
            {
                return Err(format!(
                    "semantic-interface declaration record {index} member range contains a foreign owner"
                ));
            }
        }
        let mut type_subtree_starts = Vec::with_capacity(self.types.len());
        for (index, ty) in self.types.iter().enumerate() {
            let Some(kind) = GpuSemanticInterfaceTypeKind::from_u32(ty.kind) else {
                return Err(format!(
                    "semantic-interface type record {index} has unknown kind {}",
                    ty.kind
                ));
            };
            validate_range(
                "type edge",
                index,
                ty.first_edge,
                ty.edge_count,
                self.type_edges.len(),
            )?;
            let edge_range = checked_range(
                "type edge",
                index,
                ty.first_edge,
                ty.edge_count,
                self.type_edges.len(),
            )?;
            for (edge_offset, edge) in self.type_edges[edge_range.clone()].iter().enumerate() {
                validate_index(
                    "type edge target",
                    ty.first_edge as usize + edge_offset,
                    edge.type_index,
                    self.types.len(),
                )?;
                if edge.type_index as usize >= index {
                    return Err(format!(
                        "semantic-interface type record {index} edge target {} is not in prior topological order",
                        edge.type_index
                    ));
                }
            }
            let mut subtree_start = index;
            if kind != GpuSemanticInterfaceTypeKind::Function {
                for edge in self.type_edges[edge_range.clone()].iter() {
                    let expected_child = subtree_start.checked_sub(1).ok_or_else(|| {
                        format!(
                            "semantic-interface type record {index} has a child before the start of its reverse-preorder subtree"
                        )
                    })?;
                    if edge.type_index as usize != expected_child {
                        return Err(format!(
                            "semantic-interface type record {index} child {} is not contiguous reverse preorder; expected {expected_child}",
                            edge.type_index
                        ));
                    }
                    subtree_start = type_subtree_starts[expected_child];
                }
            }
            type_subtree_starts.push(subtree_start);
            match kind {
                GpuSemanticInterfaceTypeKind::Scalar
                | GpuSemanticInterfaceTypeKind::GenericParameter
                | GpuSemanticInterfaceTypeKind::ConstParameter
                    if ty.edge_count != 0 =>
                {
                    return Err(format!(
                        "semantic-interface leaf type record {index} has {} child edges",
                        ty.edge_count
                    ));
                }
                GpuSemanticInterfaceTypeKind::Array
                | GpuSemanticInterfaceTypeKind::Slice
                | GpuSemanticInterfaceTypeKind::Reference
                    if ty.edge_count != 1 =>
                {
                    return Err(format!(
                        "semantic-interface unary type record {index} has {} child edges",
                        ty.edge_count
                    ));
                }
                GpuSemanticInterfaceTypeKind::Function if ty.edge_count == 0 => {
                    return Err(format!(
                        "semantic-interface function type record {index} has no return-type edge"
                    ));
                }
                _ => {}
            }
            match kind {
                GpuSemanticInterfaceTypeKind::Declaration
                    if ty.payload_lo == self.library_id && ty.nominal_unit_id == self.unit_id =>
                {
                    validate_index(
                        "nominal type declaration",
                        index,
                        ty.payload_hi,
                        self.declarations.len(),
                    )?
                }
                GpuSemanticInterfaceTypeKind::GenericParameter
                | GpuSemanticInterfaceTypeKind::ConstParameter => validate_index(
                    "generic type member",
                    index,
                    ty.payload_lo,
                    self.members.len(),
                )?,
                _ => {}
            }
        }
        for (index, member) in self.members.iter().enumerate() {
            if GpuSemanticInterfaceMemberKind::from_u32(member.kind).is_none() {
                return Err(format!(
                    "semantic-interface member record {index} has unknown kind {}",
                    member.kind
                ));
            }
            validate_index(
                "member owner declaration",
                index,
                member.owner_declaration,
                self.declarations.len(),
            )?;
            self.validate_name(
                "member",
                index,
                member.name_hash_lo,
                member.name_hash_hi,
                member.name_byte_start,
                member.name_byte_len,
            )?;
            validate_optional_index("member type", index, member.type_index, self.types.len())?;
            let kind = GpuSemanticInterfaceMemberKind::from_u32(member.kind)
                .expect("member kind was validated above");
            if member.type_index == INVALID
                && !matches!(
                    kind,
                    GpuSemanticInterfaceMemberKind::EnumVariant
                        | GpuSemanticInterfaceMemberKind::GenericTypeParameter
                        | GpuSemanticInterfaceMemberKind::GenericConstParameter
                )
            {
                return Err(format!(
                    "semantic-interface member record {index} has no typed signature"
                ));
            }
        }
        Ok(())
    }

    fn validate_identities(&self) -> Result<(), String> {
        for (index, module) in self.modules.iter().enumerate() {
            validate_range(
                "module segment",
                index,
                module.first_segment,
                module.segment_count,
                self.module_segments.len(),
            )?;
        }
        for (index, segment) in self.module_segments.iter().enumerate() {
            self.validate_name(
                "module segment",
                index,
                segment.name_hash_lo,
                segment.name_hash_hi,
                segment.name_byte_start,
                segment.name_byte_len,
            )?;
        }
        for (index, declaration) in self.declarations.iter().enumerate() {
            validate_index(
                "declaration module",
                index,
                declaration.module,
                self.modules.len(),
            )?;
            self.validate_name(
                "declaration",
                index,
                declaration.name_hash_lo,
                declaration.name_hash_hi,
                declaration.name_byte_start,
                declaration.name_byte_len,
            )?;
            validate_optional_index(
                "declaration owner",
                index,
                declaration.owner_declaration,
                self.declarations.len(),
            )?;
        }
        Ok(())
    }

    /// Serializes the interface into its bounded little-endian binary format.
    pub fn to_bytes(&self) -> Result<Vec<u8>, String> {
        self.validate()?;
        let byte_len = encoded_byte_len(self)?;
        let mut bytes = Vec::with_capacity(byte_len);
        bytes.extend_from_slice(&GPU_SEMANTIC_INTERFACE_MAGIC);
        push_u32(&mut bytes, self.version);
        push_u32(&mut bytes, self.library_id);
        push_u32_len(&mut bytes, "module", self.modules.len())?;
        push_u32_len(&mut bytes, "module segment", self.module_segments.len())?;
        push_u32_len(&mut bytes, "declaration", self.declarations.len())?;
        push_u32_len(&mut bytes, "type", self.types.len())?;
        push_u32_len(&mut bytes, "type edge", self.type_edges.len())?;
        push_u32_len(&mut bytes, "member", self.members.len())?;
        push_u32_len(&mut bytes, "name byte", self.name_bytes.len())?;
        push_u32(&mut bytes, self.unit_id);
        for _ in 10..HEADER_U32S {
            push_u32(&mut bytes, 0);
        }
        for row in &self.modules {
            push_u32(&mut bytes, row.first_segment);
            push_u32(&mut bytes, row.segment_count);
        }
        for row in &self.module_segments {
            push_u32(&mut bytes, row.name_hash_lo);
            push_u32(&mut bytes, row.name_hash_hi);
            push_u32(&mut bytes, row.name_byte_start);
            push_u32(&mut bytes, row.name_byte_len);
        }
        for row in &self.declarations {
            push_u32(&mut bytes, row.module);
            push_u32(&mut bytes, row.name_hash_lo);
            push_u32(&mut bytes, row.name_hash_hi);
            push_u32(&mut bytes, row.name_byte_start);
            push_u32(&mut bytes, row.name_byte_len);
            push_u32(&mut bytes, row.namespace);
            push_u32(&mut bytes, row.kind);
            push_u32(&mut bytes, row.signature_type);
            push_u32(&mut bytes, row.first_member);
            push_u32(&mut bytes, row.member_count);
            push_u32(&mut bytes, row.owner_declaration);
            push_u32(&mut bytes, row.flags);
            push_u32(&mut bytes, row.value_lo);
            push_u32(&mut bytes, row.value_hi);
        }
        for row in &self.types {
            push_u32(&mut bytes, row.kind);
            push_u32(&mut bytes, row.payload_lo);
            push_u32(&mut bytes, row.payload_hi);
            push_u32(&mut bytes, row.first_edge);
            push_u32(&mut bytes, row.edge_count);
            push_u32(&mut bytes, row.length_kind);
            push_u32(&mut bytes, row.length_lo);
            push_u32(&mut bytes, row.length_hi);
            push_u32(&mut bytes, row.nominal_unit_id);
        }
        for row in &self.type_edges {
            push_u32(&mut bytes, row.type_index);
        }
        for row in &self.members {
            push_u32(&mut bytes, row.owner_declaration);
            push_u32(&mut bytes, row.kind);
            push_u32(&mut bytes, row.ordinal);
            push_u32(&mut bytes, row.name_hash_lo);
            push_u32(&mut bytes, row.name_hash_hi);
            push_u32(&mut bytes, row.name_byte_start);
            push_u32(&mut bytes, row.name_byte_len);
            push_u32(&mut bytes, row.type_index);
            push_u32(&mut bytes, row.value_lo);
            push_u32(&mut bytes, row.value_hi);
        }
        bytes.extend_from_slice(&self.name_bytes);
        debug_assert_eq!(bytes.len(), byte_len);
        Ok(bytes)
    }

    /// Parses and validates one persisted semantic-interface artifact.
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        let header_bytes = 8usize
            .checked_add(HEADER_U32S * 4)
            .ok_or_else(|| "semantic-interface header size overflows".to_string())?;
        if bytes.len() < header_bytes || bytes[..8] != GPU_SEMANTIC_INTERFACE_MAGIC {
            return Err("semantic-interface artifact has an invalid or truncated header".into());
        }
        let mut cursor = 8usize;
        let version = read_u32(bytes, &mut cursor)?;
        let library_id = read_u32(bytes, &mut cursor)?;
        let module_count = read_count(bytes, &mut cursor, "module")?;
        let module_segment_count = read_count(bytes, &mut cursor, "module segment")?;
        let declaration_count = read_count(bytes, &mut cursor, "declaration")?;
        let type_count = read_count(bytes, &mut cursor, "type")?;
        let type_edge_count = read_count(bytes, &mut cursor, "type edge")?;
        let member_count = read_count(bytes, &mut cursor, "member")?;
        let name_byte_count = read_count(bytes, &mut cursor, "name byte")?;
        let unit_id = read_u32(bytes, &mut cursor)?;
        cursor = header_bytes;

        let expected = encoded_byte_len_from_counts(
            module_count,
            module_segment_count,
            declaration_count,
            type_count,
            type_edge_count,
            member_count,
            name_byte_count,
        )?;
        if bytes.len() != expected {
            return Err(format!(
                "semantic-interface artifact has {} bytes but its header requires {}",
                bytes.len(),
                expected
            ));
        }

        let mut modules = Vec::with_capacity(module_count);
        for _ in 0..module_count {
            modules.push(GpuSemanticInterfaceModuleRecord {
                first_segment: read_u32(bytes, &mut cursor)?,
                segment_count: read_u32(bytes, &mut cursor)?,
            });
        }
        let mut module_segments = Vec::with_capacity(module_segment_count);
        for _ in 0..module_segment_count {
            module_segments.push(GpuSemanticInterfaceModuleSegmentRecord {
                name_hash_lo: read_u32(bytes, &mut cursor)?,
                name_hash_hi: read_u32(bytes, &mut cursor)?,
                name_byte_start: read_u32(bytes, &mut cursor)?,
                name_byte_len: read_u32(bytes, &mut cursor)?,
            });
        }
        let mut declarations = Vec::with_capacity(declaration_count);
        for _ in 0..declaration_count {
            declarations.push(GpuSemanticInterfaceDeclarationRecord {
                module: read_u32(bytes, &mut cursor)?,
                name_hash_lo: read_u32(bytes, &mut cursor)?,
                name_hash_hi: read_u32(bytes, &mut cursor)?,
                name_byte_start: read_u32(bytes, &mut cursor)?,
                name_byte_len: read_u32(bytes, &mut cursor)?,
                namespace: read_u32(bytes, &mut cursor)?,
                kind: read_u32(bytes, &mut cursor)?,
                signature_type: read_u32(bytes, &mut cursor)?,
                first_member: read_u32(bytes, &mut cursor)?,
                member_count: read_u32(bytes, &mut cursor)?,
                owner_declaration: read_u32(bytes, &mut cursor)?,
                flags: read_u32(bytes, &mut cursor)?,
                value_lo: read_u32(bytes, &mut cursor)?,
                value_hi: read_u32(bytes, &mut cursor)?,
            });
        }
        let mut types = Vec::with_capacity(type_count);
        for _ in 0..type_count {
            types.push(GpuSemanticInterfaceTypeRecord {
                kind: read_u32(bytes, &mut cursor)?,
                payload_lo: read_u32(bytes, &mut cursor)?,
                payload_hi: read_u32(bytes, &mut cursor)?,
                first_edge: read_u32(bytes, &mut cursor)?,
                edge_count: read_u32(bytes, &mut cursor)?,
                length_kind: read_u32(bytes, &mut cursor)?,
                length_lo: read_u32(bytes, &mut cursor)?,
                length_hi: read_u32(bytes, &mut cursor)?,
                nominal_unit_id: read_u32(bytes, &mut cursor)?,
            });
        }
        let mut type_edges = Vec::with_capacity(type_edge_count);
        for _ in 0..type_edge_count {
            type_edges.push(GpuSemanticInterfaceTypeEdge {
                type_index: read_u32(bytes, &mut cursor)?,
            });
        }
        let mut members = Vec::with_capacity(member_count);
        for _ in 0..member_count {
            members.push(GpuSemanticInterfaceMemberRecord {
                owner_declaration: read_u32(bytes, &mut cursor)?,
                kind: read_u32(bytes, &mut cursor)?,
                ordinal: read_u32(bytes, &mut cursor)?,
                name_hash_lo: read_u32(bytes, &mut cursor)?,
                name_hash_hi: read_u32(bytes, &mut cursor)?,
                name_byte_start: read_u32(bytes, &mut cursor)?,
                name_byte_len: read_u32(bytes, &mut cursor)?,
                type_index: read_u32(bytes, &mut cursor)?,
                value_lo: read_u32(bytes, &mut cursor)?,
                value_hi: read_u32(bytes, &mut cursor)?,
            });
        }
        let name_bytes = bytes[cursor..].to_vec();
        let artifact = Self {
            version,
            library_id,
            unit_id,
            modules,
            module_segments,
            declarations,
            types,
            type_edges,
            members,
            name_bytes,
        };
        artifact.validate()?;
        Ok(artifact)
    }

    fn validate_name(
        &self,
        domain: &str,
        index: usize,
        hash_lo: u32,
        hash_hi: u32,
        start: u32,
        len: u32,
    ) -> Result<(), String> {
        let range = checked_range(domain, index, start, len, self.name_bytes.len())?;
        let name = &self.name_bytes[range];
        if name.is_empty()
            || name.len() > MAX_CANONICAL_NAME_BYTES
            || std::str::from_utf8(name).is_err()
        {
            return Err(format!(
                "semantic-interface {domain} record {index} has an empty, oversized, or non-UTF-8 canonical name"
            ));
        }
        let expected = stable_name_hash(name);
        if expected != (hash_lo, hash_hi) {
            return Err(format!(
                "semantic-interface {domain} record {index} canonical-name hash does not match its bytes"
            ));
        }
        Ok(())
    }
}

/// Exact stable hash used by GPU interface identity records. Bytes remain in
/// the artifact and must be compared after a hash match.
pub(crate) fn stable_name_hash(name: &[u8]) -> (u32, u32) {
    let mut lo = 2_166_136_261u32 ^ name.len() as u32;
    let mut hi = 0x9e37_79b9u32.wrapping_add((name.len() as u32).wrapping_mul(0x85eb_ca6b));
    for &byte in name {
        lo = (lo ^ u32::from(byte)).wrapping_mul(16_777_619);
        hi ^= u32::from(byte)
            .wrapping_add(0x9e37_79b9)
            .wrapping_add(hi << 6)
            .wrapping_add(hi >> 2);
    }
    (hash_mix(lo), hash_mix(hi))
}

fn hash_mix(mut value: u32) -> u32 {
    value ^= value >> 16;
    value = value.wrapping_mul(0x7feb_352d);
    value ^= value >> 15;
    value = value.wrapping_mul(0x846c_a68b);
    value ^ (value >> 16)
}

fn checked_u32_len(domain: &str, len: usize) -> Result<u32, String> {
    u32::try_from(len).map_err(|_| format!("semantic-interface {domain} count {len} exceeds u32"))
}

fn validate_index(domain: &str, owner: usize, index: u32, len: usize) -> Result<(), String> {
    if index as usize >= len {
        return Err(format!(
            "semantic-interface {domain} for record {owner} is {index}, outside 0..{len}"
        ));
    }
    Ok(())
}

fn validate_optional_index(
    domain: &str,
    owner: usize,
    index: u32,
    len: usize,
) -> Result<(), String> {
    if index == INVALID {
        return Ok(());
    }
    validate_index(domain, owner, index, len)
}

fn checked_range(
    domain: &str,
    owner: usize,
    start: u32,
    count: u32,
    len: usize,
) -> Result<std::ops::Range<usize>, String> {
    let start = start as usize;
    let end = start
        .checked_add(count as usize)
        .ok_or_else(|| format!("semantic-interface {domain} range for record {owner} overflows"))?;
    if end > len {
        return Err(format!(
            "semantic-interface {domain} range for record {owner} is {start}..{end}, outside 0..{len}"
        ));
    }
    Ok(start..end)
}

fn validate_range(
    domain: &str,
    owner: usize,
    start: u32,
    count: u32,
    len: usize,
) -> Result<(), String> {
    checked_range(domain, owner, start, count, len).map(drop)
}

fn encoded_byte_len(artifact: &GpuSemanticInterfaceArtifact) -> Result<usize, String> {
    encoded_byte_len_from_counts(
        artifact.modules.len(),
        artifact.module_segments.len(),
        artifact.declarations.len(),
        artifact.types.len(),
        artifact.type_edges.len(),
        artifact.members.len(),
        artifact.name_bytes.len(),
    )
}

fn encoded_byte_len_from_counts(
    modules: usize,
    module_segments: usize,
    declarations: usize,
    types: usize,
    type_edges: usize,
    members: usize,
    name_bytes: usize,
) -> Result<usize, String> {
    let words = HEADER_U32S
        .checked_add(
            modules
                .checked_mul(MODULE_U32S)
                .ok_or("module byte size overflows")?,
        )
        .and_then(|n| n.checked_add(module_segments.checked_mul(MODULE_SEGMENT_U32S)?))
        .and_then(|n| n.checked_add(declarations.checked_mul(DECLARATION_U32S)?))
        .and_then(|n| n.checked_add(types.checked_mul(TYPE_U32S)?))
        .and_then(|n| n.checked_add(type_edges.checked_mul(TYPE_EDGE_U32S)?))
        .and_then(|n| n.checked_add(members.checked_mul(MEMBER_U32S)?))
        .ok_or_else(|| "semantic-interface record byte size overflows".to_string())?;
    8usize
        .checked_add(
            words
                .checked_mul(4)
                .ok_or("semantic-interface word bytes overflow")?,
        )
        .and_then(|n| n.checked_add(name_bytes))
        .ok_or_else(|| "semantic-interface artifact byte size overflows".to_string())
}

fn push_u32(bytes: &mut Vec<u8>, value: u32) {
    bytes.extend_from_slice(&value.to_le_bytes());
}

fn push_u32_len(bytes: &mut Vec<u8>, domain: &str, len: usize) -> Result<(), String> {
    push_u32(bytes, checked_u32_len(domain, len)?);
    Ok(())
}

fn read_u32(bytes: &[u8], cursor: &mut usize) -> Result<u32, String> {
    let end = cursor
        .checked_add(4)
        .ok_or_else(|| "semantic-interface read offset overflows".to_string())?;
    let raw = bytes
        .get(*cursor..end)
        .ok_or_else(|| "semantic-interface artifact is truncated".to_string())?;
    *cursor = end;
    Ok(u32::from_le_bytes(raw.try_into().expect("four-byte slice")))
}

fn read_count(bytes: &[u8], cursor: &mut usize, domain: &str) -> Result<usize, String> {
    usize::try_from(read_u32(bytes, cursor)?)
        .map_err(|_| format!("semantic-interface {domain} count does not fit usize"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn append_name(bytes: &mut Vec<u8>, name: &str) -> (u32, u32, u32, u32) {
        let start = bytes.len() as u32;
        bytes.extend_from_slice(name.as_bytes());
        let (lo, hi) = stable_name_hash(name.as_bytes());
        (lo, hi, start, name.len() as u32)
    }

    fn representative_interface() -> GpuSemanticInterfaceArtifact {
        let mut name_bytes = Vec::new();
        let core = append_name(&mut name_bytes, "core");
        let math = append_name(&mut name_bytes, "math");
        let add = append_name(&mut name_bytes, "add");
        let lhs = append_name(&mut name_bytes, "lhs");
        GpuSemanticInterfaceArtifact {
            version: GPU_SEMANTIC_INTERFACE_VERSION,
            library_id: 7,
            unit_id: 11,
            modules: vec![GpuSemanticInterfaceModuleRecord {
                first_segment: 0,
                segment_count: 2,
            }],
            module_segments: vec![
                GpuSemanticInterfaceModuleSegmentRecord {
                    name_hash_lo: core.0,
                    name_hash_hi: core.1,
                    name_byte_start: core.2,
                    name_byte_len: core.3,
                },
                GpuSemanticInterfaceModuleSegmentRecord {
                    name_hash_lo: math.0,
                    name_hash_hi: math.1,
                    name_byte_start: math.2,
                    name_byte_len: math.3,
                },
            ],
            declarations: vec![GpuSemanticInterfaceDeclarationRecord {
                module: 0,
                name_hash_lo: add.0,
                name_hash_hi: add.1,
                name_byte_start: add.2,
                name_byte_len: add.3,
                namespace: 2,
                kind: 4,
                signature_type: 1,
                first_member: 0,
                member_count: 1,
                owner_declaration: INVALID,
                flags: 0,
                value_lo: 0,
                value_hi: 0,
            }],
            types: vec![
                GpuSemanticInterfaceTypeRecord {
                    kind: GpuSemanticInterfaceTypeKind::Scalar as u32,
                    payload_lo: 3,
                    payload_hi: 0,
                    first_edge: 0,
                    edge_count: 0,
                    length_kind: 0,
                    length_lo: 0,
                    length_hi: 0,
                    nominal_unit_id: 0,
                },
                GpuSemanticInterfaceTypeRecord {
                    kind: GpuSemanticInterfaceTypeKind::Function as u32,
                    payload_lo: 0,
                    payload_hi: 0,
                    first_edge: 0,
                    edge_count: 1,
                    length_kind: 0,
                    length_lo: 0,
                    length_hi: 0,
                    nominal_unit_id: 0,
                },
            ],
            type_edges: vec![GpuSemanticInterfaceTypeEdge { type_index: 0 }],
            members: vec![GpuSemanticInterfaceMemberRecord {
                owner_declaration: 0,
                kind: GpuSemanticInterfaceMemberKind::Parameter as u32,
                ordinal: 0,
                name_hash_lo: lhs.0,
                name_hash_hi: lhs.1,
                name_byte_start: lhs.2,
                name_byte_len: lhs.3,
                type_index: 0,
                value_lo: 0,
                value_hi: 0,
            }],
            name_bytes,
        }
    }

    #[test]
    fn semantic_interface_binary_roundtrip_preserves_canonical_typed_graph() {
        let interface = representative_interface();
        let bytes = interface.to_bytes().expect("serialize semantic interface");
        let decoded =
            GpuSemanticInterfaceArtifact::from_bytes(&bytes).expect("parse semantic interface");
        assert_eq!(decoded, interface);
    }

    #[test]
    fn semantic_interface_rejects_hash_only_or_out_of_range_identity_records() {
        let mut interface = representative_interface();
        interface.declarations[0].name_hash_lo ^= 1;
        assert!(interface.validate().unwrap_err().contains("hash"));

        let mut interface = representative_interface();
        interface.declarations[0].module = 1;
        assert!(interface.validate().unwrap_err().contains("module"));

        let mut interface = representative_interface();
        interface.version = 1;
        assert!(interface.validate().unwrap_err().contains("version"));

        let mut interface = representative_interface();
        interface.types.push(GpuSemanticInterfaceTypeRecord {
            kind: GpuSemanticInterfaceTypeKind::Declaration as u32,
            payload_lo: interface.library_id,
            payload_hi: 0,
            first_edge: interface.type_edges.len() as u32,
            edge_count: 1,
            length_kind: 0,
            length_lo: 0,
            length_hi: 0,
            nominal_unit_id: interface.unit_id,
        });
        interface
            .type_edges
            .push(GpuSemanticInterfaceTypeEdge { type_index: 0 });
        assert!(
            interface
                .validate()
                .unwrap_err()
                .contains("reverse preorder")
        );
    }

    #[test]
    fn semantic_interface_rejects_trailing_or_truncated_binary_payloads() {
        let bytes = representative_interface()
            .to_bytes()
            .expect("serialize semantic interface");
        let mut trailing = bytes.clone();
        trailing.push(0);
        assert!(GpuSemanticInterfaceArtifact::from_bytes(&trailing).is_err());
        assert!(GpuSemanticInterfaceArtifact::from_bytes(&bytes[..bytes.len() - 1]).is_err());
    }

    #[test]
    fn semantic_interface_nominal_types_carry_library_identity_and_generic_edges() {
        let mut interface = representative_interface();
        interface.types.push(GpuSemanticInterfaceTypeRecord {
            kind: GpuSemanticInterfaceTypeKind::Scalar as u32,
            payload_lo: 3,
            payload_hi: 0,
            first_edge: interface.type_edges.len() as u32,
            edge_count: 0,
            length_kind: 0,
            length_lo: 0,
            length_hi: 0,
            nominal_unit_id: 0,
        });
        let argument = (interface.types.len() - 1) as u32;
        interface.types.push(GpuSemanticInterfaceTypeRecord {
            kind: GpuSemanticInterfaceTypeKind::Declaration as u32,
            payload_lo: interface.library_id,
            payload_hi: 0,
            first_edge: interface.type_edges.len() as u32,
            edge_count: 1,
            length_kind: 0,
            length_lo: 0,
            length_hi: 0,
            nominal_unit_id: interface.unit_id,
        });
        interface.type_edges.push(GpuSemanticInterfaceTypeEdge {
            type_index: argument,
        });
        interface
            .validate()
            .expect("local nominal types should accept generic argument edges");

        let nominal = interface.types.last_mut().expect("nominal type row");
        nominal.payload_lo = 91;
        nominal.payload_hi = 1234;
        nominal.nominal_unit_id = 17;
        interface
            .validate()
            .expect("dependency nominal identities are resolved by library plus declaration");

        let nominal = interface.types.last_mut().expect("nominal type row");
        nominal.payload_lo = interface.library_id;
        nominal.payload_hi = 99;
        nominal.nominal_unit_id = interface.unit_id;
        assert!(
            interface
                .validate()
                .unwrap_err()
                .contains("nominal type declaration")
        );
    }
}
