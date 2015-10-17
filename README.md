# HF Girls Helper

These are a collection of scripts to assist a player of the adult
card-trading game "Hellfire Girls", from Nutaku

* createdb creates an empty database cards.db
* addcard adds a card to the database. It takes a set of key-value pairs,
e.g. name="Alexis Adams" cost=2 attack=240 defense=240 attribute=teen
There are a few shortcuts; you can put the rarity and attribute values in
on their own without keys, and put the defense after the attack separated
by a comma

* promote is used for a lesson
* train is used for training
* lclear is a level clear
* affect when a card hits max affection

* show gives details on one or more cards
* list lists cards matching some criteria

* alldecks <attack strength> <defense strength> calculates optimal
attribute-coordinated decks (ignoring tag matching and skills)

There are lots of options on each command

The basics all work with no dependencies except sqlite3. However, the
alldecks command and the --best option on list depend on the rglpk gem and
the glpk linear-programming library. Setting those up can be a bit tricky,
since the rglpk that is distributed is built against a fairly old glpk. I
found it best to install the current glpk and build rglpk from source

(finding the set of 5 cards maximising attack or defense subject to a cost
limit is an instance of the multi-dimensional knapsack problem, hence the
linear-programming library dependency. It's more technically interesting
than useful, probably)

It's developed under linux, and works with cygwin, but it ought to work
from the normal windows command line.

