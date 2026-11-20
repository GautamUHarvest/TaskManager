#include "CommentService.h"

#include "../common/Errors.h"
#include "TaskRules.h"

#include <algorithm>
#include <stdexcept>
#include <vector>

namespace taskmanager
{

CommentService::CommentService(CommentRepository &comments,
                               TaskRepository &tasks,
                               NotificationRepository &notifications)
    : comments_(comments), tasks_(tasks), notifications_(notifications)
{
}

CommentRecord CommentService::requireOwnComment(const UserRecord &actor,
                                                std::int64_t commentId,
                                                const char *forbiddenMessage)
{
    rules::requirePositiveId(commentId, "comment_id");
    auto comment = comments_.find(commentId);
    if (!comment)
    {
        throw NotFoundError("Comment not found");
    }
    if (comment->authorId != actor.id)
    {
        throw ForbiddenError(forbiddenMessage);
    }
    return *comment;
}

CommentRecord CommentService::addComment(
    const UserRecord &actor,
    std::int64_t taskId,
    const std::string &body,
    const std::optional<std::int64_t> &parentCommentId)
{
    rules::requirePositiveId(taskId, "task_id");
    if (parentCommentId)
    {
        rules::requirePositiveId(*parentCommentId, "parent_comment_id");
    }
    const std::string trimmedBody = rules::normalizeBody(body);

    const auto task = tasks_.find(taskId);
    if (!task)
    {
        throw NotFoundError("Task not found");
    }

    // A reply's parent must exist and belong to the same task. Its author is
    // notified alongside the assignees.
    std::optional<std::int64_t> parentAuthorId;
    if (parentCommentId)
    {
        const auto parent = comments_.find(*parentCommentId);
        if (!parent || parent->taskId != taskId)
        {
            throw std::invalid_argument(
                "Field 'parent_comment_id' must reference a comment on this "
                "task");
        }
        parentAuthorId = parent->authorId;
    }

    NewComment comment;
    comment.taskId = taskId;
    comment.authorId = actor.id;
    comment.parentCommentId = parentCommentId;
    comment.body = trimmedBody;
    const auto created = comments_.add(comment);

    std::vector<std::int64_t> recipients = task->assigneeIds;
    if (parentAuthorId)
    {
        recipients.push_back(*parentAuthorId);
    }
    const std::string message =
        actor.displayName + " commented on \"" + task->title + "\"";
    std::vector<std::int64_t> notified;
    for (const auto recipientId : recipients)
    {
        if (recipientId == actor.id ||
            std::find(notified.begin(), notified.end(), recipientId) !=
                notified.end())
        {
            continue;
        }
        notified.push_back(recipientId);
        notifications_.create(recipientId, actor.id, taskId, "comment", message);
    }
    return created;
}

CommentRecord CommentService::editComment(const UserRecord &actor,
                                          std::int64_t commentId,
                                          const std::string &body)
{
    requireOwnComment(actor, commentId, "Only the comment's author can edit it");
    return comments_.update(commentId, rules::normalizeBody(body));
}

std::int64_t CommentService::deleteComment(const UserRecord &actor,
                                           std::int64_t commentId)
{
    requireOwnComment(
        actor, commentId, "Only the comment's author can delete it");
    // Replies cascade, so count them before the delete to report what went.
    const auto replies = comments_.countDescendants(commentId);
    comments_.remove(commentId);
    return replies;
}

}  // namespace taskmanager
