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

import json
import csv
import sys
import os
import argparse
import re
from collections import namedtuple

try:
    from imdb import Cinemagoer, IMDbError
    from imdb.utils import RolesList
    from imdb.Person import Person
    from imdb.Character import Character
    from imdb.Movie import Movie
except:
    sys.exit('Failed to import Cinemagoer. You must install it by running "pip install cinemagoer"')

maxdesc = 20
barlen = 30
maxsuff = 50
CsvFields = namedtuple('CsvFields', ['iden', 'title', 'watched', 'released', 'myrating', 'description', 'runtime', 'rating', 'votes'])
csv_to_json_keys = [f for f in CsvFields._fields if f not in ['iden', 'title']]

def progbar(desc, count, total, suffix=None):
    if quiet:
        return

    fraclen = len(str(total)) * 2 + 5
    fill = int((float(count) / float(total)) * barlen) if total != 0 else barlen
    fillstr = fill * '#' + ' ' * (barlen - fill)
    fracstr = f'({count} / {total})'.ljust(fraclen)
    suffstr = ' ' * maxsuff if suffix == None else (suffix if len(suffix) <= maxsuff else (suffix[:maxsuff - 3] + '...')).ljust(maxsuff)
    print(f'{(desc + ":").ljust(maxdesc)} [{fillstr}] {fracstr} {suffstr}', end='\n' if count == total else '\r')

try:
    sys.stdout.reconfigure(encoding='utf-8', newline='\n')
except:
    pass

parser = argparse.ArgumentParser(
    formatter_class=argparse.RawTextHelpFormatter,
    description='Give this an export of an IMDb list and it will output a JSON with additional data about the movies in the list.')
parser.add_argument('-u', default=False, action='store_true', help=
    'The program will only fetch movies not already present in the output JSON')
parser.add_argument('--update', metavar='JSON', default=None, action='store', help=
    'Like -u, but you may specify a different file than the output JSON to compare against. This option overrides -u')
parser.add_argument('-f', '--force', metavar='PATTERN', default=None, action='store', help=
    '''If -u/--update specified, forces titles that match PATTERN (case-insensitive) to be redownloaded even if they are already in the update JSON.
It's enough for PATTERN to match any part of the title, not necessarily the whole title.
PATTERN uses regex syntax from python's re library, which is identical to egrep unless you use very advanced features
This feature is intended for redownloading shows after a new season has come out.''')
parser.add_argument('-m', '--max', metavar='NUM', type=int, default=0x7FFFFFFF, action='store', help=
    'Specify how many movies to fetch. Mainly for debugging. Defaults to unbounded')
parser.add_argument('-q', '--quiet', default=False, action='store_true', help=
    'Be quiet. Don\'t output anything other than the JSON to standard output')
parser.add_argument('CSV', action='store', help=
    'A CSV export of an IMDb list. If -, use standard input')
parser.add_argument('JSON', nargs='?', default=None, action='store', help=
    '''A JSON file to output to. Defaults to the same name as the input file but with type .json.
If JSON is -, use standard output. If you use standard output, you'll probably also want to use -q.
If CSV is -, JSON must be specified''')
args = parser.parse_args()

csvfile = args.CSV
fetch_amount = args.max
quiet = args.quiet
forcepat = args.force

if args.JSON == None:
    if csvfile == '-':
        parser.error('the JSON argument is required if CSV is -')

    outfile = csvfile.removesuffix('.csv') + '.json'
else:
    outfile = args.JSON

upfile = args.update if args.update != None else outfile if args.u else None

# Update mode means that we are updating an input file, not fetching everything from scratch.
# If the path doesn't exist, we will simply toggle off update mode.
# This check also catches the case that -u is passed in combination with JSON == -, btw.
update_mode = upfile != None and os.path.exists(upfile)

if upfile != None and not update_mode:
    print(f'File \'{upfile}\' doesn\'t exist. Ignoring -u/--update args.', file=sys.stderr)

# Building a list of CsvFields (id, watch date, release date, my rating) for every movie.
# Obviously we need the id from the csv in order to know what to download.
# But we are also interested in the watch date which is only in the csv,
# and the release date which is obtainable from Cinemagoer but easier through the csv (trust me).
all_csv_data = list()

with sys.stdin if csvfile == '-' else open(csvfile, 'r', newline='') as f:
    reader = csv.reader(f)

    for i, row in enumerate(reader):
        if i == 0:
            has_myrating = len(row) > 15
            continue

        progbar("Reading CSV", i - 1, reader.line_num - 1)
        all_csv_data.append(CsvFields(row[1][2:], row[5], row[2], row[13], row[15] if has_myrating else '', row[4], row[9], row[8], row[12]))

    progbar("Reading CSV", reader.line_num - 1, reader.line_num - 1)

all_csv_data = all_csv_data[:min(fetch_amount, len(all_csv_data))]

# In update mode, we will filter out movies which are already in the input file.
if update_mode:
    with open(upfile, 'r') as f:
        in_json = json.load(f)
    
    # Creating list of movie IDs which we want to redownload even if they are already in the input JSON.
    if forcepat == None:
        force_ids = []
    else:
        force_ids = [movie['imdbID'] for movie in in_json['movies'] if re.search(forcepat, movie['title'], flags=re.IGNORECASE)]

    # Creating list of IDs which we don't need to download because of update mode.
    no_redownload_ids = [movie['imdbID'] for movie in in_json['movies'] if movie['imdbID'] not in force_ids]

    # Creating list of what we want to download by excluding the ones we don't.
    csv_data = [fields for fields in all_csv_data if fields.iden not in no_redownload_ids]
else:
    csv_data = all_csv_data

# Fetching data about the movies.
# Pairs of (key, default value).
direct_keys = [('imdbID', 'N/A'), ('title', 'N/A'), ('metascore', '-1')]

# Just the keys.
people_keys = ['cast', 'director', 'writer', 'producer', 'composer', 'cinematographer', 'editor', 'stunt performer']
ia = Cinemagoer()

# Building a list of Cinemagoer movie objects for the downloaded movies.
movies = list()
info = (*Movie.default_info, 'critic reviews', 'full credits')
exit_early = None

for i, fields in enumerate(csv_data):
    progbar("Downloading", i, len(csv_data), suffix=fields.title)
    success = False

    # Errors are rather common and usually trying again works.
    for j in range(5):
        try:
            movie = ia.get_movie(fields.iden, info=info)
            movies.append(movie)
            success = True
            break
        except IMDbError:
            pass

    if not success:
        print('Terminating early due to a problem with fetching data. You can pick up from where execution left off with --update.', file=sys.stderr)
        exit_early = i
        break

progbar("Downloading", len(csv_data) if exit_early == None else exit_early, len(csv_data))

# Converting data to JSON.
def get(obj, key, default):
    # I don't trust the obj's __contains__ because it has given some weird results.
    try:
        val = obj[key]
    except KeyError:
        val = default

    return val

def json_person(person):
    # I wanted to flag if an actor is an extra, but I can't find where in the API can I get this information.
    roles = []

    if person.currentRole:
        if type(person.currentRole) is Character or type(person.currentRole) is Person:
            # Both Character and Person have the key 'name'.
            roles = [get(person.currentRole, 'name', 'N/A')]
        elif type(person.currentRole) is RolesList:
            roles = [get(char, 'name', 'N/A') for char in person.currentRole]

    roles = [role for role in roles if role != 'N/A']
    return { 'id': person.getID(), 'name': get(person, 'name', person.getID()), 'roles': roles }

def json_people(movie, key):
    people = get(movie, key, [])
    filtered = list()

    for p in people:
        # Sometimes you get empty people.
        if not p:
            continue

        # Sometimes you get the same person twice.
        if sum(1 for person in filtered if person.getID() == p.getID()) > 0:
            continue

        filtered.append(p)

    return [json_person(person) for person in filtered]

json_movies = list()
result = { 'movies': json_movies }

for i, movie in enumerate(movies):
    progbar("Building JSON", i, len(movies))
    json_movie = dict()
    json_movie.update({ key: get(movie, key, default) for key, default in direct_keys })
    # These keys will be added later, but I want them to appear before the crew keys in the file so we need to add them now too.
    json_movie.update({ k: None for k in csv_to_json_keys })
    json_movie.update({ 'myrating': None, 'watched': None, 'released': None, 'description': None, 'runtime': None })
    json_movie.update({ key: json_people(movie, key) for key in people_keys })
    json_movies.append(json_movie)

progbar("Building JSON", len(movies), len(movies))

# In update mode, appending movies from the input JSON except the ones which have been removed from the list or that were force redownloaded.
if update_mode:
    append_ids = [fields.iden for fields in all_csv_data if fields.iden not in force_ids]
    json_movies += [movie for movie in in_json['movies'] if movie['imdbID'] in append_ids]

# For data that we pull from the CSV, we'll update even movies that are skipped by update mode.
# This is because it doesn't cost us anything, and because one of the values is my rating,
# which can change so a movie which was already previous fetched may need to be updated.
for i, fields in enumerate(all_csv_data):
    progbar("Adding CSV data", i, len(all_csv_data))
    json_movie = next((m for m in json_movies if m['imdbID'] == fields.iden), None)

    # The only time it can be None is if the download phase got cut short due to an error.
    if json_movie != None:
        json_movie.update({ k: getattr(fields, k) for k in csv_to_json_keys})

progbar("Adding CSV data", len(all_csv_data), len(all_csv_data))

# There seems to be a bug in Cinemagoer, sometimes when you get a person from the cast list of a TV show,
# his name goes something like "2011 Alan Tudyk\n          \n          \n          \n          1 episode".
# We fix this by trying to find people with a name like that and replacing it with the correct name.
# By doing this after everything is downloaded and not when the name was added to the dictionary,
# we are able to optimize by using the same person's appearance in something else instead of doing the big download when possible.
def bad_name(person):
    name = person['name']
    return '\n' in name or ' episode' in name.lower()

bad_people = [p for m in json_movies for k in people_keys for p in m[k] if bad_name(p)]
exit_early = None

for i, person in enumerate(bad_people):
    progbar("Cleansing data", i, len(bad_people))
    iden = person['id']
    good_appearances = [p for m in json_movies for k in people_keys for p in m[k] if iden == p['id'] and not bad_name(p)]

    if len(good_appearances) != 0:
        person['name'] = good_appearances[0]['name']
    else:
        success = False

        for j in range(5):
            try:
                good_person = ia.get_person(iden)
                person['name'] = get(good_person, 'name', iden)
                success = True
                break
            except IMDbError:
                pass
            
        if not success:
            print('Terminating early due to a problem with fetching data. You can pick up from where execution left off with --update.', file=sys.stderr)
            exit_early = i
            break

progbar("Cleansing data", len(bad_people) if exit_early == None else exit_early, len(bad_people))

# Outputting.
with sys.stdout if outfile == '-' else open(outfile, 'w', newline='\n') as f:
    json.dump(result, f, indent=2)

    # If writing to stdout, it will be closed when we exit this scope.
    # So it's better to print done inside this scope.
    if not quiet:
        print('Done!')
    