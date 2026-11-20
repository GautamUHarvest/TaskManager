#pragma once

#include "../models/Task.h"
#include "../models/User.h"

#include <json/json.h>

#include <vector>

// Wire format for every record the API returns. Field names are snake_case
// and must match apirequirement.md and the Flutter models.
namespace taskmanager::http
{

// Public profile: never includes the password hash.
Json::Value toJson(const UserRecord &user);
Json::Value toJson(const ProjectRecord &project);
Json::Value toJson(const TaskRecord &task);
Json::Value toJson(const TaskNoteRecord &note);
Json::Value toJson(const CommentRecord &comment);
Json::Value toJson(const NotificationRecord &notification);

template <typename Record>
Json::Value toJsonArray(const std::vector<Record> &records)
{
    Json::Value array(Json::arrayValue);
    for (const auto &record : records)
    {
        array.append(toJson(record));
    }
    return array;
}

}  // namespace taskmanager::http
