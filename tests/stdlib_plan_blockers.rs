fn requirements_doc() -> &'static str {
    include_str!("../stdlib/LANGUAGE_REQUIREMENTS.md")
}

fn plan_doc() -> &'static str {
    include_str!("../stdlib/PLAN.md")
}

fn blocker_checklist() -> &'static str {
    let source = requirements_doc();
    let start = source
        .find("### Plan-Derived Blocker Checklist")
        .expect("missing plan-derived blocker checklist");
    let rest = &source[start..];
    let end = rest
        .find("\n| Stdlib requirement |")
        .expect("checklist should precede the stdlib requirement table");
    &rest[..end]
}

fn normalized(source: &str) -> String {
    source
        .to_ascii_lowercase()
        .replace('`', "")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

#[test]
fn stdlib_plan_required_surfaces_are_mapped_to_blockers() {
    let plan = plan_doc();
    let checklist = blocker_checklist();

    for plan_needle in [
        "modules, package imports",
        "Fixed arrays and slices",
        "`Option`, `Result`, `Ordering`, ranges",
        "Basic traits/interfaces",
        "Panic/assert primitives",
        "`alloc` depends on heap allocation",
        "`std` depends on a host environment",
        "Generic arrays/slices",
        "Requires module/import support",
        "Requires heap/runtime allocation",
    ] {
        assert!(
            plan.contains(plan_needle),
            "stdlib plan should still require: {}",
            plan_needle
        );
    }

    for checklist_needle in [
        "`core` modules/imports",
        "Broad qualified values such as `core::i32::abs` and `core::i32::MIN`",
        "Generic `Option`, `Result`, `Range`, collections, iterators, and helpers",
        "Traits/interfaces for `Eq`, `Ord`, `Hash`, `Debug`",
        "Arrays, slices, and ranges as reusable stdlib APIs",
        "`String`, `Vec`, maps, sets, trees, arenas, and allocation-aware formatting",
        "Module-form inherent methods such as `core::range::Range<i32>.start()`",
        "`extern fn`, host ABI declarations, allocator hooks, I/O, filesystem",
    ] {
        assert!(
            checklist.contains(checklist_needle),
            "blocker checklist should map stdlib plan surface: {}",
            checklist_needle
        );
    }
}

#[test]
fn stdlib_blockers_stay_blocked_until_gpu_only_implementations_exist() {
    let checklist = blocker_checklist();
    let normalized = normalized(checklist);

    assert!(
        normalized.contains("must remain blocked until the named gpu-only implementation exists"),
        "checklist should state that plan features stay blocked until GPU-only implementations exist"
    );
    assert!(
        normalized.contains(
            "cpu prepasses, cpu fallbacks, source concatenation, or documentation-only claims do not count"
        ),
        "checklist should reject CPU fallback and documentation-only availability claims"
    );

    for required_gpu_artifact in [
        "gpu-compatible module/package resolver",
        "general gpu qualified value lookup",
        "gpu monomorphization",
        "gpu trait/interface solving",
        "gpu method declaration records",
        "gpu generic element/length semantics",
        "gpu-visible heap allocation",
        "gpu-only compile path",
        "hir-driven assertion/panic codegen",
    ] {
        assert!(
            normalized.contains(required_gpu_artifact),
            "blocker should point at a GPU implementation artifact: {}",
            required_gpu_artifact
        );
    }

    let blocked_until_count = normalized.matches("blocked until").count();
    assert!(
        blocked_until_count >= 7,
        "expected each stdlib blocker row to be explicit; found {}",
        blocked_until_count
    );
}

#[test]
fn stdlib_assertion_panic_slice_is_hir_and_resolver_driven() {
    let requirements = requirements_doc();
    let normalized = normalized(requirements);

    for required in [
        "bounded hir-driven assertion helper pass",
        "assertion/panic lowering",
        "resolver-selected void scalar helpers",
        "typed assert(bool) expression statement",
        "hir call, return, and type metadata",
        "trap deterministically in wasm",
        "must not recognize stdlib helper names",
    ] {
        assert!(
            normalized.contains(required),
            "requirements should define the assertion/panic slice: {}",
            required
        );
    }
}

#[test]
fn stdlib_docs_do_not_claim_blocked_plan_features_are_available() {
    for (name, source) in [
        ("stdlib/PLAN.md", plan_doc()),
        ("stdlib/LANGUAGE_REQUIREMENTS.md", requirements_doc()),
    ] {
        let normalized = normalized(source);
        for forbidden in [
            "imports are loaded",
            "imports are resolved",
            "qualified constants are available",
            "qualified helper calls are lowered",
            "string is available",
            "vec is available",
            "heap allocation is available",
            "host abi declarations are executable",
            "host apis are available",
            "extern calls are lowered",
            "trait solving is implemented",
            "imported methods are available",
            "module-form impl methods are available",
            "generic monomorphization is implemented",
            "cpu fallback implements",
            "cpu prepass implements",
        ] {
            assert!(
                !normalized.contains(forbidden),
                "{} should not claim blocked stdlib feature availability: {}",
                name,
                forbidden
            );
        }
    }
}

#[test]
fn stdlib_seed_helpers_do_not_depend_on_blocked_trait_dispatch() {
    let hash = include_str!("../stdlib/core/hash.lani");
    let helper = hash
        .split("pub fn hash_i32")
        .nth(1)
        .expect("hash_i32 helper should remain present");

    assert!(
        hash.contains("pub trait Hash<T>"),
        "hash trait declaration seed should remain explicit"
    );
    assert!(
        helper.contains("return value;") && !helper.contains(".hash("),
        "hash_i32 should be a direct scalar helper until GPU trait dispatch exists"
    );
}
