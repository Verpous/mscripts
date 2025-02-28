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

# This is a library for parsing command line options (a la getopts), with a focus on brevity and easily adding the help option.
# Usage: source this script and call options::init. You may now call any API function, but in most cases you'll only need options::getopts.
# Recognized options characters are ripped straight from the case statement which handles them.
#
# Program help is ripped straight from comments which start with '##' (there are a few special forms).
# All special comment types MUST have a space after the '##' before the text begins.
# All the comments types:
# * Prologue "New-Line" comments: Lines of the form '## [TEXT]'. TEXT is treated as program description to print before the options list.
#   Note that the '##' MUST be the first characters on the line, not even spaces are allowed before them. This is true for all prologue and epilogue comment types.
# * Prologue "Continuation" comments: Lines of the form '##> [TEXT]>'. TEXT is appended to the previous line of prologue instead of being in its own line.
# * Epilogue New-Line and Continuation comments: '### [TEXT]' and '###> [TEXT]', same as prologue comments except these are printed *after* the options list.
# * Option "Case-Line" comments for options without an argument: Lines of the form 'OPTION-LETTER) ## [TEXT]'. TEXT is printed as a description for this option.
#   You can add additional spacing anywhere in this example, but you must not remove any.
#   For an option to be recognized, it MUST have a case-line comment.
# * Option "Case-Line" comments for options with an argument: Lines of the form 'OPTION-LETTER) ## METAVAR ## [TEXT]'.
#   METAVAR is the name of the argument this option takes. Again, these are mandatory, and you may add spaces but not remove any.
# * Option "New-Line" comments: Lines of the form '<spaces>## [TEXT]'. TEXT is treated as added description for the nearest previous case line.
#   Note that the line MUST begin with spaces to distinguish it from prologue new-line comments.
# * Option "Continuation" comments: Lines of the form '<spaces>##> [TEXT]'. Again, must be preceded by spaces, and continues the comment from the last line.
#
# Environment variables are supported inside special comments. Expressions such as '$VAR' or '${VAR}' are expanded according to the variables in the environment.
# A few variables are declared for your convenience:
# $DOLLAR   - expands to a literal '$', use to avoid unintended expansions.
# $SRC      - the full path to the script.
# $PROG     - the name of the script, with the file extension.
# $NAME     - the name of the script, without the file extension.

# We must capture these right away.
__options_src="${BASH_SOURCE[1]}"
__options_argv=("$@")

# options::init POSITIONAL
# Initializes options, which means you gain access to the other functions here.
# POSITIONAL is the usage string for positional arguments.
options::init() {
    __options_positional="$1"

    # Generating the options string for getopts from the case statements in the source file.
    # Options which specify a metavar are turned into options with an argument, the rest are without.
    __options_optstring=:"$(command sed -En '/^\s*([^[:space:]#:?*])\)\s+##\s/ { 
                                       s/^\s*(.)\)\s+##\s(\s*\w+\s*##\s)?.*$/\1\2/
                                       /../s/(.).*/\1:/
                                       p
                                   }' -- "$__options_src" | tr -d '\n')"

    # Automatically support help option. Error out if h option given.
    [[ "$__options_optstring" =~ h ]] && { echo "Error: option 'h' is reserved" >&2; exit 1; }
    __options_optstring+=h

    # All functions besides init are nested here so that they are only defined if initialized.
    # options::help
    # Prints help and exits.
    options::help() {
        # Most of the work is done in this subroutine, because we want to take all its output and pipe it through some extra stuff.
        options::help_internal() {
            # Printing the Usage line.
            echo "Usage: \$PROG [$(command tr -d ":" <<< "$__options_optstring")]... $__options_positional"
            
            # Prologue. That weird first expression in the second sed adds an extra newline if the description isn't empty.
            command sed -En '/^##>?\s/p' -- "$__options_src" | sed -Ez 's/^./\n&/ ; s/\n##>\s/ /g ; s/(^|\n)##\s/\1/g'
            echo

            # Now for the options help lines. It's a big pipeline.
            # Tread carefully, especially if you intend to change anything about spaces. Spaces are carefully placed where they are depended on.
            # I'll walk you through the pipeline step by step:
            # First sed, discards all non-comment lines from the file, and does some initial processing on comment lines. New-line comments are fully processed and ready to go after this.
            # After each comment type, there is a 't' statement which skips ahead to the next line so we don't accidentally read another comment type on the same line.
            command sed -En 's/^\s*([^[:space:]#:?*])\)\s+##\s/  -\1 /p ; t ; s/^\s+##\s/                /p ; t ; s/^\s+##>\s/##>/p' -- "$__options_src" |
                # Second sed, this one is for continuation comments. It uses -z to treat the whole stream as a single line, joins continuation comments to their previous line.
                command sed -Ez 's/\n##>/ /g' |
                # Awk for some heavy processing w.r.t. case-line comments. We need to catch optional metavars, discard all the garbage syntax around them, and align the text with spaces.
                # Case-line comments without a metavar also receive space-alignment, but it's much simpler.
                command gawk '/^  -.\s+\w+\s*##\s/ {
                        match($0, /^  -.\s+(\w+)/, dest)
                        spc_len = dest[1, "length"] <= 9 ? 9 - dest[1, "length"] : 0
                        spaces = sprintf("%*s", spc_len, "")
                        sub(/\s+\w+\s*##\s/, " " dest[1] "  ")
                        sub(/^  -. \w+/, "&" spaces)
                        print
                        next
                    }
                    /^  -. / {
                        sub(/^  -. /, "&           ")
                        print
                        next
                    }
                    1
                    END { print "  -h            Print this help and exit. If given twice, prints the entire source code." }'

            # Now doing the epilogue. It's the same as the intro, but with 3 #'s instead of 2.
            command sed -En '/^###>?\s/p' -- "$__options_src" | sed -Ez 's/^./\n&/ ; s/\n###>\s/ /g ; s/(^|\n)###\s/\1/g'
        }

        local width="$(command tput cols)"
        local prog="$(command basename -- "$__options_src")"

        # Expanding variables and formatting the entire thing.
        options::help_internal | DOLLAR=\$ PROG="$prog" NAME="${prog%.*}" SRC="$__options_src" command envsubst | command fmt "-$width" -s
        unset -f options::help_internal
        exit 0
    }

    options::source() {
        # View it in vim readonly mode so that you get syntax highlighting. But if output is a tty vim will fail.
        if [[ -t 1 ]]; then
            command vim -M -- "$__options_src"
        else
            command cat -- "$__options_src"
        fi

        exit 0
    }

    # options::getopts HANDLER MANDATORY_NUM
    # Parses options and invokes HANDLER on each one with $1=the option character, $2=the option's argument (if it takes one).
    # Exits with help if there are fewer than MANDATORY_NUM positional arguments provided. Pass a negative value to ignore.
    # Sets $options_shift to the number you should pass to 'shift' to discard the processed arguments.
    options::getopts() {
        local arg
        local nhelps=0
        
        while getopts "$__options_optstring" arg "${__options_argv[@]}"; do
            case "$arg" in
                h)
                    (( nhelps++ ))
                    ;;
                \?)
                    echo "Invalid option: $OPTARG" >&2
                    exit 1
                    ;;
                :)
                    # If a known option that requires an argument is given with no argument,
                    # getopts sets arg=:, OPTARG=the option letter.
                    echo "Invalid option: $OPTARG requires an argument" >&2
                    exit 1
                    ;;
                *)
                    "$1" "$arg" "$OPTARG"
                    ;;
            esac
        done

        if (( nhelps > 1 )); then
            options::source
        elif (( nhelps == 1 )); then
            options::help
        fi
        
        options_shift=$(( OPTIND - 1 ))
        (( "$2" >= 0 && "$2" > ${#__options_argv[@]} - options_shift )) && options::help
    }

    # options::optstring
    # Returns the options string that getopts accepts.
    options::get_optstring() {
        echo -n "$__options_optstring"
    }
}
