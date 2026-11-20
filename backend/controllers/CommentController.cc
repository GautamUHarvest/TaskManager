#include "CommentController.h"

#include "../http/JsonMappers.h"
#include "../http/RequestParsing.h"
#include "../http/Responses.h"

#include <utility>

namespace taskmanager
{
using namespace http;

CommentController::CommentController(CommentService &service,
                                     const http::Dispatcher &dispatcher)
    : service_(service), dispatcher_(dispatcher)
{
}

void CommentController::addComment(const drogon::HttpRequestPtr &request,
                                   drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto body = requiredBody(request);
            const auto created =
                service_.addComment(actor,
                                    requiredInt64(body, "task_id"),
                                    requiredString(body, "body"),
                                    optionalInt64(body, "parent_comment_id"));
            Json::Value response;
            response["message"] = "Comment created";
            response["comment"] = toJson(created);
            return jsonResponse(drogon::k201Created, response);
        });
}

void CommentController::updateComment(const drogon::HttpRequestPtr &request,
                                      drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto body = requiredBody(request);
            const auto updated =
                service_.editComment(actor,
                                     requiredInt64(body, "comment_id"),
                                     requiredString(body, "body"));
            Json::Value response;
            response["message"] = "Comment updated";
            response["comment"] = toJson(updated);
            return jsonResponse(drogon::k200OK, response);
        });
}

void CommentController::deleteComment(const drogon::HttpRequestPtr &request,
                                      drogon::AdviceCallback &&callback)
{
    dispatcher_.authenticated(
        request, std::move(callback), [this, request](const UserRecord &actor) {
            const auto commentId =
                requiredInt64(requiredBody(request), "comment_id");
            const auto deletedReplies = service_.deleteComment(actor, commentId);
            Json::Value response;
            response["message"] = "Comment deleted";
            response["deleted_comment_id"] = Json::Int64(commentId);
            response["deleted_reply_count"] = Json::Int64(deletedReplies);
            return jsonResponse(drogon::k200OK, response);
        });
}

}  // namespace taskmanager
