#!/bin/bash

this=$(basename $0)
current=$(readlink -e $(dirname $0))

# Don't show the source line in the output
# Used in jenkins because the workspace path make this unreadable
suppress_source_line=0

run_cmd_output=""
run_cmd_stderr_output=""
run_cmd_return=0
run_cmd_no_lineno=0

msg_beg_bl="\n"
msg_end_bl="\n\n"

roleconfig="$HOME/.purge_cfg"
vault=$(type -p vault 2> /dev/null)

# check if messages are to be printed using color
unset all_off bold black blue green red yellow white default cyan magenta
all_off="\e[0m"
bold="\e[1m"
black="${bold}\e[30m"
red="${bold}\e[31m"
green="${bold}\e[32m"
yellow="${bold}\e[33m"
blue="${bold}\e[34m"
magenta="${bold}\e[35m"
cyan="${bold}\e[36m"
white="${bold}\e[37m"
default="${bold}\e[39m"
readonly all_off bold black blue green red yellow white default cyan magenta

if [[ $1 == "--short" || $1 == "-s" ]]; then
    # A little less output in jenkins. Not useful if workspace is deleted after a run
    # "cleanWs()" because the line numbers point to files that no longer exist.
    basename[0]="\${WORKSPACE}/$(readlink -f "${BASH_SOURCE[1]}" | cut -d '/' -f 6-)"
    basename[1]="\${WORKSPACE}/$(readlink -f "${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]}" | cut -d '/' -f 6-)"
elif [[ $1 == "--no-lineno" || $1 == "-q" ]]; then
    # Best for jenkins sh step
    suppress_source_line=1
else
    # best used when running in a real bash script (default)
    basename[0]="$(readlink -f "${BASH_SOURCE[1]}")\n"
    basename[1]="$(readlink -f "${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]}")\n"
fi

err() {
    local mesg=$1
    shift
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}${all_off}${red}>>> ERROR:${source_line_no} ${mesg}${all_off}${msg_end_bl}" "$mesg" 1>&2
    if [[ $# -gt 0 ]]; then
        printf '%s ' "${@}" 1>&2
        printf "${msg_end_bl}"
    fi
    exit 1
}

debug() {
    # $1: The message to print.
    if [[ ${debug} -eq 1 ]]; then
        local mesg=$1
        shift
        [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
        printf "${msg_beg_bl}${all_off}${blue}### DEBUG:${source_line_no} ${all_off}%s${msg_end_bl}${all_off}" "${mesg}" 1>&2
        if [[ $# -gt 0 ]]; then
            printf '%s ' "${@}" 1>&2
            printf "${msg_end_bl}"
        fi
    fi
}

debug_print_array() {
    # $1 array name
    # $2 array
    if [[ $# -lt 2 ]]; then
        warn "debug_print_array: Array '$1' is empty"
        return
    fi
    local name=$1
    shift
    arr=("${@}")
    for ((i = 0; i < ${#arr[@]}; i++)); do
        debug "${name}: index: ${i}: ${arr[$i]}"
    done
}

msg() {
    local mesg=$1
    shift
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}${all_off}>>>${source_line_no} %s${msg_end_bl}" "$mesg"
    if [[ $# -gt 0 ]]; then
        printf '%s ' "${@}"
        printf "${msg_end_bl}"
    fi
}

# print a plain old message separated by blank lines
printl() {
    local mesg=$1
    shift
    printf "${msg_beg_bl}${all_off}%s${all_off}${msg_end_bl}" "${mesg}"
    if [[ $# -gt 0 ]]; then
        printf '%s ' "${@}"
        printf "${msg_end_bl}"
    fi
}

msg_bold() {
    local mesg=$1
    shift
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}${all_off}>>>${source_line_no} ${bold}%s${all_off}${msg_end_bl}" "$mesg"
    if [[ $# -gt 0 ]]; then
        printf "${bold}%s${all_off} " "${@}"
        printf "${msg_end_bl}"
    fi
}

warn() {
    local mesg=$1
    shift
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}${all_off}${yellow}=== WARNING:${all_off}${source_line_no} ${mesg}${msg_end_bl}" "$mesg" 1>&2
    if [[ $# -gt 0 ]]; then
        printf '%s ' "${@}" 1>&2
        printf "${msg_end_bl}"
    fi
}

norun() {
    local mesg=$1
    shift
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}--- NORUN:${source_line_no} ${mesg}${msg_end_bl}" "$mesg"
    if [[ $# -gt 0 ]]; then
        printf '%s ' "$@"
        printf "${msg_end_bl}"
    fi
}

dry_run() {
    local mesg=$1
    shift
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}${all_off}${cyan}--- DRYRUN:${source_line_no} ${mesg}${all_off}${msg_end_bl}" "$mesg"
    if [[ $# -gt 0 ]]; then
        printf '%s ' "$@"
        printf "${msg_end_bl}"
    fi
}

skip() {
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}${all_off}${cyan}--- SKIP:${source_line_no} %s${all_off}${msg_end_bl}" "CMD:"
    if [[ $# -gt 0 ]]; then
        printf '%s ' "$@"
        printf "${msg_end_bl}"
    fi
}

run_cmd_check_specific_exit() {
    # $1 Exit code to exit with
    # $2 Exit code to test for
    # $3 Error string if defined with print an error message
    if [[ ${dry_run} -eq 1 ]]; then
        return
    fi
    if [[ ${run_cmd_return} -eq $2 ]]; then
        return
    fi
    if [[ -n $3 ]]; then
        echo
        SOURCE_LINE_OVERRIDE=2 BASH_LINE_OVERRIDE=1 err "$3"
    fi
    exit $1
}

run_cmd_check_exit() {
    # $1 Exit code to exit with
    # $2 Error string if defined with print an error message
    if [[ ${dry_run} -eq 1 ]]; then
        return
    fi
    if [[ ${run_cmd_return} -eq 0 ]]; then
        return
    fi
    if [[ -n $2 ]]; then
        echo
        SOURCE_LINE_OVERRIDE=2 BASH_LINE_OVERRIDE=1 err "$2"
    fi
    exit $1
}

run_cmd_check_warn() {
    # $1 Exit code
    # $2 Error string if defined with print an error message
    if [[ ${dry_run} -eq 1 ]]; then
        return
    fi
    if [[ ${run_cmd_return} -eq 0 ]]; then
        return
    fi
    if [[ -n $2 ]]; then
        echo
        SOURCE_LINE_OVERRIDE=2 BASH_LINE_OVERRIDE=1 warn "$2"
    fi
}

# Runs a command in a subshell. Output is not captured
run_cmd() {
    run_cmd_return=0
    run_cmd_return=0
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    if [[ ${dry_run} -eq 1 ]]; then
        SOURCE_LINE_OVERRIDE=2 BASH_LINE_OVERRIDE=1 dry_run "CMD:" "$@"
    else
        printf "${msg_beg_bl}"
        printf ">>>${source_line_no}${all_off}${green} %s${all_off}${msg_end_bl}" "Running command (run_cmd):"
        printf "%s " "${@}"
        printf "${msg_end_bl}"
        echo -e ">>> Output: ${msg_beg_bl}"
        echo -e "$@" | source /dev/stdin
        run_cmd_return=$?
        local make_red=""
        [[ ${run_cmd_return} -ne 0 ]] && make_red="${red}"
        printf "${msg_beg_bl}${all_off}${green}>>> Command returned ($1): ${make_red}%s${all_off}${msg_end_bl}" "${run_cmd_return}"
        return $run_cmd_return
    fi
}

# Runs a command without forking. Output is not captured, stdin is not captured.
run_cmd_no_subshell() {
    run_cmd_return=0
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    if [[ ${dry_run} -eq 1 ]]; then
        SOURCE_LINE_OVERRIDE=2 BASH_LINE_OVERRIDE=1 dry_run "CMD:" "$@"
    else
        printf "${msg_beg_bl}"
        printf ">>>${source_line_no}${all_off}${green} %s${all_off}${msg_end_bl}" "Running command (run_cmd_no_subshell):"
        printf "%s " "${@}"
        printf "${msg_end_bl}"
        echo -e ">>> Output: ${msg_beg_bl}"
        "$@"
        run_cmd_return=$?
        local make_red=""
        [[ ${run_cmd_return} -ne 0 ]] && make_red="${red}"
        printf "${msg_beg_bl}${all_off}${green}>>> Command returned ($1): ${make_red}%s${all_off}${msg_end_bl}" "${run_cmd_return}"
        return $run_cmd_return
    fi
    return $run_cmd_return
}

# Runs the command, does not show output to stdout.
# Output is stored in run_cmd_output variable.
# Ouput is stored for only only one call and cleared on successive calls to this function.
run_cmd_no_output() {
    run_cmd_output=""
    run_cmd_return=0
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}"
    # printf ">>>${source_line_no} %s${msg_end_bl}" "Running command (run_cmd_no_output):"
    printf ">>>${source_line_no}${all_off}${green} %s${all_off}${msg_end_bl}" "Running command (run_cmd_no_output):"
    printf "%s " "${@}"
    printf "${msg_beg_bl}"
    echo -e "$@" | source /dev/stdin > >(tee stdout.log > /dev/null) 2> >(tee stderr.log 2> /dev/null)
    run_cmd_return=${PIPESTATUS[1]}
    run_cmd_output=$(cat stdout.log)
    run_cmd_stderr_output=$(cat stderr.log)
    local make_red=""
    local err_out=""
    [[ ${run_cmd_return} -ne 0 ]] && make_red="${red}" && err_out="${msg_beg_bl}${msg_beg_bl}${yellow}Got err:${msg_end_bl}${run_cmd_stderr_output}"
    printf "${msg_beg_bl}${all_off}${green}>>> Command returned ($1): ${make_red}%s${all_off}${err_out}${all_off}${msg_end_bl}" "${run_cmd_return}"
    # Don't leave files around
    rm stderr.log
    rm stdout.log
    return $run_cmd_return
}

# Run a command, showing and capturing the output.
run_cmd_show_and_capture_output() {
    run_cmd_output=""
    run_cmd_return=0
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    if [[ ${dry_run} -eq 1 ]]; then
        dry_run "CMD:" "$@"
    else
        printf "${msg_beg_bl}"
        printf ">>>${source_line_no} %s${msg_end_bl}" "Running command (run_cmd_show_and_capture_output):"
        printf "%s " "${@}"
        printf "${msg_end_bl}"
        echo -e ">>> Output: ${msg_beg_bl}"
        echo -e "$@" | source /dev/stdin > >(tee stdout.log) 2> >(tee stderr.log >&2)
        run_cmd_return=${PIPESTATUS[1]}
        run_cmd_output=$(cat stdout.log)
        run_cmd_stderr_output=$(cat stderr.log)
        local make_red=""
        [[ ${run_cmd_return} -ne 0 ]] && make_red="${red}"
        printf "${msg_beg_bl}>>> Command returned ($1): ${make_red}%s${all_off}${msg_end_bl}" "${run_cmd_return}"
        # Don't leave files around
        rm stderr.log
        rm stdout.log
        return $run_cmd_return
    fi
}

# Run a command even if dryrun is used. Useful for showing arguments to a function call.
run_cmd_always() {
    run_cmd_return=0
    run_cmd_return=0
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}"
    printf ">>>${source_line_no} %s${msg_end_bl}" "Running command (run_cmd_always):"
    printf "%s " "${@}"
    printf "${msg_end_bl}"
    echo -e ">>> Output: ${msg_beg_bl}"
    # echo -e "$@" | ARGS=${ARGS[@]} source /dev/stdin
    echo -e "$@" | source /dev/stdin
    run_cmd_return=$?
    local make_red=""
    [[ ${run_cmd_return} -ne 0 ]] && make_red="${red}"
    printf "${msg_beg_bl}>>> Command returned ($1): ${make_red}%s${all_off}${msg_end_bl}" "${run_cmd_return}"
    return $run_cmd_return
}

run_cmd_always_show_and_capture_output() {
    run_cmd_output=""
    run_cmd_return=0
    [ -f stdout.log ] && rm -f stdout.log
    [ -f stderr.log ] && rm -f stderr.log
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}"
    printf ">>>${source_line_no} %s${msg_end_bl}" "Running command:"
    printf "%s " "${@}"
    printf "${msg_end_bl}"
    echo -e ">>> Output: ${msg_beg_bl}"
    echo -e $@ | source /dev/stdin > >(tee -a stdout.log) 2> >(tee -a stderr.log >&2)
    run_cmd_return=${PIPESTATUS[1]}
    run_cmd_output=$(cat stdout.log)
    run_cmd_stderr_output=$(cat stderr.log)
    echo
    local make_red=""
    [[ ${run_cmd_return} -ne 0 ]] && make_red="${red}"
    printf "Command returned: ($1) ${make_red}%s${all_off}${msg_end_bl}" "${run_cmd_return}"
    return $run_cmd_return
}

# Runs the command, does not show output to stdout
# Command runs despite dryrun being active
# To use this function, define the following in your calling script:
# run_cmd_output=""
# run_cmd_return=""
run_cmd_always_suppress_output() {
    run_cmd_output=""
    run_cmd_return=0
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    printf "${msg_beg_bl}"
    printf ">>>${source_line_no} %s${msg_end_bl}" "Running command:"
    printf "%s " "${@}"
    printf "${msg_end_bl}"
    run_cmd_output=$(echo -e "$@" 2>&1 | source /dev/stdin)
    run_cmd_return=$?
    local make_red=""
    [[ ${run_cmd_return} -ne 0 ]] && make_red="${red}"
    printf "Command returned: ($1) ${make_red}%s${all_off}${msg_end_bl}" "${run_cmd_return}"
    return $run_cmd_return
}

assert_file_exists_warn() {
    local file="$1"
    local msg="${2-}"
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
    if [ -f $file ] || [ ${dry_run} -eq 1 ]; then
        return 0
    else
        printf "${all_off}${yellow}=== WARNING:${source_line_no} Assertion failed! Err: %s${msg_end_bl}${all_off}" "$msg" 1>&2
        return 0
    fi
}

assert_file_exists_exit() {
    local file="$1"
    local msg="${2-}"
    if [ -f $file ] || [ ${dry_run} -eq 1 ]; then
        return 0
    else
        [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
        printf "${all_off}${red}=== ERROR:${source_line_no} Assertion failed! Err: %s${all_off}${msg_end_bl}" "$msg" 1>&2
        exit 1
    fi
}

assert_directory_exists_warn() {
    local dir="$1"
    local msg="${2-}"
    if [ -d $dir ] || [ ${dry_run} -eq 1 ]; then
        return 0
    else
        [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
        printf "${all_off}${yellow}=== WARNING:${source_line_no} Assertion failed! Err: %s${msg_end_bl}${all_off}" "$msg" 1>&2
        return 0
    fi
}

assert_directory_exists_exit() {
    local dir="$1"
    local msg="${2-}"
    if [ -d $dir ] || [ ${dry_run} -eq 1 ]; then
        return 0
    else
        [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
        printf "${all_off}${red}=== ERROR:${source_line_no} Assertion failed! Err: %s${all_off}${msg_end_bl}" "$msg" 1>&2
        exit 1
    fi
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3-}"
    if [ "$expected" == "$actual" ]; then
        return 0
    else
        [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
        printf "${all_off}${red}=== ERROR:${source_line_no} Assertion failed! Err: %s${msg_end_bl}${all_off}" "$msg" 1>&2
        exit 1
    fi
}

assert_true() {
    local actual="$1"
    local msg="${2-}"
    SOURCE_LINE_OVERRIDE=2 BASH_LINE_OVERRIDE=1 assert_eq true "$actual" "$msg"
    return "$?"
}

assert_false() {
    local actual="$1"
    local msg="${2-}"
    SOURCE_LINE_OVERRIDE=2 BASH_LINE_OVERRIDE=1 assert_eq false "$actual" "$msg"
    return "$?"
}

# Copied from https://github.com/torokmark/assert.sh/blob/main/assert.sh
assert_not_empty() {
    local actual=$1
    local msg="${2-}"
    SOURCE_LINE_OVERRIDE=2 BASH_LINE_OVERRIDE=1 assert_not_eq "" "$actual" "$msg"
    return "$?"
}

# Copied from https://github.com/torokmark/assert.sh/blob/main/assert.sh
assert_not_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3-}"
    if [ ! "$expected" == "$actual" ]; then
        return 0
    else
        [[ $suppress_source_line -eq 0 ]] && source_line_no=" $(basename ${BASH_SOURCE[${SOURCE_LINE_OVERRIDE:-1}]})#${BASH_LINENO[${BASH_LINE_OVERRIDE:-0}]}:"
        printf "${all_off}${red}=== ERROR:${source_line_no} Assertion failed! Err: %s${msg_end_bl}${all_off}" "$msg" 1>&2
        exit 1
    fi
}

# usage: retry <cmd>
# e.g. retry ls -a
retry() {
    local count=1
    local max=5
    local delay=15
    while true; do
        "$@" && break || {
            if [[ $count -lt $max ]]; then
                ((count++))
                printf "${all_off}${yellow}=== WARNING: Command failed.${msg_end_bl}${blue}Attempt $count/$max: ${all_off}"
                sleep $delay
            else
                printf "${all_off}${red}=== ERROR: The command has failed after $count attempts with exit code := $exit_code${all_off}${msg_end_bl}"
                exit 1
            fi
        }
    done
}

# usage: retry_custom <maximum no. of retries> <delay between next attempt> <cmd>
# e.g. retry_custom 3 10 ls -a
retry_custom() {
    local count=1
    local max=$1
    shift
    local delay=$1
    shift
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" ${basename[0]}#${BASH_LINENO[0]}:"
    while true; do
        "$@" && break || {
            if [[ $count -lt $max ]]; then
                ((count++))
                printf "${all_off}${yellow}=== WARNING:${source_line_no} Command failed.${msg_end_bl}${blue}Attempt $count/$max: ${all_off}"
                sleep $delay
            else
                printf "${all_off}${red}=== ERROR:${source_line_no} The command has failed after $count attempts with exit code := $?${all_off}${msg_end_bl}"
                exit 1
            fi
        }
    done
}

# usage: retry_custom <maximum no. of retries> <delay between next attempt> <cmd>
retry_custom_no_exit() {
    local count=1
    local max=$1
    shift
    local delay=$1
    shift
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" ${basename[0]}#${BASH_LINENO[0]}:"
    while true; do
        "$@" && break || {
            if [[ $dry_run -eq 0 ]] && [[ $count -lt $max ]]; then
                ((count++))
                printf "${all_off}${yellow}=== WARNING:${source_line_no} Command failed.${msg_end_bl}${blue}Attempt $count/$max: ${all_off}"
                sleep $delay
            else
                printf "${all_off}${yellow}=== WARNING:${source_line_no} The command has failed after $count attempts with exit code := $?${all_off}${msg_end_bl}"
                return $?
            fi
        }
    done
}

# echo "DRY_RUN: ${DRY_RUN}"
[[ "${DRY_RUN}" == "true" ]] && export dry_run=1 || export dry_run=0

# A highly visible message
banner_msg() {
    # $1 the message
    title=$1
    title_len=${#title}
    title_border=$(printf '=%.0s' $(seq 1 ${title_len}))
    msg_bold "${title_border}"
    msg_bold "${title}"
    msg_bold "${title_border}"
}
