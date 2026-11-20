#pragma once

#include <drogon/HttpRequest.h>
#include <json/json.h>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

// Request readers shared by every controller. Each throws the error the
// client should see: UnauthorizedError for a missing/malformed bearer token,
// std::invalid_argument (HTTP 400) for a bad body or parameter.
namespace taskmanager::http
{

// The token from "Authorization: Bearer <token>" (scheme case-insensitive).
std::string bearerToken(const drogon::HttpRequestPtr &request);

// The JSON object body; rejects a missing, unparsable, or non-object body.
Json::Value requiredBody(const drogon::HttpRequestPtr &request);

// --- Body fields (create-style: absent and null both mean "not sent") ----
// A non-empty string.
std::string requiredString(const Json::Value &body, const char *field);
std::optional<std::string> optionalString(const Json::Value &body,
                                          const char *field);
std::int64_t requiredInt64(const Json::Value &body, const char *field);
std::optional<std::int64_t> optionalInt64(const Json::Value &body,
                                         const char *field);
// An array of integers; absent or null gives an empty list, and a single
// integer is accepted as a one-element list.
std::vector<std::int64_t> optionalInt64Array(const Json::Value &body,
                                             const char *field);

// --- Body fields (patch-style) --------------------------------------------
// On an edit, an absent key means "leave this column alone" while an
// explicit null means "clear it". These return an engaged outer optional
// only when the key is present in the body.
std::optional<std::string> patchString(const Json::Value &body,
                                       const char *field);
std::optional<std::optional<std::string>> patchNullableString(
    const Json::Value &body, const char *field);

// --- Query parameters -----------------------------------------------------
// A required positive-integer query parameter (e.g. ?task_id=12), given the
// raw value from request->getParameter().
std::int64_t requiredIdParam(const std::string &value, const char *field);

}  // namespace taskmanager::http
