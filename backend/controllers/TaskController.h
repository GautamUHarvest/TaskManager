#pragma once

#include "../http/Dispatcher.h"
#include "../services/TaskService.h"

#include <drogon/HttpAppFramework.h>

namespace taskmanager
{

// /api/task/*: create, subtask, status, update, delete, block, and the reads.
// Every handler requires a signed-in caller.
class TaskController
{
  public:
    TaskController(TaskService &service, const http::Dispatcher &dispatcher);

    void addTask(const drogon::HttpRequestPtr &request,
                 drogon::AdviceCallback &&callback);
    void addSubtask(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void changeStatus(const drogon::HttpRequestPtr &request,
                      drogon::AdviceCallback &&callback);
    void updateTask(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void deleteTask(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    // Also pushes the alert to the responsible member's live sockets.
    void raiseBlocker(const drogon::HttpRequestPtr &request,
                      drogon::AdviceCallback &&callback);
    void taskDetail(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void allTasks(const drogon::HttpRequestPtr &request,
                  drogon::AdviceCallback &&callback);
    void myTasks(const drogon::HttpRequestPtr &request,
                 drogon::AdviceCallback &&callback);
    void completedTasks(const drogon::HttpRequestPtr &request,
                        drogon::AdviceCallback &&callback);
    // GET ?project_id=N: every task (subtasks included) in one project.
    void projectTasks(const drogon::HttpRequestPtr &request,
                      drogon::AdviceCallback &&callback);

  private:
    TaskService &service_;
    const http::Dispatcher &dispatcher_;
};

}  // namespace taskmanager
