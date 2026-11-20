#include "Responses.h"

namespace taskmanager::http
{

drogon::HttpResponsePtr jsonResponse(drogon::HttpStatusCode status,
                                     const Json::Value &body)
{
    auto response = drogon::HttpResponse::newHttpJsonResponse(body);
    response->setStatusCode(status);
    response->addHeader("Cache-Control", "no-store");
    response->addHeader("Pragma", "no-cache");
    return response;
}

drogon::HttpResponsePtr noContentResponse()
{
    auto response = drogon::HttpResponse::newHttpResponse();
    response->setStatusCode(drogon::k204NoContent);
    response->addHeader("Cache-Control", "no-store");
    return response;
}

drogon::HttpResponsePtr errorResponse(drogon::HttpStatusCode status,
                                      const std::string &message)
{
    Json::Value body;
    body["error"] = message;
    return jsonResponse(status, body);
}

}  // namespace taskmanager::http
