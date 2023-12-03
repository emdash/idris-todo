||| Example TodoList CLI application using sqlite3
|||

module Main

import System
import Data.WithID
import Derive.Sqlite3
import Control.RIO.Sqlite3

%default  total
%language ElabReflection


-------------------------------------------------------------------------------
-- Data Types
-------------------------------------------------------------------------------


||| High-level type for task status
data Status
  = New
  | Incomplete
  | Completed
  | Dropped
%runElab derive "Status" [Show, Eq, ToCell, FromCell]


||| High-level type for task
record Task where
  constructor T
  name    : String
  status  : Status
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
Dependencies : SQLTable
Dependencies =
  table "dependencies"
    [ C "id"          INTEGER
    , C "task"        INTEGER
    , C "dependency"  INTEGER
    ]


||| Database command to create the dependencies table
createDependencies : Cmd TCreate
createDependencies =
  IF_NOT_EXISTS $ CREATE_TABLE Dependencies
    [ PRIMARY_KEY       ["id"]
    , AUTOINCREMENT     "id"
    , FOREIGN_KEY Tasks ["task"]        ["id"]
    , FOREIGN_KEY Tasks ["dependency"]  ["id"]
    ]


-------------------------------------------------------------------------------
-- SQL Commands and Queries
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
dependsOn : Bits32 -> Bits32 -> Cmd TInsert
dependsOn x y = INSERT Dependencies ["task", "dependency"] [val x, val y]

||| purge completed tasks
deleteCompleted : Cmd TDelete
deleteCompleted = DELETE Tasks ("status" `IN` [val Completed, val Dropped])

||| list all tasks
tasks : Query (WithID $ Task)
tasks = SELECT
  ["t.id", "t.description", "t.status"]
  [< FROM (Tasks `AS` "t")]
  `ORDER_BY` [ASC "t.id"]

||| list only new tasks
inbox : Query (WithID $ Task)
inbox = tasks `WHERE` ("t.status" `IS` val New)

||| list all incomplete tasks
incomplete : Query (WithID $ Task)
incomplete = tasks `WHERE` ("t.status" `IS_NOT` val Completed)

||| show completed tasks
completed : Query (WithID $ Task)
completed = tasks `WHERE` ("t.status" `IN` [val Completed, val Dropped])


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
  | ShowDepGraph
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
  x => Just $ cast x


||| Parse an argument vector into an application command
parse : List String -> Maybe Command
parse []               = Just $ ShowIncomplete
parse ["all"]          = Just $ ShowAll
parse ["inbox"]        = Just $ ShowInbox
parse ["completed"]    = Just $ ShowCompleted
parse ["incomplete"]   = Just $ ShowIncomplete
parse ["deps"]         = Just $ ShowDepGraph
parse ("add" :: rest)  = Just $ Add       (unwords rest)
parse ["complete", id] = Just $ Complete !(parseId id)
parse ["drop",     id] = Just $ Drop     !(parseId id)
parse ["depend", t, d] = Just $ Depend   !(parseId t)    !(parseId d)
parse ["purge"]        = Just $ Purge
parse _                = Nothing


-------------------------------------------------------------------------------
-- Entry Point
-------------------------------------------------------------------------------


0 Errs : List Type
Errs = [SqlError]

handlers : All (Handler ()) Errs
handlers = [ printLn ]

||| Dispatch application commands to the database.
app: String -> List String -> App Errs ()
app path args = withDB path $ do
  cmds $ [createTasks, createDependencies]
  case parse args of
    Nothing => die "Invalid command: \{unwords args}"
    Just ShowAll        => queryTable tasks      10000 >>= printTable
    Just ShowInbox      => queryTable inbox      10000 >>= printTable
    Just ShowCompleted  => queryTable completed  10000 >>= printTable
    Just ShowIncomplete => queryTable incomplete 10000 >>= printTable
    Just ShowDepGraph   => ?hole_6
    Just (Add desc)     => cmds $ [ insertTask $ T desc New ]
    Just (Drop id)      => cmds $ [ dropTask id ]
    Just (Complete id)  => cmds $ [ completeTask id ]
    Just (Depend t d)   => cmds $ [ dependsOn t d ]
    Just Purge          => cmds $ [ deleteCompleted ]


runCommand : String -> List String -> IO ()
runCommand path args = do
  runApp handlers $ app path args


main : IO ()
main = do
  dbPath <- getEnv "SQLTEST_DB_PATH"
  args   <- getArgs
  runCommand (fromMaybe ".todo-db" dbPath) args
