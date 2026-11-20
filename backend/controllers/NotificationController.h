#pragma once

#include "../http/Dispatcher.h"
#include "../services/NotificationService.h"

#include <drogon/HttpAppFramework.h>

namespace taskmanager
{

// /api/notification/*: all, pending-blockers, ack.
class NotificationController
{
  public:
    NotificationController(NotificationService &service,
                           const http::Dispatcher &dispatcher);

    void notifications(const drogon::HttpRequestPtr &request,
                       drogon::AdviceCallback &&callback);
    void pendingBlockers(const drogon::HttpRequestPtr &request,
                         drogon::AdviceCallback &&callback);
    void acknowledge(const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback);

  private:
    NotificationService &service_;
    const http::Dispatcher &dispatcher_;
};

}  // namespace taskmanager
