#include "CommentRepository.h"

#include "../common/Errors.h"
#include "Rows.h"

#include <stdexcept>

namespace taskmanager
{

CommentRepository::CommentRepository(const db::Database &database)
    : database_(database)
{
}

CommentRecord CommentRepository::add(const NewComment &comment)
{
    auto connection = database_.connect();
    return db::mapConstraintError(
        "Invalid comment: the task or parent comment does not exist", [&] {
            db::Transaction transaction(connection);
            db::Statement insert(
                connection,
                "INSERT INTO comments (task_id, author_id, parent_comment_id, "
                "body) VALUES (?1, ?2, ?3, ?4)");
            insert.bindInt64(1, comment.taskId);
            insert.bindInt64(2, comment.authorId);
            insert.bindOptInt64(3, comment.parentCommentId);
            insert.bindText(4, comment.body);
            insert.step();

            auto created = rows::findById(connection,
                                          rows::kCommentColumns,
                                          "comments",
                                          connection.lastInsertRowId(),
                                          rows::comment);
            if (!created)
            {
                throw std::runtime_error(
                    "Created comment could not be read back");
            }
            transaction.commit();
            return *created;
        });
}

std::vector<CommentRecord> CommentRepository::listForTask(std::int64_t taskId)
{
    auto connection = database_.connect();
    db::Statement statement(connection,
                            std::string("SELECT ") + rows::kCommentColumns +
                                " FROM comments WHERE task_id = ?1 "
                                "ORDER BY created_at, id");
    statement.bindInt64(1, taskId);
    std::vector<CommentRecord> comments;
    while (statement.step())
    {
        comments.push_back(rows::comment(statement));
    }
    return comments;
}

std::optional<CommentRecord> CommentRepository::find(std::int64_t id)
{
    auto connection = database_.connect();
    return rows::findById(
        connection, rows::kCommentColumns, "comments", id, rows::comment);
}

CommentRecord CommentRepository::update(std::int64_t id,
                                        const std::string &body)
{
    auto connection = database_.connect();
    return db::mapConstraintError("Invalid comment: the body is empty", [&] {
        db::Transaction transaction(connection);
        db::Statement update(
            connection,
            "UPDATE comments SET body = ?1, "
            "updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?2");
        update.bindText(1, body);
        update.bindInt64(2, id);
        update.step();

        auto updated = rows::findById(
            connection, rows::kCommentColumns, "comments", id, rows::comment);
        if (!updated)
        {
            throw NotFoundError("Comment not found");
        }
        transaction.commit();
        return *updated;
    });
}

void CommentRepository::remove(std::int64_t id)
{
    auto connection = database_.connect();
    db::Statement statement(connection, "DELETE FROM comments WHERE id = ?1");
    statement.bindInt64(1, id);
    statement.step();
}

std::int64_t CommentRepository::countDescendants(std::int64_t id)
{
    auto connection = database_.connect();
    db::Statement statement(
        connection,
        "WITH RECURSIVE thread(id) AS ("
        "  SELECT id FROM comments WHERE parent_comment_id = ?1"
        "  UNION ALL"
        "  SELECT c.id FROM comments c "
        "    JOIN thread t ON c.parent_comment_id = t.id"
        ") SELECT COUNT(*) FROM thread");
    statement.bindInt64(1, id);
    return statement.step() ? statement.int64Column(0) : 0;
}

}  // namespace taskmanager
