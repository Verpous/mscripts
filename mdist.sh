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

## Prints a chart of how the release or watched date of movies from a list distributes over time.
## JSON is a list to operate on, which was output by mbrowse. Accepts whatever mbrowse would accept.

# TODO: Expand to rating-based distributions: distributions over rating, metascore, and my ratings.

scripts="$(dirname -- "$BASH_SOURCE")"
source "$scripts"/options.sh
source "$scripts"/utils.sh
shopt -s extglob

omit_mode=auto
omit_zeroes=false
sortkey="-k 2,2" # All DISTRIB options output numbers with zero padding such that lexicographic sort == numerical sort.
append_nmovies_expr='(($1 > 0 ? " " : "") $1)'
uniqflag=-u
column=released
distribution=d_year
compact=true
handle_option() {
    case "$1" in
        d) ## DISTRIB ## Which distribution to output. Options are: 'year', 'month', 'day', 'month-of-year', 'week-of-year',
           ##> 'week-of-year-monday', 'day-of-year', 'day-of-month', 'day-of-week', or 'day-of-week-monday'. Defaults to 'year'.
           ## The '-monday' DISTRIBs treat Monday as the first day of the week. By default Sunday is the first day.
           ## Convenient shorthands are supported: 'y' for 'year', 'd-o-w-m' for 'day-of-week-monday', etc.
            case "${2,,}" in
                y?(ear?(s)))                                    distribution=d_year ;;
                m?(onth?(s)))                                   distribution=d_month ;;
                d?(ay?(s)))                                     distribution=d_day ;;
                m?(onth?(s))-o?(f)-y?(ear?(s)))                 distribution=d_month_of_year ;;
                w?(eek?(s))-o?(f)-y?(ear?(s)))                  distribution=d_week_of_year ;;
                w?(eek?(s))-o?(f)-y?(ear?(s))-m?(onday?(s)))    distribution=d_week_of_year_monday ;;
                d?(ay?(s))-o?(f)-y?(ear?(s)))                   distribution=d_day_of_year ;;
                d?(ay?(s))-o?(f)-m?(onth?(s)))                  distribution=d_day_of_month ;;
                d?(ay?(s))-o?(f)-w?(eek?(s)))                   distribution=d_day_of_week ;;
                d?(ay?(s))-o?(f)-w?(eek?(s))-m?(onday?(s)))     distribution=d_day_of_week_monday ;;
                *)                                              utils::die "Invalid DISTRIB: '$2'." ;;
            esac
            ;;
        o) ## OMIT ## Choose whether to omit buckets with 0 movies. Options are 'always', 'auto', or 'never'.
           ##> Defaults to 'auto', which uses a mode that makes sense for DISTRIB.
            [[ "${2,,}" != @(always|auto|never) ]] && utils::die "Invalid OMIT: '$2'."
            omit_mode="${2,,}"
            ;;
        s) ## KEY ## Sort according to one of 'date', or 'nmovies'. Defaults to 'date'.
            case "${2,,}" in
                date) ;; # Default, no action needed.
                nmovies) sortkey="-nk 1,1" ;;
                *) utils::die "Invalid SORT: '$2'." ;;
            esac
            ;;
        n) ## Don't append the numerical value to each bar.
            append_nmovies_expr=''
            ;;
        u) ## When merging JSONs, don't remove duplicate movies.
            uniqflag=""
            ;;
        w) ## Use watched date instead of release date.
            column=watched
            ;;
        g) ## PATTERN ## Only count movies whose date in YYYY-MM-DD format matches PATTERN. Syntax is the same as sed -E.
            include="$2"
            ;;
        v) ## PATTERN ## Don't count movies whose date in YYYY-MM-DD format matches PATTERN. Syntax is the same as sed -E.
            exclude="$2"
            ;;
        S) ## Space out the table.
            compact=false
            ;;
    esac
}

options::init "[JSON]..."
options::getopts handle_option -1
shift $OPTIONS_SHIFT

case "$omit_mode" in
    always)
        omit_zeroes=true
        ;;
    auto)
        [[ "$distribution" == @(d_month|d_day) ]] && omit_zeroes=true || omit_zeroes=false
        ;;
    never)
        # These distributions are too complicated to support filling in zeroes for.
        [[ "$distribution" == @(d_month|d_day) ]] && utils::die "DISTRIB '$distribution' does not support OMIT: '$omit_mode'"
        omit_zeroes=false
        ;;
esac

name_map=""

# -1 for min/max is a special value which means "use the lowest/highest value you find".
case "$distribution" in
    d_year)                 fmt=%Y  pad=4  min=-1 max=-1  ;;
    d_week_of_year)         fmt=%U  pad=2  min=0  max=53  ;;
    d_week_of_year_monday)  fmt=%W  pad=2  min=0  max=53  ;;
    d_day_of_year)          fmt=%j  pad=3  min=1  max=366 ;;
    d_day_of_month)         fmt=%d  pad=2  min=1  max=31  ;;
    # name_map will be split in awk to make an array. The array starts at 1, but d_day_of_week starts at 0.
    # So we'll actually add 1 to the index of everything (so months start at 2, days at 1), and add a dummy member for distributions that start at 1.
    d_month_of_year)        fmt=%m  pad=2  min=1  max=12  name_map=",  January, February,    March,    April,      May,     June,     July,   August,September,  October, November, December" ;;
    d_day_of_week)          fmt=%w  pad=1  min=0  max=6   name_map="   Sunday,   Monday,  Tuesday,Wednesday, Thursday,   Friday, Saturday" ;;
    d_day_of_week_monday)   fmt=%u  pad=1  min=1  max=7   name_map=",   Monday,  Tuesday,Wednesday, Thursday,   Friday, Saturday,   Sunday" ;;
    # These do not support omit_zeroes so they don't need fields other than the fmt.
    d_day)                  fmt=%Y-%m-%d ;;
    d_month)                fmt=%Y-%m ;;
esac

# If include/exclude are requested, we'll append them to the fmt so we can sed on those patterns.
[[ -z "$include" && -z "$exclude" ]] || fmt+="#%Y-%m-%d"

tmp="$(mktemp)"
sep=$'\x1F'

# First: mbrowse. -d so that it doesn't pad output with spaces, we don't really care about CSV format.
"$scripts"/mbrowse.py -dt -C "$column" -f "$fmt" $uniqflag -- "$@" |
    # Taking care of -g, -v if provided.
    if [[ -z "$include" && -z "$exclude" ]]; then
        cat
    else
        [[ -z "$include" ]] && include=. # This will always match
        [[ -z "$exclude" ]] && exclude='This will never match'
        sed -En "
            h                           # Store the full line for later.
            s/^.*#(.*)$/\1/g            # Examine just the full date which we appended after a '#'
            \\${sep}${exclude}${sep}b   # Skip this line if it matches the exclude pattern
            \\${sep}${include}${sep}!b  # Now include patterns. sed allows wrapping regexs with a different character than '/', so we use one that should never be provided as input.
            g                           # Restore the full line we backed up earlier.
            s/^(.*)#.*$/\1/gp           # Keep only the date we wish to examine for this distribution."
    fi | sort | uniq -c | # Creating count of how many times each date appears.
    # We'll take care of adding in missing dates depending on omit_zeroes.
    if $omit_zeroes; then
        cat
    else
        gawk -v min="$min" -v max="$max" -v pad="$pad" '
            function myprint(nmovies, date) { printf "%d %.*d\n", nmovies, pad, date }
            NR == 1 {
                last = (min == -1 ? $2 : min) - 1
            }
            1 {
                for (last++; last < $2; last++) myprint(0, last)
                myprint($1, $2)
            }
            END {
                if (max == -1) max = last
                if (NR == 0) last = (min == -1 ? max : min) - 1
                for (last++; last <= max; last++) myprint(0, last)
            }'
    fi | sort -s $sortkey |
    # We have everything we need to make a table now.
    gawk -v name_map="$name_map" '
        function getname(i) {
            return name_map == "" || mapping[i + 1] == "" ? i : mapping[i + 1]
        }
        BEGIN {
            split(name_map, mapping, ",")
        }
        1 {
            s = ""
            for (i = 0; i < $1; i++) s = s "="
            print "  " getname($2) "| " s '"$append_nmovies_expr"'
        }' |
        # We'll handle -S here.
        if $compact; then
            cat
        else
            # This will learn the correct amount of spaces at the start of the row from the first row, then append '<spaces>|' between rows.
            sed -En '1 { h ; s/(.*\|).*/\1/g; s/[^|]/ /g ; p ; x } ; p ; x ; p ; x'
        fi > "$tmp"

# We've got the output basically, now we want to fit it to the terminal width.
maxline="$(grep -Eo =+ -- "$tmp" | wc -L)"

if (( maxline > 0 )); then
    # 20 characters makes room for characters in the line that aren't the '=' signs.
    width="$(( "$(utils::max "$(tput cols)" 21)" - 20 ))"
    
    # If longest line is too long, squish it.
    if (( maxline >= width )); then
        # Matching {1,ceil(maxline/width)} occurences of '='. This makes the amount of '='s be reduced to ceil(nmovies/ceil(maxline/width)).
        # This is guaranteed to not exceed width, and makes bars of < ceil(maxline/width) turn into 1 '=' not 0.
        # It works because regex matching is greedy.
        search="={1,$(utils::div_ceil "$maxline" "$width")}"
        replace='='
    else # If longest line is shorter than it can be, stretch it.
        search='='
        replace="$(utils::repeat = "$(( width / maxline ))" )"
    fi
    
    sed -E "s/$search/$replace/g" -- "$tmp"
fi

rm -- "$tmp"
