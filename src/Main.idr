||| Example TodoList CLI application using sqlite3
|||
||| This goes beyond the usual flat todo-list to allow the user to
||| organize items into projects, express dependencies between tasks,
||| and then view them hierarchically.
|||
||| The GTD concepts of "projects" and "next actions" are directly
||| supported.
module Main

import System
import Data.WithID
import Data.SortedSet
import Derive.Sqlite3
import Control.RIO.Sqlite3

%default  total
%language ElabReflection


-------------------------------------------------------------------------------
-- Data Types
-------------------------------------------------------------------------------


||| High-level type for task status
data Status
  = Incomplete
  | Completed
  | Dropped
%runElab derive "Status" [Show, Eq, ToCell, FromCell]


||| High-level type for task
record Task where
  constructor T
  description : String
  status      : Status
%runElab derive "Task" [Show, Eq, ToRow, FromRow]


-------------------------------------------------------------------------------
-- Database Schema
-------------------------------------------------------------------------------


||| The main table of tasks
Tasks : SQLTable
Tasks =
  table "tasks"
    [ C "id"          INTEGER
    , C "description" TEXT
    , C "status"      TEXT
    ]


||| Database command to create the tasks table
createTasks : Cmd TCreate
createTasks =
  IF_NOT_EXISTS $ CREATE_TABLE Tasks
    [ PRIMARY_KEY ["id"]
    , AUTOINCREMENT "id"
    , NOT_NULL "description"
    ]


||| This table tracks dependencies between tasks.
DependsOn : SQLTable
DependsOn =
  table "dependencies"
    [ C "id"          INTEGER
    , C "task"        INTEGER
    , C "dependency"  INTEGER
    ]


||| Database command to create the dependencies table
createDependsOn : Cmd TCreate
createDependsOn =
  IF_NOT_EXISTS $ CREATE_TABLE DependsOn
    [ PRIMARY_KEY       ["id"]
    , AUTOINCREMENT     "id"
    , FOREIGN_KEY Tasks ["task"]        ["id"]
    , FOREIGN_KEY Tasks ["dependency"]  ["id"]
    ]


-------------------------------------------------------------------------------
-- SQL Queries
-------------------------------------------------------------------------------


||| fetch all tasks in the database
tasks : Query (WithID $ Task)
tasks = SELECT
  ["t.id", "t.description", "t.status"]
  [< FROM (Tasks `AS` "t")]
  `ORDER_BY` [ASC "t.id"]


||| fetch all task IDs from the database
taskIds : Query Bits32
taskIds = SELECT
  ["t.id"]
  [< FROM (Tasks `AS` "t")]
  `ORDER_BY` [ASC "t.id"]


||| fetch a set of tasks from a list of task ids
byIds : List Bits32 -> Query (WithID $ Task)
byIds ids = tasks `WHERE` ("t.id" `IN` map val ids)


||| fetch all incomplete tasks
incomplete : Query (WithID $ Task)
incomplete = tasks `WHERE` ("t.status" `IS` val Incomplete)


||| fetch all completed or dropped tasks
completed : Query (WithID $ Task)
completed = tasks `WHERE` ("t.status" `IN` [val Completed, val Dropped])


||| fetch all dependencies of the given task
deps : Bits32 -> Query (WithID $ Task)
deps id = SELECT
  ["t.id", "t.description", "t.status"]
  [< FROM (DependsOn `AS` "d")
  ,  JOIN (Tasks `AS` "t") `ON` ("d.dependency" == "t.id")
  ]
  `WHERE` ("d.task" == val id)


||| fetch ids of all tasks which have active dependencies
|||
||| this is a "project" in gtd parlance
|||
||| XXX: Ideally I'd use `SELECT_DISTINCT`, but this isn't implemented
||| yet, so we just return the entire task column.
projectIds : Query Bits32
projectIds = SELECT
  ["d.task"]
  [< FROM (DependsOn `AS` "d")
  ,  JOIN (Tasks `AS` "t") `ON` ("d.dependency" == "t.id")
  ]
  `WHERE` ("t.status" == val Incomplete)


||| fetch ids of active tasks which are dependencies of at least one other task.
subtaskIds : Query Bits32
subtaskIds = SELECT
  ["d.dependency"]
  [< FROM (DependsOn `AS` "d")
   , JOIN (Tasks `AS` "t") `ON` ("d.dependency" == "t.id")
  ]
  `WHERE` ("t.status" == val Incomplete)


-------------------------------------------------------------------------------
-- SQL Commands
-------------------------------------------------------------------------------


||| add a new task
insertTask : Task -> Cmd TInsert
insertTask = insert Tasks ["description", "status"]


||| drop a task by its id
dropTask : Bits32 -> Cmd TUpdate
dropTask id = UPDATE Tasks ["status" .= Dropped] ("id" == val id)


||| complete a task by id
completeTask : Bits32 -> Cmd TUpdate
completeTask id = UPDATE Tasks ["status" .= Completed] ("id" == val id)


||| make one task depend on another
depends : Bits32 -> Bits32 -> Cmd TInsert
depends task dep = INSERT DependsOn ["task", "dependency"] [val task, val dep]


||| purge completed tasks
deleteCompleted : Cmd TDelete
deleteCompleted = DELETE Tasks ("status" `IN` [val Completed, val Dropped])


||| delete any deges which are connected to any of the given nodes
deleteDeps : List Bits32 -> Cmd TDelete
deleteDeps ids =
  let ids = map val ids
  in DELETE DependsOn (("task" `IN` ids) || ("dependency" `IN` ids))


-------------------------------------------------------------------------------
-- Command Line Parsing
-------------------------------------------------------------------------------


||| High level operations of the todolist app
data Command
  -- queries
  = ShowAll
  | ShowInbox
  | ShowIncomplete
  | ShowCompleted
  | ShowProjects
  | ShowNext
  | ShowDeps     Bits32
  | ShowTree     Bits32
  -- commands
  | Add          String
  | Drop         Bits32
  | Complete     Bits32
  | Depend       Bits32 Bits32
  | Purge


||| Try to parse an ID, returning Nothing if parsing fails.
|||
||| 0 is considered an invalid ID, since sqlite ids start at 1
parseId : String -> Maybe Bits32
parseId id = case stringToNatOrZ id of
  Z => Nothing
  x => if x <= 0xFFFFFFFF then Just $ cast x else Nothing


||| Parse an argument vector into an application command
parse : List String -> Maybe Command
parse []                = Just $ ShowNext
parse ["all"]           = Just $ ShowAll
parse ["inbox"]         = Just $ ShowInbox
parse ["completed"]     = Just $ ShowCompleted
parse ["incomplete"]    = Just $ ShowIncomplete
parse ["projects"]      = Just $ ShowProjects
parse ["next"]          = Just $ ShowNext
parse ["deps", id]      = Just $ ShowDeps !(parseId id)
parse ["tree", id]      = Just $ ShowTree !(parseId id)
parse ("add" :: rest)   = Just $ Add       (unwords rest)
parse ["complete", id]  = Just $ Complete !(parseId id)
parse ["drop",     id]  = Just $ Drop     !(parseId id)
parse ["depends", t, d] = Just $ Depend   !(parseId t)    !(parseId d)
parse ["purge"]         = Just $ Purge
parse _                 = Nothing


-------------------------------------------------------------------------------
-- Entry Point
-------------------------------------------------------------------------------


||| Maximum number of results for any single query
MAX_RESULTS : Nat
MAX_RESULTS = 10000


||| Declare the list of errors we handle
0 Errs : List Type
Errs = [SqlError]


||| Handle errors by printing them
handlers : All (Handler ()) Errs
handlers = [ printLn ]


||| Deduplicate a list of values
dedup : Ord a => Eq a => List a -> List a
dedup xs = SortedSet.toList $ the (SortedSet a) $ fromList xs


||| Query the set of tasks which have dependencies
|||
||| XXX: Not sure how to express this as a single query.
projects : DB => App Errs (Table $ WithID Task)
projects = do
  withDups <- query projectIds MAX_RESULTS
  queryTable (byIds $ dedup withDups) MAX_RESULTS


||| Query the set of tasks which have no dependencies.
|||
||| These are referred to as "next actions" in gtd parlance.
|||
||| XXX: Not sure how to express this as a single query.
nextActions : DB => App Errs (Table $ WithID Task)
nextActions = do
  all   <- query taskIds     MAX_RESULTS
  projs <- query projectIds  MAX_RESULTS
  let all   = SortedSet.fromList all
  let projs = SortedSet.fromList projs
  let diff  = SortedSet.toList $ all `difference` projs
  queryTable (byIds diff) MAX_RESULTS


||| Query the set of tasks disconnected tasks
|||
||| XXX: Not sure how to express this as a single query.
inbox : DB => App Errs (Table $ WithID Task)
inbox = do
  all   <- query taskIds    MAX_RESULTS
  projs <- query projectIds MAX_RESULTS
  deps  <- query subtaskIds MAX_RESULTS
  let all   = SortedSet.fromList all
  let projs = SortedSet.fromList projs
  let deps  = SortedSet.fromList deps
  let res   = SortedSet.toList $ all `difference` (projs `union` deps)
  queryTable (byIds res) MAX_RESULTS


||| Remove tasks and dependency edges which are completed or dropped.
purge : DB => App Errs ()
purge = do
  complete <- query completed MAX_RESULTS
  cmds $ [ deleteDeps $ map (.id) complete, deleteCompleted ]


||| Display a tree expansion of the task graph rooted at the given node.
tree : DB => Nat -> Nat -> Bits32 -> App Errs ()
tree Z d _ = printLn $ indent (d * 4) "Max Recursion Depth Exceeded"
tree (S max_depth) depth id = do
  result <- query (byIds [id]) MAX_RESULTS
  case result of
    [task] => putStrLn $ "\{padLeft 4 ' ' $ show task.id} | \{indent (depth * 4) $ format task.value}"
    x      => die "expected single result, got \{show x}"
  deps <- query (deps id) MAX_RESULTS
  for_ deps $ \child => do
    tree max_depth (depth + 1) child.id
  where
    format : Task -> String
    format (T description Incomplete) = "- \{description}"
    format (T description Completed)  = "+ \{description}"
    format (T description Dropped)    = "o \{description}"


||| Dispatch application commands to the database.
app: String -> List String -> App Errs ()
app path args = withDB path $ do
  cmds $ [createTasks, createDependsOn]
  case parse args of
    Nothing => die "Invalid command: \{unwords args}"
    Just ShowAll        => queryTable tasks      MAX_RESULTS >>= printTable
    Just ShowInbox      => inbox                             >>= printTable
    Just ShowCompleted  => queryTable completed  MAX_RESULTS >>= printTable
    Just ShowIncomplete => queryTable incomplete MAX_RESULTS >>= printTable
    Just ShowProjects   => projects                          >>= printTable
    Just ShowNext       => nextActions                       >>= printTable
    Just (ShowDeps id)  => queryTable (deps id)  MAX_RESULTS >>= printTable
    Just (ShowTree id)  => tree 100 0 id
    Just (Add desc)     => cmds $ [ insertTask $ T desc Incomplete ]
    Just (Drop id)      => cmds $ [ dropTask id ]
    Just (Complete id)  => cmds $ [ completeTask id ]
    Just (Depend t d)   => cmds $ [ depends t d ]
    Just Purge          => purge


||| helper function for debugging in the repl
runCommand : String -> List String -> IO ()
runCommand path args = do
  runApp handlers $ app path args


||| main entry point which configures from environment and argv
main : IO ()
main = do
  dbPath <- getEnv "SQLTEST_DB_PATH"
  args   <- getArgs
  case args of
    _ :: args => runCommand (fromMaybe ".todo-db" dbPath) args
    _         => runCommand (fromMaybe ".todo-db" dbPath) []
