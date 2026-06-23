use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use super::{
    PACKAGE_LOCKFILE_DIGEST_ALGORITHM,
    package_lockfile_error,
    stable_content_digest,
    valid_lockfile_label,
    valid_stable_content_digest,
    validate_resolved_path,
};
use crate::compiler::CompileError;

const RESERVED_ARTIFACT_EVIDENCE_LABELS: &[&str] = &[
    "library-interface",
    "codegen-object",
    "link",
    "linked-output",
    "partial-link",
    "link-record",
    "interface-symbol",
    "object-section",
    "object-symbol",
    "unresolved-symbol",
    "relocation",
    "export-symbol",
    "runtime-service",
    "runtime-abi",
    "module",
    "import",
    "semantic",
    "semantics",
];

/// Optional produced-artifact identity metadata. Paths and hashes are
/// control-plane reproducibility evidence; each produced path has one
/// unambiguous identity, and semantic module identity remains owned by
/// parsed module/import records.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PackageLockfileArtifact {
    pub target: String,
    pub kind: String,
    pub path: PathBuf,
    pub byte_len: usize,
    pub digest: String,
}

/// Sorted artifact evidence section in a package lockfile.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct PackageLockfileArtifacts {
    /// Stable digest algorithm used for every artifact file entry.
    pub(super) digest_algorithm: String,
    /// Produced artifact files sorted by target, kind, and canonical path.
    pub(super) files: Vec<PackageLockfileArtifact>,
}

impl PackageLockfileArtifact {
    /// Creates artifact evidence from an existing produced file.
    ///
    /// The file path is canonicalized and the digest is computed from the file
    /// bytes before the artifact identity is validated.
    pub fn from_existing_file(
        target: impl Into<String>,
        kind: impl Into<String>,
        path: impl AsRef<Path>,
    ) -> Result<Self, CompileError> {
        let path = path.as_ref();
        let canonical_path = fs::canonicalize(path).map_err(|err| {
            package_lockfile_error(format!(
                "canonicalize artifact file {}: {err}",
                path.display()
            ))
        })?;
        let bytes = fs::read(&canonical_path).map_err(|err| {
            package_lockfile_error(format!(
                "read artifact file {}: {err}",
                canonical_path.display()
            ))
        })?;
        let artifact = Self {
            target: target.into(),
            kind: kind.into(),
            path: canonical_path,
            byte_len: bytes.len(),
            digest: stable_content_digest(&bytes),
        };
        artifact.validate_shape()?;
        Ok(artifact)
    }

    fn validate_shape(&self) -> Result<(), CompileError> {
        if !valid_lockfile_label(&self.target) {
            return Err(package_lockfile_error(format!(
                "artifact target {:?} must start and end with an ASCII letter or digit and contain only ASCII letters, digits, '.', '_', '-' or ':'",
                self.target
            )));
        }
        validate_artifact_evidence_label("target", &self.target)?;
        if !valid_lockfile_label(&self.kind) {
            return Err(package_lockfile_error(format!(
                "artifact kind {:?} must start and end with an ASCII letter or digit and contain only ASCII letters, digits, '.', '_', '-' or ':'",
                self.kind
            )));
        }
        validate_artifact_evidence_label("kind", &self.kind)?;
        validate_resolved_path("artifact file", &self.path)?;
        if self.byte_len == 0 {
            return Err(package_lockfile_error(format!(
                "artifact file {} byte length must be greater than zero; produced artifact identities must point at concrete artifact bytes",
                self.path.display()
            )));
        }
        if !valid_stable_content_digest(&self.digest) {
            return Err(package_lockfile_error(format!(
                "artifact file {} has invalid digest {:?}",
                self.path.display(),
                self.digest
            )));
        }
        Ok(())
    }
}

fn validate_artifact_evidence_label(label: &str, value: &str) -> Result<(), CompileError> {
    if RESERVED_ARTIFACT_EVIDENCE_LABELS.contains(&value) {
        return Err(package_lockfile_error(format!(
            "artifact {label} {value:?} is reserved for compiler module, import, semantic, or link evidence; package lockfile artifacts are control-plane path/digest metadata only"
        )));
    }
    Ok(())
}

impl PackageLockfileArtifacts {
    /// Builds the optional lockfile artifact section from produced file entries.
    ///
    /// Empty input omits the section. Non-empty input is sorted into canonical
    /// lockfile order before validation.
    pub(super) fn from_files(
        mut files: Vec<PackageLockfileArtifact>,
    ) -> Result<Option<Self>, CompileError> {
        if files.is_empty() {
            return Ok(None);
        }
        files.sort_by(compare_artifact_identity);
        let artifacts = Self {
            digest_algorithm: PACKAGE_LOCKFILE_DIGEST_ALGORITHM.to_string(),
            files,
        };
        artifacts.validate_shape()?;
        Ok(Some(artifacts))
    }

    /// Validates the artifact evidence section shape and canonical ordering.
    ///
    /// Every artifact path and identity must be unique, and entries must already
    /// be sorted by target, kind, and canonical path.
    pub(super) fn validate_shape(&self) -> Result<(), CompileError> {
        if self.digest_algorithm != PACKAGE_LOCKFILE_DIGEST_ALGORITHM {
            return Err(package_lockfile_error(format!(
                "unsupported artifact digest algorithm {:?}; expected {PACKAGE_LOCKFILE_DIGEST_ALGORITHM:?}",
                self.digest_algorithm
            )));
        }
        if self.files.is_empty() {
            return Err(package_lockfile_error(
                "artifact identity must declare at least one produced file",
            ));
        }
        let mut seen_identities = BTreeSet::new();
        let mut seen_paths = BTreeSet::new();
        let mut previous_artifact: Option<&PackageLockfileArtifact> = None;
        for artifact in &self.files {
            artifact.validate_shape()?;
            if let Some(previous_artifact) = previous_artifact {
                if compare_artifact_identity(previous_artifact, artifact).is_gt() {
                    return Err(package_lockfile_error(format!(
                        "artifact identity files must be sorted by target, kind, and canonical path; artifact {} kind {} path {} appears after artifact {} kind {} path {}; regenerate the package lockfile",
                        artifact.target,
                        artifact.kind,
                        artifact.path.display(),
                        previous_artifact.target,
                        previous_artifact.kind,
                        previous_artifact.path.display()
                    )));
                }
            }
            previous_artifact = Some(artifact);
            if !seen_paths.insert(artifact.path.clone()) {
                return Err(package_lockfile_error(format!(
                    "duplicate artifact path {}; produced artifact paths must be unique across targets and kinds",
                    artifact.path.display()
                )));
            }
            if !seen_identities.insert((
                artifact.target.clone(),
                artifact.kind.clone(),
                artifact.path.clone(),
            )) {
                return Err(package_lockfile_error(format!(
                    "duplicate artifact file for target {} kind {} {}",
                    artifact.target,
                    artifact.kind,
                    artifact.path.display()
                )));
            }
        }
        Ok(())
    }
}

fn compare_artifact_identity(
    left: &PackageLockfileArtifact,
    right: &PackageLockfileArtifact,
) -> std::cmp::Ordering {
    left.target
        .cmp(&right.target)
        .then_with(|| left.kind.cmp(&right.kind))
        .then_with(|| left.path.cmp(&right.path))
}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        path::{Path, PathBuf},
        sync::atomic::{AtomicU64, Ordering},
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::{
        super::{
            PACKAGE_LOCKFILE_COMPILER_VERSION,
            PACKAGE_LOCKFILE_LANGUAGE_EDITION,
            PACKAGE_LOCKFILE_VERSION,
            PackageLockfile,
        },
        *,
    };

    static TEMP_DIR_COUNTER: AtomicU64 = AtomicU64::new(0);

    struct TempPackageRoot {
        path: PathBuf,
    }

    impl TempPackageRoot {
        fn new(stem: &str) -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system time should be after unix epoch")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "laniusc_package_lock_{stem}_{}_{}_{}",
                std::process::id(),
                TEMP_DIR_COUNTER.fetch_add(1, Ordering::Relaxed),
                nonce
            ));
            fs::create_dir_all(&path).expect("create package lock test root");
            Self { path }
        }

        fn path(&self) -> &Path {
            &self.path
        }
    }

    impl Drop for TempPackageRoot {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    #[test]
    fn package_lockfile_rejects_artifact_evidence_labels_on_target_and_kind() {
        let root = TempPackageRoot::new("artifact_evidence_labels");
        let artifact_root = root.path().join("target");
        fs::create_dir_all(&artifact_root).expect("create package artifact root");
        let artifact_path = artifact_root.join("app.wasm");
        fs::write(&artifact_path, b"\0asm\x01\0\0\0app").expect("write package artifact");

        let err = PackageLockfileArtifact::from_existing_file(
            "linked-output",
            "final-output",
            &artifact_path,
        )
        .expect_err("artifact target labels must not claim linked-output evidence");
        let message = format!("{err:?}");
        assert!(
            message.contains("artifact target")
                && message.contains("linked-output")
                && message.contains("control-plane path/digest metadata"),
            "expected reserved artifact target label error, got {message}"
        );

        let err = PackageLockfileArtifact::from_existing_file(
            "wasm32-unknown-unknown",
            "partial-link",
            &artifact_path,
        )
        .expect_err("artifact kind labels must not claim partial-link evidence");
        let message = format!("{err:?}");
        assert!(
            message.contains("artifact kind")
                && message.contains("partial-link")
                && message.contains("control-plane path/digest metadata"),
            "expected reserved artifact kind label error, got {message}"
        );
    }

    #[test]
    fn package_lockfile_serializes_artifacts_in_canonical_identity_order() {
        let root = TempPackageRoot::new("artifact_order_serialize");
        let lockfile = lockfile_with_out_of_order_artifacts(root.path());

        let document =
            serde_json::to_value(&lockfile).expect("serialize lockfile with artifact identities");
        let artifact_files = document
            .get("artifacts")
            .and_then(|artifacts| artifacts.get("files"))
            .and_then(serde_json::Value::as_array)
            .expect("serialized lockfile should include artifact identity files");
        let artifact_kinds = artifact_files
            .iter()
            .map(|artifact| artifact.get("kind").and_then(serde_json::Value::as_str))
            .collect::<Vec<_>>();
        assert_eq!(
            artifact_kinds,
            vec![Some("a-final"), Some("z-final")],
            "public package lockfile serialization should canonicalize artifact identity order"
        );

        let roundtrip = serde_json::from_value::<PackageLockfile>(document)
            .expect("canonically serialized artifact identities should deserialize");
        assert_eq!(
            roundtrip
                .artifacts
                .iter()
                .map(|artifact| artifact.kind.as_str())
                .collect::<Vec<_>>(),
            vec!["a-final", "z-final"],
            "parsed package lockfiles should retain canonical artifact identity order"
        );
    }

    #[test]
    fn package_lockfile_rejects_persisted_artifacts_outside_canonical_identity_order() {
        let root = TempPackageRoot::new("artifact_order_parse");
        let lockfile = lockfile_with_out_of_order_artifacts(root.path());

        let mut document =
            serde_json::to_value(&lockfile).expect("serialize lockfile with artifact identities");
        let artifact_files = document
            .get_mut("artifacts")
            .and_then(|artifacts| artifacts.get_mut("files"))
            .and_then(serde_json::Value::as_array_mut)
            .expect("serialized lockfile should include mutable artifact identity files");
        assert_eq!(
            artifact_files
                .iter()
                .map(|artifact| artifact.get("kind").and_then(serde_json::Value::as_str))
                .collect::<Vec<_>>(),
            vec![Some("a-final"), Some("z-final")],
            "fixture should start from canonical artifact order"
        );
        artifact_files.swap(0, 1);

        let tampered_lockfile =
            serde_json::to_string_pretty(&document).expect("serialize tampered package lockfile");
        let err = PackageLockfile::parse_json(&tampered_lockfile)
            .expect_err("persisted artifact identities must already be canonical");
        let message = format!("{err:?}");
        assert!(
            message.contains("artifact identity files must be sorted")
                && message.contains("target")
                && message.contains("kind")
                && message.contains("canonical path"),
            "expected canonical artifact order error, got {message}"
        );
    }

    #[test]
    fn package_lockfile_write_rejects_self_recorded_artifact_output() {
        let root = TempPackageRoot::new("artifact_control_plane_output");
        let mut lockfile = lockfile_with_out_of_order_artifacts(root.path());
        lockfile.artifacts.clear();

        let lockfile_path = root.path().join("target").join("lanius.lock.json");
        let previous_lockfile_bytes = b"{\"previous\":true}";
        fs::write(&lockfile_path, previous_lockfile_bytes).expect("write previous lockfile bytes");
        lockfile.artifacts.push(
            PackageLockfileArtifact::from_existing_file(
                "wasm32-unknown-unknown",
                "final-output",
                &lockfile_path,
            )
            .expect("record previous lockfile bytes as an artifact identity"),
        );

        let err = lockfile
            .write_json_file(&lockfile_path)
            .expect_err("lockfile writes must reject self-recorded artifact paths");
        let message = format!("{err:?}");
        assert!(
            message.contains("lockfile output path") && message.contains("produced artifact"),
            "expected lockfile/artifact boundary error, got {message}"
        );
        assert_eq!(
            fs::read(&lockfile_path).expect("read previous lockfile bytes"),
            previous_lockfile_bytes,
            "rejected lockfile write must not overwrite the previous control-plane file"
        );
    }

    fn lockfile_with_out_of_order_artifacts(root: &Path) -> PackageLockfile {
        let source_root = root.join("src");
        let app_root = source_root.join("app");
        fs::create_dir_all(&app_root).expect("create package app source root");
        let entry_path = app_root.join("main.lani");
        fs::write(
            &entry_path,
            r#"
module app::main;

fn main() {
    return 0;
}
"#,
        )
        .expect("write package entry source");

        let artifact_root = root.join("target");
        fs::create_dir_all(&artifact_root).expect("create package artifact root");
        let alpha_artifact_path = artifact_root.join("alpha.wasm");
        let zeta_artifact_path = artifact_root.join("zeta.wasm");
        fs::write(&alpha_artifact_path, b"\0asm\x01\0\0\0alpha")
            .expect("write alpha package artifact");
        fs::write(&zeta_artifact_path, b"\0asm\x01\0\0\0zeta")
            .expect("write zeta package artifact");

        PackageLockfile {
            version: PACKAGE_LOCKFILE_VERSION,
            package: "artifact-order".to_string(),
            language_edition: PACKAGE_LOCKFILE_LANGUAGE_EDITION.to_string(),
            compiler_version: PACKAGE_LOCKFILE_COMPILER_VERSION.to_string(),
            roots: vec![fs::canonicalize(&source_root).expect("canonicalize source root")],
            stdlib_root: None,
            entry: fs::canonicalize(&entry_path).expect("canonicalize package entry"),
            artifacts: vec![
                PackageLockfileArtifact::from_existing_file(
                    "wasm32-unknown-unknown",
                    "z-final",
                    &zeta_artifact_path,
                )
                .expect("record zeta artifact identity"),
                PackageLockfileArtifact::from_existing_file(
                    "wasm32-unknown-unknown",
                    "a-final",
                    &alpha_artifact_path,
                )
                .expect("record alpha artifact identity"),
            ],
            replay_integrity: None,
        }
    }
}
