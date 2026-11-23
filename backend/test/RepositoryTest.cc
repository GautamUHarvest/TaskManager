// Integration tests against a real SQLite file migrated with the production
// migrations. Each test case gets its own fresh database.
#include <drogon/drogon_test.h>

#include "common/Errors.h"
#include "db/Migrations.h"
#include "db/Sqlite.h"
#include "repositories/AuthRepository.h"
#include "repositories/CommentRepository.h"
#include "repositories/NoteRepository.h"
#include "repositories/NotificationRepository.h"
#include "repositories/ProjectRepository.h"
#include "repositories/TaskRepository.h"
#include "repositories/UserRepository.h"
#include "services/TaskService.h"

#include <algorithm>
#include <atomic>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <string>
#include <unistd.h>

using namespace taskmanager;

namespace
{
// A migrated database in a unique temp directory, removed on destruction.
class TempDatabase
{
  public:
    TempDatabase()
    {
        static std::atomic<int> counter{0};
        directory_ = std::filesystem::temp_directory_path() /
                     ("taskmanager-test-" + std::to_string(::getpid()) + "-" +
                      std::to_string(counter++));
        std::filesystem::create_directories(directory_);
        path_ = (directory_ / "test.sqlite3").string();
        db::initializeDatabase(path_, TASK_MANAGER_MIGRATIONS_DIR);
        database_ = std::make_unique<db::Database>(path_);
    }

    ~TempDatabase()
    {
        std::error_code ignored;
        std::filesystem::remove_all(directory_, ignored);
    }

    const db::Database &database() const
    {
        return *database_;
    }

    // Registers an active account and returns its id.
    std::int64_t addUser(const std::string &name)
    {
        AuthRepository auth(*database_);
        return auth.createUser(
            name, name + "@uharvest.in", name, "not-a-real-hash");
    }

  private:
    std::filesystem::path directory_;
    std::string path_;
    std::unique_ptr<db::Database> database_;
};

NewTask newTask(std::int64_t creatorId, const std::string &title)
{
    NewTask task;
    task.createdById = creatorId;
    task.projectId = 1;
    task.title = title;
    task.status = "todo";
    task.type = "decide";
    task.discipline = "decide";
    return task;
}
}  // namespace

DROGON_TEST(SqliteTransactionsAndErrors)
{
    TempDatabase temp;
    auto connection = temp.database().connect();
    connection.execute("CREATE TABLE t (v TEXT UNIQUE)");

    // Not committed -> rolled back when the Transaction goes out of scope.
    {
        db::Transaction transaction(connection);
        connection.execute("INSERT INTO t VALUES ('a')");
    }
    {
        db::Statement count(connection, "SELECT COUNT(*) FROM t");
        REQUIRE(count.step());
        CHECK(count.int64Column(0) == 0);
    }

    // Committed -> persists.
    {
        db::Transaction transaction(connection);
        connection.execute("INSERT INTO t VALUES ('a')");
        transaction.commit();
    }

    // A constraint failure carries its code, even after other calls ran.
    bool sawConstraint = false;
    try
    {
        db::Statement insert(connection, "INSERT INTO t VALUES (?1)");
        insert.bindText(1, "a");
        insert.step();
    }
    catch (const db::SqliteError &error)
    {
        sawConstraint = error.isConstraint();
    }
    CHECK(sawConstraint);

    CHECK_THROWS_AS(db::mapConstraintError("dup",
                                           [&] {
                                               connection.execute(
                                                   "INSERT INTO t VALUES ('a')");
                                           }),
                    std::invalid_argument);
    // Non-constraint errors are not disguised as validation errors.
    CHECK_THROWS_AS(db::mapConstraintError(
                        "dup", [&] { connection.execute("SELECT * FROM nope"); }),
                    db::SqliteError);
}

DROGON_TEST(MigrationsAreIdempotent)
{
    TempDatabase temp;
    // Constructing TempDatabase already migrated once; a second run must be a
    // no-op rather than re-applying (and failing on) CREATE TABLE.
    CHECK_NOTHROW(db::initializeDatabase(temp.database().path(),
                                         TASK_MANAGER_MIGRATIONS_DIR));

    std::size_t files = 0;
    for (const auto &entry :
         std::filesystem::directory_iterator(TASK_MANAGER_MIGRATIONS_DIR))
    {
        files += entry.path().extension() == ".sql" ? 1 : 0;
    }
    auto connection = temp.database().connect();
    db::Statement applied(connection, "SELECT COUNT(*) FROM schema_migrations");
    REQUIRE(applied.step());
    CHECK(static_cast<std::size_t>(applied.int64Column(0)) == files);
}

DROGON_TEST(TaskRepositoryLifecycle)
{
    TempDatabase temp;
    const auto alice = temp.addUser("alice");
    const auto bob = temp.addUser("bob");
    TaskRepository tasks(temp.database());

    // Regression: an unknown assignee used to surface as HTTP 500 because the
    // SQLite error code was read after the statement had been finalized.
    auto badAssignee = newTask(alice, "Bad");
    badAssignee.assigneeIds = {999};
    CHECK_THROWS_AS(tasks.create(badAssignee), std::invalid_argument);
    CHECK(tasks.listAll().empty());  // and nothing was half-written

    auto task = newTask(alice, "Build");
    task.assigneeIds = {bob, alice};
    const auto created = tasks.create(task);
    CHECK(created.version == 1);
    // Ordered by (assigned_at, user_id) with millisecond timestamps, so the
    // order depends on whether both inserts land in the same millisecond.
    // Compare as a set.
    auto assignees = created.assigneeIds;
    std::sort(assignees.begin(), assignees.end());
    CHECK((assignees == std::vector<std::int64_t>{alice, bob}));

    // The batched assignee load in list queries matches the single-task read.
    const auto listed = tasks.listAll();
    REQUIRE(listed.size() == 1);
    CHECK(listed.front().assigneeIds == created.assigneeIds);
    CHECK(tasks.listByAssignee(bob).size() == 1);

    TaskUpdate update;
    update.taskId = created.id;
    update.assigneeIds = std::vector<std::int64_t>{alice};
    update.description.emplace(std::string("Weld it"));
    const auto updated = tasks.update(update, alice);
    CHECK(updated.version == 2);
    CHECK((updated.assigneeIds == std::vector<std::int64_t>{alice}));
    CHECK(*updated.description == "Weld it");
    CHECK(tasks.listByAssignee(bob).empty());

    auto child = newTask(bob, "Cut");
    child.parentTaskId = created.id;
    const auto subtask = tasks.createSubtask(child);
    CHECK(tasks.countSubtasks(created.id) == 1);
    CHECK(tasks.listSubtasks(created.id).front().id == subtask.id);

    CHECK_THROWS_AS(tasks.updateStatus(999, "done", alice), NotFoundError);
    CHECK(tasks.updateStatus(subtask.id, "done", bob).status == "done");
    CHECK(tasks.listCompleted().size() == 1);

    tasks.remove(subtask.id);
    tasks.remove(created.id);
    CHECK(!tasks.find(created.id));
}

DROGON_TEST(NotesCommentsNotifications)
{
    TempDatabase temp;
    const auto alice = temp.addUser("alice");
    const auto bob = temp.addUser("bob");
    TaskRepository tasks(temp.database());
    NoteRepository notes(temp.database());
    CommentRepository comments(temp.database());
    NotificationRepository notifications(temp.database());
    const auto task = tasks.create(newTask(alice, "T"));

    CHECK_THROWS_AS(notes.add(NewTaskNote{999, alice, "x"}),
                    std::invalid_argument);
    const auto note = notes.add(NewTaskNote{task.id, alice, "n"});
    CHECK(notes.update(note.id, "n2").body == "n2");
    CHECK_THROWS_AS(notes.update(999, "x"), NotFoundError);

    const auto root = comments.add(NewComment{task.id, alice, std::nullopt, "r"});
    const auto reply = comments.add(NewComment{task.id, bob, root.id, "a"});
    comments.add(NewComment{task.id, alice, reply.id, "b"});
    CHECK(comments.countDescendants(root.id) == 2);
    comments.remove(root.id);
    CHECK(comments.listForTask(task.id).empty());  // replies cascaded

    const auto alert =
        notifications.create(bob, alice, task.id, kBlockerNotificationType, "m");
    CHECK(notifications.listPendingBlockers(bob).size() == 1);
    CHECK(!notifications.acknowledge(alert.id, alice));  // not alice's
    CHECK(notifications.acknowledge(alert.id, bob));
    CHECK(notifications.acknowledge(alert.id, bob));  // idempotent
    CHECK(notifications.listPendingBlockers(bob).empty());
}

DROGON_TEST(TaskServicePermissions)
{
    // Services take the caller as a UserRecord, so they can be exercised
    // without issuing or verifying any tokens.
    TempDatabase temp;
    const auto aliceId = temp.addUser("alice");
    const auto bobId = temp.addUser("bob");
    const auto carolId = temp.addUser("carol");
    UserRepository users(temp.database());
    const auto alice = *users.findActive(aliceId);
    const auto bob = *users.findActive(bobId);
    const auto carol = *users.findActive(carolId);

    TaskRepository tasks(temp.database());
    ProjectRepository projects(temp.database());
    NoteRepository notes(temp.database());
    CommentRepository comments(temp.database());
    TaskService service(tasks, projects, users, notes, comments);

    TaskInput input;
    input.title = "Task";
    input.assigneeIds = {bobId};
    const auto task = service.addTask(alice, input);

    TaskUpdate rename;
    rename.taskId = task.id;
    rename.title = "Renamed";
    CHECK(service.editTask(bob, rename).title == "Renamed");  // assignee
    CHECK_THROWS_AS(service.editTask(carol, rename), ForbiddenError);
    CHECK_THROWS_AS(service.deleteTask(bob, task.id), ForbiddenError);

    CHECK_THROWS_AS(service.raiseBlocker(bob, task.id, bobId, "m"),
                    std::invalid_argument);  // cannot block on yourself
    CHECK_THROWS_AS(service.raiseBlocker(bob, task.id, 999, "m"),
                    std::invalid_argument);  // unknown member
    const auto raised = service.raiseBlocker(bob, task.id, carolId, " parts ");
    CHECK(raised.task.status == "blocked");
    CHECK(raised.notification.recipientId == carolId);

    TaskInput unknownProject;
    unknownProject.title = "x";
    unknownProject.projectId = 42;
    CHECK_THROWS_AS(service.addTask(alice, unknownProject),
                    std::invalid_argument);

    CHECK_NOTHROW(service.deleteTask(alice, task.id));
    CHECK_THROWS_AS(service.taskDetail(task.id), NotFoundError);
}

DROGON_TEST(TaskServiceProjectTasks)
{
    TempDatabase temp;
    const auto aliceId = temp.addUser("alice");
    UserRepository users(temp.database());
    const auto alice = *users.findActive(aliceId);

    TaskRepository tasks(temp.database());
    ProjectRepository projects(temp.database());
    NoteRepository notes(temp.database());
    CommentRepository comments(temp.database());
    TaskService service(tasks, projects, users, notes, comments);

    NewProject newProject;
    newProject.createdById = aliceId;
    newProject.name = "Rover";
    const auto rover = projects.create(newProject);

    TaskInput inRover;
    inRover.title = "Chassis";
    inRover.projectId = rover.id;
    const auto parent = service.addTask(alice, inRover);
    TaskInput child;
    child.title = "Wheels";
    child.projectId = rover.id;
    const auto subtask = service.addSubtask(alice, parent.id, child);
    TaskInput elsewhere;
    elsewhere.title = "Unfiled";
    service.addTask(alice, elsewhere);  // default project

    const auto listed = service.projectTasks(rover.id);
    REQUIRE(listed.size() == 2);  // subtasks included, other projects not
    CHECK(std::all_of(listed.begin(), listed.end(), [&](const TaskRecord &t) {
        return t.projectId == rover.id;
    }));
    CHECK(std::any_of(listed.begin(), listed.end(), [&](const TaskRecord &t) {
        return t.id == subtask.id;
    }));
    CHECK(service.projectTasks(1).size() == 1);
    CHECK_THROWS_AS(service.projectTasks(999), std::invalid_argument);
}
