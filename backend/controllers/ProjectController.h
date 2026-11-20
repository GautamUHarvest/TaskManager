#pragma once

#include "../http/Dispatcher.h"
#include "../services/ProjectService.h"

#include <drogon/HttpAppFramework.h>

namespace taskmanager
{

// /api/project/*: add, all.
class ProjectController
{
  public:
    ProjectController(ProjectService &service,
                      const http::Dispatcher &dispatcher);

    void addProject(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void allProjects(const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback);

  private:
    ProjectService &service_;
    const http::Dispatcher &dispatcher_;
};

}  // namespace taskmanager
