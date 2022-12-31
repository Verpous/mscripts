#! python

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

import json
import sys
import datetime
import argparse
import os

class Person:
    def __init__(self, iden, name):
        self.iden = iden
        self.name = name

    def __eq__(self, o):
        return isinstance(o, Person) and self.iden == o.iden

    def __ne__(self, o):
        return not self == o

    def __hash__(self):
        return hash(self.iden)

class Movie:
    def __init__(self, iden, title, rating, votes, metascore, myrating, watched, released, description, runtime, crew):
        self.iden = iden
        self.title = title
        self.rating = rating
        self.votes = votes
        self.metascore = metascore
        self.myrating = myrating
        self.watched = watched
        self.released = released
        self.description = description
        self.runtime = runtime
        self.crew = crew
        self.people = frozenset(c.person for c in crew)

    def __eq__(self, o):
        return isinstance(o, Movie) and self.iden == o.iden

    def __ne__(self, o):
        return not self == o

    def __hash__(self):
        return hash(self.iden)

class CrewMember:
    def __init__(self, person, roles):
        self.person = person
        self.roles = roles

class Appearance:
    def __init__(self, movie, roles):
        self.movie = movie
        self.roles = roles

def json_to_movie(json_movie, crew_type):
    iden = json_movie['imdbID']
    title = json_movie['title']
    rating = float(json_movie['rating'])
    votes = int(json_movie['votes'])
    metascore = int(json_movie['metascore'])
    myrating = int(json_movie['myrating']) if len(json_movie['myrating']) != 0 else -1
    watched = datetime.datetime.strptime(json_movie['watched'], '%Y-%m-%d')
    released = datetime.datetime.strptime(json_movie['released'], '%Y-%m-%d')
    description = json_movie['description']
    runtime = int(json_movie['runtime']) if len(json_movie['runtime']) != 0 else -1
    json_crew = json_movie[crew_type]
    crew = [CrewMember(Person(c['id'], c['name']), c['roles']) for c in json_crew]
    return Movie(iden, title, rating, votes, metascore, myrating, watched, released, description, runtime, crew)

def find_index(items, pred):
    return next((i for i, item in enumerate(items) if pred(item)), len(items))

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
        'length': sk_runtime,
        'minutes': sk_runtime,
        'time': sk_runtime,
    }
    return alias(valid_sort_keys, aliases, sort_key)

def gsort_alias(gsort_key):
    aliases = {
        'number of movies': gsk_nmovies,
        'num of movies': gsk_nmovies,
        'movies count': gsk_nmovies,
        'movie count': gsk_nmovies,
        'movies num': gsk_nmovies,
        'number of people': gsk_npeople,
        'num of people': gsk_npeople,
        'people count': gsk_npeople,
        'people num': gsk_npeople,
        'group size': gsk_npeople,
        'ratings': gsk_rating,
        'number of votes': gsk_votes,
        'num of votes': gsk_votes,
        'num votes': gsk_votes,
        'vote num': gsk_votes,
        'vote count': gsk_votes,
        'critic score': gsk_metascore,
        'critic scores': gsk_metascore,
        'critic rating': gsk_metascore,
        'critic ratings': gsk_metascore,
        'nosort': gsk_nosort,
        '': gsk_nosort,
        'self rating': gsk_myrating,
        'self ratings': gsk_myrating,
        'personal rating': gsk_myrating,
        'personal ratings': gsk_myrating,
        'my score': gsk_myrating,
        'my scores': gsk_myrating,
        'self score': gsk_myrating,
        'self scores': gsk_myrating,
        'personal score': gsk_myrating,
        'personal scores': gsk_myrating,
        'alpha': gsk_alpha,
        'alphabetic': gsk_alpha,
        'lexicographic': gsk_alpha,
        'name': gsk_alpha,
        'title': gsk_alpha,
    }
    return alias(valid_gsort_keys, aliases, gsort_key)

def sort_aliases(sort_keys):
    return aliases(sort_alias, sort_keys)

def gsort_aliases(gsort_keys):
    return aliases(gsort_alias, gsort_keys)

def exclude_aliases(exclude_keys):
    keys = sort_aliases(exclude_keys)
    
    if not set(keys).issubset(valid_exclude_keys):
        raise ValueError()

    return keys

def sort_func(sort_key):
    if sort_key == sk_released:
        return lambda appearance: appearance.movie.released
    if sort_key == sk_watched:
        return lambda appearance: appearance.movie.watched
    if sort_key == sk_rating:
        return lambda appearance: appearance.movie.rating
    if sort_key == sk_votes:
        return lambda appearance: appearance.movie.votes
    if sort_key == sk_metascore:
        return lambda appearance: appearance.movie.metascore
    if sort_key == sk_myrating:
        return lambda appearance: appearance.movie.myrating
    if sort_key == sk_runtime:
        return lambda appearance: appearance.movie.runtime
    if sort_key == sk_alpha:
        return lambda appearance: appearance.movie.title.lower()

    return lambda appearance: 0

def gsort_func(gsort_key):
    if gsort_key == gsk_nmovies:
        return lambda tup: len(tup[1])
    if gsort_key == gsk_rating:
        return lambda tup: sum(appearance.movie.rating for appearance in tup[1]) / len(tup[1])
    if gsort_key == gsk_votes:
        return lambda tup: sum(appearance.movie.votes for appearance in tup[1]) / len(tup[1])
    if gsort_key == gsk_metascore:
        return lambda tup: sum(appearance.movie.metascore for appearance in tup[1] if appearance.movie.metascore != -1) / len(tup[1])
    if gsort_key == gsk_myrating:
        return lambda tup: sum(appearance.movie.myrating for appearance in tup[1] if appearance.movie.myrating != -1) / len(tup[1])
    if gsort_key == gsk_npeople:
        return lambda tup: len(tup[0])
    if gsort_key == gsk_alpha:
        # The people list itself is guaranteed to be already sorted.
        return lambda tup: tuple(p.name.lower() for p in tup[0])

    return lambda tup: 0

def is_default(movie_json, xkey):
    if xkey == sk_metascore:
        return movie_json[xkey] == '-1'
    if xkey == sk_myrating:
        return movie_json['myrating'] == '' # sk_myrating is 'my rating' (with a space).

    return False

def join_keys(keys):
    return ', '.join((f"'{k}'" for k in keys))

def get_squish(creds, *gsorters):
    max_chars = 180 # This is the length that we wish not to exceed.
    max_ngroups = 0

    for gs_func in gsorters:
        group_max_gval = max((gs_func(group) for group in creds), default=0)
        group_max_ngroups = max((sum(1 for group in creds if gs_func(group) == gval) for gval in range(1, group_max_gval + 1)), default=1)

        if group_max_ngroups > max_ngroups:
            max_ngroups = group_max_ngroups
    
    return -(max_ngroups // -max_chars)

def create_breakdown(creds, title, breakdown_gsorter, squish):
    # Getting the largest value we have for this group key.
    max_gval = max((breakdown_gsorter(group) for group in creds), default=1)

    # Collecting all the data we want about each value. We want it as an int, as a str, how many groups have this value,
    # and a string of underscores that represents that same number.
    def add_data(gval):
        gval_str = str(gval)
        ngroups = sum(1 for group in creds if breakdown_gsorter(group) == gval)
        underscores = "_" * -(ngroups // -squish) # We use a trick to turn division with floor into ceiling.
        return gval, gval_str, ngroups, underscores

    gvals_data = [add_data(gval) for gval in range(1, max_gval + 1)]

    # To align things nicely we need the string length of the longest value. The list happens to be sorted so it's easy.
    maxlen = len(gvals_data[-1][1])
    spaces = ' ' * maxlen

    # This is where the magic happens. We take all the data we collected and create a table string.
    breakdown = "".join(
f'''{spaces                      } |{underscores}
{spaces[len(gval_str):]}{gval_str} |{underscores}{"| " if ngroups > 0 else ""}{ngroups}
''' for gval, gval_str, ngroups, underscores in gvals_data
    )

    # Now all that's left is to add some boring things and return.
    return (
f'''
{title}
{breakdown}{spaces} |
''')

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
default_grouping = {
    ct_cast: False,
    ct_producer: False,
    ct_stunt_performer: False,
    ct_editor: True,
    ct_writer: True,
    ct_director: True,
    ct_composer: True,
    ct_cinematographer: True,
}

sk_released = 'released'
sk_watched = 'watched'
sk_nosort = 'none'
sk_rating = 'rating'
sk_votes = 'votes'
sk_metascore = 'metascore'
sk_myrating = 'my rating'
sk_alpha = 'alphabetical'
sk_runtime = 'runtime'
valid_sort_keys = [sk_released, sk_watched, sk_rating, sk_votes, sk_nosort, sk_metascore, sk_myrating, sk_alpha, sk_runtime]
valid_exclude_keys = [sk_metascore, sk_myrating]

gsk_nosort = 'none'
gsk_rating = 'rating'
gsk_votes = 'votes'
gsk_nmovies = 'nmovies'
gsk_npeople = 'npeople'
gsk_metascore = 'metascore'
gsk_myrating = 'my rating'
gsk_alpha = 'alphabetical'
valid_gsort_keys = [gsk_nosort, gsk_rating, gsk_votes, gsk_nmovies, gsk_npeople, gsk_metascore, gsk_myrating, gsk_alpha]

parser = argparse.ArgumentParser(
    formatter_class=argparse.RawTextHelpFormatter,
    description='Give this the output of mfetch.py and a crew type and it will print the movies organized by crewmembers.',
    epilog='Crew types, sort keys, group sort keys, and exclude keys all support many aliases so you can use similar words that make sense to you,'
    " and omit spaces or replace them with '-' or '_' (e.g., 'myrating', 'stunt_performer').")
parser.add_argument('-G', '--group', choices=['yes', 'auto', 'no'], type=str.lower, default='auto', action='store', help=
    'If yes, will group people who\'ve collaborated together. Default is auto, which uses a group mode that makes sense for CREW')
parser.add_argument('-m', '--min', metavar='NUM', type=int, default=1, action='store', help=
    'Groups with fewer than NUM movies will not be printed. Defaults to unbounded')
parser.add_argument('-s', '--sort', metavar='KEYS', type=sort_aliases, default=[sk_released, sk_alpha], action='store', help=
    f'''Sort movies according to KEYS, which is a comma-delimited list of keys to sort by, in decreasing priority. Defaults to "released,alphabetical".
Valid sort keys: {join_keys(valid_sort_keys)}''')
parser.add_argument('-g', '--group-sort', metavar='KEYS', type=gsort_aliases, default=[gsk_nmovies, gsk_alpha], action='store', help=
    f'''Sort groups according to KEYS, which is a comma-delimited list of keys to sort by, in decreasing priority. Defaults to "nmovies,alphabetical".
Valid group sort keys: {join_keys(valid_gsort_keys)}''')
parser.add_argument('-p', '--print', default=False, action='store_true', help=
    'Print a list of valid crew types and exit')
parser.add_argument('-x', '--exclude', metavar='KEYS', type=exclude_aliases, default=[], action='store', help=
    f'''Exclude movies which don't have a value for any one of KEYS, which is a comma-delimited list of keys. Defaults to no exclusions.
Valid exclude keys: {join_keys(valid_exclude_keys)}''')
parser.add_argument('-r', '--reverse-movies', default=True, action='store_false', help=
    'Reverse the sort order of movies')
parser.add_argument('-R', '--reverse-groups', default=True, action='store_false', help=
    'Reverse the sort order of groups')
parser.add_argument('CREW', type=crew_alias, action='store', help=
    f'''The type of crewmember to organize movies by.
Valid crew types: {", ".join(valid_crew_types)}''')
parser.add_argument('JSON', nargs='*', action='store', help=
    '''A list of input JSONs, which were output by mfetch.py. They will be treated as a single list of unique movies. Supports:
1. '-' for standard input
2. Absolute paths, paths relative to the current directory
3. Paths relative to the directory pointed to by the MOVIES_DIR environment variable
In all forms the .json extension can optionally be omitted.
If no JSON provided, use standard input.''')
args = parser.parse_args()

# CREW is optional in this case but it's easier to keep it mandatory and ignore it.
if args.print:
    print('\n'.join(valid_crew_types))
    exit()

crew_type = args.CREW
sort_keys = args.sort
gsort_keys = args.group_sort
reverse_movies = args.reverse_movies
reverse_groups = args.reverse_groups
min_length = args.min
jsonfiles = ['-'] if len(args.JSON) == 0 else args.JSON
group_mode = True if args.group == 'yes' else False if args.group == 'no' else default_grouping[crew_type]
exclude_keys = args.exclude

movies = set()
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

    not_excluded = [m for m in data['movies'] if all(not is_default(m, xkey) for xkey in exclude_keys)]
    movies.update(json_to_movie(m, crew_type) for m in not_excluded)

if group_mode:
    # High level, the algorithm is as follows:
    #
    # foreach movie:
    #     intersect movie's people set with every other movie's
    #     if the intersection with a movie (including self) is not empty, add that intersection to a set of sets
    #
    # foreach people set in the set of sets we built:
    #     find all movies whose person set is a superset of this set
    #
    # In the end you have for every relevant person set, all movies that are accredited to it.
    # In reality the algorithm barely resembles this because of various optimizations.

    # people_sets will in the end include all relevant people sets. We know that at minimum, it should have every set that any movie has.
    # This set also allows us to only iterate over every unique movie crew pair, instead of every movie pair.
    people_sets = { movie.people for movie in movies if len(movie.people) > 0 }

    # Optimization: we only need to only iterate over each *unordered* crew pair once. For that we need people_sets to be ordered.
    unique_people = list(people_sets)

    # Optimization: 1-man crews are not interesting. Any intersection they have is either empty or equal to themselves.
    # So we will sort by crew length, and get the first index where crews have a greater length than 1.
    unique_people.sort(key=lambda people: len(people))
    start_multiple = find_index(unique_people, lambda people: len(people) > 1)

    # Now we iterate over every unordered pair of crews that both have len > 1.
    for i, p1 in enumerate(unique_people[start_multiple:]):

        # We skip the pair of any crew with itself because we started off people_sets with all of those.
        for p2 in unique_people[i + 1:]:
            intersection = p1 & p2

            # Empty intersections are skipped.
            # If the intersection is equal to p1 or p2, it's already in people_sets so we will not re-add it.
            # If we did re-add it the set will block it anyway but it doing it this way is more optimal.
            # For extra optimization juice, we don't even compare the sets, comparing lengths is enough.
            if len(intersection) not in [0, len(p1), len(p2)]:
                people_sets.add(intersection)

    # This is step 2 of the algorithm: finding each people set's credits.
    creds = [ (people, [Appearance(movie, []) for movie in movies if people.issubset(movie.people)]) for people in people_sets]
else: # Not group mode.
    creds = dict()

    for movie in movies:
        for crewmember in movie.crew:
            person = frozenset([crewmember.person])
            appearance = Appearance(movie, crewmember.roles)

            if person not in creds:
                creds[person] = [appearance]
            else:
                creds[person].append(appearance)

    creds = list(creds.items())
        
# Filtering credits below the min length.
creds = [(sorted(people, key=lambda p: p.name), appearances) for people, appearances in creds if len(appearances) >= min_length]

# Sorting by number of movies from each people set.
for gsk in gsort_keys[::-1]:
    creds.sort(key=gsort_func(gsk), reverse=reverse_groups)

# Computing these two in 1-liners with reduce proved to be the most expensive thing about this program by far
total_people_shown = set()
total_people = set()

for people, _ in creds:
    total_people_shown.update(people)

for movie in movies:
    total_people.update(movie.people)

gsorter_nmovies = gsort_func(gsk_nmovies)
gsorter_rating = gsort_func(gsk_rating)
gsorter_metascore = gsort_func(gsk_metascore)
gsorter_npeople = gsort_func(gsk_npeople)

print(
f'''Total groups shown: {len(creds)}
Total people shown: {len(total_people_shown)}
Total people: {len(total_people)}
''')

# We want a uniform squish for both breakdowns.
if group_mode:
    squish = get_squish(creds, gsorter_nmovies, gsorter_npeople)
else:
    squish = get_squish(creds, gsorter_nmovies)
    
print(create_breakdown(creds, '# of Groups For Every # of Movies', gsorter_nmovies, squish))

if group_mode:
    print(create_breakdown(creds, '# of Groups For Every Group Size', gsorter_npeople, squish))

print()

for people, appearances in creds:
    group = (people, appearances)

    for sk in sort_keys[::-1]:
        appearances.sort(key=sort_func(sk), reverse=reverse_movies)

    group_header = (
f'''{", ".join(person.name for person in people)}:
    Total: {gsorter_nmovies(group)}
    Average Rating: {gsorter_rating(group):.2f}
    Average Metascore: {gsorter_metascore(group):.2f}
    ~~~~~~~~~~~~~~~~~
''')

    # We'll align the column where we start writing roles. For this we'll need the longest movie name.
    maxlen = max(len(appearance.movie.title) for appearance in appearances)
    group_movies = '\n'.join(
        f'    {appearance.movie.title}' if len(appearance.roles) == 0 else (
        # We write '-'s between the movie name and the roles for alignment.
        f'    {appearance.movie.title} {"-" * (1 + maxlen - len(appearance.movie.title))} {", ".join(appearance.roles)}')
        for appearance in appearances
    )

    # It's better to build the big strings in memory then print them all in one than to make a bunch of little calls to print.
    print(group_header, group_movies, '\n', sep='')
