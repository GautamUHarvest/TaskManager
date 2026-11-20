#pragma once

#include <stdexcept>

// Every error type that ErrorMiddleware maps to an HTTP status, in one place,
// so lower layers can throw them without depending on the HTTP layer and the
// middleware can map them without depending on services or repositories.
//
//   std::invalid_argument  -> 400  (validation; also the base of NotFoundError)
//   UnauthorizedError      -> 401
//   ForbiddenError         -> 403
//   DuplicateUserError     -> 409
//   UserLimitError         -> 409
//   TooManyRequestsError   -> 429
//   anything else          -> 500  (logged; message not exposed)
namespace taskmanager
{

class UnauthorizedError : public std::runtime_error
{
  public:
    using std::runtime_error::runtime_error;
};

// The caller is authenticated but is not allowed to act on this resource —
// e.g. editing a task they neither created nor are assigned to, or deleting
// someone else's note.
class ForbiddenError : public std::runtime_error
{
  public:
    using std::runtime_error::runtime_error;
};

// A referenced record does not exist ("Task not found"). Derives from
// std::invalid_argument so it is still reported as HTTP 400, exactly as
// before it had its own type; giving it a distinct type means switching those
// responses to 404 later is a one-line change in ErrorMiddleware.
class NotFoundError : public std::invalid_argument
{
  public:
    using std::invalid_argument::invalid_argument;
};

class DuplicateUserError : public std::runtime_error
{
  public:
    using std::runtime_error::runtime_error;
};

class UserLimitError : public std::runtime_error
{
  public:
    using std::runtime_error::runtime_error;
};

class TooManyRequestsError : public std::runtime_error
{
  public:
    using std::runtime_error::runtime_error;
};

}  // namespace taskmanager
