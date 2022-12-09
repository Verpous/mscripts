#! /bin/bash

# Copyright (C) 2022 Aviv Edery.

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

## Takes a list of TIME durations and adds or subtracts them from the current date, then prints the resulting date in the format that mbrowse likes.
## TIME syntax is: (+|-)?[0-9]+[sihdwmy]? (case-insensitive). That is:
## 1. Optional +/- to add or subtract this amount. Defaults to add. Be careful when using '-' because it might be confused for an option.
## 2. A number.
## 3. Optional unit suffix: (s)econds/m(i)nutes/(h)ours/(d)ays/(w)eeks/(m)onths/(y)ears. Defaults to days.

scripts="$(dirname "$0")"
source "$scripts"/options.sh
source "$scripts"/utils.sh
shopt -s extglob

base_date="$(date +%s)"
output_fmt=%Y-%m-%d
handle_option() {
    case "$1" in
        d) ## DATE ## Compute relative to DATE, not 'now'. Syntax is the same as 'date -d'.
            base_date="$(date -d "$2" +%s)" || exit 1
            ;;
        f) ## FORMAT ## Output date according to FORMAT. See 'date --help' for FORMAT syntax. Defaults to '%Y-%m-%d'.
            output_fmt="$2"
            ;;
        v) ## Shorthand for '-f "%Y-%m-%d %T"' (for increased verbosity).
            output_fmt="%Y-%m-%d %T"
            ;;
    esac
}

options::init "TIME..."
options::getopts handle_option 1
shift $OPTIONS_SHIFT

secs=0

for arg in "$@"; do
    case "$arg" in
        ?(+|-)+([0-9])) (( secs += 10#"$arg" * 60 * 60 * 24 )) ;; # Default is days.
        ?(+|-)+([0-9])[sS]) (( secs += 10#"${arg::-1}" )) ;;
        ?(+|-)+([0-9])[iI]) (( secs += 10#"${arg::-1}" * 60 )) ;;
        ?(+|-)+([0-9])[hH]) (( secs += 10#"${arg::-1}" * 60 * 60 )) ;;
        ?(+|-)+([0-9])[dD]) (( secs += 10#"${arg::-1}" * 60 * 60 * 24 )) ;;
        ?(+|-)+([0-9])[wW]) (( secs += 10#"${arg::-1}" * 60 * 60 * 24 * 7 )) ;;
        ?(+|-)+([0-9])[mM]) (( secs += 10#"${arg::-1}" * 60 * 60 * 24 * 30 )) ;;
        ?(+|-)+([0-9])[yY]) (( secs += 10#"${arg::-1}" * 60 * 60 * 24 * 365 )) ;;
        *) utils::error "Invalid TIME: '$arg'. TIME syntax is (+|-)?[0-9]+[sihdwmy]? (case-insensitive)." ;;
    esac
done

date -d "@$(( base_date + secs ))" +"$output_fmt"
