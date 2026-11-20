#pragma once

#include "../http/Dispatcher.h"
#include "../services/CommentService.h"

#include <drogon/HttpAppFramework.h>

namespace taskmanager
{

// /api/task/comment, /api/task/comment/update, /api/task/comment/delete.
class CommentController
{
  public:
    CommentController(CommentService &service,
                      const http::Dispatcher &dispatcher);

    void addComment(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void updateComment(const drogon::HttpRequestPtr &request,
                       drogon::AdviceCallback &&callback);
    void deleteComment(const drogon::HttpRequestPtr &request,
                       drogon::AdviceCallback &&callback);

  private:
    CommentService &service_;
    const http::Dispatcher &dispatcher_;
};

}  // namespace taskmanager
