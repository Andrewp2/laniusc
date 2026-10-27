# Bash 5.2 + bash-completion 2.11 adapter for explicitly opted-in programs.
# Source bash-completion first, source this file, then call:
#   lanius_completion_register /path/to/program
# No user text is evaluated. The program implements the versioned NUL protocol.

# Read one bounded record into the dynamically scoped _lc_record. Callers use
# LC_ALL=C here, after the locale-sensitive cursor helper has finished.
_lanius_completion_record()
{
    _lc_record=
    ((SECONDS < _lc_deadline)) || return 1
    IFS= read -r -d '' -n 4097 -t 2 -u "$_lc_fd" _lc_record || return 1
    ((${#_lc_record} <= 4096)) || return 1
    ((_lc_bytes += ${#_lc_record} + 1))
    ((_lc_bytes <= 32768))
}

# Own the deadline sleep inside this subprocess. Cancellation must reap that
# child too, including a signal between starting sleep and assigning its PID.
_lanius_completion_watchdog()
{
    set +e +u
    local _lc_target=$1 _lc_sleeper=
    trap '
        trap "" TERM INT HUP
        _lc_sleeper=${_lc_sleeper:-$!}
        if [ -n "$_lc_sleeper" ]; then
            kill -KILL "$_lc_sleeper" 2>/dev/null || :
            wait "$_lc_sleeper" 2>/dev/null || :
        fi
        exit 0
    ' TERM INT HUP
    command sleep 2 &
    _lc_sleeper=$!
    # Any uncancelled timer completion fails closed, including a missing or
    # failing sleep command. Only the cancellation trap avoids this kill.
    wait "$_lc_sleeper" 2>/dev/null || :
    kill -KILL "$_lc_target" 2>/dev/null || :
}

# Capture every record, EOF and child status before publishing any candidate.
# _lc_frame belongs to the calling callback. Pipe/process descriptors and the
# deadline job are retired on both success and failure.
_lanius_completion_capture()
{
    local _lc_fd _lc_pid _lc_timer _lc_timer_fd _lc_status _lc_record
    local _lc_bytes=0 _lc_deadline=$((SECONDS + 8)) _lc_ok=1 _lc_i _lc_count
    _lc_frame=()
    if ! exec {_lc_fd}< <("$@" 2>/dev/null); then return 1; fi
    _lc_pid=$!
    for ((_lc_i = 0; _lc_i < 9; ++_lc_i)); do
        if ! _lanius_completion_record; then _lc_ok=0; break; fi
        _lc_frame+=("$_lc_record")
    done
    if ((_lc_ok)); then
        [ "${_lc_frame[0]}" = lanius-completion-1 ] || _lc_ok=0
        { [ "${_lc_frame[1]}" = candidates ] || [ "${_lc_frame[1]}" = files ] ||
            [ "${_lc_frame[1]}" = none ]; } || _lc_ok=0
        { [ "${_lc_frame[2]}" = space ] || [ "${_lc_frame[2]}" = nospace ]; } || _lc_ok=0
        [[ ${_lc_frame[8]} =~ ^(0|[1-9][0-9]?)$ ]] || _lc_ok=0
        { [ "${_lc_frame[3]}" = unquoted ] || [ "${_lc_frame[3]}" = single ] ||
            [ "${_lc_frame[3]}" = double ]; } || _lc_ok=0
        { [ "${_lc_frame[4]}" = unquoted ] || [ "${_lc_frame[4]}" = single ] ||
            [ "${_lc_frame[4]}" = double ]; } || _lc_ok=0
    fi
    if ((_lc_ok)); then
        _lc_count=${_lc_frame[8]}
        ((_lc_count <= 32)) || _lc_ok=0
        if [ "${_lc_frame[1]}" != candidates ]; then
            ((_lc_count == 0)) || _lc_ok=0
        fi
        if [ "${_lc_frame[1]}" != files ]; then
            [[ ! ${_lc_frame[6]} && ! ${_lc_frame[7]} ]] || _lc_ok=0
        fi
        if [ "${_lc_frame[1]}" = none ]; then [[ ! ${_lc_frame[5]} ]] || _lc_ok=0; fi
    fi
    if ((_lc_ok)); then
        for ((_lc_i = 0; _lc_i < _lc_count; ++_lc_i)); do
            if ! _lanius_completion_record; then _lc_ok=0; break; fi
            _lc_frame+=("$_lc_record")
        done
    fi
    if ((_lc_ok)); then
        if ! _lanius_completion_record || [ "$_lc_record" != end ]; then _lc_ok=0; fi
    fi
    if ((_lc_ok)); then
        # -d '' is necessary even for this one-byte read: otherwise Bash can
        # ignore a trailing NUL and incorrectly admit a nonempty wire suffix.
        _lc_record=
        if IFS= read -r -d '' -n 1 -t 2 -u "$_lc_fd" _lc_record; then
            _lc_ok=0
        else
            _lc_status=$?
            ((_lc_status == 1)) || _lc_ok=0
        fi
    fi
    exec {_lc_fd}<&-
    if ((!_lc_ok)); then
        kill -KILL "$_lc_pid" 2>/dev/null || :
        wait "$_lc_pid" 2>/dev/null || :
        _lc_frame=()
        return 1
    fi
    # A producer can close stdout before exiting. Bound the final status wait
    # too; a valid frame alone cannot turn a failed/stalled child into replies.
    # Keep the watchdog out of the interactive shell's job table: waiting a
    # canceled background job can restore cooked tty settings during Readline.
    if ! exec {_lc_timer_fd}< <(_lanius_completion_watchdog "$_lc_pid"); then
        _lc_timer=$!
        kill -TERM "$_lc_timer" 2>/dev/null || :
        wait "$_lc_timer" 2>/dev/null || :
        kill -KILL "$_lc_pid" 2>/dev/null || :
        wait "$_lc_pid" 2>/dev/null || :
        _lc_frame=()
        return 1
    fi
    _lc_timer=$!
    # Explicit wait retrieves an already-completed producer's saved status on
    # Bash 5.2. wait -n does not reliably retrieve that saved status.
    if wait "$_lc_pid" 2>/dev/null; then _lc_status=0; else _lc_status=$?; fi
    kill -TERM "$_lc_timer" 2>/dev/null || :
    wait "$_lc_timer" 2>/dev/null || :
    exec {_lc_timer_fd}<&-
    if ((_lc_status != 0)); then _lc_frame=(); return 1; fi
    return 0
}

# Filename enumeration is deliberately a host operation in an isolated shell.
# Bash glob arrays preserve embedded LF and raw bytes. Quoting the prefix makes
# its glob metacharacters literal. Enumeration's internal heap/time is outside
# the candidate/reply caps; only the produced reply has these explicit bounds.
_lanius_completion_glob()
(
    local LC_ALL=C _lc_stem=$1 _lc_prefix=$2 _lc_quote=$3 _lc_continuation=$4 _lc_trim=$5
    local _lc_spacing=$6 _lc_path _lc_word _lc_count=0 _lc_bytes
    local -a _lc_matches _lc_words=()
    set +f
    unset GLOBIGNORE || return 1
    shopt -u dotglob nocaseglob failglob extglob globstar
    shopt -s nullglob globskipdots
    _lc_matches=("$_lc_prefix"*)
    # Conservative metadata reserve, including the repeated decoded trim.
    _lc_bytes=$((${#_lc_trim} + 128))
    for _lc_path in "${_lc_matches[@]}"; do
        _lc_word=$_lc_path
        if [[ $_lc_word != /* && $_lc_word == [-@]* ]]; then _lc_word=./$_lc_word; fi
        if [[ -d $_lc_path ]]; then _lc_word+=/; _lc_spacing=nospace; fi
        _lc_word=$_lc_stem$_lc_word
        ((${#_lc_word} <= 4096 && _lc_count < 32)) || return 1
        # Readline has already retained trim. Never insert an unsafe path or
        # alter that retained text to force a candidate through this boundary.
        [ "${_lc_word:0:${#_lc_trim}}" = "$_lc_trim" ] || continue
        ((_lc_bytes += ${#_lc_word} + 1))
        ((_lc_bytes <= 32768)) || return 1
        _lc_words+=("$_lc_word")
        ((_lc_count += 1))
    done
    printf '%s\0' lanius-completion-1 candidates "$_lc_spacing" "$_lc_quote" "$_lc_continuation" "$_lc_trim" '' '' "$_lc_count"
    if ((_lc_count)); then printf '%s\0' "${_lc_words[@]}"; fi
    printf '%s\0' end
)

_lanius_completion_bash()
{
    local cur prev cword words
    local _lc_program=$1 _lc_fragment=${2-} _lc_i _lc_word _lc_head _lc_end=0
    local _lc_rawtrim _lc_trim _lc_quote _lc_continuation _lc_spacing _lc_insert _lc_piece _lc_target_quote _lc_byte _lc_j _lc_native_space=0
    local -a _lc_frame=() _lc_replies=() _lc_complete=()
    COMPREPLY=()
    declare -F _get_comp_words_by_ref >/dev/null || return 1
    # COMP_POINT and the helper use the caller's character locale. Switch to
    # byte counting only AFTER extraction, never before this call.
    _get_comp_words_by_ref -n '=:@' cur prev words cword || return 1
    local LC_ALL=C
    ((cword >= 1 && cword <= 9 && ${#_lc_fragment} <= ${#cur})) || return 1
    _lc_head=$((${#cur} - ${#_lc_fragment}))
    [ "${cur:_lc_head}" = "$_lc_fragment" ] || return 1
    _lc_rawtrim=${cur:0:_lc_head}
    if [ "$cur" = "${words[cword]}" ]; then _lc_end=1; fi
    for ((_lc_i = 1; _lc_i < cword; ++_lc_i)); do _lc_complete+=("${words[_lc_i]}"); done
    _lanius_completion_capture "$_lc_program" --lanius-complete-bash "$_lc_end" "$_lc_rawtrim" "$cur" "${_lc_complete[@]}" || return 1
    if [ "${_lc_frame[1]}" = files ]; then
        local _lc_stem=${_lc_frame[6]} _lc_prefix=${_lc_frame[7]}
        _lc_quote=${_lc_frame[3]} _lc_continuation=${_lc_frame[4]}
        _lc_trim=${_lc_frame[5]} _lc_spacing=${_lc_frame[2]}
        _lanius_completion_capture _lanius_completion_glob "$_lc_stem" "$_lc_prefix" "$_lc_quote" "$_lc_continuation" "$_lc_trim" "$_lc_spacing" || return 1
    fi
    [ "${_lc_frame[1]}" = candidates ] || return 0
    _lc_quote=${_lc_frame[3]} _lc_continuation=${_lc_frame[4]}
    _lc_trim=${_lc_frame[5]} _lc_spacing=${_lc_frame[2]}
    if ((_lc_end == 1)) && [ "$_lc_spacing" = space ] && [ "$_lc_quote" != unquoted ]; then
        _lc_native_space=1
    fi
    for ((_lc_i = 0; _lc_i < _lc_frame[8]; ++_lc_i)); do
        _lc_word=${_lc_frame[9 + _lc_i]}
        [ "${_lc_word:0:${#_lc_trim}}" = "$_lc_trim" ] || continue
        _lc_piece=${_lc_word:${#_lc_trim}}
        _lc_insert=
        if [ "$_lc_quote" = single ]; then
            # Readline already owns this opening quote. Insert inside its
            # lexical state rather than trying to close/reopen it up front.
            while [[ $_lc_piece == *"'"* ]]; do
                _lc_insert+=${_lc_piece%%"'"*}
                _lc_insert+="'\\''"
                _lc_piece=${_lc_piece#*"'"}
            done
            _lc_insert+=$_lc_piece
        elif [ "$_lc_quote" = double ]; then
            for ((_lc_j = 0; _lc_j < ${#_lc_piece}; ++_lc_j)); do
                _lc_byte=${_lc_piece:_lc_j:1}
                case $_lc_byte in
                    '\'|'"'|'$'|'`') _lc_insert+='\'; _lc_insert+=$_lc_byte ;;
                    '!') _lc_insert+="\"'!'\"" ;;
                    *) _lc_insert+=$_lc_byte ;;
                esac
            done
        elif [[ $_lc_piece && $_lc_piece != *[!a-zA-Z0-9_./=:@%+,-]* ]]; then
            _lc_insert+=$_lc_piece
        else
            _lc_insert+="'"
            while [[ $_lc_piece == *"'"* ]]; do
                _lc_insert+=${_lc_piece%%"'"*}
                _lc_insert+="'\\''"
                _lc_piece=${_lc_piece#*"'"}
            done
            _lc_insert+="$_lc_piece'"
        fi
        _lc_target_quote=unquoted
        # Bash still closes an active initial quote under noquote. Let it close
        # and add the separator for this finishing state; a manual space makes
        # Readline add a stray quote after that space.
        if ((_lc_native_space)); then _lc_target_quote=$_lc_quote; fi
        if ((_lc_end == 0)) || [ "$_lc_spacing" = nospace ]; then
            _lc_target_quote=$_lc_continuation
        fi
        if [ "$_lc_quote" != "$_lc_target_quote" ]; then
            if [ "$_lc_quote" = single ]; then _lc_insert+="'"; fi
            if [ "$_lc_quote" = double ]; then _lc_insert+='"'; fi
            if [ "$_lc_target_quote" = single ]; then _lc_insert+="'"; fi
            if [ "$_lc_target_quote" = double ]; then _lc_insert+='"'; fi
        fi
        if ((_lc_end == 1 && _lc_native_space == 0)) && [ "$_lc_spacing" = space ]; then _lc_insert+=' '; fi
        # With an initial quote, Bash consumes a matching leading quote from
        # the completion itself. Preserve a required first-byte transition by
        # supplying that consumed quote separately from the lexical encoding.
        if [ "$_lc_quote" = single ] && [ "${_lc_insert:0:1}" = "'" ]; then
            _lc_insert="'$_lc_insert"
        elif [ "$_lc_quote" = double ] && [ "${_lc_insert:0:1}" = '"' ]; then
            _lc_insert=\"$_lc_insert
        fi
        _lc_replies+=("$_lc_insert")
    done
    # Explicit quoting/spacing avoids filename-specific slash insertion into a
    # schema candidate merely because a same-named directory exists in cwd.
    compopt -o noquote -o nospace +o filenames +o default +o bashdefault || return 1
    if ((_lc_native_space)); then compopt +o nospace || return 1; fi
    COMPREPLY=("${_lc_replies[@]}")
}

lanius_completion_register()
{
    (($#)) || return 2
    declare -F _get_comp_words_by_ref >/dev/null || return 2
    complete -F _lanius_completion_bash -- "$@"
}
