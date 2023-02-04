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

## Fetches IMDb lists and updates the local json store for them and the resulting category files.
## LIST is case-insensitive and can be either:
## 1. A list name as defined in the configuration file
## 2. An IMDb list ID
## 3. The string '*', which expands to every configured list name. You should quote this argument if you use it.
## Can pull several lists at once. If no LIST provided, downloads lists marked as default in the configuration.

# TODO: Add -C option which reinterprets LISTs as categories and:
# * if '-f' is not set, it acts as though you ran mup on the categories' dependencies.
# * if '-f' is set, it only generates the requested categories.

scripts="$(dirname -- "$BASH_SOURCE")"
source "$scripts"/options.sh
source "$scripts"/utils.sh
shopt -s extglob

which cygpath &> /dev/null && path() { cygpath -- "$1"; } || path() { echo -n "$1"; }
do_fetch=true
do_gen=true
do_optimize=true
mdir="$(path "${MOVIES_DIR:-.}")"
default_downloads=~/Downloads # Tilde expansion won't happen if we write this string directly in the line below.
downloads="$(path "${MOVIES_DOWNLOADS:-$default_downloads}")"
popts=()
fopts=()
handle_option() {
    case "$1" in
        o) ## Disable optimizations that may cause the script to not function as expected.
           ##> Use this if you notice your category wasn't re-generated despite being different from last time.
            do_optimize=false
            ;;
        m) ## DIR ## The movies directory. This is where output is placed. Defaults to MOVIES_DIR env variable, or the current directory if it doesn't exist.
            mdir="$(path "$2")"
            ;;
        c) ## FILE ## Configuration file for lists and categories. Defaults to '<movies-dir>/mconfig.txt', where <movies-dir> is the directory you modify with -m.
            config="$(path "$2")"
            ;;
        d) ## DIR ## The downloads directory used by your web browser. Defaults to MOVIES_DOWNLOADS env variable, or '~/Downloads' if it doesn't exist.
            downloads="$(path "$2")"
            ;;
        f) ## Skip the step where mfetch is run to update the local JSONs. Use the JSONs that already exist in the movies directory.
            do_fetch=false
            ;;
        p) ## Skip the step where mprint is run to generate new category files. Only update the local JSONs.
            do_gen=false
            ;;
        F) ## OPTS ## Semicolon-delimited options to pass to mfetch. DON'T pass -u/--update here. Don't forget to escape/quote the semicolons!
            readarray -td \; fopts < <(echo -n "$2")
            ;;
        P) ## OPTS ## Semicolon-delimited options to pass to mprint. DON'T pass -p here, and -G is not recommended.
           ##> It's your responsibility to ensure this doesn't conflict with the category mprint options.
            readarray -td \; popts < <(echo -n "$2")
            ;;
    esac
}

options::init "[LIST]..."
options::getopts handle_option -1
shift $options_shift

[[ -d "$mdir" && -w "$mdir" ]] || utils::die "Movies directory '$mdir' doesn't exist or you do not have permissions for it"
[[ -d "$downloads" && -w "$downloads" && -r "$downloads" ]] || utils::die "Downloads directory '$downloads' doesn't exist or you do not have permissions for it"
[[ -v config ]] || config="$mdir/mconfig.txt"

declare -A default_lists=()
declare -A list_ids=()
declare -A cat_popts=()
declare -A cat_lists=()
namei=0

# This is where we parse the mconfig.
if [[ -f "$config" && -r "$config" ]]; then
    while IFS='' read -r line; do
        case "$line" in
            # We restrict fields to a set of characters that we know we can safely work with.
            # We don't even have to quote them, but we'll still try our best.
            ?(\ )[lL]\ +([[:word:]])\ +([[:word:]])\ +([[:word:]])?(\ ))
                IFS=' ' read -r t lname lid default < <(echo -n "$line")
                lname="${lname,,}"
                list_ids["$lname"]="$lid"

                # Defaults are kept in an associative array where we only care about the keys.
                # This is so that if you have two lists with the same name, the later one overwrites the earlier one.
                [[ "$default" == [Yy]* ]] && default_lists["$lname"]=1 || unset default_lists["$lname"]
                ;;
            ?(\ )[cC]\ +([[:word:]])\ +([!\ ])\ +([[:word:]\;])?(\ ))
                IFS=' ' read -r t cname cpopts_str clists_str < <(echo -n "$line")
                cname="${cname,,}"
                # Bash doesn't support nested arrays so cat_popts and cat_lists actually hold references to arrays.
                cat_popts["$cname"]=mup_var$(( namei++ ))
                cat_lists["$cname"]=mup_var$(( namei++ ))
                declare -n cpopts="${cat_popts[$cname]}"
                declare -n clists="${cat_lists[$cname]}"
                [[ "$cpopts_str" == '-' ]] && cpopts=() || readarray -td \; cpopts < <(echo -n "$cpopts_str")
                readarray -td \; clists < <(echo -n "${clists_str,,}")
                ;;
            ?(\ )) # Empty lines are allowed and ignored.
                ;;
            *)
                utils::die "Line '$line' in the configuration file is not valid"
                ;;
        esac
    done < <(expand -t 1 -- "$config" | tr -s ' ' | cat - <(echo))
else
    echo "Configuration file '$config' doesn't exist or you do not have permissions for it. Ignoring it" >&2
fi

# Setting defaults if needed. Erroring out if there are none.
(( $# == 0 )) && set -- "${!default_lists[@]}"
(( $# == 0 )) && utils::die "No LIST provided and there are no defaults set up"

# We'll use the browser to fetch the list export because some lists are private and in the browser you're already signed in.
# But before, we have to know what's the current most recent csv in the downloads folder, so that we'll know when it changes.
get_latest_csv() {
    find "$downloads" -maxdepth 1 -iname '*.csv' -printf '%B@ %f\0' | sort -znr | head -zn 1 | cut -zd ' ' -f 2- | head -c -1
}

fetch() {
    ! $do_fetch && return 0

    local lid="$1"
    local out_csv="$2.csv"
    local out_json="$2.json"

    echo "Downloading '$out_csv'..."
    local initial_csv="$(get_latest_csv)"
    local timeout=20
    SECONDS=0

    # I can't for the life of me figure out how to be logged in with cURL so we use the browser where you're assumed to be already logged in.
    python -m webbrowser "https://www.imdb.com/list/ls$lid/export?ref_=ttls_exp" > /dev/null

    # We'll try to obtain the most recent csv in the downloads folder, until it's a different one than before we started downloading.
    while local in_csv="$(get_latest_csv)"; [[ "$initial_csv" == "$in_csv" ]]; do
        if (( SECONDS > timeout )); then
            echo "Timed out when trying to download '$out_csv'. Skipping it" >&2
            return 1
        fi
    done

    # When the file is created it's sometimes empty for a bit. At some point it jumps to being fully written, without any inbetween.
    # So this waits for the file size to not be zero.
    # NOTE: [[ -e "..." ]] would be a lot nicer but for some reason it sometimes creates a copy of the file and messes everything up.
    while (( "$(stat --format="%s" "$downloads/$in_csv")" == 0 )); do
        if (( SECONDS > timeout )); then
            echo "Timed out when trying to download '$out_csv'. Skipping it" >&2
            return 1
        fi
    done

    mv "$downloads/$in_csv" "$mdir/$out_csv"

    # The optimization is that we'll diff the JSON mfetch outputs with the existing one,
    # and if nothing has changed then we won't run mprint for this later.
    if $do_optimize && [[ -f "$mdir/$out_json" ]]; then
        local temp_json="$(mktemp -p "$mdir")"
        "$scripts"/mfetch.py --update "$mdir/$out_json" "${fopts[@]}" -- "$mdir/$out_csv" "$temp_json"

        # diff exits with 0 when the files are identical.
        diff -q -- "$mdir/$out_json" "$temp_json" > /dev/null && local ret=1 || local ret=0
        mv -- "$temp_json" "$mdir/$out_json"
        return $ret
    else
        "$scripts"/mfetch.py "${fopts[@]}" -- "$mdir/$out_csv"
        return 0
    fi
}

# Similar trick to what we did with default_lists,
# an associative array where we only care about the keys is the easiest way to define a set in bash (i.e., list w/o duplicates).
declare -A gen_cats=()

# Adding all list names to the array of lists we want to fetch if '*' is in the arguments,
# then removing duplicate list names.
utils::contains '*' "$@" && uniqlists=("${!list_ids[@]}") || uniqlists=()
readarray -d '' -O ${#uniqlists[@]} uniqlists < <(printf "%s\0" "$@" | grep -Fxzv '*' | tr [:upper:] [:lower:] | sort -uz)

# We build a pattern that only matches against valid list names. This doesn't work if list_ids is empty,
# so in that case we'll create a pattern that matches nothing.
(( ${#list_ids[@]} > 0 )) && lname_pat="@($(utils::join '|' "${!list_ids[@]}"))" || lname_pat='!(*)'

# Fetch what we need.
for lname in "${uniqlists[@]}"; do
    case "$lname" in
        $lname_pat) # lname is one of the lists in the config file.
            # We'll make a note to generate all categories that use this list if it was fetched successfully.
            fetch "${list_ids[$lname]}" "$lname" && for cname in "${!cat_lists[@]}"; do
                declare -n clists="${cat_lists[$cname]}"
                utils::contains "$lname" "${clists[@]}" && gen_cats["$cname"]=1
            done
            ;;
        +([[:word:]])) # lname is not in the config file, we will assume it's an IMDb list ID.
            if fetch "$lname" "$lname"; then
                # Creating a new list and category for this list ID.
                list_ids["$lname"]="$lname"
                cat_popts["$lname"]=mup_var$(( namei++ ))
                cat_lists["$lname"]=mup_var$(( namei++ ))
                declare -n cpopts="${cat_popts[$lname]}"
                declare -n clists="${cat_lists[$lname]}"
                cpopts=()
                clists=("$lname")
                gen_cats["$lname"]=1
            fi
            ;;
        *)
            utils::die "Invalid LIST: '$lname'"
            ;;
    esac
done

# Conditionally also running mprint to update the text files.
if $do_gen; then
    readarray -t crew_types < <("$scripts"/mprint.py -p cast) # CREW doesn't matter.
    len=${#crew_types[@]}

    # We'll need the length of the longest category name for alignment.
    (( max_cname = "$(printf "%s\n" "${!gen_cats[@]}" | tr -c '\n' x | sort -r | head -n 1 | wc -c)" + 4 ))
    
    for cname in "${!gen_cats[@]}"; do
        declare -n clists="${cat_lists[$cname]}"
        declare -n cpopts="${cat_popts[$cname]}"

        # We need to surround the lnames with mdir before and .json after,
        # and I don't think any of the quick ways to do it are robust to all the weird characters mdir could have.
        jsons=()
        for lname in "${clists[@]}"; do jsons+=("$mdir/$lname.json"); done

        # We'll skip this category if one of its dependencies is missing.
        for json in "${jsons[@]}"; do
            [[ ! -f "$json" ]] && { echo "Category '$cname' requires file '$json' which doesn't exist. Skipping it" >&2; continue 2; }
        done

        mkdir -p "$mdir/$cname"
        i=0
        for crew in "${crew_types[@]}"; do
            echo -ne "Generating category $(printf "%-${max_cname}s" "'$cname': ")[$(utils::repeat "#" $i)$(utils::repeat " " $(( len - i )))]\r"
            "$scripts"/mprint.py "${popts[@]}" "${cpopts[@]}" -- "$crew" "${jsons[@]}" > "$mdir/$cname/$crew.txt"
            (( i++ ))
        done

        echo -e "Generating category $(printf "%-${max_cname}s" "'$cname': ")[$(utils::repeat "#" $len)]"
    done
fi
