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
# Usage: source this script and call options::init. You may now call options::help whenever you want, and you can call options::getopts.
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
# Another supported feature is Comment Variables. Inside special comments you can type variable names using a special syntax which expands them to their value.
# The syntax for variables is '##VARIABLE', written inside a comment (note the no spaces between the ## an the variable's name).
# Supported variables are:
# ##PROG - the name of the script, with the file extension.
# ##NAME - the name of the script, without the file extension.
# ##NUM where NUM is a number between 0 and 9 (e.g., ##0): custom variables which you can assign values to by them to options::init.
# Variables can't include the characters '/', '\', or '&'.

# We must capture these right away.
options_src="${BASH_SOURCE[1]}"
options_argv=("$@")

# Arg $1: A description of your mandatory arguments to be displayed by options::help in the usage line.
# Args $2..${11}: Values that the comment variables ##0...##9 will expand to.
# Initializes options, which means you gain access to the other functions here.
options::init() {
    options_mandatory="$1"
    options_variables=("${@:2}")

    # Generating the options string for getopts from the case statements in the source file.
    # Options which specify a metavar are turned into options with an argument, the rest are without.
    options_optstring=:"$(sed -En '/^\s*([^[:space:]#:?*])\)\s+##\s/ { 
                                       s/^\s*(.)\)\s+##\s(\s*\w+\s*##\s)?.*$/\1\2/
                                       /../s/(.).*/\1:/
                                       p
                                   }' -- "$options_src" | tr -d '\n')"

    # Automatically support help option. Error out if h option given.
    [[ "$options_optstring" =~ h ]] && { echo "Error: option 'h' is reserved" >&2; exit 1; }
    options_optstring+=h

    # All functions besides init are nested here so that they are only defined if initialized.
    # No arguments. Prints help and exits.
    options::help() {
        # Most of the work is done in this subroutine, because we want to take all its output and pipe it through some extra stuff.
        options::help_internal() {
            # Printing the Usage line.
            echo "Usage: ##PROG [$(tr -d ":" <<< "$options_optstring")]... $options_mandatory"
            
            # Prologue. That weird first expression in the second sed adds an extra newline if the description isn't empty.
            sed -En '/^##>?\s/p' -- "$options_src" | sed -Ez 's/^./\n&/ ; s/\n##>\s/ /g ; s/(^|\n)##\s/\1/g'
            echo

            # Now for the options help lines. It's a big pipeline.
            # Tread carefully, especially if you intend to change anything about spaces. Spaces are carefully placed where they are depended on.
            # I'll walk you through the pipeline step by step:
            # First sed, discards all non-comment lines from the file, and does some initial processing on comment lines. New-line comments are fully processed and ready to go after this.
            # After each comment type, there is a 't' statement which skips ahead to the next line so we don't accidentally read another comment type on the same line.
            sed -En 's/^\s*([^[:space:]#:?*])\)\s+##\s/  -\1 /p ; t ; s/^\s+##\s/                /p ; t ; s/^\s+##>\s/##>/p' -- "$options_src" |
                # Second sed, this one is for continuation comments. It uses -z to treat the whole stream as a single line, joins continuation comments to their previous line.
                sed -Ez 's/\n##>/ /g' |
                # Awk for some heavy processing w.r.t. case-line comments. We need to catch optional metavars, discard all the garbage syntax around them, and align the text with spaces.
                # Case-line comments without a metavar also receive space-alignment, but it's much simpler.
                gawk '/^  -.\s+\w+\s*##\s/ {
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
                    END { print "  -h            Display this help and exit." }'

            # Now doing the epilogue. It's the same as the intro, but with 3 #'s instead of 2.
            sed -En '/^###>?\s/p' -- "$options_src" | sed -Ez 's/^./\n&/ ; s/\n###>\s/ /g ; s/(^|\n)###\s/\1/g'
        }

        local width="$(tput cols)"
        local prog="$(basename -- "$options_src")"
        local seds=()
        local i=0
        local var

        # $1: variable name, $2: value.
        options::add_variable() {
            # The characters '/', '\', '&' are banned in variables because they are sed special characters.
            [[ ! "$2" =~ [/\\\&] ]] && seds+=("s/##$1/$2/g;") || seds+=("s/##$1/OPTIONS_ILLEGAL_VAR/g;")
        }

        options::add_variable PROG "$prog"
        options::add_variable NAME "${prog%.*}"

        for var in "${options_variables[@]}"; do
            options::add_variable "$i" "$var"
            (( i++ ))
        done

        # Expanding variables and formatting the entire thing.
        options::help_internal | sed -E "${seds[*]}" | fmt "-$width" -s
        unset -f options::help_internal
        unset -f options::add_variable
        exit 0
    }

    # Arg 1: The name of an option handler function. It is invoked with $1=the option character, $2=the option's argument (if it takes one).
    # Arg 2: The number of mandatory arguments your script takes. In case of fewer arguments, will exit with help. Pass a negative value to ignore this.
    # Invokes the handler on all option arguments, then sets $OPTIONS_SHIFT to the number you should pass to 'shift' to discard the processed arguments.
    options::getopts() {
        while getopts "$options_optstring" arg "${options_argv[@]}"; do
            case "$arg" in
                h)
                    options::help
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

        OPTIONS_SHIFT=$(( OPTIND - 1 ))
        (( "$2" >= 0 && "$2" > ${#options_argv[@]} - OPTIONS_SHIFT )) && options::help
    }
}
