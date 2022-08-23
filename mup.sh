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
## Fetches imdb lists and updates the local json store for them and the resulting category files.
## LIST is either a list name as defined in the configuration file, or an IMDb list ID (everything is case-insensitive).
## Can pull several lists at once. If no LIST provided, downloads lists marked as default in the configuration.

scripts="$(dirname "$0")"
source "$scripts"/options.sh
source "$scripts"/utils.sh
shopt -s extglob

which cygpath &> /dev/null && path() { cygpath "$1"; } || path() { echo -n "$1"; }
do_fetch=true
do_gen=true
do_optimize=true
mdir="$(path "${MOVIES_DIR:-.}")"
fdir="$(path "${MOVIES_FDIR:-$PROGRAMFILES\\Mozilla Firefox}")"
default_downloads=~/Downloads # Tilde expansion won't happen if we write this string directly in the line below.
downloads="$(path "${MOVIES_FDOWNLOADS:-$default_downloads}")"
popts=()
dopts=()
take_opt() {
    case "$1" in
        o) ## Disable optimizations that may cause the script to not function as expected.
            do_optimize=false
            ;;
        m) ## The movies directory. This is where output is placed. Defaults to MOVIES_DIR env variable, or the current directory if it doesn't exist.
            mdir="$(path "$2")"
            ;;
        c) ## Configuration file for lists and categories. Defaults to '<movies-dir>/mconfig.txt', where <movies-dir> is the directory you modify with -m.
            config="$(path "$2")"
            ;;
        b) ## Directory where Firefox is installed on your computer. Defaults to MOVIES_FDIR env variable, or '$PROGRAMFILES/Mozilla Firefox/' if it doesn't exist.
            fdir="$(path "$2")"
            ;;
        d) ## The downloads directory used by Firefox. Defaults to MOVIES_FDOWNLOADS env variable, or '~/Downloads' if it doesn't exist.
            downloads="$(path "$2")"
            ;;
        f) ## Skip the step where mfetch is run to update the local JSONs. Use the JSONs that already exist in the movies directory.
            do_fetch=false
            ;;
        p) ## Skip the step where mprint is run to generate new category files. Only update the local JSONs.
            do_gen=false
            ;;
        F) ## Comma-delimited options to pass to mfetch. DON'T pass -u/--update here.
            readarray -td , dopts < <(echo -n "$2")
            ;;
        P) ## Comma-delimited options to pass to mprint. DON'T pass -p here, and -c is not recommended. It's your responsibility to ensure this doesn't conflict with the category mprint options.
            readarray -td , popts < <(echo -n "$2")
            ;;
    esac
}

options::init fpom:c:b:d:F:P: "[LIST]..."
options::getopts take_opt -1
shift $SHIFT_AMT

[[ -d "$mdir" && -w "$mdir" ]] || utils::error "Movies directory '$mdir' doesn't exist or you do not have permissions for it."
[[ -d "$fdir" ]] || utils::error "Firefox installation directory '$fdir' doesn't exist."
[[ -f "$fdir"/firefox && -x "$fdir"/firefox ]] || utils::error "File '$fdir/firefox' doesn't exist or you do not have permissions for it."
[[ -d "$downloads" && -w "$downloads" && -r "$downloads" ]] || utils::error "Downloads directory '$downloads' doesn't exist or you do not have permissions for it."
[[ -v config ]] || config="$mdir/mconfig.txt"

declare -A default_lists=()
declare -A list_ids=()
declare -A cat_popts=()
declare -A cat_lists=()
namei=0

if [[ -f "$config" && -r "$config" ]]; then
    while IFS='' read -r line; do
        case "$line" in
            # We restrict fields to a set of characters that we know we can safely work with.
            # We don't even have to quote them, but we'll still try our best.
            ?(\ )l\ +([[:word:]])\ +([[:word:]])\ +([[:word:],])?(\ ))
                IFS=' ' read -r t lname lid default < <(echo -n "$line")
                list_ids["$lname"]="$lid"

                # Defaults are kept in an associative array where we only care about the keys.
                # This is so that if you have two lists with the same name, the later one overwrites the earlier one.
                [[ "$default" == y* ]] && default_lists["$lname"]=1 || unset default_lists["$lname"]
                ;;
            ?(\ )c\ +([[:word:]])\ +([!\ ])\ +([[:word:],])?(\ ))
                IFS=' ' read -r t cname cpopts_str clists_str < <(echo -n "$line")
                # Bash doesn't support nested arrays so cat_popts and cat_lists actually hold references to arrays.
                cat_popts["$cname"]=mup_var$(( namei++ ))
                cat_lists["$cname"]=mup_var$(( namei++ ))
                declare -n cpopts="${cat_popts[$cname]}"
                declare -n clists="${cat_lists[$cname]}"
                [[ "$cpopts_str" == '-' ]] && cpopts=() || readarray -td , cpopts < <(echo -n "$cpopts_str")
                readarray -td , clists < <(echo -n "$clists_str")
                ;;
            ?(\ )) # Empty lines are allowed and ignored.
                ;;
            *)
                utils::error "Line '$line' in the configuration file is not valid."
                ;;
        esac
    done < <(tr '\t[:upper:]' ' [:lower:]' < "$config" | tr -s ' ' | cat - <(echo))
else
    echo "Configuration file '$config' doesn't exist or you do not have permissions for it. Ignoring it." >&2
fi

# Setting defaults if needed. Erroring out if there are none.
(( $# == 0 )) && set -- "${!default_lists[@]}"
(( $# == 0 )) && utils::error "No LIST provided and there are no defaults set up."

# We'll use firefox to fetch the list export because the list is private and in firefox I am already signed in.
# But before, we have to know what's the current most recent csv in the downloads folder, so that we'll know when it changes.
get_latest_csv() {
    find "$downloads" -maxdepth 1 -iname '*.csv' -printf '%B@ %f\0' | sort -znr | head -zn 1 | cut -zd ' ' -f 2- | head -c -1
}

fetch() {
    ! $do_fetch && return 0

    local lid="$1"
    local out_csv="$2.csv"
    local out_json="$2.json"

    # The optimization is that we'll diff the JSON mfetch outputs with the existing one,
    # and if nothing has changed then we won't run mprint for this later.
    if $do_optimize && [[ -f "$mdir/$out_json" ]]; then
        local orig_json="$(mktemp -p "$mdir")"
        mv "$mdir/$out_json" "$orig_json"
        local optimizing=true
    else
        local orig_json="$mdir/$out_json"
        local optimizing=false
    fi

    echo "Downloading '$out_csv'..."
    local initial_csv="$(get_latest_csv)"
    local timeout=20
    SECONDS=0

    # I can't for the life of me figure out how to be logged in with cURL so we use Firefox where I'm assumed to be already logged in.
    # I tried to at least run Firefox -headless, but no solution is as consistent as this.
    "$fdir"/firefox "https://www.imdb.com/list/ls$lid/export?ref_=ttls_exp"

    # We'll try to obtain the most recent csv in the downloads folder, until it's a different one than before we started downloading.
    while local in_csv="$(get_latest_csv)"; [[ "$initial_csv" == "$in_csv" ]]; do
        if (( SECONDS > timeout )); then
            $optimizing && mv "$orig_json" "$mdir/$out_json"
            echo "Timed out when trying to download '$out_csv'. Skipping it." >&2
            return 1
        fi
    done

    # When the file is created it's sometimes empty for a bit. At some point it jumps to being fully written, without any inbetween.
    # So this waits for the file size to not be zero.
    # NOTE: [[ -e "..." ]] would be a lot nicer but for some reason it sometimes creates a copy of the file and messes everything up.
    while (( "$(stat --format="%s" "$downloads/$in_csv")" == 0 )); do
        if (( SECONDS > timeout )); then
            $optimizing && mv "$orig_json" "$mdir/$out_json"
            echo "Timed out when trying to download '$out_csv'. Skipping it." >&2
            return 1
        fi
    done

    mv "$downloads/$in_csv" "$mdir/$out_csv"
    "$scripts"/mfetch.py --update "$orig_json" "${dopts[@]}" -- "$mdir/$out_csv"

    if $optimizing; then
        # diff exits with 0 when the files are identical.
        diff -q "$mdir/$out_json" "$orig_json" > /dev/null && local ret=1 || local ret=0
        rm "$orig_json"
        return $ret
    else
        return 0
    fi
}

# Similar trick to what we did with default_lists,
# an associative array where we only care about the keys is the easiest way to define a set in bash (i.e., list w/o duplicates).
declare -A gen_cats=() 
readarray -d '' uniqlists < <(printf "%s\0" "$@" | tr [:upper:] [:lower:] | sort -uz)

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
            utils::error "Invalid LIST: '$lname'"
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
            [[ ! -f "$json" ]] && { echo "Category '$cname' requires file '$json' which doesn't exist. Skipping it." >&2; continue 2; }
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
