use std::{
    collections::BTreeSet,
    fs,
    path::{Component, Path, PathBuf},
};

use serde::{Deserialize, Deserializer, Serialize, Serializer, de::Error as _, ser::Error as _};

use super::package_lock::PackageLockfile;
use crate::compiler::{
    CompileError,
    EntrySourceRoots,
    ExplicitSourcePack,
    ExplicitSourcePackPathManifest,
    diagnostics::Diagnostic,
};

/// Maximum number of source roots a package manifest may declare.
pub const PACKAGE_MANIFEST_MAX_ROOTS: usize = 64;
/// Maximum number of module path segments derived from a package-relative path.
pub(super) const PACKAGE_MODULE_PATH_SEGMENT_LIMIT: usize = 8;
/// Human-readable package name validation rule used in diagnostics.
pub(super) const PACKAGE_NAME_RULES: &str = "use dot-separated ASCII package segments; each segment must start and end with a letter or digit and contain only letters, digits, '_' or '-'";

/// Control-plane package metadata. Manifest paths are package-relative so the
/// manifest stays relocatable; generated lockfiles record canonical absolute
/// paths. Root paths are file-loading candidates only, and module identity still
/// comes from parsed `module` and `import` records.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PackageManifest {
    /// Dot-separated package name used for package identity.
    pub package: String,
    /// Package-relative directories that contain user source files.
    pub roots: Vec<PathBuf>,
    /// Optional package-relative standard-library source root.
    pub stdlib_root: Option<PathBuf>,
    /// Package-relative `.lani` entry source file.
    pub entry: PathBuf,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackageManifestDocument {
    package: String,
    roots: Vec<PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    stdlib_root: Option<PathBuf>,
    entry: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Package manifest resolved against a concrete manifest directory.
pub struct ResolvedPackageManifest {
    /// Dot-separated package name from the manifest.
    pub package: String,
    /// Canonical absolute source roots.
    pub roots: Vec<PathBuf>,
    /// Canonical absolute standard-library root, when configured.
    pub stdlib_root: Option<PathBuf>,
    /// Canonical absolute entry source path.
    pub entry: PathBuf,
}

impl<'de> Deserialize<'de> for PackageManifest {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        PackageManifestDocument::deserialize(deserializer)?
            .to_validated_manifest()
            .map_err(D::Error::custom)
    }
}

impl Serialize for PackageManifest {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        self.validate_fields().map_err(S::Error::custom)?;
        PackageManifestDocument::from_manifest(self).serialize(serializer)
    }
}

impl PackageManifest {
    /// Parses and validates a package manifest from JSON text.
    pub fn parse_json(source: &str) -> Result<Self, CompileError> {
        let document = serde_json::from_str::<PackageManifestDocument>(source).map_err(|err| {
            let mut message = format!("parse package manifest JSON: {err}");
            if let Some(field) = unsupported_manifest_import_configuration_field(source) {
                message.push_str(&format!(
                    "; unsupported package manifest field `{field}`; package manifests configure source roots, optional stdlib_root, and entry only; imports are declared in .lani source files with module paths, and external package dependencies are not supported yet"
                ));
            }
            package_manifest_error(message)
        })?;
        document.to_validated_manifest()
    }

    /// Loads a JSON manifest file and resolves paths relative to its directory.
    pub fn load_json_file(path: impl AsRef<Path>) -> Result<ResolvedPackageManifest, CompileError> {
        let path = path.as_ref();
        let source =
            fs::read_to_string(path).map_err(|err| package_manifest_read_error(path, err))?;
        let base_dir = path.parent().unwrap_or_else(|| Path::new("."));
        Self::parse_json(&source)?.resolve_from_dir(base_dir)
    }

    /// Resolves package-relative manifest paths against a base directory.
    ///
    /// Resolution canonicalizes roots and entry paths, rejects overlaps and
    /// symlink escapes, and verifies that the entry maps to a valid module path.
    pub fn resolve_from_dir(
        &self,
        base_dir: impl AsRef<Path>,
    ) -> Result<ResolvedPackageManifest, CompileError> {
        self.validate_fields()?;
        let base_dir = canonical_manifest_base_dir(base_dir.as_ref())?;

        let mut seen_roots = BTreeSet::new();
        let mut roots: Vec<PathBuf> = Vec::with_capacity(self.roots.len());
        for root in &self.roots {
            let root = canonical_manifest_dir("package source root", &base_dir, root)?;
            if seen_roots.insert(root.clone()) {
                roots.push(root);
            } else {
                return Err(package_manifest_error(format!(
                    "duplicate package source root {}",
                    root.display()
                )));
            }
        }
        roots.sort();
        for (index, root) in roots.iter().enumerate() {
            for other in roots.iter().skip(index + 1) {
                if resolved_paths_overlap(root, other) {
                    return Err(package_manifest_error(format!(
                        "package source roots {} and {} overlap",
                        root.display(),
                        other.display()
                    )));
                }
            }
        }
        if roots.is_empty() {
            return Err(package_manifest_error(
                "package manifest must declare at least one source root",
            ));
        }

        let entry = canonical_manifest_file("package entry", &base_dir, &self.entry)?;
        validate_package_entry_source_path("resolved package entry", &entry)?;
        if !roots.iter().any(|root| entry.starts_with(root)) {
            return Err(package_manifest_error(format!(
                "package entry {} is not under any declared source root; declared source roots: {}",
                entry.display(),
                format_manifest_roots(&roots)
            )));
        }
        let entry_relative_path = roots
            .iter()
            .find_map(|root| entry.strip_prefix(root).ok())
            .ok_or_else(|| {
                package_manifest_error(format!(
                    "package entry {} is not relative to any declared source root; declared source roots: {}",
                    entry.display(),
                    format_manifest_roots(&roots)
                ))
            })?;
        package_source_root_relative_module_path_with_label(
            "package entry source-root relative path",
            entry_relative_path,
        )
        .map_err(package_manifest_error)?;

        let stdlib_root = self
            .stdlib_root
            .as_ref()
            .map(|root| canonical_manifest_dir("package stdlib root", &base_dir, root))
            .transpose()?;
        if let Some(stdlib_root) = &stdlib_root {
            for root in &roots {
                if resolved_paths_overlap(root, stdlib_root) {
                    return Err(package_manifest_error(format!(
                        "package stdlib root {} overlaps source root {}",
                        stdlib_root.display(),
                        root.display()
                    )));
                }
            }
        }

        Ok(ResolvedPackageManifest {
            package: self.package.clone(),
            roots,
            stdlib_root,
            entry,
        })
    }

    fn validate_fields(&self) -> Result<(), CompileError> {
        if !valid_package_name(&self.package) {
            return Err(package_manifest_error(format!(
                "invalid package name {:?}; {PACKAGE_NAME_RULES}",
                self.package,
            )));
        }
        if self.roots.is_empty() {
            return Err(package_manifest_error(
                "package manifest must declare at least one source root",
            ));
        }
        if self.roots.len() > PACKAGE_MANIFEST_MAX_ROOTS {
            return Err(package_manifest_error(format!(
                "package manifest declares {} source roots; maximum is {PACKAGE_MANIFEST_MAX_ROOTS}",
                self.roots.len()
            )));
        }
        let mut seen_manifest_roots = BTreeSet::new();
        for root in &self.roots {
            if root.as_os_str().is_empty() {
                return Err(package_manifest_error(
                    "package manifest source roots must not be empty paths",
                ));
            }
            validate_package_relative_path("source root", root)?;
            if !seen_manifest_roots.insert(root.clone()) {
                return Err(package_manifest_error(format!(
                    "duplicate package source root {}",
                    root.display()
                )));
            }
        }
        if let Some(stdlib_root) = &self.stdlib_root {
            if stdlib_root.as_os_str().is_empty() {
                return Err(package_manifest_error(
                    "package manifest stdlib root must not be an empty path",
                ));
            }
            validate_package_relative_path("stdlib root", stdlib_root)?;
        }
        if self.entry.as_os_str().is_empty() {
            return Err(package_manifest_error(
                "package manifest entry must not be an empty path",
            ));
        }
        validate_package_relative_path("entry", &self.entry)?;
        validate_package_entry_source_path("entry", &self.entry)?;
        Ok(())
    }
}

impl PackageManifestDocument {
    fn from_manifest(manifest: &PackageManifest) -> Self {
        Self {
            package: manifest.package.clone(),
            roots: manifest.roots.clone(),
            stdlib_root: manifest.stdlib_root.clone(),
            entry: manifest.entry.clone(),
        }
    }

    fn to_manifest(&self) -> PackageManifest {
        PackageManifest {
            package: self.package.clone(),
            roots: self.roots.clone(),
            stdlib_root: self.stdlib_root.clone(),
            entry: self.entry.clone(),
        }
    }

    fn to_validated_manifest(&self) -> Result<PackageManifest, CompileError> {
        let manifest = self.to_manifest();
        manifest.validate_fields()?;
        Ok(manifest)
    }
}

impl ResolvedPackageManifest {
    /// Converts resolved package roots into the entry-root structure used by loading.
    pub fn to_entry_source_roots(&self) -> EntrySourceRoots {
        EntrySourceRoots {
            stdlib_root: self.stdlib_root.clone(),
            user_roots: self.roots.clone(),
        }
    }

    /// Loads an in-memory source pack from this resolved manifest.
    pub fn load_source_pack(&self) -> Result<ExplicitSourcePack, CompileError> {
        PackageLockfile::from_resolved_manifest(self)?.load_source_pack()
    }

    /// Loads a path-backed source-pack manifest from this resolved manifest.
    pub fn load_path_manifest(&self) -> Result<ExplicitSourcePackPathManifest, CompileError> {
        PackageLockfile::from_resolved_manifest(self)?.load_path_manifest()
    }
}

fn canonical_manifest_dir(
    label: &str,
    base_dir: &Path,
    path: &Path,
) -> Result<PathBuf, CompileError> {
    let resolved = resolve_manifest_path(base_dir, path);
    let canonical = fs::canonicalize(&resolved).map_err(|err| {
        package_manifest_error(format!(
            "canonicalize {label} {}: {err}",
            resolved.display()
        ))
    })?;
    if !canonical.is_dir() {
        return Err(package_manifest_error(format!(
            "{label} {} is not a directory",
            canonical.display()
        )));
    }
    validate_manifest_boundary(label, base_dir, &canonical)?;
    validate_manifest_directory_scope(label, base_dir, &canonical)?;
    Ok(canonical)
}

fn canonical_manifest_file(
    label: &str,
    base_dir: &Path,
    path: &Path,
) -> Result<PathBuf, CompileError> {
    let resolved = resolve_manifest_path(base_dir, path);
    let canonical = fs::canonicalize(&resolved).map_err(|err| {
        package_manifest_error(format!(
            "canonicalize {label} {}: {err}",
            resolved.display()
        ))
    })?;
    if !canonical.is_file() {
        return Err(package_manifest_error(format!(
            "{label} {} is not a file",
            canonical.display()
        )));
    }
    validate_manifest_boundary(label, base_dir, &canonical)?;
    Ok(canonical)
}

fn canonical_manifest_base_dir(base_dir: &Path) -> Result<PathBuf, CompileError> {
    let canonical = fs::canonicalize(base_dir).map_err(|err| {
        package_manifest_error(format!(
            "canonicalize package manifest directory {}: {err}",
            base_dir.display()
        ))
    })?;
    if !canonical.is_dir() {
        return Err(package_manifest_error(format!(
            "package manifest directory {} is not a directory",
            canonical.display()
        )));
    }
    Ok(canonical)
}

fn validate_manifest_boundary(
    label: &str,
    base_dir: &Path,
    canonical: &Path,
) -> Result<(), CompileError> {
    if canonical.starts_with(base_dir) {
        return Ok(());
    }
    Err(package_manifest_error(format!(
        "{label} {} resolves outside package manifest directory {}; package manifest paths must not escape through symlinks",
        canonical.display(),
        base_dir.display()
    )))
}

fn validate_manifest_directory_scope(
    label: &str,
    base_dir: &Path,
    canonical: &Path,
) -> Result<(), CompileError> {
    if canonical != base_dir {
        return Ok(());
    }
    Err(package_manifest_error(format!(
        "{label} {} resolves to the package manifest directory {}; \
         use a package-owned source or stdlib subdirectory instead",
        canonical.display(),
        base_dir.display()
    )))
}

fn resolve_manifest_path(base_dir: &Path, path: &Path) -> PathBuf {
    base_dir.join(path)
}

fn unsupported_manifest_import_configuration_field(source: &str) -> Option<&'static str> {
    let document = serde_json::from_str::<serde_json::Value>(source).ok()?;
    let object = document.as_object()?;
    [
        "dependencies",
        "dev_dependencies",
        "imports",
        "import_roots",
        "packages",
    ]
    .into_iter()
    .find(|field| object.contains_key(*field))
}

fn format_manifest_roots(roots: &[PathBuf]) -> String {
    roots
        .iter()
        .map(|root| root.display().to_string())
        .collect::<Vec<_>>()
        .join(", ")
}

fn validate_package_relative_path(label: &str, path: &Path) -> Result<(), CompileError> {
    if path.is_absolute() {
        return Err(package_manifest_error(format!(
            "{label} {} must be relative; package lockfiles record canonical absolute paths",
            path.display()
        )));
    }
    let has_root_or_prefix = path
        .components()
        .any(|component| matches!(component, Component::Prefix(_) | Component::RootDir));
    let raw_path = path.to_string_lossy();
    if raw_path.contains('\\') {
        return Err(package_manifest_error(format!(
            "{label} {} must use '/' separators; package manifests do not accept backslash path separators",
            path.display()
        )));
    }
    if raw_path.contains(':') {
        return Err(package_manifest_error(format!(
            "{label} {} must not contain ':'; package manifests use portable package-relative paths and do not accept drive prefixes or URI schemes",
            path.display()
        )));
    }
    let has_unnormalized_component = raw_path
        .split(['/', '\\'])
        .any(|component| component.is_empty() || component == "." || component == "..");
    if has_root_or_prefix || has_unnormalized_component {
        return Err(package_manifest_error(format!(
            "{label} {} must be a normalized package-relative path without prefix, root, current-directory, or parent-directory components",
            path.display()
        )));
    }
    Ok(())
}

/// Returns whether a package name follows manifest package-name rules.
pub(super) fn valid_package_name(name: &str) -> bool {
    !name.is_empty()
        && name.split('.').all(|segment| {
            !segment.is_empty()
                && segment
                    .bytes()
                    .next()
                    .is_some_and(|byte| byte.is_ascii_alphanumeric())
                && segment
                    .bytes()
                    .last()
                    .is_some_and(|byte| byte.is_ascii_alphanumeric())
                && segment
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
        })
}

/// Returns whether two resolved filesystem paths overlap.
pub(super) fn resolved_paths_overlap(left: &Path, right: &Path) -> bool {
    left.starts_with(right) || right.starts_with(left)
}

/// Returns whether a path names a `.lani` source file.
pub(super) fn is_lani_source_path(path: &Path) -> bool {
    path.extension().and_then(|extension| extension.to_str()) == Some("lani")
}

/// Converts a source-root-relative file path into a module path string.
pub(super) fn package_source_root_relative_module_path_with_label(
    label: &str,
    relative_path: &Path,
) -> Result<String, String> {
    let mut path_without_extension = relative_path.to_path_buf();
    path_without_extension.set_extension("");

    let mut segments = Vec::new();
    for component in path_without_extension.components() {
        let Component::Normal(segment) = component else {
            return Err(format!(
                "{label} {} must be a normalized source-root relative path",
                relative_path.display()
            ));
        };
        let Some(segment) = segment.to_str() else {
            return Err(format!(
                "{label} {} must use UTF-8 module path segments",
                relative_path.display()
            ));
        };
        if !valid_package_module_ident_segment(segment) {
            return Err(format!(
                "{label} {} maps to invalid module path segment {:?}",
                relative_path.display(),
                segment
            ));
        }
        if is_package_module_reserved_segment(segment) {
            return Err(format!(
                "{label} {} maps to reserved keyword module path segment {:?}; module paths require identifier tokens",
                relative_path.display(),
                segment
            ));
        }
        segments.push(segment.to_string());
        if segments.len() > PACKAGE_MODULE_PATH_SEGMENT_LIMIT {
            return Err(format!(
                "{label} {} maps to a module path with more than {PACKAGE_MODULE_PATH_SEGMENT_LIMIT} segments; current resolver supports at most {PACKAGE_MODULE_PATH_SEGMENT_LIMIT} path segments",
                relative_path.display()
            ));
        }
    }

    if segments.is_empty() {
        return Err(format!(
            "{label} {} does not map to a module path",
            relative_path.display()
        ));
    }

    Ok(segments.join("::"))
}

/// Returns whether a segment is a valid package-derived module path segment.
pub(super) fn valid_package_module_path_segment(segment: &str) -> bool {
    valid_package_module_ident_segment(segment) && !is_package_module_reserved_segment(segment)
}

/// Returns whether a segment is syntactically valid as a module identifier.
pub(super) fn valid_package_module_ident_segment(segment: &str) -> bool {
    let Some(first) = segment.bytes().next() else {
        return false;
    };
    is_package_module_ident_start(first)
        && segment
            .bytes()
            .skip(1)
            .all(is_package_module_ident_continue)
}

/// Returns whether a package-derived module segment is reserved by the language.
pub(super) fn is_package_module_reserved_segment(segment: &str) -> bool {
    matches!(
        segment,
        "break"
            | "const"
            | "continue"
            | "else"
            | "enum"
            | "extern"
            | "false"
            | "fn"
            | "for"
            | "if"
            | "impl"
            | "import"
            | "in"
            | "let"
            | "match"
            | "module"
            | "pub"
            | "return"
            | "self"
            | "struct"
            | "trait"
            | "true"
            | "type"
            | "where"
            | "while"
    )
}

fn is_package_module_ident_start(byte: u8) -> bool {
    byte == b'_' || byte.is_ascii_alphabetic()
}

fn is_package_module_ident_continue(byte: u8) -> bool {
    is_package_module_ident_start(byte) || byte.is_ascii_digit()
}

fn validate_package_entry_source_path(label: &str, path: &Path) -> Result<(), CompileError> {
    if is_lani_source_path(path) {
        return Ok(());
    }
    Err(package_manifest_error(format!(
        "{label} {} must use the .lani source file extension",
        path.display()
    )))
}

fn package_manifest_error(message: impl Into<String>) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0053", "package manifest invalid")
            .with_note(message)
            .with_note(
                "package manifests must declare a package name, source roots, and a .lani entry file using normalized package-relative paths",
            ),
    )
}

fn package_manifest_read_error(path: &Path, err: std::io::Error) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0054", "package manifest could not be read")
            .with_note(format!("path: {}", path.display()))
            .with_note(format!("I/O error: {err}"))
            .with_note("pass a readable package manifest JSON file"),
    )
}
