#!/bin/bash

# A single source of truth for functions we commonly use in bash scripts.
#
# Like, double spaced log output with line numbers for readability
# and logging the command being used for easy debugging.
#
# Of course, the run_cmd* functions don't work in all cases, but they do for most.
#
# All functions included in this file should support debug logging as well as dry_run
#
# To use this script, include the following boilerplate:
#
#    # Redifined in lib.sh but it is needed to find lib.sh
#    current=$(readlink -e $(dirname $0))
#
#    # Loads lib.sh
#    function load_libsh(){
#        if source ${GLOBALLIB_SCRIPT=`realpath ${current}/../cuda_scripts/lib.sh`} 2> /dev/null; then
#            return
#        elif source ${GLOBALLIB_SCRIPT=`realpath ${current}/cuda_scripts/lib.sh`} 2> /dev/null; then
#            return
#        elif source ${GLOBALLIB_SCRIPT=`realpath ${current}/lib.sh`} 2> /dev/null; then
#            return
#        else
#            echo "ERROR: Could not locate lib.sh!" && exit 1
#        fi
#
#    }
#    load_libsh

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
vault=$(type -p vault 2>/dev/null)

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
    for ((i=0; i < ${#arr[@]}; i++ )); do
        debug "${name}: index: ${i}: ${arr[$i]}";
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
    local mesg=$1; shift
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
    local mesg=$1; shift
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
    echo -e "$@" | source /dev/stdin > >(tee stdout.log > /dev/null) 2> >(tee stderr.log 2>/dev/null)
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

# usage: retry_until_success <cmd>
# e.g. retry_until_success ls -a
retry_until_success() {
    local count=1
    local delay=30
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" ${basename[0]}#${BASH_LINENO[0]}:"
    while true; do
        "$@" && break || {
            ((count++))
            printf "${all_off}${yellow}=== WARNING:${source_line_no} Command failed.${msg_end_bl}${blue}Attempt $count:"
            sleep $delay
        }
    done
}

#usage:
#$ difftime <starttime> <endtime>
#$ difftime <startdate> <enddate>
diff_time() {
    gnudate=$(date --version 2>/dev/null | grep GNU)
    utilsflag="-j -f %FT%T%z"
    [[ $gnudate ]] && utilsflag="-d"
    s1=$(date -u $utilsflag "$1" +%s)
    s2=$(date -u $utilsflag "$2" +%s)
    sd=$((s2 - s1))
    if [ $sd -gt 59 ]; then
        mm=$(expr $sd / 60)
        if [ $mm -gt 59 ]; then
            hh=$(expr $mm / 60)
            mm=$(expr $mm % 60)
            ss=$(expr $sd % 60)
            printf "${all_off}${cyan} Elapsed $hh hours, $mm minutes, $ss seconds${msg_end_bl}"
        else
            ss=$(expr $sd % 60)
            printf "${all_off}${cyan} Elapsed $mm minutes, $ss seconds${msg_end_bl}"
        fi
    else
        printf "${all_off}${cyan} Elapsed $sd seconds${msg_end_bl}"
    fi
}

#usage:
#$ parse_yaml <path to yaml file> <optional prefix to use before each variale>
#-----sample.yaml-----
# global:
#   debug: yes
#   verbose: no
#   debugging:
#     detailed: no
# output:
#    file: yes
#---------------------
#
# parse_yaml sample.yml jenkins_
#
# All variables available to shell:
# jenkins_global_debug="yes"
# jenkins_global_verbose="no"
# jenkins_global_debugging_detailed="no"
# jenkins_output_file="yes"
parse_yaml() {
    local file=$1
    shift
    local prefix=$1
    local varfile="/tmp/vars.env"
    local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @ | tr @ '\034')
    sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" $file |
        awk -F$fs -v out_file=$varfile '{
        indent = length($1)/2;
        vname[indent] = $2;
        printf "" > out_file
        for (i in vname) {if (i > indent) {delete vname[i]}}
            if (length($3) > 0) {
                vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
                printf ("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3) >> out_file
            }
        }'

    if [ -s $varfile ]; then
        source "$varfile" 2>/dev/null
        export $(cat $varfile | egrep -v "(^#.*|^$)" | xargs)
        printf "${all_off}${cyan} All valid yaml entries have been exported to current shell as environment variables!${msg_end_bl}"
        rm -f $varfile
    else
        printf "${all_off}${yellow} $varfile is empty!${msg_end_bl} Check your input yaml file: $file${msg_end_bl}"
    fi
}

# echo "DRY_RUN: ${DRY_RUN}"
[[ "${DRY_RUN}" == "true" ]] && export dry_run=1 || export dry_run=0

ssh_svc_remote() {
    msg "ssh_svc_${TRIFORCE} $@"
    run_cmd ssh ${SSH_OPTS} -i ${PRIV_KEY} ${loginUSER}@${TRIFORCE} "$@"
    return ${run_cmd_return}
}

ssh_svc_remote_always() {
    msg "ssh_svc_${TRIFORCE} $@"
    run_cmd_always ssh ${SSH_OPTS} -i ${PRIV_KEY} ${loginUSER}@${TRIFORCE} "$@"
    return ${run_cmd_return}
}

# Generalized function of the triforce ssh examples above (no dry_run)
#
# Meant to be used with jenkins with_credentials to provide ssh details
#
# 11:04 Wed Nov 16 2022: Added by Jesus for KAPI deploy
ssh_svc_remote_cmd() {
    # $1 the host to connect
    # $@ the command to run on the remote host
    local host=$1
    shift
    msg "ssh host: ${host}"
    msg "ssh args:" "${@}"
    msg "SSH_OPTS:" "${SSH_OPTS:-<NOT SET>}"
    run_cmd ssh ${SSH_OPTS} -i ${PRIV_KEY} ${loginUSER}@${host} "$@"
    return ${run_cmd_return}
}

# Generalized function of the triforce ssh examples above
#
# Meant to be used with jenkins with_credentials to provide ssh details
#
# 11:04 Wed Nov 16 2022: Added by Jesus for KAPI deploy
ssh_svc_remote_cmd_always() {
    # $1 the host to connect
    # $@ the command to run on the remote host
    local host=$1
    shift
    msg "ssh host: ${host}"
    msg "ssh args:" "${@}"
    msg "SSH_OPTS:" "${SSH_OPTS:-<NOT SET>}"
    run_cmd_always ssh ${SSH_OPTS} -i ${PRIV_KEY} ${loginUSER}@${host} "$@":
    return ${run_cmd_return}
}

# Copy a file to a remote machine using SCP
#
# Meant to be used with jenkins with_credentials to provide ssh details
#
# 11:04 Wed Nov 16 2022: Added by Jesus for KAPI deploy
scp_file_to_remote() {
    # $1 the host to connect
    # $2 the file to copy
    # $3 the remote path and name
    local host=$1
    local local_file=$2
    local remote_file=$3
    msg "ssh host: ${host}"
    msg "local_file:" "${local_file}"
    msg "remote_file:" "${remote_file}"
    msg "SSH_OPTS:" "${SSH_OPTS:-<NOT SET>}"
    run_cmd scp ${SSH_OPTS} -i ${PRIV_KEY} ${local_file} ${loginUSER}@${host}:${remote_file}
    return ${run_cmd_return}
}

# Copy a file to a remote machine using SCP (no dry_run)
#
# Meant to be used with jenkins with_credentials to provide ssh details
#
# 11:04 Wed Nov 16 2022: Added by Jesus for KAPI deploy
scp_file_to_remote_always() {
    # $1 the host to connect
    # $2 the file to copy
    # $3 the remote path and name
    local host=$1
    local local_file=$2
    local remote_file=$3
    msg "ssh host: ${host}"
    msg "local_file:" "${local_file}"
    msg "remote_file:" "${remote_file}"
    msg "SSH_OPTS:" "${SSH_OPTS:-<NOT SET>}"
    run_cmd scp ${SSH_OPTS} -i ${PRIV_KEY} ${local_file} ${loginUSER}@${host}:${remote_file}
    return ${run_cmd_return}
}

# SSH to a remote host and check if a file exists.
#
# Function will always run even if dry_run is set.
#
# SSH connection is tried three times.
#
# Will not exit non zero on retry failure.
#
# $1:       The path to the file on the remote. Must be absolute.
# Returns:  0 if the file exists, 1 if the file does not exist. 2 is returned if ssh connect failed.
ssh_svc_remote_file_exists() {
    local count=1
    local max=3
    local delay=30
    [[ $suppress_source_line -eq 0 ]] && source_line_no=" ${basename[0]}#${BASH_LINENO[0]}:"
    msg "Checking '$1' exists on remote host..."
    while true; do
        run_cmd_always_suppress_output ssh ${SSH_OPTS} -i ${PRIV_KEY} ${loginUSER}@${TRIFORCE} "[[ -f $1 ]]" && break || {
            if [[ $run_cmd_return -eq 1 ]]; then
                # file does not exist
                return 1
            fi
            if [[ $count -lt $max ]]; then
                ((count++))
                printf "${all_off}${yellow}=== WARNING:${source_line_no} SSH Command failed.${msg_end_bl}${blue}Attempt $count/$max: ${all_off}"
                sleep $delay
            else
                printf "${all_off}${red}=== ERROR:${source_line_no} The SSH command has failed after $count attempts with exit code := $?${all_off}${msg_end_bl}"
                return ${run_cmd_return}
            fi
        }
    done
}

ssh_svc_remote_remount_cdn() {
    # $1: write or read
    msg "ssh_svc_${TRIFORCE} remount_share $@"
    if [[ $1 = "write" ]]; then
        msg "==> Enabling ${CDN_BASEPATH} as read-write"
        run_cmd ssh_svc_remote 'sudo mount -o remount,rw ${CDN_BASEPATH}'
        run_cmd_check_exit 0 "Unable to remount ${CDN_BASEPATH} as write-access"
    elif [[ $1 = "read" ]]; then
        msg "==> Enabling ${CDN_BASEPATH} as read-only"
        run_cmd ssh_svc_remote 'sudo mount -o remount,ro ${CDN_BASEPATH}'
        run_cmd_check_exit 0 "Unable to remount ${CDN_BASEPATH} as read-only"
    fi
}

rsync_svc_remote() {
    msg "rsync_svc_${TRIFORCE} $1 -> $2"
    run_cmd "rsync -av -e 'ssh ${SSH_OPTS} -i ${PRIV_KEY}' $1 ${loginUSER}@${TRIFORCE}:$2"
    return ${run_cmd_return}
}

rsync_from_svc_remote() {
    msg "rsync_svc_${TRIFORCE} $1 -> $2"
    run_cmd "rsync -av -e 'ssh ${SSH_OPTS} -i ${PRIV_KEY}' ${loginUSER}@${TRIFORCE}:$1 $2"
    return ${run_cmd_return}
}

remote_dir() {
    if [[ $1 == *"tar.gz"* ]]; then
        if [[ "$1" =~ ^([0-9a-z-]*).* ]]; then
            nname="$(echo ${BASH_REMATCH[1]})"
            name=${nname::-5}
            echo ${name}
        fi
    else
        if [[ "$1" =~ ^([0-9a-z_]*).* ]]; then
            nname="$(echo ${BASH_REMATCH[1]} | sed 's/_/-/g')"
            name=${nname}
            echo ${name}
        fi
    fi
}

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

login_vault() {
    unset token
    local KEY_NAME=$1
    local KEY_PATH=$2
    local ROLE_CFG=$3
    local NAMESPACE="cuda-installer-automation"
    local VAULT_CFG="$HOME/.vault_cfg"
    svc_secrets="secrets/svc/svc-compute-packaging"
    [[ -z $KEY_PATH ]] && KEY_PATH="$svc_secrets"
    [[ -z $ROLE_CFG ]] && ROLE_CFG="$VAULT_CFG"

    if [[ -z $KITMAKER ]]; then
        source "$ROLE_CFG"
        $vault write --field=token auth/approle/login role_id="${ROLE_ID}" secret_id="${SECRET_ID}" | $vault login --method=token --no-print -
        token=$($vault kv get --namespace="${NAMESPACE}" --field="${KEY_NAME}" "${KEY_PATH}")
        rm -f $HOME/.vault-token
    fi
}

have_command() {
    # $1: The command to check for
    # returns 0 if true, and 1 for false
    for cmd in "${commands[@]}"; do
        # debug "have_command: loop '$cmd'"
        if [[ ${cmd} == $1 ]]; then
            SOURCE_LINE_OVERRIDE=1 BASH_LINE_OVERRIDE=1 debug "have_command: '$1' is defined"
            return 0
        fi
    done
    SOURCE_LINE_OVERRIDE=1 BASH_LINE_OVERRIDE=1 debug "have_command: '$1' is not defined"
    return 1
}
