// Continuation files of an instance-copy replay (InstanceSources in
// instance_copies.rs): source files after the template's that hold only
// copies of an earlier template file's bodies. Each belongs to the module of
// the template file it continues, with that module's imports. The section
// follows the impl bindings at BODY_CONTINUATION_ROW: a header row (file
// count, first continuation file, 0, 0) that every job rewrites, then the
// continued template file of each continuation, four per row.
// Requires body_specialization_inputs.
#ifndef LANIUS_FILE_CONTINUATIONS
#define LANIUS_FILE_CONTINUATIONS
#include "../type/instances/body_impl_bindings.slang"

static const uint BODY_CONTINUATION_ROW = BODY_IMPL_ARGUMENT_ROW + BODY_MAX_IMPL_ARGUMENTS;
static const uint BODY_MAX_CONTINUATION_FILES = 1024u;

uint body_continuation_count()
{
    uint rows; uint stride;
    body_specialization_inputs.GetDimensions(rows, stride);
    if (rows <= BODY_CONTINUATION_ROW) return 0u;
    uint fit = (rows - BODY_CONTINUATION_ROW - 1u) * 4u;
    return min(body_specialization_inputs[BODY_CONTINUATION_ROW].x, min(fit, BODY_MAX_CONTINUATION_FILES));
}

// The file id of continuation 0; continuation c is file first + c.
uint body_continuation_first_file()
{
    return body_specialization_inputs[BODY_CONTINUATION_ROW].y;
}

// The template file whose module continuation `continuation` continues.
uint body_continued_file(uint continuation)
{
    uint4 row = body_specialization_inputs[BODY_CONTINUATION_ROW + 1u + continuation / 4u];
    uint lane = continuation % 4u;
    return lane == 0u ? row.x : lane == 1u ? row.y : lane == 2u ? row.z : row.w;
}
#endif
