# An Idris Sqlite3 Example

This is a command-line todolist application which demonstrates the use
of [idris2-sqlite3](https://github.com/stefan-hoeck/idris2-sqlite3/tree/main)

Still a work in progress.

It's roughly based on the
[GTD](https://en.wikipedia.org/wiki/Getting_Things_Done)
methodology.

## Build

```
pack build idris-todo
```

## Tutorial

First, create some new tasks

```
$ ./todo.sh add "Laundry"
$ ./todo.sh add "Grocery Shopping"
$ ./todo.sh add "Make Dinner"
$ ./todo.sh add "Mow Lawn"
$ ./todo.sh add "Get Gas for Lawn Mower"
```

To see all the tasks:

```
$ ./todo.sh
t.id |     t.description      | t.status
----------------------------------------
   1 | Laundry                | Incomplete
   2 | Grocery Shopping       | Incomplete
   3 | Make Dinner            | Incomplete
   4 | Mow Lawn               | Incomplete
   5 | Get Gas for Lawn Mower | Incomplete
```

Notice how some of these tasks have a dependency relationship:

- making dinner depends on grocery shopping
- mowing the lawn requires getting gas for the mower

Let's capture this information:

```
$ ./todo.sh depends 3 2
$ ./todo.sh depends 4 5
```

Now, look at what happens when we list the tasks:

```
$ ./todo.sh
t.id |     t.description      |  t.status 
------------------------------------------
   1 | Laundry                | Incomplete
   2 | Grocery Shopping       | Incomplete
   5 | Get Gas for Lawn Mower | Incomplete
```

Tasks 3 and 4 are filtered out! This is because `./todo.sh` is an
alias for `./todo.sh next`, which lists only *next actions*.

## Next Actions and Projects

In GTD, a task with dependencies is a *project*, while a task with no
dependencies is a *next action*.

Since we created dependencies between tasks, our database contains
*projects*.

### Projects

You can see the list of projects like this:

```
$ ./todo.sh projects
t.id | t.description |  t.status 
---------------------------------
   3 | Make Dinner   | Incomplete
   4 | Mow Lawn      | Incomplete
```

You can see which tasks are part of the "Make Dinner" project, like
this:

```
$ ./todo.sh deps 3
t.id |  t.description   |  t.status 
------------------------------------
   2 | Grocery Shopping | Incomplete
```

## The Dependency Graph

The dependency relationship is a general graph. Subtasks can be shared
among projects.

Let's create a new task called "Errands" to plan our shopping trip.

```
$ ./todo.sh add "Errands"
$ ./todo.sh depends 6 2
$ ./todo.sh depends 6 5
```

If we stop and think about it, many of these tasks represent household
chores. Let's make another project to organize them:

```
$ ./todo.sh add "Chores"
$ ./todo.sh depends 7 1
$ ./todo.sh depends 7 3
$ ./todo.sh depends 7 4
```

Let's take a look at the task hierarchy rooted at chores:

```
$ ./todo.sh tree 7
   7 | - Chores
   1 |     - Laundry
   3 |     - Make Dinner
   2 |         - Grocery Shopping
   4 |     - Mow Lawn
   5 |         - Get Gas for Lawn Mower
```

Now let's do the same for Errands:

```
$ ./todo.sh tree 6
   6 | - Errands
   2 |     - Grocery Shopping
   5 |     - Get Gas for Lawn Mower
```

Let's add some specific items to our shopping list

```
$ ./todo.sh add Butter
$ ./todo.sh add Flour
$ ./todo.sh add Potatoes
$ ./todo.sh depends 2 8
$ ./todo.sh depends 2 9
$ ./todo.sh depends 2 10
```

Now let's take another look at our errands project:

```
$ ./todo.sh tree 6
   6 | - Errands
   2 |     - Grocery Shopping
   8 |         - Butter
   9 |         - Flour
  10 |         - Potatoes
   5 |     - Get Gas for Lawn Mower
```

## Getting Things Done

Let's start crossing things off the list.

You go to the store, and easily find the butter and the flour, but
they were out of potatoes:

```
$ ./todo.sh complete 8
$ ./todo.sh complete 9
$ ./todo.sh drop 10
$ ./todo.sh tree 6
   6 | - Errands
   2 |     - Grocery Shopping
   8 |         + Butter
   9 |         + Flour
  10 |         o Potatoes
   5 |     - Get Gas for Lawn Mower
```

Notice how the symbols change for completed / dropped items!

Or you can simply look at the dependencies of the shopping task:

```
./todo.sh deps 2
t.id | t.description | t.status 
--------------------------------
   8 | Butter        | Completed
   9 | Flour         | Completed
  10 | Potatoes      | Dropped  
```


Now let's imagine, your errands are done, so let's complete the
remaining items.

```
$ ./todo.sh complete 2
$ ./todo.sh complete 5
$ ./todo.sh complete 6
```

Now, look at what happens to our list of next actions:

```
$ ./todo.sh
t.id |     t.description      |  t.status 
------------------------------------------
   1 | Laundry                | Incomplete
   2 | Grocery Shopping       | Completed 
   3 | Make Dinner            | Incomplete
   4 | Mow Lawn               | Incomplete
   5 | Get Gas for Lawn Mower | Completed 
   6 | Errands                | Completed
   8 | Butter                 | Completed 
   9 | Flour                  | Completed 
  10 | Potatoes               | Dropped   
```

Since we've completed the subtasks, the parent tasks now appear as
next actions. And since there are no tasks with active subtasks, our
projects list now only contains only the Chores project.

```
$ ./todo.sh projects
t.id | t.description |  t.status 
---------------------------------
   7 | Chores        | Incomplete
```

## Cleaning Up

We can remove all the completed / dropped tasks from the database like
this:

```
$ ./todo.sh purge
$ ./todo.sh
t.id | t.description |  t.status 
---------------------------------
   1 | Laundry       | Incomplete
   3 | Make Dinner   | Incomplete
   4 | Mow Lawn      | Incomplete
```

## Command Summary


| Command                 | Summary                               |
|-------------------------|---------------------------------------|
| *empty command line*    | defaults to `next`                    |
| `all`                   | show all tasks, regardless of status  |
| `inbox`                 | show only untriaged tasks             |
| `completed`             | review completed tasks                |
| `incomplete`            | show all active tasks                 |
| `projects`              | show tasks which have subtasks        |
| `next`                  | show tasks with no dependencies       |
| `deps`                  | show the direct subtasks of a project |
|-------------------------|---------------------------------------|
| `add ...`               | creates a new task                    |
| `drop <id>`             | mark task as "dropped"                |
| `complete <id>`         | mark task as completed                |
| `depends <a:id> <b:id>` | make task a depend on task b          |
| `purge`                 | drop inactive tasks                   |


