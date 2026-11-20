use crate::gpu::compiler_graph::{AccessMode, ReflectedComputeSpec};

pub(in crate::type_checker) const PATH_PROGRAM_FAILURE_COPY: &str =
    "type_check.modules.path_program_failure.copy";

pub(in crate::type_checker) const BUILD_PATH_TABLES: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.build_path_tables",
    HirNodes,
    "type_checker/modules/build_path_tables"
)
.with_aliases(&[typecheck_resource!(
    "step_program_sync" => "module_step_program_sync", ReadWrite
)])
.with_initializes(&["step_program_sync"])
.with_modes(&[
    ("module_record_family_bits", AccessMode::Write),
    ("path_id_by_owner_hir", AccessMode::Write),
    ("path_id_by_owner_token", AccessMode::Write),
    ("path_max_segment_count", AccessMode::Write),
    ("resolved_value_type_qualifier_token", AccessMode::Write),
    ("resolved_value_qualifier_binding", AccessMode::Write),
    ("path_owner_hir", AccessMode::Write),
    ("path_len", AccessMode::Write),
    ("path_call_hir", AccessMode::Write),
    ("path_owner_token", AccessMode::Write),
    ("path_kind", AccessMode::Write),
    ("path_count_out", AccessMode::Write),
    ("path_dispatch_args", AccessMode::Write),
    ("path_segment_base", AccessMode::Write),
    ("path_segment_count", AccessMode::Write),
    ("path_segment_count_out", AccessMode::Write),
    ("path_segment_name_id", AccessMode::Write),
    ("path_segment_token", AccessMode::Write),
    ("path_prefix_base", AccessMode::Write),
    ("path_prefix_id_a", AccessMode::Write),
    ("path_prefix_id_b", AccessMode::Write),
    ("path_prefix_table_state", AccessMode::Write),
]);

pub(in crate::type_checker) const RECORD_PROGRAM_FAILURE_COPY: &str =
    "type_check.modules.record_program_failure.copy";

pub(in crate::type_checker) const COMPACT_RECORDS: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.compact_records",
    HirNodes,
    "type_checker/modules/compact_records"
)
.with_aliases(&[typecheck_resource!(
    "step_program_sync" => "module_step_program_sync", ReadWrite
)])
.with_initializes(&["step_program_sync"])
.with_modes(&[
    ("module_file_id", AccessMode::Write),
    ("module_path_id", AccessMode::Write),
    ("module_owner_hir", AccessMode::Write),
    ("import_module_file_id", AccessMode::Write),
    ("import_path_id", AccessMode::Write),
    ("import_kind", AccessMode::Write),
    ("import_owner_hir", AccessMode::Write),
    ("decl_module_file_id", AccessMode::Write),
    ("decl_name_id", AccessMode::Write),
    ("decl_kind", AccessMode::Write),
    ("decl_namespace", AccessMode::Write),
    ("decl_visibility", AccessMode::Write),
    ("decl_hir_node", AccessMode::Write),
    ("decl_parent_type_decl", AccessMode::Write),
    ("decl_name_token", AccessMode::Write),
    ("decl_token_start", AccessMode::Write),
    ("decl_token_end", AccessMode::Write),
    ("decl_id_by_name_token", AccessMode::Write),
    ("module_record_family_flag", AccessMode::Write),
    ("module_record_prefix", AccessMode::Write),
    ("decl_count_out", AccessMode::Write),
    ("module_record_count_out", AccessMode::Write),
    ("import_record_count_out", AccessMode::Write),
    ("record_scan_group_sums", AccessMode::Write),
]);

pub(in crate::type_checker) const MODULE_LOOKUP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.clear_module_lookup",
    Declarations,
    "type_checker/modules/clear_module_lookup";
    writes ["module_by_canonical_id"]
);

pub(in crate::type_checker) const MODULE_KEYS_BUILD: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.build_module_keys",
    Declarations,
    "type_checker/modules/build_module_keys";
    writes [
        "module_status",
        "module_key_canonical_id",
        "module_key_segment_count",
        "module_key_segment_base",
    ]
);

pub(in crate::type_checker) const MODULE_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.module_dispatch_args",
    DispatchArguments,
    "type_checker/conditions/write_count_dispatch_args"
    ; resources [
        typecheck_resource!("count_in" => "module_count_out", Read),
        typecheck_resource!("dispatch_args" => "module_dispatch_args", Write),
    ]
);

pub(in crate::type_checker) const MODULES_VALIDATE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.validate_modules",
    Declarations,
    "type_checker/modules/validate_module_records"
)
.with_indirect_dispatch("module_dispatch_args");

pub(in crate::type_checker) const IMPORT_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_dispatch_args",
    DispatchArguments,
    "type_checker/conditions/write_count_dispatch_args"
    ; resources [
        typecheck_resource!("count_in" => "import_record_count_out", Read),
        typecheck_resource!("dispatch_args" => "import_dispatch_args", Write),
    ]
);

pub(in crate::type_checker) const DECL_KEY_RADIX_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.decl_key_radix_dispatch_args",
    DispatchArguments,
    "radix/write_radix_dispatch_args"
    ; resources [
        typecheck_resource!("name_count_in" => "decl_count_out", Read),
        typecheck_resource!("radix_dispatch_args" => "decl_key_radix_dispatch_args", Write),
    ]
);

pub(in crate::type_checker) const DECLS_VALIDATE: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.validate_decls",
    Declarations,
    "type_checker/modules/declarations/validate_decls"
    ; resources [
        typecheck_resource!("decl_status" => "decl_status", Write),
        typecheck_resource!(
            "decl_duplicate_of" => "type_decl_generic_param_count_by_owner_token",
            Write
        ),
    ]
)
.with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const DECL_NAMESPACE_MARK: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.decl_namespace.mark",
    Declarations,
    "type_checker/modules/declarations/mark_decl_namespace_keys"
    ; resources [
        typecheck_resource!("sorted_decl_key_order" => "decl_key_to_decl_id"),
        typecheck_resource!("decl_type_key_flag" => "type_instance_arg_ref_tag", Write),
        typecheck_resource!("decl_value_key_flag" => "type_instance_arg_ref_payload", Write),
    ]
)
.with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const DECL_NAMESPACE_SCATTER: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.decl_namespace.scatter",
        Declarations,
        "type_checker/modules/declarations/scatter_decl_namespace_keys"
        ; writes ["decl_type_key_to_decl_id", "decl_value_key_to_decl_id"]
        ; resources [
            typecheck_resource!("sorted_decl_key_order" => "decl_key_to_decl_id"),
            typecheck_resource!("decl_type_key_flag" => "type_instance_arg_ref_tag", Read),
            typecheck_resource!("decl_value_key_flag" => "type_instance_arg_ref_payload", Read),
        ]
    )
    .with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const DECL_LOOKUP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.declarations.clear_lookup",
    Declarations,
    "type_checker/modules/declarations/clear_decl_lookup";
    writes ["decl_lookup_state"]
);
pub(in crate::type_checker) const DECL_LOOKUP_BUILD: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.declarations.build_lookup",
    Declarations,
    "type_checker/modules/declarations/build_decl_lookup";
    resources [typecheck_resource!("decl_lookup_state" => "decl_lookup_state", ReadWrite)]
)
.with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const DECL_DUPLICATES_VALIDATE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.decl_namespace.validate_duplicates",
    Declarations,
    "type_checker/modules/declarations/validate_decl_duplicates"
)
.with_aliases(&[typecheck_resource!(
    "decl_duplicate_of" => "type_decl_generic_param_count_by_owner_token",
    Write
)])
.with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const DECL_PUBLIC_MARK: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.decl_public.mark",
    Declarations,
    "type_checker/modules/declarations/mark_public_decl_keys"
    ; resources [
        typecheck_resource!("decl_type_public_flag" => "type_instance_arg_ref_tag", Write),
        typecheck_resource!("decl_value_public_flag" => "type_instance_arg_ref_payload", Write),
    ]
)
.with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const INTERFACE_PUBLIC_DECLS_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.interface.public_decls.clear",
    Declarations,
    "type_checker/interface/declarations/clear_interface_declaration_map";
    writes [
        "interface_public_decl_count",
        "interface_public_decl_local_id",
        "interface_public_decl_index_by_local",
        "interface_public_decl_index_by_hir",
    ]
);

pub(in crate::type_checker) const INTERFACE_PUBLIC_DECLS_MAP: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.interface.public_decls.map",
        Declarations,
        "type_checker/interface/declarations/map_public_interface_declarations"
    )
    .with_aliases(&[
        typecheck_resource!("decl_type_public_flag" => "type_instance_arg_ref_tag", Read),
        typecheck_resource!("decl_value_public_flag" => "type_instance_arg_ref_payload", Read),
        typecheck_resource!("decl_type_public_prefix" => "decl_status", Read),
        typecheck_resource!(
            "decl_value_public_prefix" => "type_decl_generic_param_count_by_owner_token",
            Read
        ),
    ])
    .with_indirect_dispatch("decl_key_radix_dispatch_args");

pub(in crate::type_checker) const FILE_MODULE_MAP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.file_module_map.clear",
    Declarations,
    "type_checker/modules/clear_file_module_map"
    ; writes ["module_id_by_file_id", "decl_module_id", "import_module_id", "path_owner_module_id"]
    ; resources [typecheck_resource!("import_count_out" => "import_record_count_out", Read)]
);

pub(in crate::type_checker) const FILE_MODULE_MAP_BUILD: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.file_module_map.build",
        Declarations,
        "type_checker/modules/build_file_module_map"
        ; writes ["module_id_by_file_id"]
    )
    .with_indirect_dispatch("module_dispatch_args");

pub(in crate::type_checker) const ATTACH_RECORD_MODULES: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.records.attach_modules",
    Declarations,
    "type_checker/modules/attach_record_modules"
    ; writes ["decl_module_id", "import_module_id", "path_owner_module_id"]
    ; resources [
        typecheck_resource!("import_count_out" => "import_record_count_out", Read),
        typecheck_resource!("module_count_out" => "module_record_count_out", Read),
    ]
);

pub(in crate::type_checker) const RESOLVE_IMPORTS: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.imports.resolve",
    Declarations,
    "type_checker/modules/imports/resolve_module_imports"
    ; writes ["import_target_module_id", "import_item_name_id", "import_status"]
    ; resources [
        typecheck_resource!("status" => "status", ReadWrite),
        typecheck_resource!("import_count_out" => "import_record_count_out", Read),
    ]
)
.with_indirect_dispatch("import_dispatch_args");

pub(in crate::type_checker) const IMPORT_EDGE_SET_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_edges.clear",
    Declarations,
    "type_checker/modules/imports/clear_import_edge_set";
    writes ["import_edge_set_state"]
);

pub(in crate::type_checker) const IMPORT_EDGE_SET_BUILD: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.import_edges.build",
        Declarations,
        "type_checker/modules/imports/build_import_edge_set";
        resources [
            typecheck_resource!("import_count_out" => "import_record_count_out", Read),
            typecheck_resource!("import_edge_set_state" => "import_edge_set_state", ReadWrite),
        ]
    )
    .with_indirect_dispatch("import_dispatch_args");

pub(in crate::type_checker) const IMPORT_CYCLES_VALIDATE: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.import_cycles.validate",
        Declarations,
        "type_checker/modules/imports/validate_import_cycles";
        resources [
            typecheck_resource!("import_count_out" => "import_record_count_out", Read),
            typecheck_resource!("import_status" => "import_status", ReadWrite),
            typecheck_resource!("status" => "status", ReadWrite),
        ]
    )
    .with_indirect_dispatch("import_dispatch_args");

pub(in crate::type_checker) const IMPORT_VISIBILITY_COUNT: ReflectedComputeSpec =
    typecheck_operation!(
        "type_check.modules.import_visibility.count",
        Declarations,
        "type_checker/modules/imports/count_import_visibility"
        ; writes ["import_visible_type_count", "import_visible_value_count"]
        ; resources [
            typecheck_resource!("import_count_out" => "import_record_count_out", Read),
            typecheck_resource!("decl_type_public_flag" => "type_instance_arg_ref_tag", Read),
            typecheck_resource!("decl_value_public_flag" => "type_instance_arg_ref_payload", Read),
            typecheck_resource!("decl_type_public_prefix" => "decl_status", Read),
            typecheck_resource!(
                "decl_value_public_prefix" => "type_decl_generic_param_count_by_owner_token", Read
            ),
        ]
    )
    .with_indirect_dispatch("import_dispatch_args");

pub(in crate::type_checker) const IMPORT_VISIBLE_DISPATCH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_visible_dispatch_args",
    DispatchArguments,
    "type_checker/conditions/write_max_count_dispatch_args"
    ; resources [
        typecheck_resource!("left_count_in" => "import_visible_type_count_out", Read),
        typecheck_resource!("right_count_in" => "import_visible_value_count_out", Read),
        typecheck_resource!("dispatch_args" => "import_visible_validate_dispatch_args", Write),
    ]
);

const IMPORT_VISIBLE_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count" => "import_visible_type_count", Read),
    typecheck_resource!("import_visible_count_out" => "import_visible_type_count_out", Read),
    typecheck_resource!("import_visible_prefix" => "import_visible_type_prefix", Read),
    typecheck_resource!("decl_key_count_out" => "decl_type_key_count_out", Read),
    typecheck_resource!("decl_key_to_decl_id" => "decl_type_key_to_decl_id", Read),
    typecheck_resource!("decl_public_flag" => "type_instance_arg_ref_tag", Read),
    typecheck_resource!("decl_public_prefix" => "decl_status", Read),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_type_key_module_id", Write),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_type_key_name_id", Write),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_type_key_to_decl_id", Write),
];
const IMPORT_VISIBLE_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count" => "import_visible_value_count", Read),
    typecheck_resource!("import_visible_count_out" => "import_visible_value_count_out", Read),
    typecheck_resource!("import_visible_prefix" => "import_visible_value_prefix", Read),
    typecheck_resource!("decl_key_count_out" => "decl_value_key_count_out", Read),
    typecheck_resource!("decl_key_to_decl_id" => "decl_value_key_to_decl_id", Read),
    typecheck_resource!("decl_public_flag" => "type_instance_arg_ref_payload", Read),
    typecheck_resource!(
        "decl_public_prefix" => "type_decl_generic_param_count_by_owner_token", Read
    ),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_value_key_module_id", Write),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_value_key_name_id", Write),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_value_key_to_decl_id", Write),
];

pub(in crate::type_checker) const IMPORT_VISIBLE_TYPE_SCATTER: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.scatter_type",
        Declarations,
        "type_checker/modules/imports/scatter_import_visibility"
    )
    .with_aliases(IMPORT_VISIBLE_TYPE_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");
pub(in crate::type_checker) const IMPORT_VISIBLE_VALUE_SCATTER: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.scatter_value",
        Declarations,
        "type_checker/modules/imports/scatter_import_visibility"
    )
    .with_aliases(IMPORT_VISIBLE_VALUE_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");

const IMPORT_VISIBLE_TYPE_LOOKUP_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count_out" => "import_visible_type_count_out", Read),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_type_key_module_id", Read),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_type_key_name_id", Read),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_type_key_to_decl_id", Read),
    typecheck_resource!("import_visible_lookup_state" => "import_visible_type_lookup_state", ReadWrite),
];
const IMPORT_VISIBLE_VALUE_LOOKUP_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] =
    &[
        typecheck_resource!("import_visible_count_out" => "import_visible_value_count_out", Read),
        typecheck_resource!("import_visible_key_module_id" => "import_visible_value_key_module_id", Read),
        typecheck_resource!("import_visible_key_name_id" => "import_visible_value_key_name_id", Read),
        typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_value_key_to_decl_id", Read),
        typecheck_resource!("import_visible_lookup_state" => "import_visible_value_lookup_state", ReadWrite),
    ];

pub(in crate::type_checker) const IMPORT_VISIBLE_TYPE_LOOKUP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_visibility.clear_type_lookup",
    Declarations,
    "type_checker/modules/imports/clear_import_visible_lookup";
    resources [typecheck_resource!("import_visible_lookup_state" => "import_visible_type_lookup_state", Write)]
);
pub(in crate::type_checker) const IMPORT_VISIBLE_VALUE_LOOKUP_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.import_visibility.clear_value_lookup",
    Declarations,
    "type_checker/modules/imports/clear_import_visible_lookup";
    resources [typecheck_resource!("import_visible_lookup_state" => "import_visible_value_lookup_state", Write)]
);
pub(in crate::type_checker) const IMPORT_VISIBLE_TYPE_LOOKUP_BUILD: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.build_type_lookup",
        Declarations,
        "type_checker/modules/imports/build_import_visible_key_tables"
    )
    .with_aliases(IMPORT_VISIBLE_TYPE_LOOKUP_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");
pub(in crate::type_checker) const IMPORT_VISIBLE_VALUE_LOOKUP_BUILD: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.build_value_lookup",
        Declarations,
        "type_checker/modules/imports/build_import_visible_key_tables"
    )
    .with_aliases(IMPORT_VISIBLE_VALUE_LOOKUP_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");
const IMPORT_VISIBLE_STATUS_INITIALIZE_ALIASES:
    &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_type_status" => "import_visible_type_status", Write),
    typecheck_resource!("import_visible_type_duplicate_of" => "import_visible_type_duplicate_of", Write),
    typecheck_resource!("import_visible_value_status" => "import_visible_value_status", Write),
    typecheck_resource!("import_visible_value_duplicate_of" => "import_visible_value_duplicate_of", Write),
];
const IMPORT_VISIBLE_STATUS_VALIDATE_ALIASES:
    &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_type_status" => "import_visible_type_status", ReadWrite),
    typecheck_resource!("import_visible_type_duplicate_of" => "import_visible_type_duplicate_of", ReadWrite),
    typecheck_resource!("import_visible_value_status" => "import_visible_value_status", ReadWrite),
    typecheck_resource!("import_visible_value_duplicate_of" => "import_visible_value_duplicate_of", ReadWrite),
];
pub(in crate::type_checker) const IMPORT_VISIBLE_STATUS_INITIALIZE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.initialize_status",
        Declarations,
        "type_checker/modules/imports/validate_import_visible_keys"
    )
    .with_aliases(IMPORT_VISIBLE_STATUS_INITIALIZE_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");
pub(in crate::type_checker) const IMPORT_VISIBLE_AMBIGUITY_VALIDATE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.import_visibility.validate_ambiguity",
        Declarations,
        "type_checker/modules/imports/validate_import_visible_keys"
    )
    .with_aliases(IMPORT_VISIBLE_STATUS_VALIDATE_ALIASES)
    .with_indirect_dispatch("import_visible_validate_dispatch_args");

const RESOLVE_LOCAL_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("resolved_decl" => "resolved_type_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_type_status", Write),
];
const RESOLVE_LOCAL_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("resolved_decl" => "resolved_value_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_value_status", Write),
];

pub(in crate::type_checker) const RESOLVE_LOCAL_TYPE_PATHS: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.paths.resolve_local_type",
    HirNodes,
    "type_checker/modules/paths/resolve_local_paths"
)
.with_aliases(RESOLVE_LOCAL_TYPE_ALIASES)
.with_indirect_dispatch("path_dispatch_args");
pub(in crate::type_checker) const RESOLVE_LOCAL_VALUE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_local_value",
        HirNodes,
        "type_checker/modules/paths/resolve_local_paths"
    )
    .with_aliases(RESOLVE_LOCAL_VALUE_ALIASES)
    .with_indirect_dispatch("path_dispatch_args");

const RESOLVE_IMPORTED_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count_out" => "import_visible_type_count_out", Read),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_type_key_module_id", Read),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_type_key_name_id", Read),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_type_key_to_decl_id", Read),
    typecheck_resource!("import_visible_status" => "import_visible_type_status", Read),
    typecheck_resource!("import_visible_lookup_state" => "import_visible_type_lookup_state", Read),
    typecheck_resource!("resolved_decl" => "resolved_type_decl", ReadWrite),
    typecheck_resource!("resolved_status" => "resolved_type_status", ReadWrite),
];
const RESOLVE_IMPORTED_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_visible_count_out" => "import_visible_value_count_out", Read),
    typecheck_resource!("import_visible_key_module_id" => "import_visible_value_key_module_id", Read),
    typecheck_resource!("import_visible_key_name_id" => "import_visible_value_key_name_id", Read),
    typecheck_resource!("import_visible_key_to_decl_id" => "import_visible_value_key_to_decl_id", Read),
    typecheck_resource!("import_visible_status" => "import_visible_value_status", Read),
    typecheck_resource!("import_visible_lookup_state" => "import_visible_value_lookup_state", Read),
    typecheck_resource!("resolved_decl" => "resolved_value_decl", ReadWrite),
    typecheck_resource!("resolved_status" => "resolved_value_status", ReadWrite),
];

pub(in crate::type_checker) const RESOLVE_IMPORTED_TYPE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_imported_type",
        HirNodes,
        "type_checker/modules/paths/resolve_imported_paths"
    )
    .with_aliases(RESOLVE_IMPORTED_TYPE_ALIASES)
    .with_indirect_dispatch("path_dispatch_args");
pub(in crate::type_checker) const RESOLVE_IMPORTED_VALUE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_imported_value",
        HirNodes,
        "type_checker/modules/paths/resolve_imported_paths"
    )
    .with_aliases(RESOLVE_IMPORTED_VALUE_ALIASES)
    .with_indirect_dispatch("path_dispatch_args");

const RESOLVE_QUALIFIED_TYPE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_count_out" => "import_record_count_out", Read),
    typecheck_resource!("resolved_decl" => "resolved_type_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_type_status", Write),
];
const RESOLVE_QUALIFIED_VALUE_ALIASES: &[crate::gpu::compiler_graph::ReflectedResourceAlias] = &[
    typecheck_resource!("import_count_out" => "import_record_count_out", Read),
    typecheck_resource!("resolved_decl" => "resolved_value_decl", Write),
    typecheck_resource!("resolved_status" => "resolved_value_status", Write),
];

pub(in crate::type_checker) const RESOLVE_QUALIFIED_TYPE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_qualified_type",
        HirNodes,
        "type_checker/modules/paths/resolve_qualified_paths"
    )
    .with_aliases(RESOLVE_QUALIFIED_TYPE_ALIASES)
    .with_indirect_dispatch("path_dispatch_args");
pub(in crate::type_checker) const RESOLVE_QUALIFIED_VALUE_PATHS: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.paths.resolve_qualified_value",
        HirNodes,
        "type_checker/modules/paths/resolve_qualified_paths"
    )
    .with_aliases(RESOLVE_QUALIFIED_VALUE_ALIASES)
    .with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const TYPE_PATH_STATE_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.modules.clear_type_path_types",
    Tokens,
    "type_checker/modules/paths/clear_type_path_types";
    writes [
        "module_type_path_type",
        "module_type_path_status",
        "module_value_path_expr_head",
        "module_value_path_call_head",
        "module_value_path_call_open",
        "module_value_path_call_path_id",
        "module_value_path_call_leaf",
        "module_value_path_associated_method_token",
        "module_value_path_associated_receiver_token",
        "module_value_path_const_head",
        "module_value_path_const_end",
        "module_value_path_status",
    ]
);

const fn type_path_projection(name: &'static str) -> ReflectedComputeSpec {
    typecheck_pass!(
        name,
        HirNodes,
        "type_checker/modules/paths/project_type_paths"
    )
    .with_indirect_dispatch("path_dispatch_args")
}

pub(in crate::type_checker) const TYPE_PATHS_PROJECT: ReflectedComputeSpec =
    type_path_projection("type_check.modules.project_type_paths").with_modes(&[
        ("type_expr_ref_tag", AccessMode::Write),
        ("type_expr_ref_payload", AccessMode::Write),
    ]);
pub(in crate::type_checker) const TYPE_PATHS_PROJECT_AFTER_ALIASES: ReflectedComputeSpec =
    type_path_projection("type_check.modules.project_type_paths.after_aliases");
pub(in crate::type_checker) const TYPE_PATHS_PROJECT_AFTER_PROJECTED_ALIASES: ReflectedComputeSpec =
    type_path_projection("type_check.modules.project_type_paths.after_projected_aliases");
pub(in crate::type_checker) const TYPE_PATHS_PROJECT_AFTER_ALIAS_EQUIVALENCE: ReflectedComputeSpec =
    type_path_projection("type_check.modules.project_type_paths.after_alias_equivalence");

pub(in crate::type_checker) const TYPE_ALIASES_NORMALIZE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.normalize_type_aliases",
        Tokens,
        "type_checker/modules/paths/normalize_type_aliases"
    )
    .with_indirect_dispatch("token_active_dispatch_args");
pub(in crate::type_checker) const TYPE_ALIAS_INSTANCES_PROJECT: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.project_type_alias_instances",
        Tokens,
        "type_checker/modules/paths/project_type_alias_instances"
    )
    .with_indirect_dispatch("token_active_dispatch_args");

pub(in crate::type_checker) const NORMALIZED_VALUE_MEMBERS_RESOLVE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.resolve_normalized_value_members",
        HirNodes,
        "type_checker/modules/values/resolve_normalized_value_members"
    )
    .with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const TYPE_INSTANCES_PROJECT: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.project_type_instances",
    HirNodes,
    "type_checker/modules/paths/project_type_instances"
)
.with_indirect_dispatch("path_dispatch_args");

/// Private types an exported type's fields need become hidden interface
/// declarations before the canonical early stage. One lane per field and
/// payload row marks them (mark_hidden_interface_declarations); per-block counts (count_hidden_interface_declarations)
/// let every block publish its indices (publish_hidden_interface_declarations).
pub(in crate::type_checker) const INTERFACE_HIDDEN_DECLS_MAP: ReflectedComputeSpec = typecheck_operation!(
    "type_check.interface.public_decls.hidden",
    Declarations,
    "type_checker/interface/declarations/mark_hidden_interface_declarations"
    ; resources [
        typecheck_resource!("interface_public_decl_index_by_local" => "interface_public_decl_index_by_local", ReadWrite),
        typecheck_resource!("interface_public_decl_index_by_hir" => "interface_public_decl_index_by_hir", ReadWrite),
    ]
);

pub(in crate::type_checker) const INTERFACE_HIDDEN_DECLS_COUNT: ReflectedComputeSpec = typecheck_operation!(
    "type_check.interface.public_decls.hidden_count",
    Declarations,
    "type_checker/interface/declarations/count_hidden_interface_declarations"
    ; resources [
        typecheck_resource!("interface_public_decl_count" => "interface_public_decl_count", Read),
        typecheck_resource!("interface_public_decl_index_by_local" => "interface_public_decl_index_by_local", Read),
        typecheck_resource!("interface_hidden_block_count" => "interface_hidden_block_count", Write),
    ]
);

pub(in crate::type_checker) const INTERFACE_HIDDEN_DECLS_PUBLISH: ReflectedComputeSpec = typecheck_operation!(
    "type_check.interface.public_decls.hidden_publish",
    Declarations,
    "type_checker/interface/declarations/publish_hidden_interface_declarations"
    ; resources [
        typecheck_resource!("interface_hidden_block_count" => "interface_hidden_block_count", Read),
        typecheck_resource!("status" => "status", ReadWrite),
        typecheck_resource!("interface_public_decl_count" => "interface_public_decl_count", ReadWrite),
        typecheck_resource!("interface_public_decl_local_id" => "interface_public_decl_local_id", ReadWrite),
        typecheck_resource!("interface_public_decl_index_by_local" => "interface_public_decl_index_by_local", ReadWrite),
        typecheck_resource!("interface_public_decl_index_by_hir" => "interface_public_decl_index_by_hir", ReadWrite),
    ]
);

pub(in crate::type_checker) const VALUE_CALL_PATHS_MARK: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.mark_value_call_paths",
    HirNodes,
    "type_checker/modules/values/mark_value_call_paths"
);

pub(in crate::type_checker) const VALUE_PATHS_PROJECT: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.project_value_paths",
    HirNodes,
    "type_checker/modules/values/project_value_paths"
)
.with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const TYPE_PATHS_VALIDATE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.validate_type_paths",
    HirNodes,
    "type_checker/modules/paths/validate_type_paths"
)
.with_indirect_dispatch("path_dispatch_args");

const fn consume_value_calls(name: &'static str) -> ReflectedComputeSpec {
    typecheck_pass!(
        name,
        HirNodes,
        "type_checker/modules/values/bind_value_path_calls"
    )
    .with_indirect_dispatch("path_dispatch_args")
}

const fn mirror_value_call_leaf(name: &'static str) -> ReflectedComputeSpec {
    typecheck_pass!(
        name,
        HirNodes,
        "type_checker/modules/values/mirror_value_call_to_callee_leaf"
    )
    .with_indirect_dispatch("path_dispatch_args")
}

pub(in crate::type_checker) const VALUE_CALLS_CONSUME: ReflectedComputeSpec =
    consume_value_calls("type_check.modules.consume_value_calls");
pub(in crate::type_checker) const VALUE_CALL_LEAF_MIRROR: ReflectedComputeSpec =
    mirror_value_call_leaf("type_check.modules.mirror_value_call_leaf");
pub(in crate::type_checker) const VALUE_CALL_LEAF_MIRROR_AFTER_ROW_ARGS: ReflectedComputeSpec =
    mirror_value_call_leaf("type_check.modules.mirror_value_call_leaf_after_module_row_args");
pub(in crate::type_checker) const VALUE_CALLS_CONSUME_AFTER_METHODS: ReflectedComputeSpec =
    consume_value_calls("type_check.modules.consume_value_calls_after_methods");
pub(in crate::type_checker) const VALUE_CALL_LEAF_MIRROR_AFTER_METHODS: ReflectedComputeSpec =
    mirror_value_call_leaf("type_check.modules.mirror_value_call_leaf_after_methods");
pub(in crate::type_checker) const VALUE_CALL_LEAF_MIRROR_AFTER_METHOD_ROW_ARGS:
    ReflectedComputeSpec = mirror_value_call_leaf(
    "type_check.modules.mirror_value_call_leaf_after_methods_module_row_args",
);
pub(in crate::type_checker) const VALUE_CONSTS_CONSUME: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.consume_value_consts",
    HirNodes,
    "type_checker/modules/values/bind_value_path_constants"
)
.with_indirect_dispatch("path_dispatch_args");
pub(in crate::type_checker) const VALUE_ENUM_UNITS_CONSUME: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.consume_value_enum_units",
    HirNodes,
    "type_checker/modules/values/bind_value_path_enum_units"
)
.with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const VALUE_ENUM_UNITS_CONSUME_INFERENCE: ReflectedComputeSpec =
    VALUE_ENUM_UNITS_CONSUME.with_name("type_check.modules.consume_value_enum_units.inference");
pub(in crate::type_checker) const VALUE_ENUM_UNITS_CONSUME_AFTER_INFERENCE: ReflectedComputeSpec =
    VALUE_ENUM_UNITS_CONSUME.with_name("type_check.modules.consume_value_enum_units.after_inference");

pub(in crate::type_checker) const MATCH_PATTERNS_BIND: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.bind_match_patterns",
    HirNodes,
    "type_checker/matches/bind_match_patterns"
)
.with_indirect_dispatch("match_hir_dispatch_args");

pub(in crate::type_checker) const MATCH_IMPORTED_UNIT_PATTERNS_VALIDATE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.validate_imported_unit_patterns",
        HirNodes,
        "type_checker/matches/validate_imported_unit_patterns"
    )
    .with_indirect_dispatch("match_hir_dispatch_args");

pub(in crate::type_checker) const MATCH_EXHAUSTIVE_VALIDATE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.validate_match_exhaustive",
        HirNodes,
        "type_checker/matches/validate_match_exhaustive"
    )
    .with_indirect_dispatch("match_hir_dispatch_args");

pub(in crate::type_checker) const MATCH_PAYLOADS_TYPE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.type_match_payloads",
    HirNodes,
    "type_checker/matches/type_match_payloads"
)
.with_indirect_dispatch("match_hir_dispatch_args");

pub(in crate::type_checker) const MATCH_PAYLOADS_TYPE_INFERENCE: ReflectedComputeSpec =
    MATCH_PAYLOADS_TYPE.with_name("type_check.modules.type_match_payloads.inference");

pub(in crate::type_checker) const MATCH_PAYLOADS_TYPE_AFTER_CALLS: ReflectedComputeSpec =
    MATCH_PAYLOADS_TYPE.with_name("type_check.modules.type_match_payloads.after_calls");

pub(in crate::type_checker) const VALUE_ENUM_CALLS_CONSUME: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.consume_value_enum_calls",
    HirNodes,
    "type_checker/modules/values/bind_value_path_enum_calls"
)
.with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const VALUE_ENUM_CALLS_FINALIZE: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.modules.finalize_value_enum_calls",
        HirNodes,
        "type_checker/modules/values/finalize_value_enum_calls"
    )
    .with_indirect_dispatch("path_dispatch_args");

pub(in crate::type_checker) const VALUE_ENUM_CALLS_CONSUME_AFTER_INFERENCE: ReflectedComputeSpec =
    VALUE_ENUM_CALLS_CONSUME
        .with_name("type_check.modules.consume_value_enum_calls.after_inference");
pub(in crate::type_checker) const VALUE_ENUM_CALLS_FINALIZE_AFTER_INFERENCE: ReflectedComputeSpec =
    VALUE_ENUM_CALLS_FINALIZE
        .with_name("type_check.modules.finalize_value_enum_calls.after_inference");

pub(in crate::type_checker) const MATCH_EXPRS_TYPE: ReflectedComputeSpec = typecheck_pass!(
    "type_check.modules.type_match_exprs",
    HirNodes,
    "type_checker/matches/type_match_exprs"
)
.with_indirect_dispatch("hir_active_dispatch_args");

pub(in crate::type_checker) const MATCH_EXPRS_TYPE_INFERENCE: ReflectedComputeSpec =
    MATCH_EXPRS_TYPE.with_name("type_check.modules.type_match_exprs.inference");
