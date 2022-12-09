#! /bin/bash
# A collection of handy functions.
# All functions implemented here should make sure to skip aliases and function names with the "command" builtin.
# I've made the decision to not protect against shadowed builtins. Don't go overriding builtins, yo.

# Returns the string $1 repeated $2 times.
utils::repeat() {
    command head -c "$2" /dev/zero | command sed "s/./$1/g"
}

# Returns the time it takes the command ${@:2} to run when averaged over $1 times.
utils::avgtime() {
    local repeats="$1"
    for (( i = 0 ; i < $repeats; i++ )); do
        time -p "${@:2}" &> /dev/null
    done |& command gawk '
    /real/ {
        real += $2
        nreal++
    }
    /user/ {
        user += $2
        nuser++
    }
    /sys/ {
        sys += $2
        nsys++
    }
    END {
        print "real", real / nreal, real
        print "user", user / nuser, user
        print "sys", sys / nsys, sys
    }' | command column --table -N \ ,avg,total
}

# Joins the arguments ${@:2} with the delimiter $1. Accepts backslash escapes in $1.
utils::join() {
    (( $# == 1 )) && return
    local d="$1"
    printf %s "$2"

    for arg in "${@:3}"; do
        printf %b%s "$d" "$arg"
    done
}

# Creates an array called $1 which contains the arguments ${@:2} in reverse.
utils::reverse() {
    local dest="$1"
    declare -n dest
    dest=()
    
    for (( i = $#; i > 1; i-- )); do
        dest[$(( $# - i ))]="${!i}"
    done
}

# Returns success if "$1" is in "${@:2}"
utils::contains() {
    printf "%s\0" "${@:2}" | grep -Fxqz "$1"
}

# Returns the size of the git stash.
utils::stashsz() {
    command git rev-list --walk-reflogs --count refs/stash 2> /dev/null || builtin echo 0
}

# Echoes "$@" to stderr and exits with status=1.
utils::error() {
    echo "$@" >&2
    exit 1
}

utils::confirm() {
    local confirm
    read -p "$1 " confirm # Add a space at the end.
    [[ "$confirm" == *([[:space:]])[yY]* ]]
}