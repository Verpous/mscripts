#! python

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

# TODO: I'm running out of steam here but I'll write down ideas for the future:
# * A whole new take on mscripts: forget mpeople and mgrep,
#    all you need is mbrowse-like output with an entry not just per movie but per person per movie, with a file per crew type.
#    This easily combines with regular grep, and could even combine with awk if we introduce a good separator character (option that's shorthand for -d $'\x1F'?).
#    Then for mpeople, you could create a totally new script with mbrowse-like output but instead of being movie focused, make it people-focused.
#    Like, each line would be: person, number of movies, number of groups he belongs in, average rating, average metascore, average myrating, years active,
#    oldest movie, youngest movie, top rated movie by rating/metascore/myrating, worst rated movie by rating/metascore/myrating, there's a lot we could do...
#    Problems with this: where do you show groups, how do you stay concise?
#    As a partial step in this direction, I can add an option to mbrowse which tells it to make entries per person per movie, per crew type column which is to be printed??
# * Refactor: add a Key class which specifies its aliases and maybe extra data like "should be sorted" (for crew type columns).
#    This way you eliminate the code repetition when using the same key in multiple key types.
# * Refactor: pick one of mbrowse or mprint to double as a library when not run with __name__ == "main".
#    Put all the code there that is shared between different scripts, and import it from the other scripts to eliminate code repetition.
# * Expand mconfig to include default mbrowse options, parse mconfig in here and support mbrowsing categories.

import json
import sys
import datetime
import argparse
import tempfile
import os
import csv
import tempfile
import subprocess

try:
    from colorama import just_fix_windows_console
    just_fix_windows_console()
except:
    print('Failed to import Colorama. Colored output may be wrong. You should run "pip install colorama" and make sure you have at least v0.4.6', file=sys.stderr)

class Movie:
    def __init__(self, obj, source):
        self.obj = obj
        self.source = source
        self.record = None

    def get_title(self, lower=False):
        return self.obj['title'].lower() if lower else self.obj['title']

    def get_runtime(self, default=None):
        return int(self.obj['runtime']) if len(self.obj['runtime']) > 0 else default

    def get_released(self):
        return datetime.datetime.strptime(self.obj['released'], '%Y-%m-%d')

    def get_watched(self):
        return datetime.datetime.strptime(self.obj['watched'], '%Y-%m-%d')

    def get_rating(self):
        return float(self.obj['rating'])

    def get_votes(self):
        return int(self.obj['votes'])

    def get_metascore(self, default=None):
        return int(self.obj['metascore']) if self.obj['metascore'] != '-1' else default

    def get_myrating(self, default=None):
        return int(self.obj['myrating']) if len(self.obj['myrating']) > 0 else default

    def get_days_left(self, default=None):
        try:
            date = datetime.datetime.strptime(self.get_description(), '%Y-%m-%d')
        except:
            return default

        return (date - datetime.datetime.today()).days

    def get_description(self):
        return self.obj['description']

    def get_crew(self, crew_type, lower=False, default=None):
        if len(self.obj[crew_type]) == 0:
            return default

        # Some crew types should be sorted, some not. It's the same as which should be grouped and which not.
        sort_crew = {
            ct_cast: False,
            ct_producer: False,
            ct_stunt_performer: False,
            ct_editor: True,
            ct_writer: True,
            ct_director: True,
            ct_composer: True,
            ct_cinematographer: True,
        }

        crew = (member['name'].lower() if lower else member['name'] for member in self.obj[crew_type])

        # The list returned may not be lower, but it's always sorted as if it was.
        return sorted(crew, key=str.lower) if sort_crew[crew_type] else list(crew)

    def get_iden(self):
        return self.obj['imdbID']

    def __eq__(self, o):
        return isinstance(o, Movie) and self.get_iden() == o.get_iden()

    def __ne__(self, o):
        return not self == o

    def __hash__(self):
        return hash(self.get_iden())

def alias(valid_items, aliases, item):
    aliases.update({ key: key for key in valid_items })
    with_dash = { key.replace(' ', '-'): value for key, value in aliases.items() if ' ' in key }
    with_underscore = { key.replace(' ', '_'): value for key, value in aliases.items() if ' ' in key }
    no_spaces = { key.replace(' ', ''): value for key, value in aliases.items() if ' ' in key }
    aliases.update(with_dash)
    aliases.update(with_underscore)
    aliases.update(no_spaces)

    item = item.lower()
    if item not in aliases:
        raise ValueError()

    return aliases[item]

def aliases(alias_func, items):
    return [alias_func(item) for item in str.split(items, sep=',')]

def crew_alias(crew_type):
    aliases = {
        'actor': ct_cast,
        'actors': ct_cast,
        'directors': ct_director,
        'writers' : ct_writer,
        'producers' : ct_producer,
        'composers' : ct_composer,
        'cinematographers' : ct_cinematographer,
        'editors' : ct_editor,
        'stunt actor' : ct_stunt_performer,
        'stunt actors' : ct_stunt_performer,
        'stunt performers' : ct_stunt_performer,
        'stunt cast' : ct_stunt_performer,
    }
    return alias(valid_crew_types, aliases, crew_type)

def sort_alias(sort_key):
    aliases = {
        'rdate': sk_released,
        'release date': sk_released,
        'released date': sk_released,
        'date released': sk_released,
        'release': sk_released,
        'wdate': sk_watched,
        'watch date': sk_watched,
        'watched date': sk_watched,
        'date watched': sk_watched,
        'nosort': sk_nosort,
        '': sk_nosort,
        'ratings': sk_rating,
        'number of votes': sk_votes,
        'num of votes': sk_votes,
        'num votes': sk_votes,
        'vote num': sk_votes,
        'vote count': sk_votes,
        'critic score': sk_metascore,
        'critic scores': sk_metascore,
        'critic rating': sk_metascore,
        'critic ratings': sk_metascore,
        'self rating': sk_myrating,
        'self ratings': sk_myrating,
        'personal rating': sk_myrating,
        'personal ratings': sk_myrating,
        'my score': sk_myrating,
        'my scores': sk_myrating,
        'self score': sk_myrating,
        'self scores': sk_myrating,
        'personal score': sk_myrating,
        'personal scores': sk_myrating,
        'alpha': sk_alpha,
        'alphabetic': sk_alpha,
        'lexicographic': sk_alpha,
        'name': sk_alpha,
        'title': sk_alpha,
        'movie': sk_alpha,
        'length': sk_runtime,
        'minutes': sk_runtime,
        'time': sk_runtime,
        'days left': sk_leaving,
        'leave date': sk_leaving,
        'leaves': sk_leaving,
        'days remaining': sk_leaving,
        'explanation': sk_description,
        'desc': sk_description,
        'descriptions': sk_description,
    }

    try:
        return alias(valid_sort_keys, aliases, sort_key)
    except ValueError:
        return crew_alias(sort_key)

def column_alias(column_key):
    aliases = {
        'rdate': ck_released,
        'release date': ck_released,
        'released date': ck_released,
        'date released': ck_released,
        'release': ck_released,
        'wdate': ck_watched,
        'watch date': ck_watched,
        'watched date': ck_watched,
        'date watched': ck_watched,
        'ratings': ck_rating,
        'number of votes': ck_votes,
        'num of votes': ck_votes,
        'num votes': ck_votes,
        'vote num': ck_votes,
        'vote count': ck_votes,
        'critic score': ck_metascore,
        'critic scores': ck_metascore,
        'critic rating': ck_metascore,
        'critic ratings': ck_metascore,
        'self rating': ck_myrating,
        'self ratings': ck_myrating,
        'personal rating': ck_myrating,
        'personal ratings': ck_myrating,
        'my score': ck_myrating,
        'my scores': ck_myrating,
        'self score': ck_myrating,
        'self scores': ck_myrating,
        'personal score': ck_myrating,
        'personal scores': ck_myrating,
        'name': ck_title,
        'movie': ck_title,
        'length': ck_runtime,
        'minutes': ck_runtime,
        'time': ck_runtime,
        'days left': ck_leaving,
        'leave date': ck_leaving,
        'leaves': ck_leaving,
        'days remaining': ck_leaving,
        'list': ck_source,
        'lists': ck_source,
        'file': ck_source,
        'files': ck_source,
        'origin': ck_source,
        'origins': ck_source,
        'from': ck_source,
        'explanation': ck_description,
        'desc': ck_description,
        'descriptions': ck_description,
    }

    try:
        return alias(valid_column_keys, aliases, column_key)
    except ValueError:
        return crew_alias(column_key)

def sort_aliases(sort_keys):
    return aliases(sort_alias, sort_keys)

def column_aliases(column_keys):
    if column_keys == '*':
        return False, list(valid_column_keys)

    if column_keys.startswith('+'):
        return True, aliases(column_alias, column_keys[1:])
    
    return False, aliases(column_alias, column_keys)

def exclude_aliases(exclude_keys):
    _, keys = column_aliases(exclude_keys)
    
    if not set(keys).issubset(valid_exclude_keys):
        raise ValueError()

    return keys

def join_keys(keys):
    return ', '.join((f"'{k}'" for k in keys))

def uniq_append(l, x):
    if x not in l:
        l.append(x)

def do(func, arg, default):
    return default if arg == None else func(arg)

def clampstr(s, maxlen=30, from_start=True):
    return s if len(s) <= maxlen or verbose else s[:maxlen - 3] + '...' if from_start else '...' + s[-(maxlen - 3):]

def num_to_pretty_str(num, abbreviate=False):
    if abbreviate:
        # I graciously thank this StackOverflow user https://stackoverflow.com/a/45846841/12553917.
        num = float('{:.3g}'.format(num))
        magnitude = 0
        while abs(num) >= 1000:
            magnitude += 1
            num /= 1000.0
        return '{}{}'.format('{:f}'.format(num).rstrip('0').rstrip('.'), ['', 'K', 'M', 'B', 'T'][magnitude])
    else:
        return '{:,}'.format(movie.get_votes())


def runtime_str(runtime):
    hrs = runtime // 60
    mins = runtime % 60
    return f'{str(hrs)}:{str(mins).zfill(2)}'

def sort_func(sort_key):
    if sort_key == sk_released:
        return True, lambda movie: movie.get_released()
    if sort_key == sk_watched:
        return True, lambda movie: movie.get_watched()
    if sort_key == sk_rating:
        return True, lambda movie: movie.get_rating()
    if sort_key == sk_votes:
        return True, lambda movie: movie.get_votes()
    if sort_key == sk_metascore:
        return True, lambda movie: movie.get_metascore(-1)
    if sort_key == sk_myrating:
        return True, lambda movie: movie.get_myrating(-1)
    if sort_key == sk_runtime:
        return False, lambda movie: movie.get_runtime(-1)
    if sort_key == sk_leaving:
        return False, lambda movie: movie.get_days_left(0x7FFFFFFF)
    if sort_key == sk_alpha:
        return False, lambda movie: movie.get_title(True)
    if sort_key == sk_description:
        return False, lambda movie: movie.get_description().lower()
    if sort_key in valid_crew_types:
        return False, lambda movie: tuple(movie.get_crew(sort_key, True, []))

    return False, lambda movie: 0

def get_column(movie, col_key):
    if col_key == ck_title:
        return clampstr(movie.get_title(), maxlen=45)
    if col_key == ck_leaving:
        return do(str, movie.get_days_left(), '-')
    if col_key == ck_runtime:
        return do(runtime_str, movie.get_runtime(), '-')
    if col_key == ck_released:
        return str(movie.get_released().date() if verbose else movie.get_released().year)
    if col_key == ck_rating:
        return str(movie.get_rating())
    if col_key == ck_votes:
        return num_to_pretty_str(movie.get_votes(), abbreviate=not verbose)
    if col_key == ck_metascore:
        return do(str, movie.get_metascore(), '-')
    if col_key == ck_watched:
        return str(movie.get_watched().date())
    if col_key == ck_myrating:
        return do(str, movie.get_myrating(), '-')
    if col_key == ck_source:
        return clampstr(movie.source, from_start=False) # From the end because in long paths the end matters most.
    if col_key == ck_description:
        return clampstr(movie.get_description())
    if col_key in valid_crew_types:
        return do(lambda l: clampstr(', '.join(l)), movie.get_crew(col_key), '-')

def is_default(movie, xkey):
    return get_column(movie, column_alias(xkey)) == '-'

# Assumes that input is valid. That means:
# records is a matrix of strings (that is, a list of equal-length lists of strings).
# use_colors is False or colors is a nonempty list of color codes.
def tabulate(records, fillchar=' ', spacious=False, use_color=True, file=sys.stdin,
    fillcolor=  '\033[30;1m\033[K', # Gray
    headercolor='\033[4m\033[K',    # Underline
    column_colors=[
                '\033[39m\033[K',   # White
                '\033[32;1m\033[K', # Green
                '\033[33m\033[K',   # Yellow
                '\033[34;1m\033[K', # Blue
                '\033[31;1m\033[K', # Red
                '\033[35;1m\033[K', # Purple
                '\033[36;1m\033[K', # Light Blue
                '\033[33;1m\033[K', # Light Yellow
    ]):

    # We need the max length of each column for alignment.
    ncolumns = len(records[0])
    maxlens = [2 + max(len(record[col]) for record in records) for col in range(ncolumns)]

    # Setting it up so that the code following can be the same regardless of color usage.
    if use_color:
        nocolor = '\033[m\033[K'
    else:
        column_colors=['']
        nocolor = ''
        fillcolor = ''
        headercolor = ''

    # Printing columns, with alignment and color!
    # Note: This program, and my other python scripts, all hit 'OSError [Errno 22]' when piping to less.
    # This fixes it: https://stackoverflow.com/a/66874837/12553917, but I'm worried about the consequences of using this and it's not worth the hassle.
    for row, record in enumerate(records):
        for col, entry in enumerate(record):
            color = column_colors[col % len(column_colors)]
            print(f'{color}{headercolor}{entry}{nocolor}{fillcolor}{(maxlens[col] - len(entry)) * fillchar}{nocolor}', end='', file=file)
        
        print(file=file)

        if spacious and row < len(records) - 1:
            print(file=file)

        headercolor = '' # After first row, make header color none.

# This is needed. Trust me.
try:
    sys.stdout.reconfigure(encoding='utf-8', newline='\n')
except:
    pass

ct_cast = 'cast'
ct_editor = 'editor'
ct_writer = 'writer'
ct_director = 'director'
ct_composer = 'composer'
ct_producer = 'producer'
ct_cinematographer = 'cinematographer'
ct_stunt_performer = 'stunt performer'
valid_crew_types = [ct_cast, ct_editor, ct_writer, ct_director, ct_composer, ct_producer, ct_cinematographer, ct_stunt_performer]

sk_released = 'released'
sk_watched = 'watched'
sk_nosort = 'none'
sk_rating = 'rating'
sk_votes = 'votes'
sk_metascore = 'metascore'
sk_myrating = 'my rating'
sk_alpha = 'alphabetical'
sk_runtime = 'runtime'
sk_leaving = 'leaving'
sk_description = 'description'
valid_sort_keys = [sk_released, sk_watched, sk_rating, sk_votes, sk_nosort, sk_metascore, sk_myrating, sk_alpha, sk_runtime, sk_leaving] + valid_crew_types

ck_title = 'title'
ck_leaving = 'leaving'
ck_runtime = 'runtime'
ck_released = 'released'
ck_rating = 'rating'
ck_votes = 'votes'
ck_metascore = 'metascore'
ck_watched = 'watched'
ck_myrating = 'my rating'
ck_source = 'source'
ck_description = 'description'
valid_column_keys = [ck_title, ck_leaving, ck_runtime, ck_released, ck_rating, ck_votes, ck_metascore, ck_watched, ck_myrating, ck_source, ck_description] + valid_crew_types
valid_exclude_keys = [ck_metascore, ck_myrating, ck_leaving]

are_cols_additive=False

parser = argparse.ArgumentParser(
    formatter_class=argparse.RawTextHelpFormatter,
    description='Give this the output of mfetch.py and it will print the movies in the JSONs sorted however you like. Designed to help you pick what to watch.',
    epilog='Sort keys, exclude keys, and column names all support many aliases so you can use similar words that make sense to you,'
    ''' and omit spaces or replace them with '-' or '_' (e.g., 'myrating', 'release_date').

About the "leaving" sort option: if you set the movie's description in IMDb to a date in the format YYYY-MM-DD (e.g. 2023-07-25), this option will sort by that date.
I set the descriptions to the dates I know movies in my watchlist will be leaving streaming services, so I can prioritize watching them before they're gone.''')
parser.add_argument('-s', '--sort', metavar='KEYS', type=sort_aliases, default=[sk_leaving, sk_runtime, sk_alpha], action='store', help=
    f'''Sort movies according to KEYS, which is a comma-delimited list of keys to sort by, in decreasing priority. Defaults to 'leaving,runtime,alphabetical'.
Valid sort keys: {join_keys(valid_sort_keys)}''')
parser.add_argument('-x', '--exclude', metavar='KEYS', type=exclude_aliases, default=[], action='store', help=
    f'''Exclude movies which don't have a value for any one of KEYS, which is a comma-delimited list of keys. Defaults to no exclusions.
Valid exclude keys: {join_keys(valid_exclude_keys)}''')
parser.add_argument('-c', '--color', choices=['always', 'auto', 'never'], default='auto', action='store', help=
    'Set whether columns should be colored')
parser.add_argument('-d', '--dsv', default=False, action='store_true', help=
    "Format output as delimiter-separated values. Causes '-c' to be ignored. See '-D' for more information")
parser.add_argument('-D', '--delim', metavar='DELIM', default=',', action='store', help=
    "Set the delimiter for '-d'. Defaults to commas (i.e., CSV)")
parser.add_argument('-C', '--columns', metavar='COLUMNS', type=column_aliases, action='store', default=(True, []), help=
    'List of columns to print, delimited by commas. Defaults to \'title,leaving,runtime,released,rating,metascore,director\','
    f''' with a few other "smart" columns which activate when a condition is met.
This option overrides the defaults and smart columns. Only the columns you specify will be printed.
Beginning this string with a '+' will cause the columns to be added to the default (and smart) columns instead of replacing them.
If COLUMNS is '*', will print all columns.
Valid column names: {join_keys(valid_column_keys)}''')
parser.add_argument('-v', '--verbose', default=False, action='store_true', help=
    'Use verbose output, like writing the full release date instead of just the year, and not chopping long strings')
parser.add_argument('-r', '--reverse', default=False, action='store_true', help=
    'Reverse the sort order. By default some sort keys are ascending and some descending based on what makes sense to me. This reverses those defaults')
parser.add_argument('-u', '--unique', default=False, action='store_true', help=
    'When merging JSONs, remove duplicate movies. Note that duplicate movies can still have a different leaving date, and this will arbitrarily omit one of them')
parser.add_argument('-S', '--spacious', default=False, action='store_true', help=
    'Add an empty line between entries')
parser.add_argument('-L', '--less', default=False, action='store_true', help=
    'Pipe output to less')
parser.add_argument('JSON', nargs='*', action='store', help=
    '''A list of input JSONs, which were output by mfetch.py. They will be treated as a single list of movies. Supports:
1. '-' for standard input
2. Absolute paths, paths relative to the current directory
3. Paths relative to the directory pointed to by the MOVIES_DIR environment variable
In all forms the .json extension can optionally be omitted.
If no JSON provided, use standard input.''')

# With no JSON, or when JSON is -, use standard input.
# Will search for matching filenames with a ".json" extension if you omit it.
# Also, will search for matching files in the directory pointed to by the MOVIES_DIR env variable.''')
args = parser.parse_args()

sort_keys = args.sort
dsv = args.dsv
delim = args.delim
verbose = args.verbose
reverse_all = args.reverse
uniqify = args.unique
spacious = args.spacious
less = args.less
exclude_keys = args.exclude
jsonfiles = ['-'] if len(args.JSON) == 0 else args.JSON

if args.color == 'always':
    color=True
elif args.color == 'auto':
    color=sys.stdout.isatty()
elif args.color == 'never':
    color=False

if args.columns[0]:
    column_keys = [ck_title, ck_leaving, ck_runtime, ck_released, ck_rating, ck_metascore, ct_director]
    column_keys.extend(args.columns[1])

    # "Smart" optional columns.
    if sk_watched in sort_keys:
        uniq_append(column_keys, ck_watched)

    if sk_votes in sort_keys:
        uniq_append(column_keys, ck_votes)

    if sk_myrating in sort_keys:
        uniq_append(column_keys, ck_myrating)

    if sk_description in sort_keys:
        uniq_append(column_keys, ck_description)
        
    if len(jsonfiles) > 1:
        uniq_append(column_keys, ck_source)
else:
    column_keys = args.columns[1]

movies = list()
read_stdin = False

for jsonfile in jsonfiles:
    # Ugly way to skip stdin after the first time because it will be closed for subsequent times.
    if jsonfile == '-':
        if read_stdin:
            continue
        read_stdin = True

    # We allow filenames without the .json extension, and also paths relative to the MOVIES_DIR env var.
    try:
        matching_file = next(path for path in [
            jsonfile,
            f'{jsonfile}.json',
            f'{(os.environ.get("MOVIES_DIR", "."))}/{jsonfile}',
            f'{(os.environ.get("MOVIES_DIR", "."))}/{jsonfile}.json'
            ] if path == '-' or os.path.isfile(path))
    except:
        sys.exit(f"{jsonfile}: No such file.")
        
    with sys.stdin if matching_file == '-' else open(matching_file, 'r') as f:
        data = json.load(f)

    file_movies = [Movie(movie_json, jsonfile) for movie_json in data['movies']]
    movies.extend(m for m in file_movies if all(not is_default(m, xkey) for xkey in exclude_keys))

if uniqify:
    movies = list(set(movies))

# Set each movie's table record.
for movie in movies:
    movie.record = [get_column(movie, ck) for ck in column_keys]

# Sort the movies according to the sort key. Must iterate in reverse priority order.
# Note there is an assumption here that the sort is stable.
for sk in sort_keys[::-1]:
    reverse, sorter = sort_func(sk)
    movies.sort(key=sorter, reverse=reverse ^ reverse_all)

# Inserting a dummy object with the column names.
column_titles = {
    ck_title: 'Title',
    ck_leaving: 'Days Left',
    ck_runtime: 'Runtime',
    ck_released: 'Release',
    ck_rating: 'Rating',
    ck_votes: 'Votes',
    ck_metascore: 'Metascore',
    ck_watched: 'Watched',
    ck_myrating: 'My Rating',
    ck_source: 'List',
    ck_description: 'Description',
    ct_cast: 'Actors',
    ct_editor: 'Editors',
    ct_writer: 'Writers',
    ct_director: 'Directors',
    ct_composer: 'Composers',
    ct_producer: 'Producers',
    ct_cinematographer: 'Cinematographers',
    ct_stunt_performer: 'Stunt Actors',
}

dummy = Movie(None, None)
dummy.record = [column_titles[ck] for ck in column_keys]
movies.insert(0, dummy)

# Pipe to less if requested. I tried a lot of variations including of course Popen(stdin=PIPE), this is the only one that works.
with tempfile.NamedTemporaryFile('w', encoding='utf-8') if less else sys.stdout as f:
    # Output movies in a pretty table.
    if dsv:
        writer = csv.writer(f, delimiter=delim)
        writer.writerows(movie.record for movie in movies)
    else:
        tabulate([movie.record for movie in movies], fillchar='.' if color else ' ', spacious=spacious, use_color=color, file=f)
    
    f.flush()

    if less:
        try:
            ps = subprocess.Popen(['less', '-RS', f.name])
            ps.wait()
        except:
            print("-L option failed. You either don't have less it or it is not in PATH.", file=sys.stderr)

