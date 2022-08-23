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

mfetch is a python script that takes an IMDb list exported as CSV, and downloads a bunch of additional data about the movies in the list from IMDb. It outputs a JSON file which stores all that data locally.

To export an IMDb list to CSV you need to open the list on IMDb's website and press the three dots found here:

![image](https://user-images.githubusercontent.com/30209851/186282847-ddf747af-d5e7-4572-a59a-a3e557bd5cf9.png)

This script can run for hours if your script is very big. Because of this you can run it with the -u/--update options to make it take an earlier JSON that it outputted and only add movies from the list that are not already there. So if you only want to update it with the latest movie you've watched, it will only take a couple of seconds.

The first thing you need to do is run this. mfetch is a python script that 

## mprint

This and mfetch are the only two essential parts of this toolset.

## mup

This is that 3-letter command I mentioned earlier. `mup` (which stands for movie update) is a bash script which automates all but the most advanced usage of mfetch and mprint. After some initial setup, all you need to do is occasionally run `mup` (just like that, without arguments) and it will update all your local text files according to the way you want it to. You can even set it to run periodically and completely hide it away. If you're not a command line person, you can learn this script alone and skip reading about the rest.



explain configuration, options, blah blah

## mgrep


## What else?

The repository also includes two additional scripts I haven't talked about, options.sh and utils.sh. These are just bash libraries I wrote to use in my scripts. mup and mgrep depend on them. You get to have them as a bonus if you'd like to use them in your own scripts.

options is a wrapper around getopts with a focus on conciseness and easily adding the -h option for help.

utils is just a collection of handy functions.

## Dependencies

firefox, cinemagoer, python, bash, gnu coreutils, what about versions?
