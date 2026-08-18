use crate::gpu::compiler_graph::{PrefixScanGraphPasses, ReflectedComputeSpec};

macro_rules! dependency_scan_passes {
    ($label:literal) => {
        PrefixScanGraphPasses {
            local: $label,
            hierarchy_up_first: concat!($label, ".hierarchy_up.first"),
            hierarchy_up_rest: concat!($label, ".hierarchy_up.rest"),
            hierarchy_down: concat!($label, ".hierarchy_down"),
            apply: concat!($label, ".apply"),
        }
    };
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) enum DependencyTypeIndexStage {
    ModulePaths,
    CallCollection,
    AfterTypeClear,
    TypeInstanceProjection,
    CallParamScatter,
    MethodProjection,
    CallValidation,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct DependencyTypeIndexPassNames {
    pub(in crate::type_checker) stage: DependencyTypeIndexStage,
    pub(in crate::type_checker) initialize: &'static str,
    pub(in crate::type_checker) jump_a_to_b: &'static str,
    pub(in crate::type_checker) jump_b_to_a: &'static str,
    pub(in crate::type_checker) jump_final_a_to_b: &'static str,
    pub(in crate::type_checker) clear_generic_arity: &'static str,
    pub(in crate::type_checker) count_generic_arity: &'static str,
}

pub(in crate::type_checker) const DEPENDENCY_TYPE_INDEX_MODULE_PATHS: DependencyTypeIndexPassNames =
    DependencyTypeIndexPassNames {
        stage: DependencyTypeIndexStage::ModulePaths,
        initialize: "type_check.dependencies.module_paths.type_index.initialize",
        jump_a_to_b: "type_check.dependencies.module_paths.type_index.jump.a_to_b",
        jump_b_to_a: "type_check.dependencies.module_paths.type_index.jump.b_to_a",
        jump_final_a_to_b: "type_check.dependencies.module_paths.type_index.jump.final_a_to_b",
        clear_generic_arity: "type_check.dependencies.module_paths.generic_arity.clear",
        count_generic_arity: "type_check.dependencies.module_paths.generic_arity.count",
    };

#[derive(Clone, Copy)]
pub(in crate::type_checker) enum DependencyPageStage {
    ModulePaths,
    CallCollection,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct DependencyPagePassNames {
    pub(in crate::type_checker) stage: DependencyPageStage,
    pub(in crate::type_checker) clear_module_lookup: &'static str,
    pub(in crate::type_checker) build_module_lookup: &'static str,
    pub(in crate::type_checker) resolve_imports: &'static str,
    pub(in crate::type_checker) count_import_visibility: &'static str,
    pub(in crate::type_checker) visible_scan: PrefixScanGraphPasses,
    pub(in crate::type_checker) scatter_import_visibility: &'static str,
    pub(in crate::type_checker) clear_visible_lookup: &'static str,
    pub(in crate::type_checker) build_visible_lookup: &'static str,
    pub(in crate::type_checker) resolve_type_paths: &'static str,
    pub(in crate::type_checker) resolve_value_paths: &'static str,
    pub(in crate::type_checker) type_index: DependencyTypeIndexPassNames,
    pub(in crate::type_checker) project_types: &'static str,
}

pub(in crate::type_checker) const DEPENDENCY_PAGE_MODULE_PATHS: DependencyPagePassNames =
    DependencyPagePassNames {
        stage: DependencyPageStage::ModulePaths,
        clear_module_lookup: DEPENDENCY_MODULE_LOOKUP_CLEAR.name,
        build_module_lookup: DEPENDENCY_MODULE_LOOKUP_BUILD.name,
        resolve_imports: DEPENDENCY_IMPORTS_RESOLVE.name,
        count_import_visibility: DEPENDENCY_IMPORT_VISIBILITY_COUNT.name,
        visible_scan: dependency_scan_passes!("type_check.dependencies.visible.scan"),
        scatter_import_visibility: DEPENDENCY_IMPORT_VISIBILITY_SCATTER.name,
        clear_visible_lookup: DEPENDENCY_VISIBLE_LOOKUP_CLEAR.name,
        build_visible_lookup: DEPENDENCY_VISIBLE_LOOKUP_BUILD.name,
        resolve_type_paths: DEPENDENCY_TYPE_PATHS_RESOLVE.name,
        resolve_value_paths: DEPENDENCY_VALUE_PATHS_RESOLVE.name,
        type_index: DEPENDENCY_TYPE_INDEX_MODULE_PATHS,
        project_types: DEPENDENCY_TYPES_PROJECT.name,
    };

pub(in crate::type_checker) const DEPENDENCY_TYPE_INDEX_CALL_COLLECTION:
    DependencyTypeIndexPassNames = DependencyTypeIndexPassNames {
    stage: DependencyTypeIndexStage::CallCollection,
    initialize: "type_check.dependencies.call_collection.type_index.initialize",
    jump_a_to_b: "type_check.dependencies.call_collection.type_index.jump.a_to_b",
    jump_b_to_a: "type_check.dependencies.call_collection.type_index.jump.b_to_a",
    jump_final_a_to_b: "type_check.dependencies.call_collection.type_index.jump.final_a_to_b",
    clear_generic_arity: "type_check.dependencies.call_collection.generic_arity.clear",
    count_generic_arity: "type_check.dependencies.call_collection.generic_arity.count",
};

macro_rules! dependency_type_index_names {
    ($name:ident, $stage:ident, $prefix:literal) => {
        pub(in crate::type_checker) const $name: DependencyTypeIndexPassNames =
            DependencyTypeIndexPassNames {
                stage: DependencyTypeIndexStage::$stage,
                initialize: concat!($prefix, ".type_index.initialize"),
                jump_a_to_b: concat!($prefix, ".type_index.jump.a_to_b"),
                jump_b_to_a: concat!($prefix, ".type_index.jump.b_to_a"),
                jump_final_a_to_b: concat!($prefix, ".type_index.jump.final_a_to_b"),
                clear_generic_arity: concat!($prefix, ".generic_arity.clear"),
                count_generic_arity: concat!($prefix, ".generic_arity.count"),
            };
    };
}

dependency_type_index_names!(
    DEPENDENCY_TYPE_INDEX_AFTER_TYPE_CLEAR,
    AfterTypeClear,
    "type_check.dependencies.after_type_clear"
);
dependency_type_index_names!(
    DEPENDENCY_TYPE_INDEX_TYPE_INSTANCE_PROJECTION,
    TypeInstanceProjection,
    "type_check.dependencies.type_instance_projection"
);
dependency_type_index_names!(
    DEPENDENCY_TYPE_INDEX_CALL_PARAM_SCATTER,
    CallParamScatter,
    "type_check.dependencies.call_param_scatter"
);
dependency_type_index_names!(
    DEPENDENCY_TYPE_INDEX_METHOD_PROJECTION,
    MethodProjection,
    "type_check.dependencies.method_projection"
);
dependency_type_index_names!(
    DEPENDENCY_TYPE_INDEX_CALL_VALIDATION,
    CallValidation,
    "type_check.dependencies.call_validation"
);

pub(in crate::type_checker) const DEPENDENCY_PAGE_CALL_COLLECTION: DependencyPagePassNames =
    DependencyPagePassNames {
        stage: DependencyPageStage::CallCollection,
        clear_module_lookup: "type_check.dependencies.call_collection.clear_module_lookup",
        build_module_lookup: "type_check.dependencies.call_collection.build_module_lookup",
        resolve_imports: "type_check.dependencies.call_collection.resolve_imports",
        count_import_visibility: "type_check.dependencies.call_collection.count_import_visibility",
        visible_scan: dependency_scan_passes!(
            "type_check.dependencies.call_collection.visible.scan"
        ),
        scatter_import_visibility: "type_check.dependencies.call_collection.scatter_import_visibility",
        clear_visible_lookup: "type_check.dependencies.call_collection.clear_visible_lookup",
        build_visible_lookup: "type_check.dependencies.call_collection.build_visible_lookup",
        resolve_type_paths: "type_check.dependencies.call_collection.resolve_type_paths",
        resolve_value_paths: "type_check.dependencies.call_collection.resolve_value_paths",
        type_index: DEPENDENCY_TYPE_INDEX_CALL_COLLECTION,
        project_types: "type_check.dependencies.call_collection.project_types",
    };

pub(in crate::type_checker) const DEPENDENCY_WORKSPACE_CLEAR: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.clear_workspace",
        Declarations,
        "type_checker/dependencies/00_clear_workspace"
    )
    .initializer();

pub(in crate::type_checker) const DEPENDENCY_MODULE_LOOKUP_CLEAR: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.clear_module_lookup",
        Declarations,
        "type_checker/dependencies/00a_clear_module_lookup"
    )
    .initializer();

pub(in crate::type_checker) const DEPENDENCY_MODULE_LOOKUP_BUILD: ReflectedComputeSpec = typecheck_pass!(
    "type_check.dependencies.build_module_lookup",
    Declarations,
    "type_checker/dependencies/00_build_module_lookup"
);

pub(in crate::type_checker) const DEPENDENCY_IMPORTS_RESOLVE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.resolve_imports",
        Declarations,
        "type_checker/dependencies/01_resolve_imports"
    )
    .with_initializes(&["import_target_dependency_module_id"])
    .with_indirect_dispatch("import_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_IMPORT_VISIBILITY_COUNT: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.count_import_visibility",
        Declarations,
        "type_checker/dependencies/02_count_import_visibility"
    )
    .with_indirect_dispatch("import_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_IMPORT_VISIBILITY_SCATTER: ReflectedComputeSpec = typecheck_pass!(
    "type_check.dependencies.scatter_import_visibility",
    Declarations,
    "type_checker/dependencies/03_scatter_import_visibility"
);

pub(in crate::type_checker) const DEPENDENCY_VISIBLE_LOOKUP_CLEAR: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.clear_visible_lookup",
        Declarations,
        "type_checker/dependencies/04_clear_visible_lookup"
    )
    .initializer();

pub(in crate::type_checker) const DEPENDENCY_VISIBLE_LOOKUP_BUILD: ReflectedComputeSpec = typecheck_pass!(
    "type_check.dependencies.build_visible_lookup",
    Declarations,
    "type_checker/dependencies/05_build_visible_lookup"
);

pub(in crate::type_checker) const DEPENDENCY_TYPE_PATHS_RESOLVE: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.dependencies.resolve_type_paths",
        Declarations,
        "type_checker/dependencies/06_resolve_paths"
        ; resources [
            typecheck_resource!("resolved_dependency_decl" => "dependency_resolved_type_decl"),
            typecheck_resource!("resolved_status" => "resolved_type_status"),
        ]
    )
    .with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_VALUE_PATHS_RESOLVE: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.dependencies.resolve_value_paths",
        Declarations,
        "type_checker/dependencies/06_resolve_paths"
        ; resources [
            typecheck_resource!("resolved_dependency_decl" => "dependency_resolved_value_decl"),
            typecheck_resource!("resolved_status" => "resolved_value_status"),
        ]
    )
    .with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_TYPES_PROJECT: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.dependencies.project_types",
        Declarations,
        "type_checker/dependencies/11_project_types"
        ; resources [
            typecheck_resource!("resolved_dependency_decl" => "dependency_resolved_type_decl"),
        ]
    )
    .with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_TYPES_PROJECT_AFTER_CLEAR: ReflectedComputeSpec =
    DEPENDENCY_TYPES_PROJECT.with_name("type_check.dependencies.project_types.after_type_clear");

pub(in crate::type_checker) const DEPENDENCY_TYPE_INSTANCES_PROJECT: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.project_type_instances",
        Declarations,
        "type_checker/dependencies/14_project_type_instances"
    )
    .with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_CALLS_PROJECT: ReflectedComputeSpec = typecheck_pass!(
    "type_check.dependencies.project_calls",
    Calls,
    "type_checker/dependencies/07_project_calls"
)
.with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_CALL_PARAMS_PROJECT: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.project_call_params",
        Calls,
        "type_checker/dependencies/07a_project_call_params"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_CALL_PARAMS_SCATTER: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.scatter_call_params",
        CallArguments,
        "type_checker/dependencies/07b_scatter_call_params"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_METHODS_PROJECT: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.project_methods",
        HirNodes,
        "type_checker/dependencies/15_project_methods"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_CALL_ARGS_VALIDATE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.validate_call_args",
        HirNodes,
        "type_checker/dependencies/08_validate_call_args"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_CALL_RESULTS_SUBSTITUTE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.validate_call_results.substitute",
        HirNodes,
        "type_checker/dependencies/08a_validate_call_results"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const DEPENDENCY_CALL_RESULTS_VALIDATE: ReflectedComputeSpec =
    DEPENDENCY_CALL_RESULTS_SUBSTITUTE
        .with_name("type_check.dependencies.validate_call_results.validate");

pub(in crate::type_checker) const DEPENDENCY_GENERIC_CALL_RESULTS_RESOLVE: ReflectedComputeSpec =
    DEPENDENCY_CALL_RESULTS_SUBSTITUTE
        .with_name("type_check.dependencies.resolve_generic_call_results");

pub(in crate::type_checker) const DEPENDENCY_CALL_COMPARE_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.dependencies.call_compare_dispatch_args",
    DispatchArguments,
    "type_checker/count/dispatch_args"
    ; resources [
        typecheck_resource!("count_in" => "dependency_call_compare_total", Read),
        typecheck_resource!(
            "dispatch_args" => "dependency_call_compare_dispatch_args", Write
        ),
    ]
);

pub(in crate::type_checker) const DEPENDENCY_CALL_TYPE_ARGS_VALIDATE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.dependencies.validate_call_type_args",
        HirNodes,
        "type_checker/dependencies/08b_validate_call_type_args"
    )
    .with_indirect_dispatch("dependency_call_compare_dispatch_args");
