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

scripts="$(dirname -- "$BASH_SOURCE")"
source "$scripts"/options.sh
source "$scripts"/utils.sh
shopt -s extglob

omit_mode=auto
omit_zeroes=false
sortkey="-k 2,2" # All PRECISION options output numbers with zero padding such that lexicographic sort == numerical sort.
append_nmovies_expr='(($1 > 0 ? " " : "") $1)'
uniqflag=-u
datetype=released
precision=p_year
include="" # This default pattern will always match.
exclude="THIS DEFAULT PATTERN WILL NEVER MATCH"
monday_weeks=false
handle_option() {
    case "$1" in
        p) ## PRECISION ## Divide movies into buckets of 'year', 'month', 'day', 'quarter-of-year', 'month-of-year', 'week-of-year',
           ##> 'week-of-year-monday', 'day-of-year', 'day-of-month', 'day-of-week', or 'day-of-week-monday'. Defaults to 'year'.
           ## Be warned: some of these may run for about a minute.
           ## The '-monday' PRECISIONs treat Monday as the first day of the week. By default Sunday is the first day.
           ## Convenient shorthands are supported: 'y' for 'year', 'd-o-w-m' for 'day-of-week-monday', etc.
            case "${2,,}" in
                y?(ear?(s)))                                    precision=p_year ;;
                m?(onth?(s)))                                   precision=p_month ;;
                d?(ay?(s)))                                     precision=p_day ;; 
                m?(onth?(s))-o?(f)-y?(ear?(s)))                 precision=p_month_of_year ;;
                w?(eek?(s))-o?(f)-y?(ear?(s)))                  precision=p_week_of_year ;;
                w?(eek?(s))-o?(f)-y?(ear?(s))-m?(onday?(s)))    precision=p_week_of_year_monday ;;
                d?(ay?(s))-o?(f)-y?(ear?(s)))                   precision=p_day_of_year ;;
                d?(ay?(s))-o?(f)-m?(onth?(s)))                  precision=p_day_of_month ;;
                d?(ay?(s))-o?(f)-w?(eek?(s)))                   precision=p_day_of_week ;;
                d?(ay?(s))-o?(f)-w?(eek?(s))-m?(onday?(s)))     precision=p_day_of_week_monday ;;
                q?(uarter?(s))-o?(f)-y?(ear?(s)))               precision=p_quarter_of_year ;;
                *)                                              utils::error "Invalid PRECISION: '$2'." ;;
            esac
            ;;
        o) ## OMIT ## Choose whether to omit buckets with 0 movies. Options are 'always', 'auto', or 'never'.
           ##> Defaults to 'auto', which uses a mode that makes sense for PRECISION.
            [[ "${2,,}" != @(always|auto|never) ]] && utils::error "Invalid OMIT: '$2'."
            omit_mode="${2,,}"
            ;;
        s) ## KEY ## Sort according to one of 'date', or 'nmovies'. Defaults to 'date'.
            case "${2,,}" in
                date) ;; # Default, no action needed.
                nmovies) sortkey="-nk 1,1" ;;
                *) utils::error "Invalid SORT: '$2'." ;;
            esac
            ;;
        n) ## Don't append the numerical value to each bar.
            append_nmovies_expr=''
            ;;
        u) ## When merging JSONs, don't remove duplicate movies.
            uniqflag=""
            ;;
        w) ## Use watched date instead of release date.
            datetype=watched
            ;;
        g) ## PATTERN ## Only count movies whose date in %Y-%m-%d format matches PATTERN. Syntax is the same as egrep.
            include="$2"
            ;;
        v) ## PATTERN ## Don't count movies whose date in %Y-%m-%d format matches PATTERN. Syntax is the same as egrep.
            exclude="$2"
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
        [[ "$precision" == @(p_month|p_day) ]] && omit_zeroes=true || omit_zeroes=false
        ;;
    never)
        # These precisions are too complicated to support filling in zeroes for.
        [[ "$precision" == @(p_month|p_day) ]] && utils::error "PRECISION '$precision' does not support OMIT: '$omit_mode'"
        omit_zeroes=false
        ;;
esac

name_map=""

# Precisions which don't support omit_zeroes don't need to be here.
# -1 for min/max is a special value which means "use the lowest/highest value you find".
case "$precision" in
    p_year)                 pad=1  min=-1 max=-1  ;;
    p_quarter_of_year)      pad=1  min=1  max=4   ;;
    p_week_of_year)         pad=2  min=0  max=53  ;;
    p_week_of_year_monday)  pad=2  min=0  max=53  ;;
    p_day_of_year)          pad=3  min=1  max=366 ;;
    p_day_of_month)         pad=2  min=1  max=31  ;;
    # name_map will be split in awk to make an array. The array starts at 1, but p_day_of_week starts at 0.
    # So we'll actually add 1 to the index of everything (so months start at 2, days at 1), and add a dummy member for precisions that start at 1.
    p_month_of_year)        pad=2  min=1  max=12  name_map=",  January, February,    March,    April,      May,     June,     July,   August,September,  October, November, December" ;;
    p_day_of_week)          pad=1  min=0  max=6   name_map="   Sunday,   Monday,  Tuesday,Wednesday, Thursday,   Friday, Saturday" ;;
    p_day_of_week_monday)   pad=1  min=1  max=7   name_map=",   Monday,  Tuesday,Wednesday, Thursday,   Friday, Saturday,   Sunday" ;;
esac

set_precision_cut() {
    cut -d - -f "$1"
}

# This function is really slow. The alternative implementation using sed 's///e' is even slower.
set_precision_date() {
    local d

    while read -r d; do
        date -d "$d" +"$1"
    done
}

# Takes a bunch of lines containing dates in %Y-%m-%d format, and replaces the dates with the precision we desire.
set_precision() {
    case "$precision" in
        p_day)                  cat ;;
        p_year)                 set_precision_cut 1 ;;
        p_month)                set_precision_cut 1,2 ;;
        p_month_of_year)        set_precision_cut 2 ;;
        p_day_of_month)         set_precision_cut 3 ;;
        p_quarter_of_year)      set_precision_date %q ;;
        p_week_of_year)         set_precision_date %U ;;
        p_week_of_year_monday)  set_precision_date %W ;;
        p_day_of_year)          set_precision_date %j ;;
        p_day_of_week)          set_precision_date %w ;;
        p_day_of_week_monday)   set_precision_date %u ;;
    esac
}

tmp="$(mktemp)"

# The sed expression omits the header row and prepares data for parsing easier.
"$scripts"/mbrowse.py -vC "$datetype" $uniqflag -- "$@" | sed -En '2,$s/ //gp' |
    grep -E -- "$include" | grep -Ev -- "$exclude" | set_precision | sort | uniq -c |
    { $omit_zeroes && cat || gawk -v min="$min" -v max="$max" -v pad="$pad" '
        NR == 1 {
            last = (min == -1 ? $2 : min) - 1
        }
        1 {
            for (last++; last < $2; last++) printf "%d %.*d\n", 0, pad, last
            printf "%d %.*d\n", $1, pad, $2
        }
        END {
            if (max == -1) max = last
            if (NR == 0) last = (min == -1 ? max : min) - 1
            for (last++; last <= max; last++) printf "%d %.*d\n", 0, pad, last
        }'
    } | sort -s $sortkey | gawk -v name_map="$name_map" '
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
        }' > "$tmp"

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
        search="={1,$(utils::div_ceil "$maxline" "$width")}" # "$(utils::repeat = "$(utils::div_ceil "$maxline" "$width")" )"
        replace='='
    else # If longest line is shorter than it can be, stretch it.
        search='='
        replace="$(utils::repeat = "$(( width / maxline ))" )"
    fi
    
    sed -E "s/$search/$replace/g" -- "$tmp"
fi

rm -- "$tmp"
