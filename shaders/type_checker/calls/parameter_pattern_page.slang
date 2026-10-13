import dependency_interface;

// Parameter rows retain canonical indexes into their callable's immutable
// page. A reader must own that page before interpreting the pattern. Local
// parameter patterns already use checked references and need no page.
public bool parameter_pattern_page_contains(uint library, uint unit, uint declaration)
{
    return library == 0xffffffffu ||
        dependency_find_declaration(library, unit, declaration) != 0xffffffffu ||
        dependency_find_method(library, unit, declaration) != 0xffffffffu;
}
