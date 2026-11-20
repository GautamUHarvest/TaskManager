#include "RequestParsing.h"

#include "../common/Errors.h"
#include "../common/Text.h"

#include <stdexcept>

namespace taskmanager::http
{
namespace
{
std::invalid_argument fieldError(const char *field, const char *problem)
{
    return std::invalid_argument(std::string("Field '") + field + "' " +
                                 problem);
}
}  // namespace

std::string bearerToken(const drogon::HttpRequestPtr &request)
{
    const auto &authorization = request->getHeader("authorization");
    if (authorization.size() <= 7 ||
        text::lowercase(authorization.substr(0, 7)) != "bearer ")
    {
        throw UnauthorizedError("A bearer access token is required");
    }
    return authorization.substr(7);
}

Json::Value requiredBody(const drogon::HttpRequestPtr &request)
{
    const auto &body = request->getJsonObject();
    if (!body || !body->isObject())
    {
        throw std::invalid_argument("A JSON request body is required");
    }
    return *body;
}

std::string requiredString(const Json::Value &body, const char *field)
{
    if (!body.isMember(field) || !body[field].isString() ||
        body[field].asString().empty())
    {
        throw fieldError(field, "is required");
    }
    return body[field].asString();
}

std::optional<std::string> optionalString(const Json::Value &body,
                                          const char *field)
{
    if (!body.isMember(field) || body[field].isNull())
    {
        return std::nullopt;
    }
    if (!body[field].isString())
    {
        throw fieldError(field, "must be a string");
    }
    return body[field].asString();
}

std::int64_t requiredInt64(const Json::Value &body, const char *field)
{
    if (!body.isMember(field) || body[field].isNull() ||
        !body[field].isIntegral())
    {
        throw fieldError(field, "is required and must be an integer");
    }
    return body[field].asInt64();
}

std::optional<std::int64_t> optionalInt64(const Json::Value &body,
                                         const char *field)
{
    if (!body.isMember(field) || body[field].isNull())
    {
        return std::nullopt;
    }
    if (!body[field].isIntegral())
    {
        throw fieldError(field, "must be an integer");
    }
    return body[field].asInt64();
}

std::vector<std::int64_t> optionalInt64Array(const Json::Value &body,
                                             const char *field)
{
    std::vector<std::int64_t> result;
    if (!body.isMember(field) || body[field].isNull())
    {
        return result;
    }
    const auto &value = body[field];
    if (value.isIntegral())
    {
        result.push_back(value.asInt64());
        return result;
    }
    if (!value.isArray())
    {
        throw fieldError(field, "must be an array of integers");
    }
    for (const auto &element : value)
    {
        if (!element.isIntegral())
        {
            throw fieldError(field, "must contain only integers");
        }
        result.push_back(element.asInt64());
    }
    return result;
}

std::optional<std::string> patchString(const Json::Value &body,
                                       const char *field)
{
    if (!body.isMember(field))
    {
        return std::nullopt;
    }
    if (!body[field].isString())
    {
        throw fieldError(field, "must be a string");
    }
    return body[field].asString();
}

std::optional<std::optional<std::string>> patchNullableString(
    const Json::Value &body, const char *field)
{
    // in_place is deliberate: optional's converting construction is subtle
    // when the contained type is itself an optional, and this spells out
    // "outer engaged (field present), inner = the value or NULL".
    using Patch = std::optional<std::optional<std::string>>;
    if (!body.isMember(field))
    {
        return std::nullopt;
    }
    if (body[field].isNull())
    {
        return Patch(std::in_place, std::nullopt);
    }
    if (!body[field].isString())
    {
        throw fieldError(field, "must be a string or null");
    }
    return Patch(std::in_place, body[field].asString());
}

std::int64_t requiredIdParam(const std::string &value, const char *field)
{
    const auto paramError = [field](const char *problem) {
        return std::invalid_argument(std::string("Query parameter '") + field +
                                     "' " + problem);
    };
    if (value.empty())
    {
        throw paramError("is required");
    }
    std::int64_t parsed = 0;
    try
    {
        std::size_t consumed = 0;
        parsed = std::stoll(value, &consumed);
        if (consumed != value.size())
        {
            throw std::invalid_argument("trailing characters");
        }
    }
    catch (const std::exception &)
    {
        throw paramError("must be an integer");
    }
    if (parsed <= 0)
    {
        throw paramError("must be a positive id");
    }
    return parsed;
}

}  // namespace taskmanager::http
