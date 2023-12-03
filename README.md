# An Idris Sqlite3 Example

This is a command-line todolsit application which demonstrates the use
of [idris2-sqlite3](https://github.com/stefan-hoeck/idris2-sqlite3/tree/main)

Still a work in progress.

It's roughly a GTD model

## Command Summary


| Command                | Summary                              |
|------------------------|--------------------------------------|
| `all`                  | show all tasks, regardless of status |
| `inbox`                | show only new tasks                  |
| `completed`            | review completed tasks               |
| `incomplete`           | show all active tasks                |
| `add ...`              | creates a new task                   |
| `drop <id>`            | mark task as "dropped"               |
| `complete <id>`        | mark task as completed               |
| `depend <a:id> <b:id>` | make task a depend on task b         |
| `purge`                | drop inactive tasks                  |


