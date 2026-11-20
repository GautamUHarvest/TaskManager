#pragma once

#include <drogon/HttpResponse.h>
#include <json/json.h>

#include <string>

// Response builders. Every API response is marked uncacheable: bodies carry
// tokens or per-user data.
namespace taskmanager::http
{

drogon::HttpResponsePtr jsonResponse(drogon::HttpStatusCode status,
                                     const Json::Value &body);

drogon::HttpResponsePtr noContentResponse();

// {"error": message} with the given status.
drogon::HttpResponsePtr errorResponse(drogon::HttpStatusCode status,
                                      const std::string &message);

}  // namespace taskmanager::http
