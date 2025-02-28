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

## Prints how the movies from JSONs distribute over various ways.
## DISTRIBUTION is how you'd like to see movies distributed. All are explained below.
## JSON is a list to operate on, which was output by mfetch. Accepts whatever mbrowse would accept.

### DISTRIBUTION may be any one of:
### 
###   [release|watch]-year
###   [release|watch]-month
###   [release|watch]-day
###   [release|watch]-month-of-year
###   [release|watch]-week-of-year
###   [release|watch]-week-of-year-monday
###   [release|watch]-day-of-year
###   [release|watch]-day-of-month
###   [release|watch]-day-of-week
###   [release|watch]-day-of-week-monday
###   rating[-granular]
###   metascore[-granular]
###   my-rating
###   leaving
###   crew-size[-granular]
###   title-length
###   run-time[-granular]
###   votes[-granular]
### 
### Convenient shorthands are supported: 't-l' for 'title-length', 'm-g' for 'metascore-granular', 'w-d-o-w-m' for 'watch-day-of-week-monday', etc.
### The 'monday' distributions treat Monday as the first day of the week. By default Sunday is the first day.
### 
### About -g, -v: for release and watched distributions, the pattern is matched against the respective date in YYYY-MM-DD format.
###> For crew-size, it's the output of 'mbrowse --dsv "|" --verbose --columns <the desired crew types>'
###> For the rest, it's matched against the respective value as it is printed by 'mbrowse --verbose'.

# Try to maintain this list of all distributions. It's helpful for debugging.
# release-year release-month release-day release-month-of-year release-week-of-year release-week-of-year-monday release-day-of-year release-day-of-month release-day-of-week release-day-of-week-monday watch-year watch-month watch-day watch-month-of-year watch-week-of-year watch-week-of-year-monday watch-day-of-year watch-day-of-month watch-day-of-week watch-day-of-week-monday leaving rating rating-granular my-rating metascore metascore-granular crew-size title-length run-time votes votes-granular crew-size-granular run-time-granular

scripts="$(dirname -- "$BASH_SOURCE")"
source "$scripts"/options.sh
source "$scripts"/utils.sh
shopt -s extglob

omit_mode=auto
omit_zeroes=false
sortkey=2,2
append_nmovies=1
compact=true
bopts=()
fit=0
crews=*
title=true
prepend_key=1
append_key=0
handle_option() {
    case "$1" in
        o) ## OMIT ## Choose whether to omit buckets with 0 movies. Options are 'always', 'auto', or 'never'.
           ##> Defaults to 'auto', which uses a mode that depends on DISTRIBUTION.
            [[ "${2,,}" != @(always|auto|never) ]] && utils::die "Invalid OMIT: '$2'"
            omit_mode="${2,,}"
            ;;
        s) ## Sort based on the table values, not the keys.
            sortkey=1,1
            ;;
        n) ## Don't append the numerical value to each bar.
            append_nmovies=0
            ;;
        g) ## PATTERN ## Only count movies which match PATTERN. Syntax is like egrep. What is matched against depends on DISTRIBUTION, see below.
            include="$2"
            ;;
        v) ## PATTERN ## Opposite of -g. DON'T count the movies that match.
            exclude="$2"
            ;;
        S) ## Space out the table.
            compact=false
            ;;
        b) ## OPTS ## Semicolon-delimited options to pass to mbrowse. Use at your own risk. Mainly for -u, -x.
            readarray -td \; bopts < <(echo -n "$2")
            ;;
        f) ## FACTOR ## Define custom scaling factor to apply to the table. Defaults to 0, which means a value will be computed to make the table fit in the terminal width.
           ## Positive numbers stretch, negatives squish.
            fit="$2"
            ;;
        c) ## CREWS ## Comma-delimited list of crew types to count in crew-size distribution. Defaults to '*', which means all crew types.
            crews="$2"
            ;;
        t) ## Don't print a title.
            title=false
            ;;
        k) ## Don't write the key at the start of each bar.
            prepend_key=0
            ;;
        K) ## Append the key to the end of each bar.
            append_key=1
            ;;
    esac
}

options::init "DISTRIBUTION [JSON]..."
options::getopts handle_option 1
shift $options_shift

case "${1,,}" in
    # All start with 'd', then the key to distribute on, then the distribution.
    r?(elease)-y?(ear?(s)))                                     distribution=d_release_year                 ;;
    r?(elease)-m?(onth?(s)))                                    distribution=d_release_month                ;;
    r?(elease)-d?(ay?(s)))                                      distribution=d_release_day                  ;;
    r?(elease)-m?(onth?(s))-o?(f)-y?(ear?(s)))                  distribution=d_release_month_of_year        ;;
    r?(elease)-w?(eek?(s))-o?(f)-y?(ear?(s)))                   distribution=d_release_week_of_year         ;;
    r?(elease)-w?(eek?(s))-o?(f)-y?(ear?(s))-m?(onday?(s)))     distribution=d_release_week_of_year_monday  ;;
    r?(elease)-d?(ay?(s))-o?(f)-y?(ear?(s)))                    distribution=d_release_day_of_year          ;;
    r?(elease)-d?(ay?(s))-o?(f)-m?(onth?(s)))                   distribution=d_release_day_of_month         ;;
    r?(elease)-d?(ay?(s))-o?(f)-w?(eek?(s)))                    distribution=d_release_day_of_week          ;;
    r?(elease)-d?(ay?(s))-o?(f)-w?(eek?(s))-m?(onday?(s)))      distribution=d_release_day_of_week_monday   ;;
    w?(atch?(ed))-y?(ear?(s)))                                  distribution=d_watch_year                   ;;
    w?(atch?(ed))-m?(onth?(s)))                                 distribution=d_watch_month                  ;;
    w?(atch?(ed))-d?(ay?(s)))                                   distribution=d_watch_day                    ;;
    w?(atch?(ed))-m?(onth?(s))-o?(f)-y?(ear?(s)))               distribution=d_watch_month_of_year          ;;
    w?(atch?(ed))-w?(eek?(s))-o?(f)-y?(ear?(s)))                distribution=d_watch_week_of_year           ;;
    w?(atch?(ed))-w?(eek?(s))-o?(f)-y?(ear?(s))-m?(onday?(s)))  distribution=d_watch_week_of_year_monday    ;;
    w?(atch?(ed))-d?(ay?(s))-o?(f)-y?(ear?(s)))                 distribution=d_watch_day_of_year            ;;
    w?(atch?(ed))-d?(ay?(s))-o?(f)-m?(onth?(s)))                distribution=d_watch_day_of_month           ;;
    w?(atch?(ed))-d?(ay?(s))-o?(f)-w?(eek?(s)))                 distribution=d_watch_day_of_week            ;;
    w?(atch?(ed))-d?(ay?(s))-o?(f)-w?(eek?(s))-m?(onday?(s)))   distribution=d_watch_day_of_week_monday     ;;
    l?(eaving))                                                 distribution=d_leaving                      ;;
    r?(ating))                                                  distribution=d_rating                       ;;
    r?(ating)-g?(ranular))                                      distribution=d_rating_granular              ;;
    m?(y)-r?(ating))                                            distribution=d_myrating                     ;;
    m?(etascore))                                               distribution=d_metascore                    ;;
    m?(etascore)-g?(ranular))                                   distribution=d_metascore_granular           ;;
    c?(rew)-s?(ize?(s)))                                        distribution=d_crew                         ;;
    c?(rew)-s?(ize?(s))-g?(ranular))                            distribution=d_crew_granular                ;;
    t?(itle)-l?(ength))                                         distribution=d_title                        ;;
    v?(ote?(s)))                                                distribution=d_votes                        ;;
    v?(ote?(s))-g?(ranular))                                    distribution=d_votes_granular               ;;
    r?(un)-t?(ime?(s)))                                         distribution=d_runtime                      ;;
    r?(un)-t?(ime?(s))-g?(ranular))                             distribution=d_runtime_granular             ;;
    *)                                                          utils::die "Invalid DISTRIBUTION: '$1'"     ;;
esac

shift

case "$omit_mode" in
    always)
        omit_zeroes=true
        ;;
    auto)
        [[ "$distribution" == d_@(release|watch)_@(month|day) ]] && omit_zeroes=true || omit_zeroes=false
        ;;
    never)
        # These distributions are too complicated to support filling in zeroes for.
        [[ "$distribution" == d_@(release|watch)_@(month|day) ]] && utils::die "DISTRIBUTION '$distribution' does not support OMIT: '$omit_mode'"
        omit_zeroes=false
        ;;
esac

# Here goes column configuration.
case "$distribution" in
    d_release*)     column=release    ;;
    d_watch*)       column=watched    ;;
    d_leaving*)     column=leaving    ;;
    d_rating*)      column=rating     ;;
    d_myrating*)    column=myrating   ;;
    d_metascore*)   column=metascore  ;;
    d_title*)       column=title      ;;
    d_runtime*)     column=runtime    ;;
    d_votes*)       column=votes      ;;
    d_crew*)
        [[ "$crews" == '*' ]] && crews="$("$scripts"/mprint.py -p cast | head -c -1 | tr '\n' ,)"
        column="$crews"
        ;;
    *) utils::die "Error: no column for DISTRIBUTION: $distribution" ;;
esac

# Here goes sort type configuration.
case "$distribution" in
    # All date distributions output numbers with zero padding such that lexicographic sort == numerical sort.
    d_@(release|watch)*)                                                sorttype=""  ;;
    # Rating distributions do not use this padding so they need to be treated as numbers.
    d_@(rating|myrating|metascore|leaving|crew|title|runtime|votes)*)   sorttype=-n  ;;
esac

# If the table should be sorted by values instead of keys then it's always -n, otherwise it's the same as the key type.
[[ "$sortkey" == "1,1" ]] && result_sorttype=-n || result_sorttype="$sorttype"

# Here goes date format configuration.
case "$distribution" in
    d_@(release|watch)_year)                fmt=%Y        ;;
    d_@(release|watch)_week_of_year)        fmt=%U        ;;
    d_@(release|watch)_week_of_year_monday) fmt=%W        ;;
    d_@(release|watch)_day_of_year)         fmt=%j        ;;
    d_@(release|watch)_day_of_month)        fmt=%d        ;;
    d_@(release|watch)_month_of_year)       fmt=%m        ;;
    d_@(release|watch)_day_of_week)         fmt=%w        ;;
    d_@(release|watch)_day_of_week_monday)  fmt=%u        ;;
    d_@(release|watch)_day)                 fmt=%Y-%m-%d  ;;
    d_@(release|watch)_month)               fmt=%Y-%m     ;;
esac

# Here goes omit zeroes configuration (some distributions don't support it and aren't here).
# 'x' for min/max is a special value which means "use the lowest/highest value you find".
case "$distribution" in
    d_@(release|watch)_year)                zeropad=4  min=x   max=x    ;;
    d_@(release|watch)_week_of_year)        zeropad=2  min=0   max=53   ;;
    d_@(release|watch)_week_of_year_monday) zeropad=2  min=0   max=53   ;;
    d_@(release|watch)_day_of_year)         zeropad=3  min=1   max=366  ;;
    d_@(release|watch)_day_of_month)        zeropad=2  min=1   max=31   ;;
    d_@(release|watch)_month_of_year)       zeropad=2  min=1   max=12   ;;
    d_@(release|watch)_day_of_week)         zeropad=1  min=0   max=6    ;;
    d_@(release|watch)_day_of_week_monday)  zeropad=1  min=1   max=7    ;;
    d_leaving)                              zeropad=1  min=x   max=x    ;;
    d_rating)                               zeropad=1  min=1   max=10   ;;
    d_rating_granular)                      zeropad=1  min=10  max=100  ;;
    d_myrating)                             zeropad=1  min=1   max=10   ;;
    d_metascore)                            zeropad=1  min=0   max=10   ;;
    d_metascore_granular)                   zeropad=1  min=0   max=100  ;;
    d_crew*)                                zeropad=1  min=0   max=x    ;;
    d_runtime*)                             zeropad=1  min=0   max=x    ;;
    d_votes*)                               zeropad=1  min=0   max=x    ;;
    d_title)                                zeropad=1  min=1   max=x    ;;
esac

# Here goes table formatting configuration.
case "$distribution" in
    # name_map will be split in awk to make an array. The array starts at 1. Some fields start at 0, so in awk we index at [i + 1].
    # This means fields that start at 1 will need 1 dummy field in the beginning to make them start at 2, etc.
    d_@(release|watch)_month_of_year)       spacepad=9   namefunc=dictmap      name_map=";January;February;March;April;May;June;July;August;September;October;November;December" ;;
    d_@(release|watch)_day_of_week)         spacepad=9   namefunc=dictmap      name_map="Sunday;Monday;Tuesday;Wednesday;Thursday;Friday;Saturday" ;; # Sunday=0; so we need one dummy at the start.
    d_@(release|watch)_day_of_week_monday)  spacepad=9   namefunc=dictmap      name_map=";Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday" ;;
    d_rating)                               spacepad=7   namefunc=dictmap      name_map="0.0-0.9;1.0-1.9;2.0-2.9;3.0-3.9;4.0-4.9;5.0-5.9;6.0-6.9;7.0-7.9;8.0-8.9;9.0-9.9;10.0" ;;
    d_rating_granular)                      spacepad=4   namefunc=dictmap      name_map="$(echo {0..100} | sed -E 's/([0-9]*)([0-9])/\1.\2/g ; y/ /;/')" ;; # 0..9 are only here to pad the array.
    d_metascore)                            spacepad=5   namefunc=dictmap      name_map="00-09;10-19;20-29;30-39;40-49;50-59;60-69;70-79;80-89;90-99;100" ;;
    d_votes)                                spacepad=15  namefunc=bucketvotes  votepow=5 ;;
    d_votes_granular)                       spacepad=15  namefunc=bucketvotes  votepow=4 ;;
    d_crew)                                 spacepad=11  namefunc=bucket10     ;;
    d_runtime)                              spacepad=11  namefunc=bucket10     ;;
    d_myrating)                             spacepad=3   namefunc=identity     ;;
    d_metascore_granular)                   spacepad=3   namefunc=identity     ;;
    d_leaving)                              spacepad=5   namefunc=identity     ;;
    d_crew_granular)                        spacepad=5   namefunc=identity     ;;
    d_title)                                spacepad=4   namefunc=identity     ;;
    d_runtime_granular)                     spacepad=5   namefunc=identity     ;;
    d_@(release|watch)_day)                 spacepad=10  namefunc=identity     ;;
    d_@(release|watch)_month)               spacepad=7   namefunc=identity     ;;
    *)                                      spacepad=1   namefunc=identity     ;;
esac

# If include/exclude are requested, we'll append them to the fmt so we can sed on those patterns.
[[ ! "$include" && ! "$exclude" ]] || fmt+="#%Y-%m-%d"

trap 'rm -f -- "$tmp"' EXIT
tmp="$(mktemp)" # Fit to screen step requires a double pass on the file.
sep=$'\x1F'     # Character that certainly won't be given as input PATTERNs for -v, -g so we can use it as the sed separator.
na=-2147483648  # Empty values '-' will be mapped to this instead, because it sorts at the beginning both numerically and lexicographically.

div_pow_of_10() {
    sed -E "s/^[0-9]{1,$1}$/0/g ; t ; s/[0-9]{$1}$//g"
}

# First: mbrowse. For most distributions, --dsv only means we don't pad the output with spaces.
# For crew-size and title-length, the DSV delimiter matters and -v matters too. -v is also important for votes.
"$scripts"/mbrowse.py --dsv \| -tv -C "$column" -f "$fmt" "${bopts[@]}" -- "$@" |
    # Taking care of -g, -v if provided.
    if [[ ! "$include" && ! "$exclude" ]]; then
        cat
    else
        [[ ! "$include" ]] && include=. # This will always match
        [[ ! "$exclude" ]] && exclude='This will never match'

        case "$distribution" in
            d_@(release|watch)*)
                # Time distributions append the full date just for this.
                sed -En "
                    h                           # Store the full line for later.
                    s/^.*#(.*)$/\1/g            # Examine just the full date which we appended after a '#'
                    \\${sep}${exclude}${sep}b   # Skip this line if it matches the exclude pattern.
                    \\${sep}${include}${sep}!b  # Skip this line if it doesn't match the include pattern.
                    g                           # Restore the full line we backed up earlier.
                    s/^(.*)#.*$/\1/gp           # Keep only the date we wish to examine for this distribution."
                ;;
            *)
                # Rating distributions are simple.
                grep -Ev -- "$exclude" | grep -E -- "$include"
                ;;
        esac
    fi | 
    case "$distribution" in
        d_rating)               cut -d . -f 1 ;;
        d_rating_granular)      tr -d . ;;
        d_metascore)            div_pow_of_10 1 ;; # This means 100 will be in its own category.
        d_crew)                 gawk '{ printf "%d\n", gsub(/(^[^|-])|\|[^|-]|,/, "") }' | div_pow_of_10 1 ;; # This only works if there are no commas in people's names. I checked, there aren't.
        d_crew_granular)        gawk '{ printf "%d\n", gsub(/(^[^|-])|\|[^|-]|,/, "") }' ;;
        d_title)                gawk '{ printf "%d\n", length($0) }' ;;
        d_runtime)              gawk -F : '!/^-$/ { printf "%d\n", 60 * $1 + $2 }' | div_pow_of_10 1 ;;
        d_runtime_granular)     gawk -F : '!/^-$/ { printf "%d\n", 60 * $1 + $2 }' ;;
        d_votes*)               tr -d , | div_pow_of_10 "$votepow" ;;
        *)                      cat ;;
    esac | sed -E "s/^-$/$na/g" | sort $sorttype | uniq -c | # Creating count of how many times each date appears.
    # We'll take care of adding in missing dates depending on omit_zeroes.
    if $omit_zeroes; then
        cat
    else
        gawk -v min="$min" -v max="$max" -v zeropad="$zeropad" -v na="$na" '
            function myprint(nmovies, key) { printf "%d %.*d\n", nmovies, zeropad, key }
            $2 == na {
                print
            }
            $2 != na && last == "" {
                last = (min == "x" ? $2 : min) - 1
            }
            $2 != na {
                for (last++; last < $2; last++) myprint(0, last)
                myprint($1, $2)
            }
            END {
                if (max != "x" && (last != "" || min != "x")) {
                    if (last == "") last = min - 1
                    for (last++; last <= max; last++) myprint(0, last)
                }
            }'
    fi | sort -s $result_sorttype -k "$sortkey" |
    # We have everything we need to make a table now.
    gawk -v spacepad="$spacepad" -v na="$na" -v namefunc="$namefunc" -v name_map="$name_map" -v votepow="$votepow" \
        -v append_nmovies="$append_nmovies" -v append_key="$append_key" -v prepend_key="$prepend_key" '
        function identity(i) {
            return i
        }
        function dictmap(i) {
            return mapping[i + 1] == "" ? i : mapping[i + 1]
        }
        function bucket10(i) {
            return i == 0 ? "0-9" : sprintf("%s0-%s9", i, i)
        }
        function bucketvotes(i) {
            return i == 0 ? sprintf("0-1%s", votezeroes) : sprintf("%d%s-%d%s", i, votezeroes, i + 1, votezeroes)
        }
        BEGIN {
            split(name_map, mapping, ";")
            votezeroes = votepow == 4 ? "0K" : "00K" # Only 4, 5 are supported.
        }
        1 {
            bar = ""
            for (i = 0; i < $1; i++) bar = bar "="
            n = $2 == na ? "N/A" : @namefunc($2)
            printf "  %s|%s%s%s\n", (!prepend_key ? "" : sprintf("%*s", spacepad, n)), bar, (!append_nmovies ? "" : $1 > 0 ? " " $1 : $1), (!append_key ? "" : sprintf(" (%s)", n))
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
    if (( fit == 0 )); then
        # Margin makes room for characters in the line that aren't the '=' signs.
        keylen="$(utils::max "$zeropad" "$spacepad")"
        (( margin = 5 + keylen * prepend_key + (keylen + 3) * append_key + 6 * append_nmovies))    
        width="$(( "$(utils::max "$(tput cols)" "$margin" )" - margin + 1 ))"
    fi
    
    # If longest line is too long, squish it.
    if (( fit < 0 || (fit == 0 && maxline >= width) )); then
        (( fit == 0 )) && (( fit = "$(utils::div_ceil "$maxline" "$width")" )) || (( fit *= -1 ))
        # Matching {1,ceil(maxline/width)} occurences of '='. This makes the amount of '='s be reduced to ceil(nmovies/ceil(maxline/width)).
        # This is guaranteed to not exceed width, and makes bars of < ceil(maxline/width) turn into 1 '=' not 0.
        # It works because regex matching is greedy.
        search="={1,$fit}"
        replace='='
    else # If longest line is shorter than it can be, stretch it.
        (( fit == 0 )) && (( fit = width / maxline ))
        search='='
        replace="$(utils::repeat = "$fit" )"
    fi
    
    sed -Ei "s/$search/$replace/g" -- "$tmp"
fi

$title && case "$distribution" in
    d_release_year)                 echo "Number of Movies Released Per Year" ;;
    d_release_month)                echo "Number of Movies Released Per Month" ;;
    d_release_day)                  echo "Number Of Movies Released Per Day" ;;
    d_release_month_of_year)        echo "Number of Movies Released Per Month of a Year" ;;
    d_release_week_of_year)         echo "Number of Movies Released Per Week of a Year (Weeks Start at Sunday)" ;;
    d_release_week_of_year_monday)  echo "Number of Movies Released Per Week of a Year (Weeks Start at Monday)" ;;
    d_release_day_of_year)          echo "Number of Movies Released Per Day of a Year" ;;
    d_release_day_of_month)         echo "Number of Movies Released Per Day of a Month" ;;
    d_release_day_of_week)          echo "Number of Movies Released Per Day of a Week (Weeks Start at Sunday)" ;;
    d_release_day_of_week_monday)   echo "Number of Movies Released Per Day of a Week (Weeks Start at Monday)" ;;
    d_watch_year)                   echo "Number of Movies Watched Per Year" ;;
    d_watch_month)                  echo "Number of Movies Watched Per Month" ;;
    d_watch_day)                    echo "Number Of Movies Watched Per Day" ;;
    d_watch_month_of_year)          echo "Number of Movies Watched Per Month of a Year" ;;
    d_watch_week_of_year)           echo "Number of Movies Watched Per Week of a Year (Weeks Start at Sunday)" ;;
    d_watch_week_of_year_monday)    echo "Number of Movies Watched Per Week of a Year (Weeks Start at Monday)" ;;
    d_watch_day_of_year)            echo "Number of Movies Watched Per Day of a Year" ;;
    d_watch_day_of_month)           echo "Number of Movies Watched Per Day of a Month" ;;
    d_watch_day_of_week)            echo "Number of Movies Watched Per Day of a Week (Weeks Start at Sunday)" ;;
    d_watch_day_of_week_monday)     echo "Number of Movies Watched Per Day of a Week (Weeks Start at Monday)" ;;
    d_leaving)                      echo "Number of Movies Per Number of Days Until They Leave" ;;
    d_rating?(_granular))           echo "Number of Movies Per IMDb Rating" ;;
    d_myrating)                     echo "Number of Movies Per My IMDb Rating" ;;
    d_metascore)                    echo "Number of Movies Per Metascore" ;;
    d_metascore_granular)           echo "Number of Movies Per Metascore" ;;
    d_crew?(_granular))             echo "Number of Movies Per Crew Size For Crew Types: $crews" ;;
    d_title)                        echo "Number of Movies Per Title Length" ;;
    d_votes?(_granular))            echo "Number of Movies Per Number of Votes on IMDb" ;;
    d_runtime?(_granular))          echo "Number of Movies Per Runtime (Minutes)" ;;
    *)                              utils::die "Error: no title for DISTRIBUTION: $distribution" ;;
esac

cat -- "$tmp"
