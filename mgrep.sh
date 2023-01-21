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

## Prints the full credits of any person whose credits match PATTERN in mprint's output files.
## PATTERN is in extended regex (like egrep, grep -E).
## WHERE indicates a .txt file output by mprint. Supports (in order of precedence):
## 1. '-' for standard input (so you can pipe mprint into mgrep)
## 2. Absolute paths, paths relative to the current directory
## 3. Paths relative to the lookup category
## In all forms the .txt extension can optionally be omitted. All forms are case-sensitive.
## If no WHERE provided, searches all .txt files in the lookup category.

scripts="$(dirname -- "$BASH_SOURCE")"
source "$scripts"/options.sh
source "$scripts"/utils.sh

which cygpath &> /dev/null && path() { cygpath "$1"; } || path() { echo -n "$1"; }
casing="-i"
fnames=true
limit=false
nmatches=""
invert=""
minimal=false
mdir="$(path "${MOVIES_DIR:-.}")"
exclude=$'\x18'"THIS PATTERN WILL NEVER MATCH"
[[ -t 1 ]] && color=true || color=false
handle_option() {
    case "$1" in
        i) ## Turn on case sensitivity for PATTERN. Default is to be case-insensitive.
            casing=""
            ;;
        C) ## WHEN ## Set color to one of 'always', 'auto', or 'never' (case-insensitive). Defaults to 'auto'.
            case "${2,,}" in
                always) color=true ;;
                auto) ;; # Default, no action needed.
                never) color=false ;;
                *) utils::error "Invalid color mode: '$2'" ;;
            esac
            ;;
        H) ## Don't print the file name for each match.
            fnames=false
            ;;
        M) ## NUM ## Stop after NUM matches.
            { (( nmatches = 10#"$2" )); } &> /dev/null || utils::error "Invalid max count: '$2'"
            limit=true
            ;;
        v) ## Select non-matching people.
            invert="-v"
            ;;
        V) ## PATTERN ## Don't select people who match PATTERN. This is different from '-v', which inverts the pattern of people who *do* match.
            exclude="$2"
            ;;
        x) ## Exclude full credits, print only people names (PATTERN is still matched against the full credits).
            minimal=true
            ;;
        m) ## DIR ## The movies directory. This is the output directory used by mup. Defaults to MOVIES_DIR env variable, or the current directory if it doesn't exist.
            mdir="$(path "$2")"
            ;;
        c) ## FILE ## Configuration file for lists and categories. Defaults to '<movies-dir>/mconfig.txt', where <movies-dir> is the directory you modify with -m.
            config="$(path "$2")"
            ;;
        l) ## CATEGORY ## Lookup category for relative path arguments. Only the basename of the category's directory, not an absolute or relative path.
            category="$2"
            ;;
    esac
}

options::init "PATTERN [WHERE]..."
options::getopts handle_option 1
shift $OPTIONS_SHIFT
pattern="$1"
shift

get_catdir() {
    [[ -d "$mdir" && -r "$mdir" ]] || { echo "Movies directory '$mdir' doesn't exist or you do not have permissions for it" >&2; return 1; }
    [[ -v config ]] || config="$mdir/mconfig.txt"

    if [[ ! -v category && -f "$config" && -r "$config" ]]; then
        category="$(grep -ioEm 1 "^[[:blank:]]*c[[:blank:]]+[[:alnum:]_]+" -- "$config" | grep -ioE "[[:alnum:]_]+$")" ||
            { echo "Unable to obtain default category from the configuration file" >&2; return 1; }
        category="$category"
    elif [[ ! -v category ]]; then
        echo "Configuration file '$config' doesn't exist or you do not have permissions for it, therefore a default category could not be determined" >&2
        return 1
    fi

    # We want to check if $category is a directory directly in $mdir. Find alone is not enough,
    # because it doesn't support fixed string patterns. So we get a list of valid categories and use grep to match the one we want.
    find -- "$mdir" -mindepth 1 -maxdepth 1 -type d -printf "%f\0" | grep -Fxqz -- "$category" ||
        { echo "Category '$category' does not exist in the movies directory '$mdir'"; return 1; }
    catdir="$mdir/$category"
    return 0
}

get_catdir || echo "WHERE arguments relative to the lookup category will not work because the directory could not be determined" >&2

if (( $# == 0 )); then
    # Nothing to do here if there are no args and no defaults.
    [[ -v catdir ]] || exit
    # %f gives us the basename which looks nicer.
    readarray -d '' where < <(find -- "$catdir" -maxdepth 1 -iname '*.txt' -printf "%f\0")
else
    where=("$@")
fi

# grep uses these variables to change the color scheme. We hardcoded the default colors so we must disable the user's preferences.
# Maybe in the future I'll add support for adapting to these colors.
unset GREP_COLORS GREP_COLOR

if $color; then
    # Same colors that grep uses.
    purple=$'\033[35m\033[K'
    blue=$'\033[36m\033[K'
    nocolor=$'\033[m\033[K'
    grepcolor=always
else
    purple=""
    blue=""
    nocolor=""
    grepcolor=never
fi

if $minimal; then
    # In minimal mode we want to get rid of any lines that aren't a person's name (including empty lines).
    strip='/^[[:space:]]{4}/d;/^$/d'

    # If color is on we need to strip color from the line in order to pattern match it,
    # but restore color to lines which aren't deleted.
    $color && strip=$'h;s/\033[[]01;31m\033[[]K|\033[[]m\033[[]K//g;'"$strip;g"
else
    strip=""
fi

lastcount=0
tmpfile="$(mktemp)"

# We need a character that surely won't appear in the file to use as a temporary replacement for newlines. Unit Separator sounds like a good choice.
sep=$'\x1F'

# Processing the search pattern a bit to hide implementation details.
[[ "$pattern" == ^* ]] && pattern="^${sep}${pattern:1}"
pattern="$(echo -n "$pattern" | tr '\n' "$sep")"

for loc in "${where[@]}"; do
    # Because we split into one grep call for each file (we have good reasons),
    # we must keep track of the number of matches between them if the -M option is provided.
    if $limit; then
        (( nmatches -= lastcount ))
        (( nmatches <= 0 )) && exit 0
        mflag="-m $nmatches"
    fi

    if [[ "$loc" == '-' ]]; then
        infile=/dev/stdin
    else
        IFS='' read -rd '' infile < <(find -L -- "$loc" "$loc.txt" "$catdir/$loc" "$catdir/$loc.txt" -maxdepth 0 -type f,p -readable -print0 2> /dev/null)
        [[ -z "$infile" ]] && { echo "'$loc' is not a valid WHERE. Skipping it" >&2; continue; }
    fi

    # With -H, creating an op that prints the filename (with optional color).
    # Without -H, output looks better with an extra newline between files.
    $fnames && op="s#^#${purple}${loc}${nocolor}${blue}:${nocolor}#" || op='$a '$'\n'
    
    # Alright listen up 'cuz there's a lot going on here. The algorithm is:
    # 1. Flatten each person's full credits into one line (so one line per person)
    # 2. Match the desired pattern against these lines
    # 3. Undo the flattening operation (that is, for the remaining people, restore theirs credits to multi-line)
    # There are complications and also this is a big effin' pipe but don't worry, everything will be explained.

    # Step 1, the flattening. We use US (Unit Separator) and as a temporary replacements for newlines so we can restore them at step 3.
    # We also get rid of the head of the file up to where it starts listing people.
    # The first person in the list gets printed a little different, so we inject our own US in there to make him like the rest.
    # The flattened file is stored to a temp file (and also piped on) because we'll need to revisit it if $limit==true.
    sed -En "s/^$/$sep/ ; /^\S.*:$/,\$p" -- "$infile" | tr "\\n$sep" "$sep\\n" | cat <(echo -n "$sep") - | tee -- "$tmpfile" |
    # Steps 2 and 3. We match the pattern and then unflatten.
    # We don't restore it exactly to its original form, to achieve prettier output.
    grep -Ev $casing -e "$exclude" | grep -E --color=$grepcolor $casing $invert $mflag -e "$pattern" | tr -d '\n' | tr "$sep" '\n' |
    # There were several bugs as a cause of patterns which match across multiple lines.
    # If lines get deleted, or we try to append the filename before each line, or whatever, it messes up the colors.
    # The solution is an algorithm which finds multi-line color blocks, and turns them into several single-line color blocks.
    if $color; then
        gawk '
        BEGIN {
            RS = "\033[[]01;31m\033[[]K"
            FS = "\033[[]m\033[[]K"
            ORS = "\033[01;31m\033[K"
            OFS = "\033[m\033[K"
        }

        # The first line should not be edited assuming input is correct (which it is).
        NR == 1 { print }
        
        # Also assuming input is correct, every line but the first ought to have exactly 2 fields,
        # $1 is the entire part of the line that should be colored, and $2 is the entire part that should not be.
        NR > 1 { print gensub(/\n/, (OFS "\n" ORS), "g", $1), $2 }
        ' | head -c -11 # AWK is surprisingly terrible at detecting the last line, so we printed an extra red at the end that we must get rid of.
    else
        # No bugs to fix in this case. Pipe on.
        cat
    fi |
    # Deleting the first line for prettier output, and additional ops which depend on options.
    sed -E "1d ; $strip ; $op"

    # This is what we need tmpfile for.
    $limit && lastcount="$(grep -Ec $casing $invert $mflag -e "$pattern" -- "$tmpfile")"
done

rm -- "$tmpfile"
