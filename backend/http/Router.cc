#include "Router.h"

#include "../common/Text.h"
#include "../security/OriginPolicy.h"

#include <sstream>
#include <stdexcept>

namespace taskmanager::http
{
namespace
{
const char *methodName(drogon::HttpMethod method)
{
    switch (method)
    {
        case drogon::Get:
            return "GET";
        case drogon::Post:
            return "POST";
        default:
            throw std::logic_error("Router only registers GET and POST");
    }
}

// The browser may only ask to send these request headers.
bool hasOnlyAllowedHeaders(const std::string &headers)
{
    std::istringstream stream(headers);
    std::string header;
    while (std::getline(stream, header, ','))
    {
        header = text::lowercase(text::trim(header));
        if (header.empty())
        {
            continue;
        }
        if (header != "authorization" && header != "content-type")
        {
            return false;
        }
    }
    return true;
}

drogon::HttpResponsePtr preflightResponse(
    const drogon::HttpRequestPtr &request,
    const std::set<std::string> &allowedMethods)
{
    auto response = drogon::HttpResponse::newHttpResponse();
    response->addHeader("Vary", "Origin");

    const auto &origin = request->getHeader("origin");
    if (!security::isAllowedOrigin(origin))
    {
        response->setStatusCode(drogon::k403Forbidden);
        return response;
    }

    const auto &requestedMethod =
        request->getHeader("access-control-request-method");
    if (allowedMethods.count(requestedMethod) == 0)
    {
        response->setStatusCode(drogon::k405MethodNotAllowed);
        return response;
    }
    if (!hasOnlyAllowedHeaders(
            request->getHeader("access-control-request-headers")))
    {
        response->setStatusCode(drogon::k403Forbidden);
        return response;
    }

    response->setStatusCode(drogon::k204NoContent);
    response->addHeader("Access-Control-Allow-Origin", origin);
    response->addHeader("Access-Control-Allow-Credentials", "true");
    response->addHeader("Access-Control-Allow-Methods", requestedMethod);
    response->addHeader("Access-Control-Allow-Headers",
                        "Authorization, Content-Type");
    response->addHeader("Access-Control-Max-Age", "600");
    return response;
}
}  // namespace

Router::Router(drogon::HttpAppFramework &app)
    : app_(app),
      methods_(std::make_shared<std::map<std::string, std::set<std::string>>>())
{
}

void Router::record(const std::string &path, drogon::HttpMethod method)
{
    if (!(*methods_)[path].insert(methodName(method)).second)
    {
        throw std::logic_error("Route registered twice: " + path);
    }
}

void Router::installCorsPreflight()
{
    // Only exercised by direct cross-origin dev (Flutter dev server ->
    // backend). Behind nginx the app is same-origin and never preflights.
    app_.registerSyncAdvice(
        [methods = methods_](const drogon::HttpRequestPtr &request) {
            if (request->method() != drogon::Options)
            {
                return drogon::HttpResponsePtr{};
            }
            const auto route = methods->find(request->path());
            if (route == methods->end())
            {
                return drogon::HttpResponsePtr{};
            }
            return preflightResponse(request, route->second);
        });
}

}  // namespace taskmanager::http
