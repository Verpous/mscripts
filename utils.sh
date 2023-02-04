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

# utils::repeat STRING REPEATS
# Returns STRING repeated REPEATS times.
utils::repeat() {
    local s=""

    for (( i = 0; i < "$2"; i++ )); do
        s+="$1"
    done

    echo -n "$s"
}

# Returns the time it takes COMMAND to run when averaged over ITERATIONS times.
# utils::avgtime ITERATIONS COMMAND...
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

# utils::join DELIM [ELEMENT]...
# Returns all ELEMENTs with DELIM separators.
utils::join() {
    (( $# == 1 )) && return
    local d="$1"
    printf %s "$2"

    for arg in "${@:3}"; do
        printf %b%s "$d" "$arg"
    done
}

# utils::reverse ARRAY [ELEMENT]...
# Creates an array called ARRAY which contains all ELEMENTs in reverse.
utils::reverse() {
    local dest="$1"
    declare -n dest
    dest=()
    
    for (( i = $#; i > 1; i-- )); do
        dest[$(( $# - i ))]="${!i}"
    done
}

# utils::contains VALUE ELEMENT...
# Returns success if one of ELEMENTs is equal to VALUE.
utils::contains() {
    printf "%s\0" "${@:2}" | command grep -Fxqz "$1"
}

# utils::stashsz
# Returns the size of the git stash.
utils::stashsz() {
    command git rev-list --walk-reflogs --count refs/stash 2> /dev/null || echo 0
}

# utils::die MESSAGE
# Prints MESSAGE to stderr and exits with failure.
utils::die() {
    printf "%s\n" "$*" >&2
    exit 1
}

# utils::confirm PROMPT
# Reads a string with the prompt PROMPT and returns success if it begins with a Y (case-insensitive), otherwise failure.
utils::confirm() {
    local confirm
    read -p "$1 " confirm # Add a space at the end.
    [[ "$confirm" == *([[:space:]])[yY]* ]]
}

# utils::min [NUM]...
# Returns the smallest of all NUMs.
utils::min() {
    printf "%d\n" "$@" | command sort -n | command head -n 1
}

# utils::max [NUM]...
# Returns the largest of all NUMs.
utils::max() {
    printf "%d\n" "$@" | command sort -n | command tail -n 1
}

# utils::clamp VALUE MIN MAX
# Returns VALUE, but no less than MIN and no more than MAX.
utils::clamp() {
    local value="$1"
    local min="$2"
    local max="$3"
    echo "$(( "$value" < "$min" ? "$min" : "$value" > "$max" ? "$max" : "$value" ))"
}

# utils::sign NUM
# Returns the sign of NUM (-1, 0, or 1).
utils::sign() {
    utils::clamp "$1" -1 1
}

# utils::div_floor NUMERATOR DENOMINATOR
# Divides NUMERATOR by DENOMINATOR with floor and returns the result.
# Bash division operator is only floor for positive numbers. This is for negatives too.
utils::div_floor() {
    local nume_sign="$(utils::sign "$1")"
    local deno_sign="$(utils::sign "$2")"
    local nume="$(( "$1" * nume_sign ))"
    local deno="$(( "$2" * deno_sign ))"
    echo "$(( (nume_sign * deno_sign) * (nume / deno) - (nume_sign != deno_sign && nume % deno != 0) ))"
}

# utils::div_ceil NUMERATOR DENOMINATOR
# Divides NUMERATOR by DENOMINATOR with ceiling and returns the result.
utils::div_ceil() {
    # div_ceil() == -div_floor(a, -b)
    echo "$(( -"$(utils::div_floor "$1" -"$2" )" ))"
}