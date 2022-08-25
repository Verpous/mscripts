# mscripts

table of contents

This is a set of tools I wrote to answer questions I had about the movies I've watched. Using mscripts, you can quickly answer questions like "where else have I seen this actor?", "what's the director I've seen the most movies from?", "what's the full list of writers who wrote a Star Wars film?", and many others.

All the tools are command line tools. To use their full power, you need to be comfortable with this. If you're not, there's only a single 3-letter command you need to remember in order to still make good use of them.

## Deeper description, how to use, examples

First of all, a note: mscripts supports movies and shows alike. Whenever I refer to movies, that includes shows too.

Essentially, what these tools do is they allow you to take an IMDb list and generate a text file with insights about the people behind the movies in the list. Most of its contents are a list of people and the other movies that they've been in, which looks like this:

```
Arnold Montey:
    Total: 8
    Average Rating: 7.98
    Average Metascore: 69.38
    ~~~~~~~~~~~~~~~~~
    Inception ----------------------------------------- Stock Broker
    V for Vendetta ------------------------------------ V Follower
    Star Wars: Episode III - Revenge of the Sith ------ Opera Guest
    The Lord of the Rings: The Two Towers ------------- Rohan Recruit
    Star Wars: Episode II - Attack of the Clones ------ Starfreighter Security Officer
    The Lord of the Rings: The Fellowship of the Ring - Burning Ringwraith
    Gladiator ----------------------------------------- Roman Soldier
    Star Wars: Episode I - The Phantom Menace --------- Naboo Royal Security Guard

Kenny Baker:
    Total: 7
    Average Rating: 7.64
    Average Metascore: 64.29
    ~~~~~~~~~~~~~~~~~
    Star Wars: Episode III - Revenge of the Sith --- R2-D2
    Star Wars: Episode II - Attack of the Clones --- R2-D2
    Star Wars: Episode I - The Phantom Menace ------ R2-D2
    Willow ----------------------------------------- Nelwyn Band Member
    Star Wars: Episode VI - Return of the Jedi ----- R2-D2, Paploo
    Star Wars: Episode V - The Empire Strikes Back - R2-D2
    Star Wars -------------------------------------- R2-D2

Harrison Ford:
    Total: 7
    Average Rating: 8.26
    Average Metascore: 74.43
    ~~~~~~~~~~~~~~~~~
    Indiana Jones and the Last Crusade ------------- Indiana Jones
    Indiana Jones and the Temple of Doom ----------- Indiana Jones
    Star Wars: Episode VI - Return of the Jedi ----- Han Solo
    Blade Runner ----------------------------------- Deckard
    Indiana Jones and the Raiders of the Lost Ark -- Indy
    Star Wars: Episode V - The Empire Strikes Back - Han Solo
    Star Wars -------------------------------------- Han Solo

Samuel L. Jackson:
    Total: 6
    Average Rating: 7.48
    Average Metascore: 68.67
    ~~~~~~~~~~~~~~~~~
    Star Wars: Episode III - Revenge of the Sith - Mace Windu
    Kill Bill: Vol. 2 ---------------------------- Rufus
    Star Wars: Episode II - Attack of the Clones - Mace Windu
    Unbreakable ---------------------------------- Elijah Price
    Star Wars: Episode I - The Phantom Menace ---- Mace Windu
    Pulp Fiction --------------------------------- Jules Winnfield
...
```

What you're seeing here is a few of the actors who've been in movies I own on DVD, sorted by how many of those movies they've been in. This snippet only includes the top few. For every actor, it shows all the movies from my "owned on DVD" list that they've been in sorted by release date, their roles in those movies, and the average rating and metascore of those movies.

You can create lists like this for various types of crew: cast, directors, writers, composers, producers, cinematographers, and stunt cast. You can also control sorting options: you can sort movies by their release date, the date you watched them, their rating by IMDb users, their rating by you, their metascore, or alphabetically. You can sort people too, by their average user rating, your rating, or metascore, by the number of movies they've been in from the list, alphabetically, or by the number of people in the group (more on that later). You can also apply a filter to only see movies that you rated.

Once these files are generated, you can either open them in a text editor and have a look, or you can quickly look up stuff in them using `mgrep` (more on that later).

I maintain a list on IMDb of all the movies I've watched, and another one for shows. My main use for these tools is to get insights on those list. For example, I can easily look up an actor's name and get a list of all the other movies I've seen them in. All I need to do is type: `mgrep "harrison ford"`.

All these scripts support the -h option if you need help. Nevertheless, let's dive into them.

## mfetch

mfetch is a python script that takes an IMDb list exported to CSV, and downloads a bunch of additional data about the movies in the list from IMDb. It outputs a JSON file which stores all that data locally.

To export an IMDb list to CSV you need to open the list on IMDb's website and press the three dots found here:

![image](https://user-images.githubusercontent.com/30209851/186282847-ddf747af-d5e7-4572-a59a-a3e557bd5cf9.png)

Then press the "Export" button to download the list as a CSV. Say the file is named 'movies.csv'. Then the next thing you would do is run:

`mfetch.py -u movies.csv`

This will create a JSON named movies.json in the current directory. Note the -u flag. This script can run for hours if your list is very big. What -u does is it makes mfetch only download movies which are not already in movies.json. So you only need do the big run once, and subsequent runs will finish in seconds. Note that you can add -u even if movies.json doesn't exist yet, and it will be ignored.

To make sure everything works, I recommend running `mfetch.py -m 10 <your-list>.csv`. This will make mfetch download no more than 10 movies, so you can see if it works before doing the big run. Once you're confident, you can run mfetch again with -u to not even redownload those 10 movies.

Like all other scripts here, you can use -h to get the full list of options.

## mprint

mprint is a python script which takes a JSON or multiple JSONs outputted by mfetch, and outputs a text file with insights about the movies in these JSONs for you to read. The example from above about actors in movies I own on DVD was generated with the command:

`mprint.py cast dvds.json`.

Every call to mprint provides one "crew type", in this case cast, and a list of JSON files. The output is a list of crewmembers of the requested type and what movies they've been in from any one of the input JSONs. For example, if I have a list of shows I've watched which I've downloaded into shows.json, and one for movies which is movies.json, then the command:

`mprint.py director shows.json movies.json`

Will show me all the directors behind all the movies and shows I've watched. By default they will be sorted by how many of those movies/shows they directed. If I want to, say, sort them by their average metascore, I can run:

`mprint.py -g metascore director shows.json movies.json`

For some crew types, it makes sense to group people who work together as a single "person". There's no sense in showing movies directed by Joel Coen separately from ones directed by Ethan Coen. For this, mprint supports the -c (or --cluster) option, which will find people who collaborate and show them as a single entry. In the case of the Coens, it looks like this:

```
Ethan Coen, Joel Coen:
    Total: 12
    Average Rating: 7.57
    Average Metascore: 77.33
    ~~~~~~~~~~~~~~~~~
    The Ballad of Buster Scruggs
    Hail, Caesar!
    Inside Llewyn Davis
    True Grit
    No Country for Old Men
    O Brother, Where Art Thou?
    The Big Lebowski
    Fargo
    Barton Fink
    Miller's Crossing
    Raising Arizona
    Blood Simple
```

Because of this option, I make a distinction between **people** and **groups**. A person is just one guy, but a group is an entry like the one above which can be one or more people who collaborated. If you run mprint with `-c no`, then all groups will be 1-man groups and be no different than a person. By default mprint knows what cluster option makes sense for each crew type so you do not need to specify it. Directors get clustered, actors don't, etc.

The -g flag from earlier stands for "group sort". You can sort groups in a number of ways, including even by the number of people in the group.

Besides the ability to sort groups, you can also sort each group's movies with the -s option. You can also omit movies that are missing a key. For example, you can filter out movies you haven't rated with `-x myrating`.

So for one final example, say you want to know who is the writer with the highest average rating by you out of the movies that you've seen and rated and which of those movies did he write sorted by the order you watched them, but only the ones with at least 3 movies because any fewer is not a large enough sample size. Then you can type:

`mprint.py -x myrating -g myrating -s watched -m 3 writer movies.json`

Note: sorting by the day you watched the movies actually sorts by the day they were added to your IMDb list. So it only takes on the "watch order" meaning if you add movies to your list as you watch them.

## mup

To sum up what we've read so far, you're supposed to go open IMDb in the browser, export your list to CSV, run mfetch on that CSV, and then run mprint on the resulting JSON maybe even a dozen times to update all the text files you're interested in. If only there was a way to automate all that...

Introducing mup. mup is that 3-letter command I mentioned earlier. It's a bash script which automates all but the most advanced usage of mfetch and mprint. With this tool you will never need to export your lists to CSV manually or directly run mfetch and mprint. All you need to do is configure mup with the lists you're interested in, and then type `mup.sh` and it will take care of everything.

mup works by downloading **lists**, and generating **categories**. A list is just an IMDb list. mup needs to know which lists you're interested in so it can export them to CSV and then produce a JSON with all their data. But then mup needs to know what mprint output are you interested in producing from these lists. This is what categories are for. A category is a folder with a text file for every crew type generated by mprint with options of your choice.

All the output from mup is placed in a directory of your choice which we will call the **movies directory**.

For example, I have a list of all the movies I've watched on IMDb, and one for shows. If I run the command:

`mup.sh movies shows`

mup will: 

1. Download my movies and shows lists from IMDb as CSVs, and place these CSVs in the movies directory under the names movies.csv, shows.csv
2. Run mfetch to download additional data, producing two JSONs (also in the movies directory): "movies.json" and "shows.json"
3. Create four directories in the movies directory for me named "movies", "shows", "all", and "rated". These are my categories. Each of these directories includes mprint output for every crew type in files named: "cast.txt", "director.txt", "writer.txt", etc.. The "movies" category includes only people who were in movies. The "shows" directory is only for people from the shows. The "all" category is for movies and shows combined. The "rated" category includes everyone but only from movies/shows that I've rated

The movies directory will end up looking like this:


The names of these lists and categories is not important. Later I'll explain how to configure mup with the lists and categories you're interested in.

For example I have a list for the movies I've watched and one for shows I've watched. So if I want mup to download them both, I need to run:

`mup.sh movies shows`

### mup & Firefox

In order to 

### Configuration


You should create an empty directory which we will call the **movies directory**. 



explain configuration, options, blah blah

## mgrep


## What else?

The repository also includes two additional scripts I haven't talked about, options.sh and utils.sh. These are just bash libraries I wrote to use in my scripts. mup and mgrep depend on them. You get to have them as a bonus if you'd like to use them in your own scripts.

options is a wrapper around getopts with a focus on conciseness and easily adding the -h option for help.

utils is just a collection of handy functions.

## Dependencies

firefox, cinemagoer, python, bash, gnu coreutils, what about versions?
