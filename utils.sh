#! /bin/bash

# Copyright (C) 2023 Aviv Edery.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

# A collection of handy functions.
# All functions implemented here should make sure to skip aliases and function names with the "command" builtin.
# I've made the decision to not protect against shadowed builtins. Don't go overriding builtins, yo.

# Returns the string $1 repeated $2 times.
utils::repeat() {
    local s=""

    for (( i = 0; i < "$2"; i++ )); do
        s+="$1"
    done

    echo -n "$s"
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
    printf "%s\0" "${@:2}" | command grep -Fxqz "$1"
}

# Returns the size of the git stash.
utils::stashsz() {
    command git rev-list --walk-reflogs --count refs/stash 2> /dev/null || echo 0
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

# Returns the min of all arguments (all must be numerical).
utils::min() {
    printf "%d\n" "$@" | command sort -n | command head -n 1
}

# Returns the max of all arguments (all must be numerical).
utils::max() {
    printf "%d\n" "$@" | command sort -n | command tail -n 1
}

# Returns $1 clamped into the interval [$2, $3].
utils::clamp() {
    local value="$1"
    local min="$2"
    local max="$3"
    echo "$(( "$value" < "$min" ? "$min" : "$value" > "$max" ? "$max" : "$value" ))"
}

# Returns the sign of $1 (-1, 0, or 1).
utils::sign() {
    utils::clamp "$1" -1 1
}

# Divides $1 by $2 with floor and returns the result.
# Bash division operator is only floor for positive numbers. This is for negatives too.
utils::div_floor() {
    local nume_sign="$(utils::sign "$1")"
    local deno_sign="$(utils::sign "$2")"
    local nume="$(( "$1" * nume_sign ))"
    local deno="$(( "$2" * deno_sign ))"
    echo "$(( (nume_sign * deno_sign) * (nume / deno) - (nume_sign != deno_sign && nume % deno != 0) ))"
}

# Divides $1 by $2 with ceiling and returns the result.
utils::div_ceil() {
    # div_ceil() == -div_floor(a, -b)
    echo "$(( -"$(utils::div_floor "$1" -"$2" )" ))"
}