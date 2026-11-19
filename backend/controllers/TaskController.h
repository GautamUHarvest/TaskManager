#pragma once

#include <drogon/HttpAppFramework.h>
#include <trantor/utils/TaskQueue.h>

#include "../services/TaskService.h"

namespace taskmanager
{

class TaskController
{
  public:
    TaskController(TaskService &service, trantor::TaskQueue &workers);

    void addTask(const drogon::HttpRequestPtr &request,
                 drogon::AdviceCallback &&callback);
    void addSubtask(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void addNote(const drogon::HttpRequestPtr &request,
                 drogon::AdviceCallback &&callback);
    void addComment(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void addProject(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void allProjects(const drogon::HttpRequestPtr &request,
                     drogon::AdviceCallback &&callback);
    void changeStatus(const drogon::HttpRequestPtr &request,
                      drogon::AdviceCallback &&callback);
    void updateTask(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void deleteTask(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void updateNote(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void deleteNote(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void updateComment(const drogon::HttpRequestPtr &request,
                       drogon::AdviceCallback &&callback);
    void deleteComment(const drogon::HttpRequestPtr &request,
                       drogon::AdviceCallback &&callback);
    void taskDetail(const drogon::HttpRequestPtr &request,
                    drogon::AdviceCallback &&callback);
    void allUsers(const drogon::HttpRequestPtr &request,
                  drogon::AdviceCallback &&callback);
    void notifications(const drogon::HttpRequestPtr &request,
                       drogon::AdviceCallback &&callback);
    void allTasks(const drogon::HttpRequestPtr &request,
                  drogon::AdviceCallback &&callback);
    void myTasks(const drogon::HttpRequestPtr &request,
                 drogon::AdviceCallback &&callback);
    void completedTasks(const drogon::HttpRequestPtr &request,
                        drogon::AdviceCallback &&callback);

  private:
    template <typename Work>
    void run(const drogon::HttpRequestPtr &request,
             drogon::AdviceCallback &&callback,
             Work work);

    TaskService &service_;
    trantor::TaskQueue &workers_;
};

}  // namespace taskmanager
