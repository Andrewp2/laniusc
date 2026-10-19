// src/compiler/gpu_compiler/x86_codegen.rs

use super::*;

impl<'gpu> GpuCompiler<'gpu> {
    /// Returns the initialized x86 linker or its deferred initialization error.
    pub(super) fn x86_linker(&self) -> Result<&x86::GpuX86Linker, &str> {
        self.x86_linker.as_deref().map_err(String::as_str)
    }

    /// Compile one in-memory source string through the x86_64 backend using
    /// `<source>` as the diagnostic path.
    pub async fn compile_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu(src)?;
        self.compile_expanded_source_to_x86_64_with_diagnostic_path(&src, PathBuf::from("<source>"))
            .await
    }
    /// Read a source file from disk and compile it through the x86_64 backend
    /// with diagnostics labeled by that path.
    pub async fn compile_source_to_x86_64_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let path = path.as_ref();
        let src = prepare_source_for_gpu_from_path(path)?;
        self.compile_expanded_source_to_x86_64_with_diagnostic_path(&src, path.to_path_buf())
            .await
    }
    /// Compile an in-memory source pack through the x86_64 backend after
    /// bounded codegen-unit validation.
    pub async fn compile_source_pack_to_x86_64<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_source_pack_to_x86_64_with_paths(sources, None)
            .await
    }

    async fn compile_source_pack_to_x86_64_with_paths<S: AsRef<str>>(
        &self,
        sources: &[S],
        source_paths: Option<&[Option<PathBuf>]>,
    ) -> Result<Vec<u8>, CompileError> {
        if sources.is_empty() {
            return Err(x86_empty_source_pack_compile_error());
        }
        validate_in_memory_source_pack_fits_codegen_unit(
            "compile source pack to x86_64",
            sources,
            self.resident_source_unit_limits(),
        )?;
        self.compile_x86_source_pack_with_specialization(sources, source_paths)
            .await
    }

    /// Compile an explicit in-memory source-pack manifest through the x86_64
    /// backend and preserve manifest source paths for diagnostics.
    pub async fn compile_source_pack_manifest_to_x86_64(
        &self,
        source_pack: &ExplicitSourcePack,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_source_pack_to_x86_64_with_paths(
            &source_pack.sources,
            Some(&source_pack.source_paths),
        )
        .await
    }
    /// Compiles prepared source text to x86_64 output using a synthetic path.
    pub(in crate::compiler) async fn compile_expanded_source_to_x86_64(
        &self,
        src: &str,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_expanded_source_to_x86_64_with_diagnostic_path(src, PathBuf::from("<source>"))
            .await
    }

    pub(in crate::compiler) async fn compile_expanded_source_to_x86_64_with_diagnostic_path(
        &self,
        src: &str,
        diagnostic_path: PathBuf,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_x86_source_pack_with_specialization(&[src], Some(&[Some(diagnostic_path)]))
            .await
    }

    pub(super) async fn compile_x86_source_pack_with_specialization<S: AsRef<str>>(
        &self,
        sources: &[S],
        source_paths: Option<&[Option<PathBuf>]>,
    ) -> Result<Vec<u8>, CompileError> {
        let pending = self.compile_x86_source_pack_auto(sources, source_paths).await?;
        let objects = self.specialize_pending_x86_source_pack_objects(vec![pending]).await?;
        let first_source = sources.first().map(|source| {
            let path = source_paths.and_then(|paths| paths.first()).and_then(Option::as_deref);
            (source.as_ref(), path)
        });
        let input_span = crate::gpu::trace::HostSpan::new("host.compiler", "codegen.x86.link.input");
        let input = x86::GpuX86LinkInput::for_executable_refs(objects.iter())
            .map_err(|error| x86_link_input_error(error, first_source))?;
        drop(input_span);
        let linker = self
            .x86_linker()
            .map_err(|reason| CompileError::GpuCodegen(reason.to_owned()))?;
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        linker
            .link_executable(&self.gpu.device, &self.gpu.queue, &input)
            .map_err(|error| x86_source_pack_link_error("link native generic source pack", error))
    }
}

pub(super) fn x86_empty_source_pack_compile_error() -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0017", "missing main entrypoint")
            .with_primary_label(DiagnosticLabel::primary(
                PathBuf::from("<source pack>"),
                1,
                1,
                1,
                None,
                "the source pack is empty; the native x86 backend has no entrypoint",
            ))
            .with_note("x86 source packs must contain at least one source file before native entry selection can run"),
    )
}

/// Maps a link-input error. When no object defines `main` this is the
/// missing-main diagnostic, anchored at the start of the first source when its
/// text is at hand. Any other link-input error is a source-pack artifact
/// failure.
pub(super) fn x86_link_input_error(
    error: String,
    first_source: Option<(&str, Option<&Path>)>,
) -> CompileError {
    if error != x86::X86_LINK_NO_ENTRY_OBJECT {
        return source_pack_artifact_store_error(error);
    }
    let (path, source_line) = match first_source {
        Some((text, path)) => (
            path.map_or_else(|| PathBuf::from("<source>"), Path::to_path_buf),
            text.lines().next().map(str::to_owned),
        ),
        None => (PathBuf::from("<source pack>"), None),
    };
    CompileError::Diagnostic(
        Diagnostic::error("LNC0017", "missing main entrypoint")
            .with_primary_label(DiagnosticLabel::primary(
                path,
                1,
                1,
                1,
                source_line,
                "no function named `main` is defined; the native x86 backend has no entrypoint",
            ))
            .with_help("define `fn main()` or `fn main() -> i32` as the program entry"),
    )
}

pub(super) fn x86_source_pack_link_error(context: &str, error: anyhow::Error) -> CompileError {
    if let Some(missing) = error.downcast_ref::<x86::GpuX86MissingSymbolDefinition>() {
        return CompileError::Diagnostic(
            Diagnostic::error("LNC0017", "referenced function has no native definition")
                .with_primary_label(DiagnosticLabel::primary(
                    PathBuf::from("<source pack link>"), 1, 1, 1, None,
                    "a referenced function has no executable native body",
                ))
                .with_note(missing.to_string())
                .with_help("provide an executable native definition; imported generic payload bodies require concrete specialization support"),
        );
    }
    source_pack_artifact_store_error(format!("{context}: {error}"))
}

#[cfg(test)]
mod tests {
    use super::{super::typecheck::CompiledSourcePackObject, *};

    #[test]
    fn checked_nominal_recipes_retain_private_public_payloads_without_calls_or_predicates() {
        use crate::type_checker::{
            CheckedBinderIdentity as Binder,
            CheckedGenericApplicationArgument as Argument,
            CheckedGenericConstantValue as Constant,
            CheckedGenericType as Type,
            CheckedNominalIdentity as Identity,
            CheckedNominalRecipeKind as Kind,
            CheckedParameterDomain as Domain,
        };
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let source = r#"
module checkpoint::nominal_recipes;
type Items<T, const N:usize> = [T;N];
pub struct Visible<T, const N:usize, U> {
    values:Items<T,N>, borrowed:&[T;N], view:[U], flag:bool
}
struct Hidden<T, const N:usize, U> { value:Visible<T,N,U>, tail:[T;N] }
pub enum State<T, const N:usize, U> { Absent, Data([T;N], &T, [U]) }
enum HiddenState { Quiet, HiddenData(i32, bool) }
struct Empty {}
enum Never {}
struct Leaf { code:i32 }
fn main()->i32 { let literal:Leaf = Leaf { code:0 }; return 0; }
"#;
        let unit = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.to_owned()].into(), 43, 17, Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        )).expect("retain all original nominal recipes without calls or predicates");
        assert!(unit.generic_calls.is_empty());
        let contracts = unit.checked_contracts.as_ref();
        assert!(contracts.predicates.is_empty());
        assert!(contracts.implementations.is_empty());
        assert_eq!(contracts.source_unit, Some([43, 17]));
        assert_eq!(contracts.nominal_recipes.len(), 7,
            "aliases and struct literal fields do not create declaration recipes");
        let declaration = |name: &[u8]| unit.interface.declarations.iter().position(|row| {
            let start = row.name_byte_start as usize;
            &unit.interface.name_bytes[start..start + row.name_byte_len as usize] == name
        }).expect("exported declaration") as u32;
        let public_recipe = |name: &[u8]| contracts.nominal_recipes.iter().find(|recipe| {
            recipe.identity == Identity::Public([43, 17, declaration(name)])
        }).expect("recipe retains the actual exported nominal identity");
        let mut owners = std::collections::BTreeSet::new();
        for recipe in &contracts.nominal_recipes {
            let owner = &contracts.binders[recipe.owner as usize];
            assert_eq!(owner.source_hir, recipe.source_hir);
            assert!(owner.callable.is_none());
            assert!(owners.insert(recipe.owner), "each nominal owns one binder");
            match recipe.identity {
                Identity::Public([library, unit, declaration]) => {
                    assert_eq!([library, unit], [43, 17]);
                    assert_eq!(owner.binder, Binder::Public { owner: declaration, scope: 0 });
                }
                Identity::SourceLocal { unit, declaration_token } => {
                    assert_eq!(unit, [43, 17]);
                    assert_ne!(declaration_token, u32::MAX);
                    assert!(matches!(owner.binder, Binder::SourceLocal { .. }));
                }
            }
            for parameter in &owner.parameters {
                assert_eq!(parameter.identity.unit, [43, 17]);
                assert_eq!(parameter.identity.binder, owner.binder);
            }
        }
        let check_parameters = |owner: u32| {
            let parameters = &contracts.binders[owner as usize].parameters;
            assert_eq!(parameters.len(), 3);
            assert_eq!(parameters.iter().map(|p| (
                p.identity.source_ordinal, p.identity.domain, p.binding_slot,
            )).collect::<Vec<_>>(), vec![
                (0, Domain::Type, 0), (1, Domain::Constant, 0), (2, Domain::Type, 1),
            ], "ordered source parameters retain independent binding domains");
            [parameters[0], parameters[1], parameters[2]]
        };
        let check_array = |ty: &Type, element, length| {
            let Type::Array { element: actual, length: count, .. } = ty else {
                panic!("expected normalized array recipe, got {ty:?}");
            };
            assert_eq!(actual.as_ref(), &Type::Parameter(element));
            assert_eq!(*count, Constant::Parameter(length));
        };
        let visible = public_recipe(b"Visible");
        assert_eq!(visible.kind, Kind::Record);
        let [t, n, u] = check_parameters(visible.owner);
        assert_eq!(visible.groups.len(), 1);
        assert_eq!(visible.groups[0].len(), 4);
        check_array(&visible.groups[0][0], t, n);
        let Type::Reference(referent) = &visible.groups[0][1] else {
            panic!("reference field preserves the array referent");
        };
        check_array(referent, t, n);
        assert_eq!(visible.groups[0][2], Type::Slice(Box::new(Type::Parameter(u))));
        assert_eq!(visible.groups[0][3], Type::Scalar(2));

        let hidden = contracts.nominal_recipes.iter().find(|recipe| {
            recipe.kind == Kind::Record
                && matches!(recipe.identity, Identity::SourceLocal { .. })
                && contracts.binders[recipe.owner as usize].parameters.len() == 3
        }).expect("private generic record recipe");
        let [hidden_t, hidden_n, hidden_u] = check_parameters(hidden.owner);
        assert_ne!(hidden_t.identity, t.identity, "same spelling does not merge owners");
        assert_eq!(hidden.groups.len(), 1);
        assert_eq!(hidden.groups[0].len(), 2);
        let Type::Nominal { identity, arguments, .. } = &hidden.groups[0][0] else {
            panic!("nested nominal field preserves its ordered operands");
        };
        assert_eq!(*identity, visible.identity);
        assert_eq!(arguments, &vec![
            Argument::Type(Type::Parameter(hidden_t)),
            Argument::Constant(Constant::Parameter(hidden_n)),
            Argument::Type(Type::Parameter(hidden_u)),
        ]);
        check_array(&hidden.groups[0][1], hidden_t, hidden_n);

        let state = public_recipe(b"State");
        assert_eq!(state.kind, Kind::Enum);
        let [state_t, state_n, state_u] = check_parameters(state.owner);
        assert_ne!(state_t.identity, t.identity);
        assert_eq!(state.groups.iter().map(Vec::len).collect::<Vec<_>>(), vec![0, 3]);
        check_array(&state.groups[1][0], state_t, state_n);
        assert_eq!(state.groups[1][1], Type::Reference(Box::new(Type::Parameter(state_t))));
        assert_eq!(state.groups[1][2], Type::Slice(Box::new(Type::Parameter(state_u))));
        let private_enum = contracts.nominal_recipes.iter().find(|recipe| {
            recipe.kind == Kind::Enum && matches!(recipe.identity, Identity::SourceLocal { .. })
                && recipe.groups.len() == 2
        }).expect("private nongeneric enum recipe");
        assert_eq!(private_enum.groups, vec![vec![], vec![Type::Scalar(3), Type::Scalar(2)]]);
        assert!(contracts.binders[private_enum.owner as usize].parameters.is_empty());
        assert!(contracts.nominal_recipes.iter().any(|recipe| {
            recipe.kind == Kind::Record && recipe.groups == vec![Vec::<Type>::new()]
        }), "empty record retains one empty field group");
        assert!(contracts.nominal_recipes.iter().any(|recipe| {
            recipe.kind == Kind::Enum && recipe.groups.is_empty()
        }), "empty enum retains zero variant groups without an invented layout");
        assert!(contracts.nominal_recipes.iter().any(|recipe| {
            recipe.kind == Kind::Record && recipe.groups == vec![vec![Type::Scalar(3)]]
        }), "literal expression rows do not replace the Leaf declaration type");

        let retained = contracts.clone();
        let empty = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec!["module checkpoint::empty; fn main()->i32{return 0;}".to_owned()].into(),
            43, 17, Vec::new().into(), SourcePackArtifactTarget::X86_64,
        )).expect("reuse the same workspace and numeric unit identity");
        assert!(empty.checked_contracts.nominal_recipes.is_empty());
        assert_eq!(unit.checked_contracts.as_ref(), &retained,
            "all owned recipes survive source workspace reuse");
    }

    #[test]
    fn checked_nominal_recipes_replay_reuses_the_original_symbolic_snapshot() {
        use crate::type_checker::CheckedGenericType as Type;
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let source = r#"
module checkpoint::recipe_replay;
pub struct Envelope<T, const N:usize> { values:[T;N] }
enum Hidden<T> { Absent, Present(T) }
pub fn keep<T, const N:usize>(value:[T;N])->[T;N] { return value; }
fn main()->i32 { let values = keep<i32,2>([19,23]); return 0; }
"#;
        let template = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.to_owned()].into(), 44, 18, Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        )).expect("original symbolic recipe snapshot");
        assert_eq!(template.generic_calls.len(), 1);
        assert_eq!(template.checked_contracts.nominal_recipes.len(), 2);
        let retained = template.checked_contracts.as_ref().clone();
        assert!(retained.nominal_recipes.iter().flat_map(|recipe| &recipe.groups)
            .flatten().any(|ty| matches!(ty, Type::Parameter(_))),
            "the original enum payload is declaration-owned and symbolic");
        let replay = pollster::block_on(compiler.compile_body_specialization(
            &template, &template.generic_calls[0],
        )).expect("concrete body replay retains original nominal recipes");
        assert!(std::sync::Arc::ptr_eq(&replay.checked_contracts, &template.checked_contracts),
            "replay must reuse the original recipe and binder snapshot");
        assert_eq!(replay.checked_contracts.as_ref(), &retained);
        assert_eq!(replay.interface, template.interface);
    }

    #[test]
    fn checked_unit_contracts_keep_impl_subjects_and_shadowed_method_binders() {
        use crate::type_checker::CheckedGenericType as Type;
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let source = r#"
struct Cell<T> { value:T }
trait Mark {}
impl Mark for i32 {}
impl<T> Mark for Cell<T> where T:Mark {}
impl<T> Cell<T> where T:Mark {
    fn own<T>(value:T)->T { return value; }
}
fn keep<T>(value:T)->T where T:Mark { return value; }
fn main()->i32 { return 0; }
"#;
        let unit = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.to_owned()].into(),
            37,
            9,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("retain accepted implementation and callable bound subjects");
        assert!(unit.generic_calls.is_empty(), "this isolates contract retention");
        let contracts = unit.checked_contracts.as_ref();
        assert_eq!(contracts.predicates.len(), 3);
        let mut owners = std::collections::BTreeSet::new();
        for predicate in &contracts.predicates {
            let owner = &contracts.binders[predicate.owner as usize];
            let Type::Parameter(parameter) = &predicate.subject else {
                panic!("bound subject must retain its canonical declaration parameter");
            };
            assert_eq!(parameter.identity.unit, [37, 9]);
            assert_eq!(parameter.identity.binder, owner.binder);
            assert_eq!(parameter.identity.source_ordinal, 0);
            assert!(owner.parameters.contains(parameter));
            assert!(owners.insert(predicate.owner), "each source scope owns its own T");
        }
        // Method-level where clauses remain a separate unsupported feature.
        // Its own parameter still must not capture the enclosing impl subject.
        let method_owner = contracts.binders.iter().find(|owner| {
            owner.callable.is_some() && owner.enclosing_owner.is_some()
        }).expect("generic method owns its shadowing parameter");
        let impl_index = method_owner.enclosing_owner.unwrap();
        let impl_bound = contracts.predicates.iter().find(|predicate| predicate.owner == impl_index)
            .expect("the method's lexical implementation retains its own bound");
        assert_eq!(method_owner.parameters.len(), 1);
        let method_parameter = &method_owner.parameters[0];
        assert_eq!(method_parameter.identity.binder, method_owner.binder);
        let Type::Parameter(impl_parameter) = &impl_bound.subject else { unreachable!() };
        assert_ne!(method_parameter.identity, impl_parameter.identity,
            "method T must not capture the enclosing implementation's T");
        assert!(contracts.predicates.iter().any(|predicate| {
            let owner = &contracts.binders[predicate.owner as usize];
            owner.callable.is_some() && owner.enclosing_owner.is_none()
        }), "ordinary function bounds retain their existing owner contract");
    }

    #[test]
    fn generic_impl_owner_keys_use_source_tokens() {
        use crate::gpu::readback::{PagedReadback, ReadbackRegion};
        use crate::type_checker::CheckedGenericType as Type;
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let source = r#"
module checkpoint::owner_keys;
pub struct Cell<T> { value:T }
pub struct Wrap<T> { value:T }
pub trait Mark {}
pub impl Mark for i32 {}
pub impl<T> Mark for Cell<T> where T:Mark {}
pub impl<T> Mark for Wrap<T> where T:Mark {}
pub impl<T> Cell<T> {
    pub fn own<T>(&self, value:T)->T { return value; }
}
pub fn keep<T>(value:T)->T where T:Mark { return value; }
fn main()->i32 { return 0; }
"#;
        pollster::block_on(compiler.semantic_interface_for_source_pack_unit_with_dependency_pages(
            38, 10, &[source], &[],
        )).expect("export distinct named and implementation generic owners");
        let hir = compiler.parser.current_resident_hir().expect("current checked source HIR");
        let readback = PagedReadback::new(&compiler.gpu.device, "generic owner keys", 16 * 1024);
        let words = |bytes: &[u8]| bytes.chunks_exact(4)
            .map(|word| u32::from_le_bytes(word.try_into().unwrap())).collect::<Vec<_>>();
        let counts = readback.read_regions(&compiler.gpu.device, &compiler.gpu.queue, &[
            ReadbackRegion::from_buffer(&hir.count, 0, 4, "HIR count").unwrap(),
            ReadbackRegion::from_buffer(&hir.generic_param_count, 0, 4, "parameter count").unwrap(),
        ], "generic owner counts").unwrap();
        let hir_count = words(&counts[0])[0] as usize;
        let parameter_count = words(&counts[1])[0] as usize;
        let source_rows = readback.read_regions(&compiler.gpu.device, &compiler.gpu.queue, &[
            ReadbackRegion::from_buffer(&hir.core, 0, hir_count * 16, "HIR core").unwrap(),
            ReadbackRegion::from_buffer(&hir.payload, 0, hir_count * 16, "HIR payload").unwrap(),
            ReadbackRegion::from_buffer(&hir.generic_params, 0, parameter_count * 16, "parameters").unwrap(),
        ], "generic owner source rows").unwrap();
        let core = words(&source_rows[0]);
        let payload = words(&source_rows[1]);
        let parameters = words(&source_rows[2]);
        let (keys, token_capacity) = compiler.type_checker.with_semantic_interface_identity_buffers(|buffers| {
            let view = buffers.generic_param_owner_token;
            assert!((parameter_count * 4) as u64 <= view.byte_size);
            let bytes = readback.read(&compiler.gpu.device, &compiler.gpu.queue,
                view.buffer, view.byte_offset, parameter_count * 4, "accepted generic owner keys").unwrap();
            (words(&bytes), buffers.type_expr_ref_tag.byte_size / 4)
        }).expect("current interface identity tables");
        let mut trait_impl_owners = std::collections::BTreeSet::new();
        let mut source_owners = std::collections::BTreeMap::new();
        let mut disjoint_domain_case = false;
        for (parameter, actual) in parameters.chunks_exact(4).zip(keys) {
            let owner = parameter[0] as usize;
            let head = &core[owner * 4..owner * 4 + 4];
            let body = &payload[owner * 4..owner * 4 + 4];
            let expected = if head[0] == 35 { head[2] } else { body[1] };
            assert_eq!(actual, expected, "generic lookup key must identify the declaration's source token");
            if let Some(previous) = source_owners.insert(actual, owner) {
                assert_eq!(previous, owner, "unrelated source owners must not share a lookup key");
            }
            if head[0] == 35 && body[0] == 2 {
                trait_impl_owners.insert(owner);
                assert!((body[1] as u64) < token_capacity,
                    "trait-bound HIR must exercise the old token-valid fallback");
                disjoint_domain_case |= body[1] != head[2];
            }
        }
        assert_eq!(trait_impl_owners.len(), 2);
        assert!(disjoint_domain_case, "fixture must distinguish HIR indices from token anchors");
        let unit = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.to_owned()].into(), 38, 10, Vec::new().into(), SourcePackArtifactTarget::X86_64,
        )).expect("retain independent implementation and function binder contracts");
        let contracts = unit.checked_contracts.as_ref();
        assert_eq!(contracts.predicates.len(), 3);
        for predicate in &contracts.predicates {
            let owner = &contracts.binders[predicate.owner as usize];
            let Type::Parameter(parameter) = &predicate.subject else { panic!("canonical bound parameter"); };
            assert_eq!(parameter.identity.binder, owner.binder);
            assert!(owner.parameters.contains(parameter));
        }
    }

    #[test]
    fn checked_unit_contracts_preserve_zero_call_graphs_and_private_owners_after_reuse() {
        use crate::type_checker::{
            CheckedBinderIdentity,
            CheckedGenericApplicationArgument as Argument,
            CheckedGenericConstantValue as Constant,
            CheckedGenericType as Type,
            CheckedNominalIdentity,
            CheckedParameterDomain,
        };
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let source = r#"
module checkpoint::contracts;
pub struct Cell<T, const L:usize> { value:T }
pub trait Rel<A> {}
trait HiddenRel<A> {}
pub trait Visible<T> { pub fn visible(self, value:T)->T; }
trait Hidden<T> { fn hidden(self, value:T)->T; }
pub impl Visible<[i32;2]> for bool {
    pub fn visible(self, value:[i32;2])->[i32;2] { return value; }
}
impl Hidden<[bool;0]> for i32 {
    fn hidden(self, value:[bool;0])->[bool;0] { return value; }
}
pub impl Rel<&[Cell<i32,2>;2]> for Cell<[i32;2],2> {}
pub fn exposed<T,U,const N:usize>(v:T, values:[U;N])->T
    where T:Rel<Cell<[U;N],N>> { return v; }
fn private_bound<T,U,const N:usize>(v:T, values:[U;N])->T
    where T:HiddenRel<Cell<[U;N],N>> { return v; }
pub fn reference<T,U>(v:T)->T where T:Rel<&[Cell<U,2>;2]> { return v; }
pub fn view<T,U>(v:T)->T where T:Rel<[U]> { return v; }
fn main()->i32 { return 0; }
"#;
        let unit = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.to_owned()].into(),
            31,
            4,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("retain accepted contracts without generic calls");
        assert!(unit.generic_calls.is_empty());
        let contracts = unit.checked_contracts.as_ref();
        assert_eq!(contracts.source_unit, Some([31, 4]));
        assert_eq!(contracts.predicates.len(), 4);
        assert_eq!(contracts.implementations.len(), 3);
        let owner = |index: u32| {
            contracts
                .binders
                .get(index as usize)
                .expect("contract owner indexes the shared immutable owner table")
        };
        let declaration = |name: &[u8]| {
            unit.interface
                .declarations
                .iter()
                .position(|declaration| {
                    let start = declaration.name_byte_start as usize;
                    &unit.interface.name_bytes[start..start + declaration.name_byte_len as usize]
                        == name
                })
                .expect("exported declaration") as u32
        };
        let public_predicate = |name: &[u8]| {
            let owner = declaration(name);
            contracts
                .predicates
                .iter()
                .find(|predicate| {
                    predicate.public_index.is_some_and(|index| {
                        unit.interface.predicates[index as usize].owner_ref == owner
                    })
                })
                .expect("snapshot aliases the actual exported predicate row")
        };
        let exposed = public_predicate(b"exposed");
        let hidden = contracts
            .predicates
            .iter()
            .find(|predicate| predicate.public_index.is_none())
            .expect("private callable predicate is retained");
        assert_eq!(
            owner(exposed.owner).binder,
            CheckedBinderIdentity::Public {
                owner: declaration(b"exposed"),
                scope: 0,
            }
        );
        assert!(matches!(
            owner(hidden.owner).binder,
            CheckedBinderIdentity::SourceLocal { .. }
        ));
        assert_ne!(
            owner(exposed.owner).source_hir,
            owner(hidden.owner).source_hir
        );
        assert!(
            matches!(hidden.trait_identity, CheckedNominalIdentity::SourceLocal {
            unit: [31, 4], declaration_token,
        } if declaration_token != u32::MAX)
        );
        assert_eq!(
            exposed.trait_identity,
            CheckedNominalIdentity::Public([31, 4, declaration(b"Rel")])
        );
        let parameter = |ty: &Type| match ty {
            Type::Parameter(parameter) => *parameter,
            other => panic!("expected a declaration-owned parameter: {other:?}"),
        };
        for predicate in [exposed, hidden] {
            let owner = owner(predicate.owner);
            assert_eq!(owner.parameters.len(), 3);
            let parameters = &owner.parameters;
            for (index, (domain, ordinal, slot)) in [
                (CheckedParameterDomain::Type, 0, 0),
                (CheckedParameterDomain::Type, 1, 1),
                (CheckedParameterDomain::Constant, 2, 0),
            ]
            .into_iter()
            .enumerate()
            {
                let retained = parameters[index];
                assert_eq!(retained.identity.unit, [31, 4]);
                assert_eq!(retained.identity.binder, owner.binder);
                assert_eq!(retained.identity.domain, domain);
                assert_eq!(retained.identity.source_ordinal, ordinal);
                assert_eq!(retained.binding_slot, slot);
                assert_eq!(retained.constant_scalar,
                    (domain == CheckedParameterDomain::Constant).then_some(crate::primitive_types::SCALAR_USIZE));
            }
            assert_eq!(parameter(&predicate.subject), parameters[0]);
            let [
                Argument::Type(Type::Nominal {
                    identity,
                    arguments,
                    words,
                    ..
                }),
            ] = predicate.arguments.as_slice()
            else {
                panic!("complete nominal operand: {predicate:?}")
            };
            assert_eq!(
                *identity,
                CheckedNominalIdentity::Public([31, 4, declaration(b"Cell")])
            );
            assert_eq!(*words, None);
            let [
                Argument::Type(Type::Array {
                    element,
                    length,
                    words,
                }),
                Argument::Constant(value),
            ] = arguments.as_slice()
            else {
                panic!("ordered nested type/constant operands: {arguments:?}")
            };
            assert_eq!(parameter(element), parameters[1]);
            assert_eq!(*length, Constant::Parameter(parameters[2]));
            assert_eq!(*value, Constant::Parameter(parameters[2]));
            assert_eq!(*words, None);
        }
        assert_ne!(
            parameter(&exposed.subject).identity,
            parameter(&hidden.subject).identity,
            "same spelling and slots in separate binders must remain distinct"
        );
        let reference = public_predicate(b"reference");
        let [Argument::Type(Type::Reference(array))] = reference.arguments.as_slice() else {
            panic!("reference graph: {reference:?}")
        };
        let Type::Array {
            element,
            length: Constant::Literal(length_value),
            ..
        } = array.as_ref()
        else {
            panic!("reference retains array graph: {array:?}")
        };
        assert_eq!(length_value.count(), Some(2));
        let Type::Nominal {
            identity,
            arguments,
            ..
        } = element.as_ref()
        else {
            panic!("array retains nominal graph: {element:?}")
        };
        assert_eq!(
            *identity,
            CheckedNominalIdentity::Public([31, 4, declaration(b"Cell")])
        );
        assert_eq!(
            arguments,
            &vec![
                Argument::Type(Type::Parameter(owner(reference.owner).parameters[1])),
                Argument::Constant(Constant::Literal(crate::constant_value::CheckedConstantValue::from_words(
                    crate::primitive_types::SCALAR_USIZE, [2, 0]).unwrap())),
            ]
        );
        let view = public_predicate(b"view");
        assert_eq!(
            view.arguments,
            vec![Argument::Type(Type::Slice(Box::new(Type::Parameter(
                owner(view.owner).parameters[1]
            ),)))]
        );

        assert_eq!(
            unit.interface.implementations.len(),
            2,
            "private implementation is not a fabricated public interface row"
        );
        let private_impl = contracts
            .implementations
            .iter()
            .find(|implementation| implementation.public_index.is_none())
            .expect("private implementation survives the accepted-unit boundary");
        assert_eq!(private_impl.subject, Type::Scalar(3));
        assert!(
            matches!(private_impl.trait_identity, CheckedNominalIdentity::SourceLocal {
            unit: [31, 4], declaration_token,
        } if declaration_token != u32::MAX)
        );
        let [
            Argument::Type(Type::Array {
                element,
                length: Constant::Literal(length_value),
                ..
            }),
        ] = private_impl.arguments.as_slice()
        else {
            panic!("private complete graph: {private_impl:?}")
        };
        assert_eq!(length_value.count(), Some(0));
        assert_eq!(element.as_ref(), &Type::Scalar(2));
        let compound = contracts
            .implementations
            .iter()
            .find(|implementation| matches!(implementation.subject, Type::Nominal { .. }))
            .expect("compound implementation subject");
        let Type::Nominal {
            identity,
            arguments,
            ..
        } = &compound.subject
        else {
            unreachable!()
        };
        assert_eq!(
            *identity,
            CheckedNominalIdentity::Public([31, 4, declaration(b"Cell")])
        );
        assert!(matches!(arguments.as_slice(), [
            Argument::Type(Type::Array { element, length: Constant::Literal(length), .. }),
            Argument::Constant(Constant::Literal(value)),
        ] if element.as_ref() == &Type::Scalar(3) && length.words() == [crate::primitive_types::SCALAR_U32, 2, 0] &&
            value.words() == [crate::primitive_types::SCALAR_USIZE, 2, 0]));
        assert!(matches!(
            compound.arguments.as_slice(),
            [Argument::Type(Type::Reference(_))]
        ));
        let object = unit.object.clone().into_x86_64().expect("native object");
        let bindings = contracts
            .implementations
            .iter()
            .flat_map(|implementation| {
                let implementation_owner = owner(implementation.owner);
                assert!(
                    implementation_owner.parameters.is_empty(),
                    "these concrete implementations have no generic header"
                );
                if let Some(index) = implementation.public_index {
                    let exported = unit.interface.implementations[index as usize];
                    assert_eq!(
                        implementation.trait_identity,
                        CheckedNominalIdentity::Public([
                            exported.trait_library_id,
                            exported.trait_unit_id,
                            exported.trait_declaration_index,
                        ])
                    );
                    let start = exported.first_method_binding as usize;
                    let exported_bindings = &unit.interface.implementation_method_bindings
                        [start..start + exported.method_binding_count as usize];
                    assert_eq!(
                        implementation.method_bindings.len(),
                        exported_bindings.len()
                    );
                    for (binding, exported_binding) in
                        implementation.method_bindings.iter().zip(exported_bindings)
                    {
                        let member = unit.interface.members
                            [exported_binding.implementation_method_member as usize];
                        assert_eq!(
                            binding.required_symbol,
                            exported_binding.required_method_symbol
                        );
                        assert_eq!(binding.receiver_mode, member.trait_method_receiver_mode());
                        assert_eq!(binding.method_hir, member.value_hi & 0x7fff_ffff);
                    }
                }
                &implementation.method_bindings
            })
            .collect::<Vec<_>>();
        assert_eq!(bindings.len(), 2);
        for binding in bindings {
            assert_eq!(&binding.target[..2], &[31, 4]);
            assert_eq!(
                object
                    .symbols
                    .iter()
                    .filter(|symbol| {
                        symbol.section == x86::GpuX86ObjectSection::Text
                            && x86_object_symbol_identity(&object, symbol) == binding.target
                    })
                    .count(),
                1,
                "required binding names one executable callable: {binding:?}"
            );
        }
        let retained = contracts.clone();
        let empty = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec!["module checkpoint::empty; fn main()->i32{return 0;}".to_owned()].into(),
            31,
            4,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("reuse workspace with no contracts or generic calls");
        assert!(empty.generic_calls.is_empty());
        assert!(empty.checked_contracts.predicates.is_empty());
        assert!(empty.checked_contracts.implementations.is_empty());
        assert_eq!(empty.checked_contracts.binders.len(), 1);
        let empty_main = &empty.checked_contracts.binders[0];
        assert!(empty_main.parameters.is_empty());
        assert!(empty_main.enclosing_owner.is_none());
        assert!(
            empty_main.callable.is_some(),
            "main retains its executable owner"
        );
        assert!(empty.checked_call_owners.is_empty());
        assert_eq!(unit.checked_contracts.as_ref(), &retained);
        let changed = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.replace("[i32;2]", "[i32;3]")].into(),
            31,
            4,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("reuse workspace with new accepted contract graphs");
        assert!(changed.generic_calls.is_empty());
        assert_eq!(changed.checked_contracts.implementations.len(), 3);
        assert_ne!(
            changed.checked_contracts.implementations,
            retained.implementations
        );
        assert_eq!(
            unit.checked_contracts.as_ref(),
            &retained,
            "old graphs and private identities belong to their immutable source snapshot"
        );
    }

    #[test]
    fn checked_unit_contracts_keep_actual_callers_and_execute_after_workspace_reuse() {
        use crate::type_checker::{CheckedGenericTarget, CheckedGenericType as Type};
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let unit = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    r#"
module checkpoint::callers;
pub trait Mark {}
pub impl Mark for i32 {}
pub trait Visible { pub fn visible(self)->i32; }
trait Hidden { fn hidden(self)->i32; }
pub impl Visible for bool { pub fn visible(self)->i32 { return 23; } }
impl Hidden for i32 { fn hidden(self)->i32 { return self; } }
pub fn keep<T>(value:T)->T { return value; }
pub fn relay<T>(value:T)->T where T:Mark { return keep(value); }
struct Cell<T> { value:T }
impl<T> Cell<T> { fn through(&self)->T { return keep(self.value); } }
fn concrete()->i32 {
    let flag=keep(false);
    if (flag) { return 1; }
    return keep(19);
}
fn main()->i32 {
    let cell:Cell<i32> = Cell{value:23};
    if (concrete()!=19 || relay(19)!=19 || cell.through()!=23) { return 1; }
    let flag=false;
    if (flag.visible()!=23) { return 2; }
    let value=23;
    if (value.hidden()!=23) { return 3; }
    return 0;
}
"#
                    .to_owned(),
                ]
                .into(),
                32,
                5,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("retain exact callers beside accepted local contracts");
        let declaration = |name: &[u8]| {
            unit.interface
                .declarations
                .iter()
                .position(|declaration| {
                    let start = declaration.name_byte_start as usize;
                    &unit.interface.name_bytes[start..start + declaration.name_byte_len as usize]
                        == name
                })
                .expect("public callable") as u32
        };
        let contracts = unit.checked_contracts.as_ref();
        assert_eq!(contracts.source_unit, Some([32, 5]));
        let owner_for = |call_hir| {
            let owners = unit
                .checked_call_owners
                .iter()
                .filter(|owner| owner.call_hir == call_hir)
                .collect::<Vec<_>>();
            assert_eq!(
                owners.len(),
                1,
                "each retained call has one exact enclosing callable"
            );
            assert_ne!(owners[0].function_hir, u32::MAX);
            owners[0].function_hir
        };
        let keep = declaration(b"keep");
        let keep_binder = contracts.binders.iter().find(|owner| matches!(owner.binder,
            crate::type_checker::CheckedBinderIdentity::Public { owner, scope: 0 } if owner == keep
        )).expect("unbounded generic helper still owns a retained binder");
        assert_eq!(keep_binder.parameters.len(), 1);
        let calls = unit.generic_calls.iter().filter(|call| {
            matches!(call.target, CheckedGenericTarget::Local { native_symbol, .. } if native_symbol == keep)
        }).collect::<Vec<_>>();
        assert_eq!(calls.len(), 4);
        let relay = contracts
            .predicates
            .iter()
            .find(|predicate| {
                predicate.public_index.is_some_and(|index| {
                    unit.interface.predicates[index as usize].owner_ref == declaration(b"relay")
                })
            })
            .expect("generic relay's own bound");
        let relay_owner = contracts
            .binders
            .get(relay.owner as usize)
            .expect("relay predicate references the shared owner table");
        let relay_call = calls
            .iter()
            .find(|call| {
                matches!(&call.arguments[0].ty,
            Type::Parameter(parameter) if parameter.identity.binder == relay_owner.binder)
            })
            .expect("generic caller retains its own parameter");
        assert_eq!(owner_for(relay_call.call_hir), relay_owner.source_hir);
        let method_hir = unit
            .generic_calls
            .iter()
            .find_map(|call| match call.target {
                CheckedGenericTarget::Local {
                    specialization_symbol,
                    ..
                } if specialization_symbol & 0x8000_0000 != 0 => {
                    Some(specialization_symbol & 0x7fff_ffff)
                }
                _ => None,
            })
            .expect("main invokes the nongeneric method in a generic impl");
        let method_call = calls
            .iter()
            .find(|call| {
                matches!(&call.arguments[0].ty,
            Type::Parameter(parameter) if parameter.identity.binder != relay_owner.binder)
            })
            .expect("method uses its enclosing impl parameter");
        assert_eq!(
            owner_for(method_call.call_hir),
            method_hir,
            "the enclosing callable is the method, not its generic impl"
        );
        let Type::Parameter(method_parameter) = &method_call.arguments[0].ty else {
            unreachable!()
        };
        let (impl_owner_index, impl_binder) = contracts
            .binders
            .iter()
            .enumerate()
            .find(|(_, owner)| owner.binder == method_parameter.identity.binder)
            .expect("the generic impl binder survives independently of predicate rows");
        assert!(impl_binder.parameters.contains(method_parameter));
        assert_ne!(
            method_hir, impl_binder.source_hir,
            "the parameter's generic owner is distinct from the call's enclosing method"
        );
        let method_owner = contracts
            .binders
            .iter()
            .find(|owner| owner.source_hir == method_hir)
            .expect("nongeneric method retains its own lexical owner row");
        assert!(
            method_owner.parameters.is_empty(),
            "the method must not recapture its impl's generic parameters"
        );
        assert_eq!(
            method_owner.enclosing_owner,
            Some(impl_owner_index as u32),
            "method scope points to its exact generic impl in the same owner table"
        );
        assert_ne!(method_hir, relay_owner.source_hir);
        let concrete_calls = calls
            .iter()
            .filter(|call| matches!(call.arguments[0].ty, Type::Scalar(_)))
            .collect::<Vec<_>>();
        assert_eq!(concrete_calls.len(), 2);
        let concrete_owner = owner_for(concrete_calls[0].call_hir);
        assert_eq!(owner_for(concrete_calls[1].call_hir), concrete_owner);
        assert_ne!(concrete_owner, method_hir);
        assert_ne!(
            concrete_owner, relay_owner.source_hir,
            "nongeneric free caller must not inherit another function's generic owner"
        );
        let relay_symbol = declaration(b"relay");
        let main_call = unit.generic_calls.iter().find(|call| matches!(call.target,
            CheckedGenericTarget::Local { native_symbol, .. } if native_symbol == relay_symbol
        )).expect("main invokes the generic relay");
        assert_ne!(
            concrete_owner,
            owner_for(main_call.call_hir),
            "calls nested in concrete must not be attributed to main"
        );
        assert_eq!(contracts.implementations.len(), 3);
        assert_eq!(
            contracts
                .implementations
                .iter()
                .filter(|implementation| implementation.public_index.is_none())
                .count(),
            1
        );
        let retained = contracts.clone();
        let retained_call_owners = unit.checked_call_owners.to_vec();
        let overwritten =
            pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
                vec!["module checkpoint::scratch; fn main()->i32{return 7;}".to_owned()].into(),
                32,
                5,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ))
            .expect("replace frontend and lowering workspace");
        assert!(overwritten.checked_contracts.predicates.is_empty());
        assert!(overwritten.checked_contracts.implementations.is_empty());
        assert_eq!(overwritten.checked_contracts.binders.len(), 1);
        let scratch_main = &overwritten.checked_contracts.binders[0];
        assert!(scratch_main.parameters.is_empty());
        assert!(scratch_main.enclosing_owner.is_none());
        assert!(
            scratch_main.callable.is_some(),
            "main retains its executable owner"
        );
        assert!(overwritten.checked_call_owners.is_empty());
        assert_eq!(unit.checked_contracts.as_ref(), &retained);
        assert_eq!(
            unit.checked_call_owners.as_ref(),
            retained_call_owners.as_slice()
        );
        let objects = pollster::block_on(compiler.specialize_x86_source_pack_objects(&[&unit]))
            .expect("specialize local calls after accepted snapshots outlive scratch");
        let input =
            x86::GpuX86LinkInput::for_executable_refs(objects.iter().map(|object| object.as_ref()))
                .expect("prepare local contract control");
        let linked = compiler
            .x86_linker()
            .expect("x86 linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link local contract control");
        assert_x86_main_exit(&linked, "checked-unit-contracts-after-reuse", 0);
        assert_eq!(unit.checked_contracts.as_ref(), &retained);
        assert_eq!(
            unit.checked_call_owners.as_ref(),
            retained_call_owners.as_slice()
        );
    }

    #[test]
    fn checked_unit_contracts_retain_nongeneric_imported_caller_owner() {
        use crate::type_checker::CheckedGenericTarget;

        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let provider = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    r#"
module checkpoint::imported_owner;
pub fn keep<T>(value:T)->T { return value; }
pub fn ordinary(value:i32)->i32 { return value; }
"#
                    .to_owned(),
                ]
                .into(),
                33,
                6,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("compile generic and ordinary provider functions");
        let keep_declaration = provider
            .interface
            .declarations
            .iter()
            .position(|declaration| {
                let start = declaration.name_byte_start as usize;
                &provider.interface.name_bytes[start..start + declaration.name_byte_len as usize]
                    == b"keep"
            })
            .expect("public generic helper") as u32;
        let caller = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    r#"
module checkpoint::caller;
import checkpoint::imported_owner;
fn main()->i32 {
    let value = checkpoint::imported_owner::ordinary(19);
    return checkpoint::imported_owner::keep(value + 23);
}
"#
                    .to_owned(),
                ]
                .into(),
                34,
                7,
                vec![vec![provider.interface.clone()]].into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("retain a caller with no local generic declarations");
        assert_eq!(
            caller.generic_calls.len(),
            1,
            "ordinary imported calls are pruned"
        );
        let call = &caller.generic_calls[0];
        assert!(matches!(
            call.target,
            CheckedGenericTarget::Dependency { library_id: 33, unit_id: 6, declaration_index }
                if declaration_index == keep_declaration
        ));
        assert_eq!(
            caller.checked_call_owners.len(),
            1,
            "owner rows are pruned with ordinary calls after requirement resolution"
        );
        let call_owner = caller.checked_call_owners[0];
        assert_eq!(call_owner.call_hir, call.call_hir);
        let contracts = caller.checked_contracts.as_ref();
        assert_eq!(contracts.source_unit, Some([34, 7]));
        assert_eq!(contracts.binders.len(), 1);
        let owner = &contracts.binders[0];
        assert_eq!(
            owner.source_hir, call_owner.function_hir,
            "the retained call references its actual nongeneric main owner"
        );
        assert_eq!(caller.x86_call_hirs.len(), 2,
            "both imported ordinary and generic calls emit native symbols");
        assert_eq!(caller.x86_call_function_hirs.as_ref(),
            &[call_owner.function_hir, call_owner.function_hir],
            "ordinary imported call retains its exact checked caller owner");
        assert_eq!(caller.x86_call_hirs.iter().filter(|&&hir| hir == call.call_hir).count(), 1,
            "only the generic call belongs to the generic evidence inventory");
        assert!(owner.parameters.is_empty());
        assert!(owner.enclosing_owner.is_none());
        let native_symbol = owner
            .callable
            .map(|callable| callable.native_symbol)
            .expect("main owns an executable callable identity");
        let CompiledSourcePackObject::X86_64(object) = &caller.object else {
            unreachable!()
        };
        let definitions = object
            .symbols
            .iter()
            .filter(|symbol| symbol.section == x86::GpuX86ObjectSection::Text)
            .collect::<Vec<_>>();
        assert_eq!(definitions.len(), 1);
        assert_eq!(
            x86_object_symbol_identity(object, definitions[0]),
            [34, 7, native_symbol]
        );
        assert!(object.entry_offset.is_some(), "main has an executable entry wrapper");
    }

    #[test]
    fn checked_unit_contracts_retain_all_nongeneric_executable_owners() {
        use std::collections::BTreeSet;

        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let free_source = r#"
module checkpoint::owners;
pub fn exported()->i32 { return 19; }
fn private_free()->i32 { return 23; }
"#;
        let inherent_source = r#"
pub struct Cell { value:i32 }
pub impl Cell {
    pub fn public_inherent(&self)->i32 { return self.value; }
    fn private_inherent(&self)->i32 { return self.value; }
}
"#;
        let trait_source = r#"
pub trait Visible { pub fn public_trait(self)->i32; }
trait Hidden { fn private_trait(self)->i32; }
pub impl Visible for bool { pub fn public_trait(self)->i32 { return 19; } }
impl Hidden for i32 { fn private_trait(self)->i32 { return self; } }
"#;
        for (source, expected_callable_count, with_trait_contracts) in [
            (
                format!("{free_source}\n{inherent_source}\n{trait_source}"),
                6,
                true,
            ),
            (format!("{free_source}\n{inherent_source}"), 4, false),
            // `impl` itself enables predicate passes. A free-only provider
            // separately exercises retention with those producers inactive.
            (free_source.to_owned(), 2, false),
        ] {
            let unit = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
                vec![source.to_owned()].into(),
                35,
                8,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ))
            .expect("retain nongeneric definitions without calls");
            assert!(unit.generic_calls.is_empty());
            assert!(unit.checked_call_owners.is_empty());
            let contracts = unit.checked_contracts.as_ref();
            assert_eq!(contracts.source_unit, Some([35, 8]));
            assert!(
                contracts
                    .binders
                    .iter()
                    .all(|owner| owner.parameters.is_empty())
            );
            let callable_owners = contracts
                .binders
                .iter()
                .filter_map(|owner| {
                    owner
                        .callable
                        .map(|callable| (owner, callable.native_symbol))
                })
                .collect::<Vec<_>>();
            assert_eq!(
                callable_owners.len(),
                expected_callable_count,
                "retain every free and implemented method body; trait requirements have no executable owner"
            );
            let retained_symbols = callable_owners
                .iter()
                .map(|(_, symbol)| [35, 8, *symbol])
                .collect::<BTreeSet<_>>();
            assert_eq!(retained_symbols.len(), callable_owners.len());
            let CompiledSourcePackObject::X86_64(object) = &unit.object else {
                unreachable!()
            };
            assert!(object.entry_offset.is_none());
            let definitions = object
                .symbols
                .iter()
                .filter(|symbol| symbol.section == x86::GpuX86ObjectSection::Text)
                .map(|symbol| x86_object_symbol_identity(object, symbol))
                .collect::<BTreeSet<_>>();
            assert_eq!(
                retained_symbols, definitions,
                "every public or private native body has exactly its actual retained owner"
            );
            let trait_method_hirs = contracts.implementations.iter()
                .flat_map(|implementation| implementation.method_bindings.iter())
                .map(|binding| binding.method_hir)
                .collect::<BTreeSet<_>>();
            let inherent_methods = callable_owners.iter()
                .filter(|(owner, _)| owner.enclosing_owner.is_some()
                    && !trait_method_hirs.contains(&owner.source_hir))
                .collect::<Vec<_>>();
            if expected_callable_count > 2 {
                assert_eq!(inherent_methods.len(), 2,
                    "both inherent methods retain their lexical impl owner");
                let parent_index = inherent_methods[0].0.enclosing_owner.unwrap();
                assert!(inherent_methods.iter().all(|(owner, _)|
                    owner.enclosing_owner == Some(parent_index)));
                let parent = &contracts.binders[parent_index as usize];
                assert!(parent.callable.is_none());
                assert!(parent.parameters.is_empty());
                assert!(contracts.implementations.iter().all(|implementation|
                    implementation.owner != parent_index));
                let public_method = exported_inherent_method(&unit.interface, b"public_inherent");
                assert!(inherent_methods.iter().any(|(owner, symbol)|
                    owner.source_hir == (public_method.value_hi & 0x7fff_ffff)
                        && *symbol == public_method.value_hi));
                assert!(matches!(parent.binder,
                    crate::type_checker::CheckedBinderIdentity::Public { owner, scope }
                        if owner == public_method.owner_ref
                            && scope == (0xc000_0000 | parent.source_hir)),
                    "the shared non-callable parent is the exact exported inherent impl scope");
            } else {
                assert!(inherent_methods.is_empty());
            }
            if !with_trait_contracts {
                assert!(contracts.predicates.is_empty());
                assert!(contracts.implementations.is_empty());
                assert!(unit.interface.predicates.is_empty());
                assert!(unit.interface.implementations.iter().all(|implementation|
                    implementation.kind == crate::compiler::GpuSemanticInterfaceImplementationKind::Inherent as u32));
                assert_eq!(unit.interface.implementations.len(), usize::from(expected_callable_count > 2),
                    "only an exported inherent group adds an interface implementation; checked trait contracts stay empty");
                continue;
            }
            assert_eq!(contracts.implementations.len(), 2);
            assert_eq!(
                contracts
                    .implementations
                    .iter()
                    .filter(|implementation| implementation.public_index.is_none())
                    .count(),
                1,
                "the private implementation remains a source-owned contract"
            );
            for implementation in &contracts.implementations {
                assert_eq!(implementation.method_bindings.len(), 1);
                for binding in &implementation.method_bindings {
                    let owners = callable_owners
                        .iter()
                        .filter(|(owner, _)| owner.source_hir == binding.method_hir)
                        .collect::<Vec<_>>();
                    assert_eq!(owners.len(), 1);
                    assert_eq!([35, 8, owners[0].1], binding.target);
                    assert_eq!(owners[0].0.enclosing_owner, Some(implementation.owner),
                        "every nongeneric impl method retains its exact implementation parent");
                    let parent = &contracts.binders[implementation.owner as usize];
                    assert!(parent.callable.is_none());
                    assert!(parent.parameters.is_empty());
                }
            }
            let public_requirement = unit
                .interface
                .members
                .iter()
                .find(|member| {
                    member.kind
                        == crate::compiler::GpuSemanticInterfaceMemberKind::TraitMethod as u32
                })
                .expect("public required signature is retained as an interface contract");
            let requirement_hir = public_requirement.value_hi & 0x7fff_ffff;
            assert!(
                callable_owners
                    .iter()
                    .all(|(owner, _)| owner.source_hir != requirement_hir),
                "a required trait signature must not be recorded as an executable callable"
            );
        }
    }

    #[test]
    fn implementation_evidence_targets_defined_public_and_private_native_methods() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let source = include_str!(
            "../../../../../tests/fixtures/stdlib_compiler_state/implementation-evidence-export/local-evidence.lani"
        );
        let unit = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.to_owned()].into(),
            19,
            3,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("export implementation evidence alongside executable code");
        assert_eq!(unit.interface.implementation_method_bindings.len(), 2);
        let object = unit.object.clone().into_x86_64().unwrap();
        for binding in &unit.interface.implementation_method_bindings {
            let target = [
                binding.target_library_id,
                binding.target_unit_id,
                binding.target_symbol,
            ];
            assert_eq!(&target[..2], &[19, 3]);
            assert_eq!(
                object
                    .symbols
                    .iter()
                    .filter(|symbol| symbol.section == x86::GpuX86ObjectSection::Text
                        && x86_object_symbol_identity(&object, symbol) == target)
                    .count(),
                1,
                "every implementation binding names exactly one native body: {target:?}"
            );
        }
        let objects = pollster::block_on(compiler.specialize_x86_source_pack_objects(&[&unit]))
            .expect("compile generic calls using the same implementation contracts");
        let input =
            x86::GpuX86LinkInput::for_executable_refs(objects.iter().map(|object| object.as_ref()))
                .expect("prepare implementation native program");
        let linked = compiler
            .x86_linker()
            .expect("x86 linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link implementation native program");
        assert_x86_main_exit(&linked, "implementation-evidence-native-targets", 0);
    }

    #[test]
    fn gpu_projects_compiled_user_call_to_relocatable_x86_object() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let object = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    r#"
pub fn seven() -> i32 {
    return 7;
}

fn main() -> i32 {
    return seven();
}
"#
                    .to_owned(),
                ]
                .into(),
                11,
                3,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("compile relocatable x86 unit")
        .object
        .into_x86_64()
        .expect("select x86 object");
        assert_eq!(object.library_id, 11);
        assert_eq!(object.unit_id, 3);
        assert!(object.entry_offset.is_some());
        assert!(
            object.relocations.is_empty(),
            "local calls must stay position-independent"
        );
        assert!(object.symbols.iter().any(|symbol| {
            symbol.section == x86::GpuX86ObjectSection::Text
                && x86_object_symbol_identity(&object, symbol) == [11, 3, 0]
        }));
        let encoded = object.to_bytes().expect("serialize x86 object");
        assert_eq!(
            x86::GpuX86RelocatableObject::from_bytes(&encoded).unwrap(),
            object
        );
        let input =
            x86::GpuX86LinkInput::for_executable(&[object]).expect("flatten projected x86 object");
        let linked = compiler
            .x86_linker()
            .expect("x86 linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link projected x86 object");
        assert_x86_main_exit(&linked, "projected-local-call", 7);
    }

    #[test]
    fn gpu_links_graph_projected_x86_call_across_compilation_units() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let provider_source = [r#"
module core::math;

pub fn seven() -> i32 {
    return 7;
}
"#];
        let noise_interface = pollster::block_on(compiler.semantic_interface_for_source_pack(
            8,
            &["module noise::unused;\npub fn zero() -> i32 { return 0; }"],
        ))
        .expect("project unrelated semantic interface");
        let provider = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                provider_source
                    .iter()
                    .map(|source| source.to_string())
                    .collect::<Vec<_>>()
                    .into(),
                7,
                0,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("compile provider x86 unit");
        let provider_interface = provider.interface;
        let provider_object = provider.object.into_x86_64().expect("provider x86 object");
        assert_eq!(provider_object.entry_offset, None);

        let consumer_source = [r#"
module app::main;
import core::math;

fn main() -> i32 {
    return core::math::seven();
}
"#];
        let consumer_object = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                consumer_source
                    .iter()
                    .map(|source| source.to_string())
                    .collect::<Vec<_>>()
                    .into(),
                11,
                2,
                vec![vec![noise_interface], vec![provider_interface]].into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("compile consumer x86 unit against provider interface")
        .object
        .into_x86_64()
        .expect("consumer x86 object");
        assert!(consumer_object.entry_offset.is_some());
        assert_eq!(consumer_object.relocations.len(), 1);
        let relocation = &consumer_object.relocations[0];
        assert_eq!(relocation.kind, x86::GpuX86RelocationKind::CallRel32);
        assert_eq!(
            relocation.target_kind,
            x86::GpuX86RelocationTargetKind::Symbol
        );
        let undefined = &consumer_object.symbols[relocation.target_index as usize];
        assert_eq!(undefined.section, x86::GpuX86ObjectSection::Undefined);
        let definition = provider_object
            .symbols
            .iter()
            .find(|symbol| symbol.section == x86::GpuX86ObjectSection::Text)
            .expect("provider public function definition");
        assert_eq!(
            x86_object_symbol_identity(&consumer_object, undefined),
            x86_object_symbol_identity(&provider_object, definition),
            "dependency declaration identity must survive semantic and target lowering"
        );

        let input = x86::GpuX86LinkInput::for_executable(&[provider_object, consumer_object])
            .expect("flatten cross-unit x86 objects");
        let linked = compiler
            .x86_linker()
            .expect("x86 linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link cross-unit x86 objects");
        assert_x86_main_exit(&linked, "projected-cross-unit-call", 7);
    }

    #[test]
    fn retained_template_sources_recompile_after_caller_inputs_are_changed() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let definitions = r#"
module support::maybe;
// Preserve the exact UTF-8 source: λ, é.
pub enum Maybe<T> { Some(T), None }
pub fn unwrap_or<T>(value: Maybe<T>, fallback: T) -> T {
    return match (value) { Some(inner) -> inner, None -> fallback };
}
pub fn seven() -> i32 { return 7; }
"#;
        let entry = r#"
module app::main;
import support::maybe;
fn main() -> i32 { return support::maybe::seven(); }
"#;
        let mut inputs = vec![definitions.to_owned(), entry.to_owned()];
        let unit = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            inputs.clone().into(),
            11,
            3,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("compile checked sources containing a deferred generic body");

        inputs[0] = definitions.replace("return 7;", "return 99;");
        inputs[1] = "module app::main; fn main() -> i32 { return 99; }".into();
        drop(inputs);
        let retained = unit.template_sources.clone();
        assert_eq!(
            retained.as_ref(),
            &[definitions.to_owned(), entry.to_owned()]
        );

        // Another frontend job overwrites the resident lexer/parser buffers.
        // Recompiling from the retained input must still recover the same body
        // and file order, independently of those buffers and the caller's text.
        let rebuilt = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            retained,
            11,
            3,
            unit.template_dependency_pages.clone(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("recompile the retained source snapshot");
        for (label, unit) in [
            ("template-source-original", unit),
            ("template-source-rebuilt", rebuilt),
        ] {
            let object = unit.object.into_x86_64().expect("select x86 object");
            let input = x86::GpuX86LinkInput::for_executable(&[object])
                .expect("prepare retained-source object for linking");
            let linked = compiler
                .x86_linker()
                .expect("x86 linker")
                .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
                .expect("link retained-source object");
            assert_x86_main_exit(&linked, label, 7);
        }
    }

    #[test]
    fn retained_template_context_recompiles_with_original_dependency_interfaces() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let provider = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec!["module support::math; pub fn seven() -> i32 { return 7; }".into()].into(),
            7,
            0,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("compile the original dependency");
        let noise = pollster::block_on(compiler.semantic_interface_for_source_pack(
            8,
            &["module noise::unused; pub fn zero() -> i32 { return 0; }"],
        ))
        .expect("check an unrelated interface on its own dependency page");
        let mut dependencies: std::sync::Arc<[Vec<crate::compiler::GpuSemanticInterfaceArtifact>]> =
            vec![vec![noise], vec![], vec![provider.interface.clone()]].into();
        let source = r#"
module app::main;
import support::math;
pub enum Maybe<T> { Some(T), None }
pub fn unwrap_or<T>(value: Maybe<T>, fallback: T) -> T {
    return match (value) { Some(inner) -> inner, None -> fallback };
}
fn main() -> i32 { return support::math::seven(); }
"#;
        let original = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.to_owned()].into(),
            11,
            3,
            dependencies.clone(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("check and emit a unit containing a deferred body and an imported call");

        // The same canonical dependency identity now has an incompatible
        // signature. It must affect a fresh compilation, not the retained
        // context from which an earlier checked template will be instantiated.
        let changed = pollster::block_on(compiler.semantic_interface_for_source_pack(
            7,
            &["module support::math; pub fn seven() -> bool { return true; }"],
        ))
        .expect("overwrite frontend scratch and publish a changed dependency signature");
        std::sync::Arc::make_mut(&mut dependencies)[2][0] = changed;
        let error = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.to_owned()].into(),
            11,
            3,
            dependencies,
            SourcePackArtifactTarget::X86_64,
        ))
        .err()
        .expect("the changed dependency must reject the old caller");
        assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
        assert_eq!(original.template_dependency_pages.len(), 3);
        assert!(original.template_dependency_pages[1].is_empty());

        let rebuilt = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            original.template_sources.clone(),
            11,
            3,
            original.template_dependency_pages.clone(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("recompile the source with its original ordered dependency context");
        let provider_object = provider
            .object
            .into_x86_64()
            .expect("select original provider object");
        for (label, unit) in [
            ("template-context-original", original),
            ("template-context-rebuilt", rebuilt),
        ] {
            let object = unit.object.into_x86_64().expect("select consumer object");
            let input = x86::GpuX86LinkInput::for_executable_refs([&provider_object, &object])
                .expect("prepare original dependency and consumer objects");
            let linked = compiler
                .x86_linker()
                .expect("x86 linker")
                .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
                .expect("link using the original dependency identity");
            assert_x86_main_exit(&linked, label, 7);
        }
    }

    /// A cold unit's parser shape can carry more tokens than the unit has:
    /// shape headroom, or a warm shape kept after an edit shortened the file.
    /// Neither a unit's interface nor a consumer checked against it may
    /// depend on that.
    #[test]
    fn dependency_interfaces_do_not_depend_on_parser_token_headroom() {
        use std::sync::atomic::Ordering;

        use crate::{compiler::GpuSemanticInterfaceArtifact, parser::driver::TEST_WARM_SHAPE_HEADROOM};

        struct HeadroomGuard;
        impl Drop for HeadroomGuard {
            fn drop(&mut self) {
                TEST_WARM_SHAPE_HEADROOM.store(u8::MAX, Ordering::Relaxed);
            }
        }
        let _guard = HeadroomGuard;
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let mut salt = 0usize;
        let mut compile = |headroom: bool,
                           source: &str,
                           library_id: u32,
                           pages: Vec<Vec<GpuSemanticInterfaceArtifact>>| {
            TEST_WARM_SHAPE_HEADROOM.store(u8::from(headroom), Ordering::Relaxed);
            // Distinct bytes per call keep each content-keyed parser shape cold.
            salt += 1;
            let source = format!("{source}{}", "\n".repeat(salt));
            pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
                vec![source].into(),
                library_id,
                0,
                pages.into(),
                SourcePackArtifactTarget::X86_64,
            ))
        };
        fn interface_differences(
            label: &str,
            off: &GpuSemanticInterfaceArtifact,
            on: &GpuSemanticInterfaceArtifact,
        ) -> Vec<String> {
            let mut differences = Vec::new();
            macro_rules! field {
                ($($name:ident),*) => {$(
                    if off.$name != on.$name {
                        differences.push(format!(
                            "{label}.{}: headroom off {:?}\n    headroom on  {:?}",
                            stringify!($name), off.$name, on.$name,
                        ));
                    }
                )*};
            }
            field!(
                version, library_id, unit_id, modules, module_segments, declarations, types,
                type_edges, members, predicates, predicate_arguments, implementations,
                implementation_arguments, implementation_method_bindings, name_bytes
            );
            differences
        }
        let inner_source = "module lib::inner; pub struct Boxed<T> { value: T, code: i32 }";
        let outer_source = "module lib::outer; import lib::inner; pub struct Wrap<T> { child: lib::inner::Boxed<T>, marker: i32 }";
        let helper_source = "module lib::extract; import lib::inner; import lib::outer; pub fn take<T>(value: lib::outer::Wrap<T>) -> T { return value.child.value; }";
        let mut problems = Vec::new();
        let inner = [false, true].map(|headroom| {
            compile(headroom, inner_source, 10, Vec::new())
                .expect("compile inner record")
                .interface
        });
        problems.extend(interface_differences("inner", &inner[0], &inner[1]));
        let outer = [false, true].map(|headroom| {
            let pages = vec![vec![inner[usize::from(headroom)].clone()]];
            compile(headroom, outer_source, 11, pages)
                .expect("compile outer record")
                .interface
        });
        problems.extend(interface_differences("outer", &outer[0], &outer[1]));
        for dependencies in [false, true] {
            for headroom in [false, true] {
                let at = usize::from(dependencies);
                let pages = vec![vec![inner[at].clone(), outer[at].clone()]];
                if let Err(error) = compile(headroom, helper_source, 14, pages) {
                    let error = format!("{error:?}");
                    problems.push(format!(
                        "helper (dependencies compiled with headroom {dependencies}, helper with {headroom}): {}",
                        &error[..error.len().min(600)],
                    ));
                }
            }
        }
        assert!(problems.is_empty(), "{}", problems.join("\n"));
    }

    #[test]
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    fn dependency_pages_preserve_record_fields_and_generic_body_replay() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let inner = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec!["module lib::inner; pub struct Boxed<T> { value: T, code: i32 }".into()].into(),
            10,
            0,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("compile inner record");
        let outer = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec!["module lib::outer; import lib::inner; pub struct Wrap<T> { child: lib::inner::Boxed<T>, marker: i32 }".into()].into(),
            11, 0, vec![vec![inner.interface.clone()]].into(), SourcePackArtifactTarget::X86_64,
        )).expect("compile outer record");
        let helper_source = r#"
module lib::extract;
import lib::inner;
import lib::outer;
pub fn take<T>(value: lib::outer::Wrap<T>) -> T { return value.child.value; }
"#;
        let source = r#"
module app::main;
import lib::inner;
import lib::outer;
import lib::extract;
TAKE_DEFINITION
fn main() -> i32 {
    let original: lib::outer::Wrap<[i32; 2]> = Wrap {
        child: Boxed { value: [19, 23], code: 7 }, marker: 11
    };
    let extracted: [i32; 2] = TAKE_CALL(original);
    extracted[0] = -9;
    if (original.child.value[0] != 19 || original.child.code != 7 || original.marker != 11) {
        return 1;
    }
    let saved = original;
    original.child.value[1] = -3;
    original.child.code = 99;
    if (saved.child.code != 7 || saved.child.value[1] != 23 || extracted[1] != 23) {
        return 2;
    }
    return saved.child.value[0] + saved.child.value[1];
}
"#;
        for (order, records) in [
            (
                "flat",
                vec![vec![inner.interface.clone(), outer.interface.clone()]],
            ),
            (
                "inner-first",
                vec![vec![inner.interface.clone()], vec![outer.interface.clone()]],
            ),
            (
                "outer-first",
                vec![vec![outer.interface.clone()], vec![inner.interface.clone()]],
            ),
        ] {
            let helper =
                pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
                    vec![helper_source.to_owned()].into(),
                    14,
                    0,
                    records.clone().into(),
                    SourcePackArtifactTarget::X86_64,
                ))
                .unwrap_or_else(|error| panic!("{order}: compile extraction template: {error:?}"));
            let mut pages = records;
            if pages.len() == 1 {
                pages[0].push(helper.interface.clone());
            } else {
                pages.push(vec![helper.interface.clone()]);
            }
            for (mode, definition, call) in [
                (
                    "ordinary",
                    "fn take(value: lib::outer::Wrap<[i32; 2]>) -> [i32; 2] { return value.child.value; }",
                    "take",
                ),
                (
                    "local generic",
                    "fn take<T>(value: lib::outer::Wrap<T>) -> T { return value.child.value; }",
                    "take",
                ),
                ("imported generic", "", "lib::extract::take"),
            ] {
                let label = format!("{order} {mode}");
                let program = source
                    .replace("TAKE_DEFINITION", definition)
                    .replace("TAKE_CALL", call);
                let consumer =
                    pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
                        vec![program].into(),
                        12,
                        0,
                        pages.clone().into(),
                        SourcePackArtifactTarget::X86_64,
                    ))
                    .unwrap_or_else(|error| panic!("{label}: compile record fields: {error:?}"));
                let objects = pollster::block_on(
                    compiler
                        .specialize_x86_source_pack_objects(&[&inner, &outer, &helper, &consumer]),
                )
                .unwrap_or_else(|error| panic!("{label}: specialize record fields: {error:?}"));
                let input = x86::GpuX86LinkInput::for_executable_refs(
                    objects.iter().map(|object| object.as_ref()),
                )
                .expect("prepare field operation objects");
                let executable = compiler
                    .x86_linker()
                    .expect("x86 linker")
                    .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
                    .unwrap_or_else(|error| panic!("{label}: link record fields: {error:?}"));
                assert_x86_main_exit(&executable, &label, 42);
            }
            let concrete = source.replace("TAKE_DEFINITION",
                "fn take(value: lib::outer::Wrap<[i32; 2]>) -> [i32; 2] { return value.child.value; }")
                .replace("TAKE_CALL", "take");
            for (invalid, code) in [
                (
                    concrete.replace(
                        "return saved.child.value[0] + saved.child.value[1];",
                        "return saved.child.missing;",
                    ),
                    "LNC0042",
                ),
                (
                    concrete.replace("value: [19, 23]", "value: [true, false]"),
                    "LNC0006",
                ),
            ] {
                let error = pollster::block_on(
                    compiler.semantic_interface_for_source_pack_unit_with_dependency_pages(
                        12,
                        0,
                        &[invalid],
                        &pages,
                    ),
                )
                .expect_err("field names and types must reject independently of page order");
                let diagnostic = error.to_public_diagnostic();
                assert_eq!(diagnostic.code, code, "{order}: {error:?}");
                assert!(diagnostic.primary_label.is_some(), "{order}: {error:?}");
            }
        }
    }

    #[test]
    fn retained_generic_call_environments_keep_each_calls_concrete_type() {
        use crate::type_checker::{CheckedGenericTarget, CheckedGenericType};
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let definitions = r#"
module support::maybe;
pub enum Maybe<T> { Some(T), None }
pub fn is_some<T>(value: Maybe<T>) -> bool {
    return match (value) { Some(_) -> true, None -> false };
}
pub impl<T> Maybe<T> {
    pub fn is_some(&self) -> bool {
        return match (self) { Some(_) -> true, None -> false };
    }
}
pub impl Maybe<bool> {
    pub fn unwrap_or(&self, fallback: bool) -> bool {
        return match (self) { Some(value) -> value, None -> fallback };
    }
}
"#;
        let memory = std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../stdlib/core/mem.lani"),
        )
        .expect("read the actual memory intrinsic module");
        let vector = std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../stdlib/std/vec.lani"),
        )
        .expect("read the actual generic vector module");
        let provider = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![definitions.to_owned(), memory, vector].into(),
            7,
            0,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("compile a generic predicate and memory intrinsics");
        let source = r#"
module app::main;
import support::maybe;
import core::mem;
import std::vec;
fn local_is_some<T>(value: support::maybe::Maybe<T>) -> bool {
    return match (value) { support::maybe::Some(_) -> true, support::maybe::None -> false };
}
fn main() -> i32 {
    let b: support::maybe::Maybe<bool> = support::maybe::Some(false);
    let absent: support::maybe::Maybe<bool> = support::maybe::None();
    let i: support::maybe::Maybe<i32> = support::maybe::Some(-7);
    let high: u32 = 2147483648;
    let u: support::maybe::Maybe<u32> = support::maybe::Some(high);
    let f: support::maybe::Maybe<f32> = support::maybe::Some(-0.0);
    let c: support::maybe::Maybe<char> = support::maybe::Some('x');
    let s: support::maybe::Maybe<str> = support::maybe::Some("");
    let storage: [i32; 2] = [7, 11];
    let view: [i32] = core::mem::i32_slice_from_raw_parts(core::mem::i32_array_data_ptr(storage), 2);
    let v: support::maybe::Maybe<[i32]> = support::maybe::Some(view);
    if (!support::maybe::is_some(b) || support::maybe::is_some(absent)) { return 1; }
    if (!support::maybe::is_some(i) || !support::maybe::is_some(u)) { return 2; }
    if (!support::maybe::is_some(f) || !support::maybe::is_some(c)) { return 3; }
    if (!support::maybe::is_some(s) || !support::maybe::is_some(v)) { return 4; }
    if (!local_is_some(b) || !local_is_some(i)) { return 5; }
    if (core::mem::first(7, 11) != 7 || core::mem::first(false, true)) { return 6; }
    if (!b.is_some() || !i.is_some() || absent.is_some()) { return 7; }
    if (b.unwrap_or(true) || !absent.unwrap_or(true)) { return 8; }
    let signed_empty: std::vec::Vec<i32> = std::vec::new();
    let bool_empty: std::vec::Vec<bool> = std::vec::new();
    if (!signed_empty.is_empty() || !bool_empty.is_empty()) { return 9; }
    return 0;
}
"#;
        let consumer = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.to_owned()].into(),
            11,
            3,
            vec![vec![provider.interface.clone()]].into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("compile independent calls to one generic declaration");
        let declaration = provider
            .interface
            .declarations
            .iter()
            .position(|declaration| {
                let start = declaration.name_byte_start as usize;
                &provider.interface.name_bytes[start..start + declaration.name_byte_len as usize]
                    == b"is_some"
            })
            .expect("find the generic predicate identity") as u32;
        let target = CheckedGenericTarget::Dependency {
            library_id: 7,
            unit_id: 0,
            declaration_index: declaration,
        };
        let calls = consumer
            .generic_calls
            .iter()
            .filter(|call| call.target == target)
            .collect::<Vec<_>>();
        assert_eq!(calls.len(), 8, "{:?}", consumer.generic_calls);
        assert_eq!(
            calls
                .iter()
                .map(|call| call.call_hir)
                .collect::<std::collections::BTreeSet<_>>()
                .len(),
            8
        );
        assert!(
            calls.iter().all(|call| call.has_complete_arguments()),
            "{calls:?}"
        );
        let actual = calls
            .iter()
            .map(|call| call.arguments[0].ty.clone())
            .collect::<Vec<_>>();
        for ty in [
            CheckedGenericType::Scalar(2),
            CheckedGenericType::Scalar(3),
            CheckedGenericType::Scalar(4),
            CheckedGenericType::Scalar(5),
            CheckedGenericType::Scalar(6),
            CheckedGenericType::Scalar(7),
            CheckedGenericType::Slice(Box::new(CheckedGenericType::Scalar(3))),
        ] {
            assert!(actual.contains(&ty), "missing {ty:?}: {calls:?}");
        }
        let local_calls = consumer
            .generic_calls
            .iter()
            .filter(|call| {
                matches!(
                    call.target,
                    CheckedGenericTarget::Local {
                        generic_parameter_count: 1,
                        ..
                    }
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(local_calls.len(), 2, "{:?}", consumer.generic_calls);
        assert!(local_calls.iter().all(|call| call.has_complete_arguments()));
        assert!(
            local_calls
                .iter()
                .any(|call| call.arguments[0].ty == CheckedGenericType::Scalar(2))
        );
        assert!(
            local_calls
                .iter()
                .any(|call| call.arguments[0].ty == CheckedGenericType::Scalar(3))
        );
        let first = provider
            .interface
            .declarations
            .iter()
            .position(|declaration| {
                let start = declaration.name_byte_start as usize;
                &provider.interface.name_bytes[start..start + declaration.name_byte_len as usize]
                    == b"first"
            })
            .expect("find the real repeated-parameter helper") as u32;
        let repeated = consumer
            .generic_calls
            .iter()
            .filter(|call| {
                call.target
                    == CheckedGenericTarget::Dependency {
                        library_id: 7,
                        unit_id: 0,
                        declaration_index: first,
                    }
            })
            .collect::<Vec<_>>();
        assert_eq!(repeated.len(), 2, "{:?}", consumer.generic_calls);
        assert!(
            repeated
                .iter()
                .all(|call| call.has_complete_arguments() && call.arguments.len() == 1),
            "repeated T claims must produce one binding per call: {repeated:?}"
        );
        let method_target = |name: &[u8]| {
            let method = exported_inherent_method(&provider.interface, name);
            CheckedGenericTarget::DependencyMethod {
                library_id: 7,
                unit_id: 0,
                method_symbol: method.value_hi,
            }
        };
        let method_calls = consumer
            .generic_calls
            .iter()
            .filter(|call| call.target == method_target(b"is_some"))
            .collect::<Vec<_>>();
        assert_eq!(method_calls.len(), 3, "{:?}", consumer.generic_calls);
        assert!(
            method_calls
                .iter()
                .all(|call| call.has_complete_arguments()),
            "{method_calls:?}"
        );
        assert!(
            method_calls
                .iter()
                .any(|call| call.arguments[0].ty == CheckedGenericType::Scalar(2))
        );
        assert!(
            method_calls
                .iter()
                .any(|call| call.arguments[0].ty == CheckedGenericType::Scalar(3))
        );
        assert!(
            consumer
                .generic_calls
                .iter()
                .all(|call| call.target != method_target(b"unwrap_or")),
            "a concrete bool method must not require its owner's generic T: {:?}",
            consumer.generic_calls
        );
        let constructor = provider
            .interface
            .declarations
            .iter()
            .position(|declaration| {
                let start = declaration.name_byte_start as usize;
                &provider.interface.name_bytes[start..start + declaration.name_byte_len as usize]
                    == b"new"
            })
            .expect("find Vec's generic free constructor") as u32;
        let constructors = consumer
            .generic_calls
            .iter()
            .filter(|call| {
                call.target
                    == CheckedGenericTarget::Dependency {
                        library_id: 7,
                        unit_id: 0,
                        declaration_index: constructor,
                    }
            })
            .collect::<Vec<_>>();
        assert_eq!(
            constructors.len(),
            2,
            "zero-argument calls must not disappear: {:?}",
            consumer.generic_calls
        );
        assert!(
            constructors.iter().all(|call| {
                call.required_generic_parameters == Some(1)
                    && call.arguments.len() == 1
                    && call.arguments[0].slot == 0
                    && call.has_complete_arguments()
            }),
            "result annotations must supply complete constructor bindings: {constructors:?}"
        );
        for expected in [CheckedGenericType::Scalar(3), CheckedGenericType::Scalar(2)] {
            assert!(
                constructors
                    .iter()
                    .any(|call| call.arguments[0].ty == expected),
                "each constructor must retain its own annotated result type: {constructors:?}"
            );
        }
        let retained = consumer.generic_calls.clone();
        let overwritten =
            pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
                vec!["module app::main; fn main() -> i32 { return 99; }".into()].into(),
                11,
                3,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ))
            .expect("overwrite lexer, parser, and checker workspace");
        assert!(overwritten.generic_calls.is_empty());
        assert_eq!(consumer.generic_calls.as_ref(), retained.as_ref());
        let objects = pollster::block_on(
            compiler.specialize_x86_source_pack_objects(&[&provider, &consumer]),
        )
        .expect("instantiate memory helpers after scratch reuse");
        let input =
            x86::GpuX86LinkInput::for_executable_refs(objects.iter().map(|object| object.as_ref()))
                .expect("prepare generic predicate objects");
        let linked = compiler
            .x86_linker()
            .expect("x86 linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link generic predicate calls after scratch reuse");
        assert_x86_main_exit(&linked, "retained-generic-call-environments", 0);
    }

    #[test]
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    fn caller_private_nominals_execute_through_imported_generic_relay() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let provider = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    r#"
module support::relay;
fn keep<T>(value: T) -> T { return value; }
pub fn relay<T>(value: T) -> T { return keep(value); }
"#
                    .to_owned(),
                ]
                .into(),
                7,
                0,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("compile imported relay with a second generic call");
        let consumer = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    r#"
module app::main;
import support::relay;
struct Pair { first: i32, second: i32 }
enum Choice { Empty, Value(i32) }
fn main() -> i32 {
    let pair: Pair = Pair { first: -7, second: 49 };
    let returned: Pair = support::relay::relay(pair);
    if (returned.first != -7 || returned.second != 49) { return 1; }
    let present: Choice = Value(-17);
    let absent: Choice = Empty();
    let returned_present: Choice = support::relay::relay(present);
    let returned_absent: Choice = support::relay::relay(absent);
    let payload: i32 = match (returned_present) { Value(value) -> value, Empty -> 99 };
    if (payload != -17) { return 2; }
    let is_empty: bool = match (returned_absent) { Value(_) -> false, Empty -> true };
    if (!is_empty) { return 3; }
    return 0;
}
"#
                    .to_owned(),
                ]
                .into(),
                11,
                3,
                vec![vec![provider.interface.clone()]].into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("compile caller-private record and enum arguments");
        let objects = pollster::block_on(
            compiler.specialize_x86_source_pack_objects(&[&provider, &consumer]),
        )
        .expect("replay private nominal graphs through both generic bodies");
        let input =
            x86::GpuX86LinkInput::for_executable_refs(objects.iter().map(|object| object.as_ref()))
                .expect("prepare caller and generic relay objects");
        let linked = compiler
            .x86_linker()
            .expect("x86 linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link caller-private nominal roundtrip");
        assert_x86_main_exit(&linked, "caller-private-nominal-relay", 0);
    }

    #[test]
    fn retained_symbolic_call_graphs_preserve_caller_binders_after_workspace_reuse() {
        use crate::type_checker::{
            CheckedBinderIdentity,
            CheckedGenericApplicationArgument as Argument,
            CheckedGenericConstantValue as Constant,
            CheckedGenericTarget,
            CheckedGenericType as Type,
            CheckedNominalIdentity,
            CheckedParameterDomain,
        };

        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let provider = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    r#"
module core::retain;
pub fn keep<V>(value: V) -> V { return value; }
pub fn keep_array<V, const L: usize>(value: [V; L]) -> [V; L] { return value; }
"#
                    .to_owned(),
                ]
                .into(),
                7,
                0,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("compile generic graph retention helpers");
        let sources = vec![
            r#"// Public caller comment: π and 🐦 occupy multiple bytes.

module app::symbolic;
import core::retain;
pub struct PublicCell<V, const L: usize> { value: V }
pub fn exposed<T, const N: usize>(value: T, array: [T; N], cell: PublicCell<[T; N], N>, reference: &[T], view: [T]) -> i32 {
    let first: T = core::retain::keep(value);
    let repeated: T = core::retain::keep(value);
    let array_copy: [T; N] = core::retain::keep(array);
    let cell_copy: PublicCell<[T; N], N> = core::retain::keep(cell);
    let reference_copy: &[T] = core::retain::keep(reference);
    let view_copy: [T] = core::retain::keep(view);
    let constant_copy: [T; N] = core::retain::keep_array(array);
    return 0;
}
"#.to_owned(),
            r#"// Private caller comment: λ and 雪 precede every retained call.
module app::hidden;
import core::retain;
struct PrivateCell<V, const L: usize> { value: V }
fn hidden<T, const N: usize>(value: T, array: [T; N], cell: PrivateCell<[T; N], N>, reference: &[T], view: [T]) -> i32 {
    let first: T = core::retain::keep(value);
    let repeated: T = core::retain::keep(value);
    let array_copy: [T; N] = core::retain::keep(array);
    let cell_copy: PrivateCell<[T; N], N> = core::retain::keep(cell);
    let reference_copy: &[T] = core::retain::keep(reference);
    let view_copy: [T] = core::retain::keep(view);
    let constant_copy: [T; N] = core::retain::keep_array(array);
    return 0;
}
fn main() -> i32 { return 0; }
"#.to_owned(),
        ];
        let source_paths = vec![
            Some(PathBuf::from("retained/public.lani")),
            Some(PathBuf::from("retained/private.lani")),
        ];
        // The canonical call span begins at the callee's first token: `core`
        // for these qualified calls. Derive byte offsets from fixture text,
        // independently of HIR IDs and the GPU's token/span publication.
        let mut expected_calls = Vec::new();
        let mut file_start = 0usize;
        for (file_index, source) in sources.iter().enumerate() {
            for (local_start, _) in source.match_indices("core::retain::keep") {
                assert!(local_start > 0);
                assert!(source[..local_start].chars().count() < local_start);
                expected_calls.push((
                    [u32::try_from(file_start + local_start).unwrap(), 4],
                    file_index,
                    local_start,
                ));
            }
            file_start += source.len();
        }
        assert_eq!(expected_calls.len(), 14);
        assert_eq!(expected_calls.iter().filter(|call| call.1 == 1).count(), 7);
        let consumer = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages_and_paths(
                sources.clone().into(),
                11,
                3,
                vec![vec![provider.interface.clone()]].into(),
                SourcePackArtifactTarget::X86_64,
                Some(&source_paths),
            ),
        ).expect("retain symbolic caller graphs and diagnostic origins");
        let assert_call_sources = |unit: &super::super::typecheck::CompiledSourcePackUnit| {
            assert_eq!(unit.template_sources.as_ref(), sources.as_slice());
            assert_eq!(unit.template_source_paths.as_ref(), source_paths.as_slice());
            let mut spans = unit.generic_calls.iter().map(|call| call.source_span).collect::<Vec<_>>();
            spans.sort_unstable();
            assert_eq!(
                spans,
                expected_calls.iter().map(|call| call.0).collect::<Vec<_>>(),
                "every call retains its exact global byte span, including the second file offset",
            );
            let files = crate::compiler::source_pack_diagnostic_files(
                unit.template_sources.as_ref(), Some(unit.template_source_paths.as_ref()),
            );
            for (span, (_, file_index, expected_local)) in spans.iter().zip(&expected_calls) {
                let file = crate::compiler::source_pack_file_for_global_span(&files, span[0] as usize)
                    .expect("retained call belongs to its immutable source file");
                let local = file.local_start_for_global(span[0] as usize);
                let label = crate::compiler::diagnostic_label_from_source_span(
                    file.path.clone(), &file.source, local, span[1] as usize, "retained call",
                );
                assert_eq!(&file.path, source_paths[*file_index].as_ref().unwrap());
                assert_eq!(local, *expected_local);
                assert_eq!(label.path, file.path);
                assert_eq!(label.byte_start, Some(*expected_local));
                assert_eq!(label.byte_end, Some(*expected_local + 4));
                assert_eq!(&file.source[local..local + span[1] as usize], "core");
            }
        };
        assert_call_sources(&consumer);
        let declaration = |interface: &crate::compiler::GpuSemanticInterfaceArtifact,
                           name: &[u8]| {
            interface
                .declarations
                .iter()
                .position(|declaration| {
                    let start = declaration.name_byte_start as usize;
                    &interface.name_bytes[start..start + declaration.name_byte_len as usize] == name
                })
                .expect("public declaration identity") as u32
        };
        let keep_target = CheckedGenericTarget::Dependency {
            library_id: 7,
            unit_id: 0,
            declaration_index: declaration(&provider.interface, b"keep"),
        };
        let array_target = CheckedGenericTarget::Dependency {
            library_id: 7,
            unit_id: 0,
            declaration_index: declaration(&provider.interface, b"keep_array"),
        };
        let calls = consumer
            .generic_calls
            .iter()
            .filter(|call| call.target == keep_target)
            .collect::<Vec<_>>();
        assert_eq!(calls.len(), 12, "{:?}", consumer.generic_calls);
        assert!(
            calls.iter().all(|call| {
                call.arguments.len() == 1
                    && call.arguments[0].ty.has_semantic_identity()
                    && !call.arguments[0].ty.is_closed()
                    && !call.has_complete_arguments()
            }),
            "symbolic identity must survive without claiming executable layout: {calls:?}"
        );
        let direct_parameters = calls
            .iter()
            .filter_map(|call| match call.arguments[0].ty {
                Type::Parameter(parameter) => Some(parameter),
                _ => None,
            })
            .collect::<Vec<_>>();
        assert_eq!(
            direct_parameters.len(),
            4,
            "repeated direct T claims: {calls:?}"
        );
        let public_binder = CheckedBinderIdentity::Public {
            owner: declaration(&consumer.interface, b"exposed"),
            scope: 0,
        };
        let public_parameter = *direct_parameters
            .iter()
            .find(|parameter| parameter.identity.binder == public_binder)
            .expect("exported caller owns its parameter");
        let private_parameter = *direct_parameters
            .iter()
            .find(|parameter| {
                matches!(
                    parameter.identity.binder,
                    CheckedBinderIdentity::SourceLocal { .. }
                )
            })
            .expect("private caller retains a source-owned binder");
        assert_ne!(
            public_parameter.identity, private_parameter.identity,
            "same spelling and binding slot must not merge different caller declarations"
        );
        let array_calls = consumer
            .generic_calls
            .iter()
            .filter(|call| call.target == array_target)
            .collect::<Vec<_>>();
        assert_eq!(array_calls.len(), 2, "{:?}", consumer.generic_calls);
        for parameter in [public_parameter, private_parameter] {
            assert_eq!(parameter.identity.unit, [11, 3]);
            assert_eq!(parameter.identity.domain, CheckedParameterDomain::Type);
            assert_eq!(parameter.identity.source_ordinal, 0);
            assert_eq!(parameter.binding_slot, 0);
            assert_eq!(
                direct_parameters
                    .iter()
                    .filter(|candidate| **candidate == parameter)
                    .count(),
                2,
                "repeated occurrences retain the same declaration-owned identity"
            );
            let parameter_type = Type::Parameter(parameter);
            let file_index = usize::from(parameter != public_parameter);
            let file_start = sources[..file_index].iter().map(String::len).sum::<usize>();
            let assert_origins = |target: &CheckedGenericTarget, ty: &Type, expression: &str| {
                let mut actual = consumer.generic_calls.iter()
                    .filter(|call| &call.target == target && call.arguments.len() == 1
                        && &call.arguments[0].ty == ty)
                    .map(|call| call.source_span)
                    .collect::<Vec<_>>();
                actual.sort_unstable();
                let expected = sources[file_index].match_indices(expression)
                    .map(|(local, _)| [u32::try_from(file_start + local).unwrap(), 4])
                    .collect::<Vec<_>>();
                assert!(!expected.is_empty(), "fixture contains {expression}");
                assert_eq!(actual, expected,
                    "call origins stay associated with caller binder, callee, and argument type: {expression}");
            };
            assert_origins(&keep_target, &parameter_type, "core::retain::keep(value)");
            let array_type = calls.iter().map(|call| &call.arguments[0].ty).find(|ty| {
                matches!(ty, Type::Array { element, .. } if element.as_ref() == &parameter_type)
            }).expect("symbolic array remains an array");
            let Type::Array {
                length: Constant::Parameter(constant),
                words,
                ..
            } = array_type
            else {
                panic!("symbolic array length must retain its constant binder: {array_type:?}");
            };
            assert_origins(&keep_target, array_type, "core::retain::keep(array)");
            assert_eq!(*words, None, "unknown width must remain unavailable");
            assert_eq!(constant.identity.unit, parameter.identity.unit);
            assert_eq!(constant.identity.binder, parameter.identity.binder);
            assert_eq!(constant.identity.domain, CheckedParameterDomain::Constant);
            assert_eq!(
                constant.identity.source_ordinal, 1,
                "source ordinal includes type and constant parameters in header order"
            );
            assert_eq!(
                constant.binding_slot, 0,
                "constant binding slots are independent of type slots and source ordinals"
            );
            let expected_operands = vec![
                Argument::Type(array_type.clone()),
                Argument::Constant(Constant::Parameter(*constant)),
            ];
            let nominal = calls.iter().map(|call| &call.arguments[0].ty).find(|ty| {
                matches!(ty, Type::Nominal { arguments, .. } if arguments == &expected_operands)
            }).expect("nominal retains nested symbolic array and ordered constant operand");
            let Type::Nominal {
                identity, words, ..
            } = nominal
            else {
                unreachable!()
            };
            assert_origins(&keep_target, nominal, "core::retain::keep(cell)");
            assert_eq!(
                *words, None,
                "symbolic nominal does not fabricate native layout"
            );
            if parameter == public_parameter {
                assert_eq!(
                    *identity,
                    CheckedNominalIdentity::Public([
                        11,
                        3,
                        declaration(&consumer.interface, b"PublicCell"),
                    ])
                );
            } else {
                assert!(
                    matches!(identity, CheckedNominalIdentity::SourceLocal {
                    unit: [11, 3], declaration_token,
                } if *declaration_token != u32::MAX),
                    "private nominal identity must not fabricate an export index: {nominal:?}"
                );
            }
            let slice_type = Type::Slice(Box::new(parameter_type.clone()));
            for (expected, expression) in [
                (slice_type.clone(), "core::retain::keep(view)"),
                (Type::Reference(Box::new(slice_type)), "core::retain::keep(reference)"),
            ] {
                assert_origins(&keep_target, &expected, expression);
                assert!(
                    calls.iter().any(|call| call.arguments[0].ty == expected),
                    "missing symbolic reference/slice graph {expected:?}: {calls:?}"
                );
            }
            let constant_call = array_calls
                .iter()
                .find(|call| call.arguments.len() == 1 && call.arguments[0].ty == parameter_type)
                .expect("array helper binds the same caller type parameter");
            assert_origins(&array_target, &parameter_type, "core::retain::keep_array(array)");
            assert_eq!(constant_call.constants.len(), 1, "{constant_call:?}");
            assert_eq!(constant_call.constants[0].slot, 0);
            assert_eq!(
                constant_call.constants[0].value,
                Constant::Parameter(*constant),
                "top-level and nested constants must preserve the same caller binder"
            );
            assert!(
                !constant_call.has_complete_arguments(),
                "symbolic environments are not native specialization inputs"
            );
        }
        let retained = consumer.generic_calls.to_vec();
        let replacement_paths = [Some(PathBuf::from("replacement/scratch.lani"))];
        let overwritten =
            pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages_and_paths(
                vec!["module scratch; fn main() -> i32 { return 0; }".to_owned()].into(),
                11,
                3,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
                Some(&replacement_paths),
            ))
            .expect("reuse all lexer, parser, and checker scratch buffers");
        assert!(overwritten.generic_calls.is_empty());
        assert_eq!(overwritten.template_source_paths.as_ref(), replacement_paths.as_slice());
        assert_eq!(
            consumer.generic_calls.as_ref(),
            retained.as_slice(),
            "caller binders, nested types, and source spans outlive workspace reuse"
        );
        assert_call_sources(&consumer);
    }

    #[test]
    fn retained_nominal_applications_keep_declarations_and_all_ordered_arguments() {
        use crate::type_checker::{
            CheckedGenericApplicationArgument as Argument,
            CheckedGenericConstantValue,
            CheckedGenericTarget,
            CheckedGenericType,
        };
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let provider = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    "module core::retain; pub fn keep<T>(value: T) -> T { return value; }"
                        .to_owned(),
                ]
                .into(),
                7,
                0,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("generic provider");
        let consumer = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    r#"
module app::main;
import core::retain;
struct Cell<T> { value: T, sentinel: i32 }
struct Twin<A, B> { first: A, second: B }
fn main() -> i32 {
    let integer: Cell<i32> = Cell { value: -7, sentinel: 99 };
    let flag: Cell<bool> = Cell { value: false, sentinel: 99 };
    let words: [str; 2] = ["Ω", ""];
    let text: Cell<[str; 2]> = Cell { value: words, sentinel: 99 };
    let twin: Twin<bool, i32> = Twin { first: false, second: -7 };
    let integer_copy: Cell<i32> = core::retain::keep(integer);
    let second_integer: Cell<i32> = core::retain::keep(integer);
    let flag_copy: Cell<bool> = core::retain::keep(flag);
    let text_copy: Cell<[str; 2]> = core::retain::keep(text);
    let twin_copy: Twin<bool, i32> = core::retain::keep(twin);
    return 0;
}
"#
                    .to_owned(),
                ]
                .into(),
                11,
                3,
                vec![vec![provider.interface.clone()]].into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("retained nominal graph consumer");
        let types = consumer
            .generic_calls
            .iter()
            .filter(|call| {
                matches!(
                    call.target,
                    CheckedGenericTarget::Dependency {
                        library_id: 7,
                        unit_id: 0,
                        ..
                    }
                )
            })
            .map(|call| call.arguments[0].ty.clone())
            .collect::<Vec<_>>();
        assert_eq!(types.len(), 5, "{types:?}");
        let mut cells = Vec::new();
        let mut twins = Vec::new();
        for ty in &types {
            let CheckedGenericType::Nominal {
                identity,
                arguments,
                words,
                ..
            } = ty
            else {
                panic!("accepted nominal arguments were erased: {ty:?}");
            };
            assert_eq!(identity.unit(), [11, 3]);
            if arguments.len() == 1 {
                cells.push((*identity, arguments.clone(), *words));
            } else {
                twins.push((*identity, arguments.clone(), *words));
            }
        }
        assert_eq!(cells.len(), 4);
        assert!(
            cells.iter().all(|cell| cell.0 == cells[0].0),
            "one declaration across separate instance rows"
        );
        assert_eq!(
            cells
                .iter()
                .filter(|cell| cell.1 == [Argument::Type(CheckedGenericType::Scalar(3))])
                .count(),
            2
        );
        assert!(cells.iter().any(
            |cell| cell.1 == [Argument::Type(CheckedGenericType::Scalar(2))] && cell.2 == Some(2)
        ));
        assert!(cells.iter().any(|cell| cell.1
            == [Argument::Type(CheckedGenericType::Array {
                element: Box::new(CheckedGenericType::Scalar(7)),
                length: CheckedGenericConstantValue::count_literal(2),
                words: Some(4),
            })]
            && cell.2 == Some(5)));
        assert_eq!(twins.len(), 1);
        assert_ne!(
            twins[0].0, cells[0].0,
            "equal layouts retain distinct declarations"
        );
        assert_eq!(
            twins[0].1,
            [
                Argument::Type(CheckedGenericType::Scalar(2)),
                Argument::Type(CheckedGenericType::Scalar(3))
            ]
        );
        assert_eq!(twins[0].2, Some(2));
    }

    #[test]
    fn retained_contextual_environments_preserve_all_thirty_two_parameters() {
        use crate::type_checker::{
            CheckedGenericConstantValue,
            CheckedGenericTarget,
            CheckedGenericType,
        };
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let parameters = (0..32)
            .map(|slot| format!("T{slot}"))
            .collect::<Vec<_>>()
            .join(", ");
        let source = format!(
            "module core::contexts; pub enum Many<{parameters}> {{ Empty }} pub fn absent<{parameters}>() -> Many<{parameters}> {{ return Empty(); }}"
        );
        let provider = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source].into(),
            7,
            0,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("contextual provider");
        let spellings = ["i32", "str", "[str; 2]", "[i32]"];
        let arguments = (0..32)
            .map(|slot| spellings[slot % 4])
            .collect::<Vec<_>>()
            .join(", ");
        let source = format!(
            "module app::main; import core::contexts; fn main() -> i32 {{ let value: core::contexts::Many<{arguments}> = core::contexts::absent(); return 0; }}"
        );
        let consumer = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source].into(),
            11,
            3,
            vec![vec![provider.interface.clone()]].into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("retained contextual consumer");
        let calls = consumer
            .generic_calls
            .iter()
            .filter(|call| {
                matches!(
                    call.target,
                    CheckedGenericTarget::Dependency {
                        library_id: 7,
                        unit_id: 0,
                        ..
                    }
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(calls.len(), 1);
        let call = calls[0];
        assert!(call.has_complete_arguments(), "{call:?}");
        assert_eq!(call.required_generic_parameters, Some(32));
        assert_eq!(call.arguments.len(), 32);
        for (slot, argument) in call.arguments.iter().enumerate() {
            let expected = match slot % 4 {
                0 => CheckedGenericType::Scalar(3),
                1 => CheckedGenericType::Scalar(7),
                2 => CheckedGenericType::Array {
                    element: Box::new(CheckedGenericType::Scalar(7)),
                    length: CheckedGenericConstantValue::count_literal(2),
                    words: Some(4),
                },
                _ => CheckedGenericType::Slice(Box::new(CheckedGenericType::Scalar(3))),
            };
            assert_eq!(argument.slot, slot as u32);
            assert_eq!(argument.ty, expected, "contextual slot {slot}");
        }
        let retained = consumer.generic_calls.clone();
        let plain = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec!["module plain; fn main() -> i32 { return 0; }".to_owned()].into(),
            12,
            0,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("workspace reuse without contextual slots");
        assert!(plain.generic_calls.is_empty());
        assert_eq!(consumer.generic_calls.as_ref(), retained.as_ref());

        let source = format!(
            "module local::contexts; enum Many<{parameters}> {{ Empty }} fn absent<{parameters}>() -> Many<{parameters}> {{ return Empty(); }} fn main() -> i32 {{ let value: Many<{arguments}> = absent(); return 0; }}"
        );
        let local = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source].into(),
            13,
            0,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("retained local result-only bindings");
        let calls = local
            .generic_calls
            .iter()
            .filter(|call| {
                matches!(
                    call.target,
                    CheckedGenericTarget::Local {
                        generic_parameter_count: 32,
                        ..
                    }
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(calls.len(), 1, "{:?}", local.generic_calls);
        assert!(calls[0].has_complete_arguments(), "{:?}", calls[0]);
        let expected = retained[0]
            .arguments
            .iter()
            .map(|argument| (argument.slot, argument.ty.clone()))
            .collect::<Vec<_>>();
        let actual = calls[0]
            .arguments
            .iter()
            .map(|argument| (argument.slot, argument.ty.clone()))
            .collect::<Vec<_>>();
        assert_eq!(
            actual, expected,
            "local and imported result constraints retain the same types"
        );
        let anonymous = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec!["pub enum Maybe<T> { Some(T), None } fn main() -> i32 { let value: Maybe<bool> = Some(false); return 0; }".to_owned()].into(),
            14,
            0,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("anonymous public enum after named contextual modules");
        assert_eq!(anonymous.interface.modules.len(), 1);
        assert_eq!(anonymous.interface.modules[0].segment_count, 0);
        assert!(anonymous.interface.module_segments.is_empty());
        assert_eq!(consumer.generic_calls.as_ref(), retained.as_ref());
    }

    #[test]
    fn retained_generic_result_environments_preserve_two_slots_and_record_layouts() {
        use crate::type_checker::{
            CheckedGenericTarget,
            CheckedGenericType,
            CheckedNominalIdentity,
        };
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../stdlib/core");
        let sources = ["result.lani", "mem.lani"]
            .iter()
            .map(|name| {
                std::fs::read_to_string(root.join(name))
                    .expect("read actual standard-library source")
            })
            .collect::<Vec<_>>();
        let provider = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            sources.into(),
            7,
            0,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("compile the actual Result module");
        let source = r#"
module app::main;
import core::result;
import core::mem;
struct Pair { first: i32, second: i32 }
struct Quad { first: i32, second: i32, third: i32, fourth: i32 }
fn main() -> i32 {
    let backing: [i32; 2] = [7, 11];
    let view: [i32] = core::mem::i32_slice_from_raw_parts(core::mem::i32_array_data_ptr(backing), 2);
    let left: core::result::Result<[i32], str> = core::result::Ok(view);
    let right: core::result::Result<str, [i32]> = core::result::Err(view);
    let pair: Pair = Pair { first: -7, second: 11 };
    let quad: Quad = Quad { first: 3, second: 5, third: 7, fourth: 11 };
    let record: core::result::Result<Pair, Quad> = core::result::Ok(pair);
    if (!core::result::is_ok(left) || core::result::is_ok(right)) { return 1; }
    if (!core::result::is_ok(record)) { return 2; }
    if (!left.is_ok() || right.is_ok() || !record.is_ok()) { return 4; }
    let recovered: Pair = match (record) { core::result::Ok(inner) -> inner, core::result::Err(error) -> pair };
    if (recovered.first != -7 || recovered.second != 11) { return 3; }
    return 0;
}
"#;
        let consumer = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![source.to_owned()].into(),
            11,
            3,
            vec![vec![provider.interface.clone()]].into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("compile Result descriptor and record calls");
        let declaration = provider
            .interface
            .declarations
            .iter()
            .position(|declaration| {
                let start = declaration.name_byte_start as usize;
                declaration.owner_declaration == u32::MAX
                    && &provider.interface.name_bytes
                        [start..start + declaration.name_byte_len as usize]
                        == b"is_ok"
            })
            .expect("find the free Result predicate") as u32;
        let target = CheckedGenericTarget::Dependency {
            library_id: 7,
            unit_id: 0,
            declaration_index: declaration,
        };
        let calls = consumer
            .generic_calls
            .iter()
            .filter(|call| call.target == target)
            .collect::<Vec<_>>();
        assert_eq!(calls.len(), 3, "{:?}", consumer.generic_calls);
        assert!(
            calls
                .iter()
                .all(|call| call.required_generic_parameters == Some(2)),
            "{calls:?}"
        );
        let complete = calls
            .iter()
            .filter(|call| call.has_complete_arguments())
            .collect::<Vec<_>>();
        assert_eq!(
            complete.len(),
            3,
            "descriptor and private record bindings retain checked layouts: {calls:?}"
        );
        let record_call = complete
            .iter()
            .find(|call| {
                matches!(
                    call.arguments[0].ty,
                    CheckedGenericType::Nominal { words: Some(2), .. }
                )
            })
            .expect("retain the two-word successful record");
        assert!(
            matches!(
                record_call.arguments[1].ty,
                CheckedGenericType::Nominal {
                    identity: CheckedNominalIdentity::SourceLocal { unit: [11, 3], .. },
                    words: Some(4),
                    ..
                }
            ),
            "retain the independent four-word error record: {record_call:?}"
        );
        for expected in [
            [
                CheckedGenericType::Slice(Box::new(CheckedGenericType::Scalar(3))),
                CheckedGenericType::Scalar(7),
            ],
            [
                CheckedGenericType::Scalar(7),
                CheckedGenericType::Slice(Box::new(CheckedGenericType::Scalar(3))),
            ],
        ] {
            assert!(
                complete.iter().any(|call| call
                    .arguments
                    .iter()
                    .map(|arg| arg.ty.clone())
                    .collect::<Vec<_>>()
                    == expected),
                "missing ordered T/E bindings {expected:?}: {calls:?}"
            );
        }
        let method = exported_inherent_method(&provider.interface, b"is_ok");
        let method_calls = consumer
            .generic_calls
            .iter()
            .filter(|call| {
                call.target
                    == CheckedGenericTarget::DependencyMethod {
                        library_id: 7,
                        unit_id: 0,
                        method_symbol: method.value_hi,
                    }
            })
            .collect::<Vec<_>>();
        assert_eq!(method_calls.len(), 3, "{:?}", consumer.generic_calls);
        assert!(
            method_calls
                .iter()
                .all(|call| call.required_generic_parameters == Some(2)),
            "{method_calls:?}"
        );
        assert_eq!(
            method_calls
                .iter()
                .filter(|call| call.has_complete_arguments())
                .count(),
            3,
            "descriptor and private record receiver environments resolve: {method_calls:?}"
        );
        assert!(
            method_calls.iter().any(|call| matches!(
                call.arguments[0].ty,
                CheckedGenericType::Nominal {
                    identity: CheckedNominalIdentity::SourceLocal { unit: [11, 3], .. },
                    words: Some(2),
                    ..
                }
            ) && matches!(
                call.arguments[1].ty,
                CheckedGenericType::Nominal {
                    identity: CheckedNominalIdentity::SourceLocal { unit: [11, 3], .. },
                    words: Some(4),
                    ..
                }
            )),
            "method receivers retain the same ordered record layouts: {method_calls:?}"
        );
        for expected in [
            [
                CheckedGenericType::Slice(Box::new(CheckedGenericType::Scalar(3))),
                CheckedGenericType::Scalar(7),
            ],
            [
                CheckedGenericType::Scalar(7),
                CheckedGenericType::Slice(Box::new(CheckedGenericType::Scalar(3))),
            ],
        ] {
            assert!(
                method_calls.iter().any(|call| call
                    .arguments
                    .iter()
                    .map(|argument| argument.ty.clone())
                    .collect::<Vec<_>>()
                    == expected),
                "missing ordered receiver bindings {expected:?}: {method_calls:?}"
            );
        }
        let objects = pollster::block_on(
            compiler.specialize_x86_source_pack_objects(&[&provider, &consumer]),
        )
        .expect("specialize the real Result functions");
        let input =
            x86::GpuX86LinkInput::for_executable_refs(objects.iter().map(|object| object.as_ref()))
                .expect("prepare Result objects");
        let linked = compiler
            .x86_linker()
            .expect("x86 linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link the real Result functions");
        assert_x86_main_exit(&linked, "retained-generic-result-environments", 0);
    }

    #[test]
    fn scalar_body_specialization_executes_both_variants_and_clears_between_jobs() {
        use crate::type_checker::{CheckedGenericTarget, CheckedGenericType};

        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let definitions = r#"
module support::maybe;
pub enum Maybe<T> { Some(T), None }
pub fn unwrap_or<T>(value: Maybe<T>, fallback: T) -> T {
    return match (value) { Some(inner) -> inner, None -> fallback };
}
pub fn is_some<T>(value: Maybe<T>) -> bool {
    return match (value) { Some(_) -> true, None -> false };
}
pub fn seven() -> i32 { return 7; }
pub fn marker<T>(value: i32) -> i32 { return value; }
"#;
        let template = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            vec![definitions.to_owned()].into(),
            7,
            2,
            Vec::new().into(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("compile original provider with a deferred generic payload body");
        let marker = template
            .interface
            .declarations
            .iter()
            .position(|declaration| {
                let start = declaration.name_byte_start as usize;
                &template.interface.name_bytes[start..start + declaration.name_byte_len as usize]
                    == b"marker"
            })
            .expect("retain the uncalled generic marker") as u32;
        let CompiledSourcePackObject::X86_64(original) = &template.object else {
            unreachable!()
        };
        assert!(original.symbols.iter().any(|symbol| {
            symbol.section == x86::GpuX86ObjectSection::Text
                && x86_object_symbol_identity(original, symbol) == [7, 2, marker]
        }), "the ordinary object emits a generic body with a concrete signature");

        for (label, scalar, source) in [
            (
                "bool",
                2,
                r#"
module app::main;
import support::maybe;
fn main() -> i32 {
    let no: support::maybe::Maybe<bool> = support::maybe::None();
    let yes: support::maybe::Maybe<bool> = support::maybe::Some(true);
    let zero: support::maybe::Maybe<bool> = support::maybe::Some(false);
    if (!support::maybe::unwrap_or(no, true)) { return 1; }
    if (support::maybe::unwrap_or(no, false)) { return 2; }
    if (!support::maybe::unwrap_or(yes, false)) { return 3; }
    if (support::maybe::unwrap_or(zero, true)) { return 4; }
    if (!support::maybe::is_some(zero)) { return 5; }
    if (support::maybe::seven() != 7) { return 6; }
    return 0;
}
"#,
            ),
            (
                "i32",
                3,
                r#"
module app::main;
import support::maybe;
fn main() -> i32 {
    let no: support::maybe::Maybe<i32> = support::maybe::None();
    let negative: support::maybe::Maybe<i32> = support::maybe::Some(-7);
    let zero: support::maybe::Maybe<i32> = support::maybe::Some(0);
    let low: support::maybe::Maybe<i32> = support::maybe::Some(-2147483648);
    let high: support::maybe::Maybe<i32> = support::maybe::Some(2147483647);
    if (support::maybe::unwrap_or(no, 99) != 99) { return 1; }
    if (support::maybe::unwrap_or(negative, 99) != -7) { return 2; }
    if (support::maybe::unwrap_or(zero, 99) != 0) { return 3; }
    if (support::maybe::unwrap_or(low, 99) != -2147483648) { return 4; }
    if (support::maybe::unwrap_or(high, -7) != 2147483647) { return 5; }
    if (!support::maybe::is_some(zero)) { return 6; }
    if (support::maybe::seven() != 7) { return 7; }
    return 0;
}
"#,
            ),
        ] {
            let consumer =
                pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
                    vec![source.to_owned()].into(),
                    11,
                    3,
                    vec![vec![template.interface.clone()]].into(),
                    SourcePackArtifactTarget::X86_64,
                ))
                .expect("compile a concrete caller against the original generic interface");
            // Both generic functions retain T. Their Maybe<T> parameter
            // layouts remain open until the scheduler instantiates them.
            let call = consumer
                .generic_calls
                .iter()
                .find(|call| {
                    let CheckedGenericTarget::Dependency {
                        library_id: 7,
                        unit_id: 2,
                        declaration_index,
                    } = call.target
                    else {
                        return false;
                    };
                    let CompiledSourcePackObject::X86_64(original) = &template.object else {
                        unreachable!()
                    };
                    !original.symbols.iter().any(|symbol| {
                        symbol.section == x86::GpuX86ObjectSection::Text
                            && x86_object_symbol_identity(original, symbol)
                                == [7, 2, declaration_index]
                    })
                })
                .expect("retained call to the unresolved generic body");
            assert!(call.has_complete_arguments(), "{call:?}");
            assert_eq!(call.arguments.len(), 1);
            assert_eq!(call.arguments[0].ty, CheckedGenericType::Scalar(scalar));
            let objects = pollster::block_on(
                compiler.specialize_x86_source_pack_objects(&[&template, &consumer]),
            )
            .expect("admit and specialize every concrete generic body");
            let input =
                x86::GpuX86LinkInput::for_executable_refs(objects.iter().map(|object| object.as_ref()))
                    .expect("prepare all checked provider, caller, and replay objects");
            let linked = compiler
                .x86_linker()
                .expect("x86 linker")
                .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
                .expect("link the concrete generic body");
            assert_x86_main_exit(&linked, &format!("scalar-body-{label}"), 0);

            let ordinary =
                pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
                    template.template_sources.clone(),
                    7,
                    2,
                    template.template_dependency_pages.clone(),
                    SourcePackArtifactTarget::X86_64,
                ))
                .expect("ordinary checking after specialization");
            let original = template.object.clone().into_x86_64().unwrap();
            let ordinary = ordinary.object.into_x86_64().unwrap();
            assert_eq!(
                ordinary, original,
                "replay substitutions and scope must clear before the next ordinary job, including the uncalled generic marker"
            );
        }
    }

    #[test]
    fn scalar_body_specializations_route_multiple_types_in_one_native_program() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let template = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    r#"
module support::maybe;
pub enum Maybe<T> { Some(T), None }
pub fn unwrap_or<T>(value: Maybe<T>, fallback: T) -> T {
    return match (value) { Some(inner) -> inner, None -> fallback };
}
pub fn is_some<T>(value: Maybe<T>) -> bool {
    return match (value) { Some(_) -> true, None -> false };
}
pub fn seven() -> i32 { return 7; }
pub impl<T> Maybe<T> {
    pub fn take_or(&self, fallback: T) -> T {
        return match (self) { Some(inner) -> inner, None -> fallback };
    }
}
"#
                    .to_owned(),
                ]
                .into(),
                7,
                2,
                Vec::new().into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("compile a retained generic definition");
        let consumer = pollster::block_on(
            compiler.compile_source_pack_unit_with_dependency_pages(
                vec![
                    r#"
module app::main;
import support::maybe;
fn main() -> i32 {
    let absent_bool: support::maybe::Maybe<bool> = support::maybe::None();
    let zero_bool: support::maybe::Maybe<bool> = support::maybe::Some(false);
    let absent_i32: support::maybe::Maybe<i32> = support::maybe::None();
    let zero_i32: support::maybe::Maybe<i32> = support::maybe::Some(0);
    let negative: support::maybe::Maybe<i32> = support::maybe::Some(-2147483648);
    if (!support::maybe::unwrap_or(absent_bool, true)) { return 1; }
    if (support::maybe::unwrap_or(zero_bool, true)) { return 2; }
    if (support::maybe::unwrap_or(absent_i32, 99) != 99) { return 3; }
    if (support::maybe::unwrap_or(zero_i32, 99) != 0) { return 4; }
    if (support::maybe::unwrap_or(negative, 99) != -2147483648) { return 5; }
    if (!support::maybe::is_some(zero_bool)) { return 6; }
    if (!support::maybe::is_some(negative)) { return 7; }
    if (support::maybe::seven() != 7) { return 8; }
    if (!absent_bool.take_or(true) || zero_bool.take_or(true)) { return 9; }
    if (absent_i32.take_or(99) != 99 || zero_i32.take_or(99) != 0) { return 10; }
    if (negative.take_or(99) != -2147483648) { return 11; }
    return 0;
}
"#
                    .to_owned(),
                ]
                .into(),
                11,
                3,
                vec![vec![template.interface.clone()]].into(),
                SourcePackArtifactTarget::X86_64,
            ),
        )
        .expect("compile a caller with interleaved concrete types");
        let objects = pollster::block_on(
            compiler.specialize_x86_source_pack_objects(&[&template, &consumer]),
        )
        .expect("schedule distinct free and receiver body specializations");
        assert_eq!(
            objects.len(),
            6,
            "two original units plus two type instances for each free function and method"
        );
        let input =
            x86::GpuX86LinkInput::for_executable_refs(objects.iter().map(|object| object.as_ref()))
                .expect("prepare distinct specialization objects");
        let linked = compiler
            .x86_linker()
            .expect("x86 linker")
            .link_executable(&compiler.gpu.device, &compiler.gpu.queue, &input)
            .expect("link different instances of one generic definition");
        assert_x86_main_exit(&linked, "scalar-bodies-multiple-types", 0);
        let ordinary = pollster::block_on(compiler.compile_source_pack_unit_with_dependency_pages(
            template.template_sources.clone(),
            7,
            2,
            template.template_dependency_pages.clone(),
            SourcePackArtifactTarget::X86_64,
        ))
        .expect("compile an ordinary job after receiver body specialization");
        let method = exported_inherent_method(&template.interface, b"take_or");
        let CompiledSourcePackObject::X86_64(ordinary_object) = &ordinary.object else {
            unreachable!()
        };
        assert!(
            !ordinary_object.symbols.iter().any(|symbol| {
                symbol.section == x86::GpuX86ObjectSection::Text
                    && x86_object_symbol_identity(ordinary_object, symbol)
                        == [7, 2, method.value_hi]
            }),
            "ordinary jobs must clear receiver-owned substitutions"
        );
        let CompiledSourcePackObject::X86_64(original) = &consumer.object else {
            unreachable!()
        };
        assert!(
            original
                .symbols
                .iter()
                .all(|symbol| symbol.identity_byte_len == 12),
            "link scheduling must preserve the original cached caller object"
        );
    }

    fn exported_inherent_method<'a>(
        interface: &'a GpuSemanticInterfaceArtifact,
        name: &[u8],
    ) -> &'a crate::compiler::GpuSemanticInterfaceMemberRecord {
        let (member_index, method) = interface.members.iter().enumerate().find(|(_, member)| {
            let start = member.name_byte_start as usize;
            member.kind == crate::compiler::GpuSemanticInterfaceMemberKind::ImplementationMethod as u32
                && &interface.name_bytes[start..start + member.name_byte_len as usize] == name
        }).expect("find exported implementation method");
        assert_ne!(method.owner_ref, u32::MAX);
        assert_ne!(method.owner_ref & 0x8000_0000, 0, "method has a tagged implementation owner");
        let implementation = &interface.implementations[(method.owner_ref & 0x7fff_ffff) as usize];
        assert_eq!(implementation.kind, crate::compiler::GpuSemanticInterfaceImplementationKind::Inherent as u32);
        assert!((implementation.first_member as usize..(implementation.first_member + implementation.member_count) as usize)
            .contains(&member_index));
        assert_eq!(method.receiver_type_index, implementation.subject_type,
            "method retains the complete implementation subject");
        method
    }

    fn x86_object_symbol_identity(
        object: &x86::GpuX86RelocatableObject,
        symbol: &x86::GpuX86ObjectSymbolRecord,
    ) -> [u32; 3] {
        let start = symbol.identity_byte_start as usize;
        let bytes = &object.identity_bytes[start..start + 12];
        [
            u32::from_le_bytes(bytes[0..4].try_into().unwrap()),
            u32::from_le_bytes(bytes[4..8].try_into().unwrap()),
            u32::from_le_bytes(bytes[8..12].try_into().unwrap()),
        ]
    }

    fn assert_x86_main_exit(bytes: &[u8], artifact_name: &str, expected: i32) {
        use std::os::unix::fs::PermissionsExt;

        let path =
            std::env::temp_dir().join(format!("laniusc-{artifact_name}-{}", std::process::id()));
        std::fs::write(&path, bytes).expect("write projected linked x86 executable");
        let mut permissions = std::fs::metadata(&path).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(&path, permissions).unwrap();
        let status = std::process::Command::new(&path)
            .status()
            .expect("run projected linked x86 executable");
        let _ = std::fs::remove_file(path);
        assert_eq!(status.code(), Some(expected));
    }
}
