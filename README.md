# mscripts

- [mscripts](#mscripts)
  - [Description](#description)
  - [mfetch](#mfetch)
  - [mprint](#mprint)
  - [mup](#mup)
    - [mup & Firefox](#mup--firefox)
    - [Configuration](#configuration)
    - [Options](#options)
  - [mgrep](#mgrep)
  - [What Else is Included?](#what-else-is-included)
  - [Installation](#installation)
  - [Notes](#notes)

This is a set of tools I wrote to answer questions I had about the movies I've watched. Using mscripts, you can quickly answer questions like 'where else have I seen this actor?', 'what's the director I've seen the most movies from?', 'what's the full list of writers who wrote a Star Wars film?', and many others.

All the tools are command line tools. To use their full power, you need to be comfortable with this. If you're not, there's only a single 3-letter command you need to remember in order to still make good use of them.

## Description

First of all, a note: mscripts supports movies and shows alike. Whenever I refer to movies, that includes shows too.

Essentially, what these tools do is they allow you to take an IMDb list and generate a text file with insights about the people behind the movies in the list. Mostly this file contains a list of people and the other movies that they've been in, which looks like this:

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

What you're seeing here is a few of the actors who've been in movies I own on DVD, sorted by how many of those movies they've been in. This snippet only includes the top few. For every actor, it shows all the movies from my 'owned on DVD' list that they've been in sorted by release date, their roles in those movies, and the average rating and metascore of those movies.

You can create lists like this for various types of crew: cast, directors, writers, composers, producers, cinematographers, and stunt cast. You can also control sorting options: you can sort movies by their release date, the date you watched them, their rating by IMDb users, their rating by you, their metascore, or alphabetically. You can sort people too, by their average user rating, your rating, or metascore, by the number of movies they've been in from the list, alphabetically, or by the number of people in the group (more on that later). You can also apply a filter to only see movies that you rated.

Once these files are generated, you can either open them in a text editor and have a look, or you can quickly look up stuff in them using mgrep.

I maintain a list on IMDb of all the movies I've watched, and another one for shows. My main use for these tools is to get insights on those list. For example, I can easily look up an actor's name and get a list of all the other movies I've seen them in.

All these scripts support the `-h` option if you need help. Nevertheless, let's dive into them.

## mfetch

mfetch is a Python script that takes an IMDb list exported to CSV, and downloads a bunch of additional data about the movies in the list from IMDb. It outputs a JSON file which stores all that data locally.

To export an IMDb list to CSV you need to open the list on IMDb's website and press the three dots found here:

![image](https://user-images.githubusercontent.com/30209851/187076718-1636f8a2-6b0d-416f-bfe5-0b7627a8f79b.png)

Then press the 'Export' button to download the list as a CSV. Say the file is named 'movies.csv'. Then the next thing you would do is run:

`python mfetch.py -u movies.csv`

This will create a JSON named 'movies.json' in the current directory. Note the `-u` flag. This script can run for hours if your list is very big. What `-u` does is it makes mfetch only download movies which are not already in 'movies.json'. So you only need do the big run once, and subsequent runs will finish in seconds. Note that you can add `-u` even if 'movies.json' doesn't exist yet, and it will be ignored.

To make sure everything works, I recommend running `python mfetch.py -m 10 <your-list>.csv`. This will make mfetch download no more than 10 movies, so you can see if it works before doing the big run. Once you're confident, you can run mfetch again with `-u` to not even redownload those 10 movies.

Like all other scripts here, you can use `-h` to get the full list of options.

## mprint

mprint is a Python script which takes a JSON or multiple JSONs output by mfetch for your lists, and outputs text with insights about the movies in these lists for you to read. The example from earlier about actors in movies I own on DVD was generated with the command:

`python mprint.py cast dvds.json`.

mprint takes as input a **crew type**, in this case cast, and a list of JSON files. The output is a list of crewmembers of the requested type and what movies they've been in from any one of the input JSONs. For example, I've got my list of shows I've watched in 'shows.json', and movies in 'movies.json'. The command:

`python mprint.py director shows.json movies.json`

Will show me all the directors behind all the movies and shows I've watched. By default they will be sorted by how many of those movies/shows they directed. If I want to, say, sort them by their average metascore, I can run:

`python mprint.py -g metascore director shows.json movies.json`

mprint outputs to standard output. You'll usually want to redirect it into a .txt file.

For some crew types, it makes sense to group people who've collaborated into a single entry. There's no sense in showing movies directed by Joel Coen separately from ones directed by Ethan Coen. For this, mprint supports the `-G` option, which you can use to make mprint group who've collaborated and show them as a single entry. In the case of the Coens, it looks like this:

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

Because of this option, I make a distinction between **people** and **groups**. A person is just one guy, but a group is an entry like the one above which can be one or more people who collaborated. If you run mprint with `-G no`, then all groups will be 1-man groups and be no different than a person. By default mprint knows what group mode makes sense for each crew type so you do not need to specify it. Directors get grouped, actors don't, etc.

The `-g` (lowercase) flag from earlier stands for 'group sort'. You can sort groups in a number of ways, including even by the number of people in the group.

Besides the ability to sort groups, you can also sort each group's movies with `-s`. You can also omit movies that are missing a key. For example, you can filter out movies you haven't rated with `-x myrating`.

So for one final example, say you want to know who is the writer that you've rated the highest on average and which of the movies you've rated did he write sorted by the order you watched them, but only out of writers with at least 3 rated movies. Then you can run:

`python mprint.py -x myrating -g myrating -s watched -m 3 writer movies.json`

Note: sorting by the date you watched the movies actually sorts by the date they were added to your IMDb list. So it's more akin to the 'list order' option on IMDb.

## mup

So far we've seen that you're supposed to open IMDb in the browser, export your list to CSV, run mfetch on that CSV, and then run mprint on the resulting JSON maybe even a dozen times to update all the text files you're interested in. If only there was a way to automate all that...

Introducing mup. mup is that 3-letter command I mentioned earlier. It's a Bash script which automates all but the most advanced usage of mfetch and mprint. With this tool you will never need to export your lists to CSV manually or directly run mfetch and mprint. All you need to do is configure mup with the lists you're interested in, then run `bash mup.sh` and it will take care of everything.

mup works by downloading **lists**, and generating **categories**. A list is just an IMDb list. mup needs to know which lists you're interested in so it can export them to CSV and then produce a JSON with all their data. But then mup needs to know what mprint output you're interested in producing from these lists. This is what categories are for. A category is a folder with a text file for every crew type generated by mprint with arguments of your choice.

All the output from mup is placed in a directory of your choice which we will call the **movies directory**.

For example, I have a list of all the movies I've watched on IMDb, and one for shows. If I run the command:

`bash mup.sh movies shows`

mup will: 

1. Download my movies and shows lists from IMDb as CSVs, and place these CSVs in the movies directory under the names 'movies.csv', 'shows.csv'
2. Run mfetch to download additional data, producing two JSONs (also in the movies directory): 'movies.json' and 'shows.json'
3. Create four directories in the movies directory for me named 'movies', 'shows', 'all', and 'rated'. These are my categories. Each of these directories includes mprint output for every crew type in files named: 'cast.txt', 'director.txt', 'writer.txt', etc. The 'movies' category includes only people who were in movies. The 'shows' directory is only for people from the shows. The 'all' category is for movies and shows combined. The 'rated' category includes everyone but only from movies/shows that I've rated

The movies directory (not to be confused with the directory for the category 'movies') will end up looking like this:

![image](https://user-images.githubusercontent.com/30209851/187076736-664562c6-c952-4594-80ea-9c6817213e48.png)

And the 'all', 'movies', 'shows', 'rated' directories will all look like this (but with different file contents):

![image](https://user-images.githubusercontent.com/30209851/186733395-d31d1456-2f78-42f7-a77f-1013d648efac.png)

The names of these lists and categories is not important. Later I'll explain how to configure mup with your own lists and categories. You'll even be able to set defaults so you can simply run mup without arguments.

### mup & Firefox

In order to automatically export your list to CSV, mup needs to request a URL from IMDb. But if the list is private, IMDb will refuse unless you are logged in. The way I was able to solve this problem is to make mup open up the URL in Firefox, where you are assumed to be already logged in. I wish I could have solved it better (if you want to help, please get in touch by opening an issue or something). What this means is that you need to have Firefox and be logged in to IMDb for mup to work. Also, when you run mup you'll get some leftover open tabs in Firefox that I haven't been able to close automatically.

### Configuration

First, you should create an empty directory to use as the movies directory. Mine is in the documents folder and is simply called 'movies'.

Next, you need to create some environment variables. Fill in the right values for these variables and add them to your bashrc (if you're using Bash):

```bash
export MOVIES_DIR="path/to/movies"   # Path to the movies directory
export MOVIES_FDIR="path/to/firefox" # Path to the firefox installation *directory*. This is a dirname!
export MOVIES_FDOWNLOADS=~/Downloads # Path to where Firefox downloads files
```

Next, create a file named **exactly** 'mconfig.txt' in your movies directory. This is where you define your lists and categories. Here's a complete mconfig for example:

```
L movies 123456789 Y
L shows 987654321 Y
L blurays 135792468 N
L dvds 246813579 N
C all - movies,shows
C rated -x,myrating movies,shows
C home - blurays,dvds
C movies - movies
C shows - shows
C blurays - blurays
C dvds - dvds
```

Every line in the mconfig defines either a list or a category. Lines which define a list are of the form:

`L <list-name> <list-id> <default?>`

`<list-name>` is a name you want to give your list. When I run `bash mup.sh movies`, mup looks for a list with the name movies in my mconfig, and the files it creates for this list get named 'movies.csv', 'movies.json'. This field only supports alphanumeric characters and underscores, and is case-insensitive.

`<list-id>` is the ID given to your list by IMDb (the IDs in this example are made up). You can find out your list's ID by opening it up in the browser. The URL of the list page should look like this: `imdb.com/list/ls123456789`. Whatever number it says there instead of '123456789' is your list's ID. mup needs to know this ID in order to export your list to CSV.

You can actually run `bash mup.sh 123456789` directly to download this list and create a category for it even if it's not in your mconfig. But it's easier to memorize a name and naming it lets you include it in cool categories.

`<default?>` indicates if this list should be downloaded when you run mup without arguments. If it starts with a Y (case-insensitive), that means yes. Any other string means no. With the example above, if I run mup without arguments, only the movies and shows lists get downloaded.

Now let's talk about categories. A category definition looks like this:

`C <category-name> <mprint-options> <lists>`

`<category-name>` is the name of the category. The fact that I have a category 'home' means that mup will produce a directory 'home' for all this category's files. Like list names, this can only contain alphanumeric characters and underscores, and is case-insensitive.

`<mprint-options>` is a **comma-delimited** list of options to pass to mprint. For example, the 'rated' category is for all the movies and shows I've watched, but only the ones I rated. It does this by passing `-x myrating` to mprint. If you don't want to pass any options to mprint, set this to `-`.

`<lists>` is a **comma-delimited** list of list names that are combined to form this category. The 'all' category from above is for movies and shows combined. The 'dvds' category includes only movies from the 'dvds' list. When you run mup to download some lists, mup automatically updates only the categories which depend on them. This field is case-insensitive, like list names.

You can add as many spaces/tabs as you want between fields in this file, but spaces are not allowed within a field. Not even in quotes! Quotes have no special meaning here. You must also not leave any field empty, which is why empty `<mprint-options>` is actually indicated by a `-`.

Only ASCII characters are supported in this file, so keep it in English.

### Options

mup supports lots of options that you can read about with `-h`. One option I want to elaborate on is `-o`. When mup downloads a list, it checks if the list has changed at all since the last time mup ran. If it hasn't, categories which depend on this list aren't updated. This can significantly shorten mup's runtime, but it can have unexpected results. For example, if you run mup, change a category's `<mprint-options>`, then run mup again, the category won't be updated with the new options. The `-o` option disables this optimization. Use it if you notice mup not updating a category you expect it to.

If you know your lists haven't changed and only the categories have, you can also run mup with `-f`. This skips the step where lists are updated entirely so the only thing mup does is generate new categories using existing list files, and it won't try this optimization.

## mgrep

Once you've got the mprint output files you're interested in, the most common way to use them is to look up people and see what else they've done. You *could* navigate to the .txt file, open it up in a text editor of your choice, and look up the name you're looking for. But with mgrep you can find people who match a pattern very quickly.

Recall, a person's entry looks like this:

```
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
```

mgrep lets you find all people in a category whose entry matches a pattern. The pattern can match any part of the person's entry. Pattern syntax is the same as egrep, or grep -E. You could find this complete entry for Harrison Ford by typing:

`bash mgrep.sh "harrison f"`

or:

`bash mgrep.sh -- "- indiana jones"`

Or any other pattern which matches any part of his entry. Notice that the pattern is case insensitive. You can even match multiline patterns, as long as all the lines belong to the same person's entry. So if you don't remember Karl Urban's name, but you remember he was in *Dredd* and *The Lord of the Rings*, you can find him using:

`bash mgrep.sh "dredd.*lord of the rings|lord of the rings.*dredd"`

The use of `|` in the pattern ensures that it will work no matter which movie came first.

You can actually include the newline character in the pattern. But the pattern does **not** accept escape sequences like '\n'. Escape sequences have the same behavior as egrep. To match a newline, you need to actually have a newline character in the string, which in Bash you can insert with `$'\n'`. However, it's a lot easier to fill in the gap between lines with a simple wildcard like `.*`, as you can see above.

mgrep searches in a category of your choice, and prints all the people from any crew type who match the pattern in this category. Say I want to find all the people from movies I own at home who were in *The Lord of the Rings: The Fellowship of the Ring* and have an average rating of at least 8.6 and less than 8.8. Then I'll do:

`bash mgrep.sh -l home 'average rating: 8\.[6-7].*the fellowship of the ring'`

And I'll get this output:

```
cast.txt:John Rhys-Davies:
cast.txt:    Total: 5
cast.txt:    Average Rating: 8.64
cast.txt:    Average Metascore: 84.60
cast.txt:    ~~~~~~~~~~~~~~~~~
cast.txt:    The Lord of the Rings: The Return of the King ----- Gimli
cast.txt:    The Lord of the Rings: The Two Towers ------------- Gimli, Voice of Treebeard
cast.txt:    The Lord of the Rings: The Fellowship of the Ring - Gimli
cast.txt:    Indiana Jones and the Last Crusade ---------------- Sallah
cast.txt:    Indiana Jones and the Raiders of the Lost Ark ----- Sallah
cast.txt:
cast.txt:Sean Bean:
cast.txt:    Total: 4
cast.txt:    Average Rating: 8.65
cast.txt:    Average Metascore: 88.25
cast.txt:    ~~~~~~~~~~~~~~~~~
cast.txt:    The Martian --------------------------------------- Mitch Henderson
cast.txt:    The Lord of the Rings: The Return of the King ----- Boromir
cast.txt:    The Lord of the Rings: The Two Towers ------------- Boromir
cast.txt:    The Lord of the Rings: The Fellowship of the Ring - Boromir
cast.txt:
cast.txt:Elijah Wood:
cast.txt:    Total: 4
cast.txt:    Average Rating: 8.60
cast.txt:    Average Metascore: 82.75
cast.txt:    ~~~~~~~~~~~~~~~~~
cast.txt:    The Hobbit: An Unexpected Journey ----------------- Frodo
cast.txt:    The Lord of the Rings: The Return of the King ----- Frodo
cast.txt:    The Lord of the Rings: The Two Towers ------------- Frodo
cast.txt:    The Lord of the Rings: The Fellowship of the Ring - Frodo
stunt performer.txt:Sala Baker:
stunt performer.txt:    Total: 4
stunt performer.txt:    Average Rating: 8.68
stunt performer.txt:    Average Metascore: 84.00
stunt performer.txt:    ~~~~~~~~~~~~~~~~~
stunt performer.txt:    The Lord of the Rings: The Return of the King
stunt performer.txt:    Pirates of the Caribbean: The Curse of the Black Pearl
stunt performer.txt:    The Lord of the Rings: The Two Towers
stunt performer.txt:    The Lord of the Rings: The Fellowship of the Ring
stunt performer.txt:
stunt performer.txt:Kirk Maxwell:
stunt performer.txt:    Total: 4
stunt performer.txt:    Average Rating: 8.60
stunt performer.txt:    Average Metascore: 89.00
stunt performer.txt:    ~~~~~~~~~~~~~~~~~
stunt performer.txt:    Avatar
stunt performer.txt:    The Lord of the Rings: The Return of the King
stunt performer.txt:    The Lord of the Rings: The Two Towers
stunt performer.txt:    The Lord of the Rings: The Fellowship of the Ring
```

You can also limit searches to certain files. Say you want to find George Lucas's credits, but only as a writer or director. Then you should do:

`bash mgrep.sh -l home "george lucas" writer director`

What's happening here is that mgrep will only look for George Lucas in the files 'writer.txt', 'director.txt' in the category 'home'. The '.txt' can be optionally omitted so you can simply write crew types. You can also give mgrep a full path to a file even outside of any category, like:

`bash mgrep.sh "george lucas" ~/Desktop/cast.txt`

Or you could pass in `-` to read from standard input. This lets you pipe mprint into mgrep. You can mix and match, like:

`python mprint.py director -s alphabetical | bash mgrep.sh "george lucas" writer - ~/Desktop/cast.txt`

By default mgrep searches all crew types in the given category. If you don't specify a category (with `-l`), mgrep searches in **the first category defined in the mconfig file**. The same file mup uses. For me, the default category is all movies and shows I've seen combined.

There's lots of options to control the output of mgrep, many of which are borrowed from grep. As always you can read more with `-h`.

## What Else is Included?

The repository also includes two additional scripts I haven't talked about: 'options.sh' and 'utils.sh'. These are just Bash libraries I wrote to use in my scripts. mup and mgrep depend on them, so you get to have them as a bonus. You could even use them in your own scripts.

options is a wrapper around getopts with a focus on brevity and easily generating a useful `-h` option.

utils is just a collection of handy functions. Some of them are unrelated to mscripts.

## Installation

Just clone this repository and you can run the scripts. I recommend adding their folder to PATH. There are some dependencies you'll need to install, listed here:

* Python, for mfetch and mprint. I don't know exactly what minimum version you need. It's best to go with something recent. I'm using 3.9.7
* [Cinemagoer](https://cinemagoer.github.io/), for mfetch. You can simply `pip install cinemagoer`
* Bash, for mup and mgrep. Again, use something recent, I don't know minimum versions. I'm on Bash 4.4.23
* GNU Coreutils (`grep`, `find`, `sed`, `mv`, `mktemp`, etc.), for mup and mgrep
* Firefox, for mup

If you're on Linux, you probably already have Bash and all the GNU Coreutils. If you're on Windows like me, you'll need to install them. I use mingw-w64, which I've installed through [MSYS2](https://www.msys2.org/). Git also comes bundled with Bash and some utils, which I think is sufficient and is certainly easier to install.

## Notes

* I'm on Windows, but I use Bash the GNU Coreutils ported over by MinGW. I think everything here should work on Linux, but I haven't tested it
* I constantly get ideas for new features and I can't help myself so there'll probably be updates
* All the example commands above start with `python` or `bash` e.g. `python mfetch.py`, or `bash mup.sh`. In reality, I never run them like that. All the scripts have shebangs so depending on your environment you may be able to simply run `mprint.py`, `mup.sh`
* Even just typing `mup.sh` can be a pain. It would be a lot nicer if you could simply type `mup` and that's it. On Linux I understand the custom is to get rid of the extension in filenames of executables. I don't like that though, so instead I have a `command_not_found_handle` in my bashrc which lets me omit them when running shell scripts. Bash treats functions named `command_not_found_handle` specially and runs them when a command isn't found:

```bash
command_not_found_handle() {
    unset -f command_not_found_handle
    local cmmnd="$1.sh"
    shift
    exec "$cmmnd" "$@"
}
```
