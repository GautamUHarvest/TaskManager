#pragma once

#include "../models/Task.h"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

// Pure validation, normalization and permission rules for the task domain.
// No I/O and no framework types, so they are unit-tested directly
// (test/TaskRulesTest.cc). Validation failures throw std::invalid_argument
// with the client-facing message.
namespace taskmanager::rules
{

// Default project when the client does not name one: the "Unidentified"
// project seeded by migration 006.
inline constexpr std::int64_t kDefaultProjectId = 1;

// Status, falling back to "todo" when absent. Throws on an unknown value.
std::string resolveStatus(const std::optional<std::string> &status);
// Type / discipline, falling back to "decide" when absent or blank.
std::string resolveType(const std::optional<std::string> &type);
std::string resolveDiscipline(const std::optional<std::string> &discipline);

// Trims; blank becomes nullopt; longer than maxLength throws.
std::optional<std::string> normalizeOptionalText(
    const std::optional<std::string> &value,
    std::size_t maxLength,
    const char *field);

// Rejects non-positive ids and drops duplicates, keeping first-seen order.
std::vector<std::int64_t> normalizeAssigneeIds(
    const std::vector<std::int64_t> &assigneeIds);

// Note / comment / blocker message body: trimmed, 1 to 4000 characters.
std::string normalizeBody(const std::string &body);

// Throws "Field '<field>' must be a positive id" when id <= 0.
void requirePositiveId(std::int64_t id, const char *field);

// Largest accepted task index; keeps a typo from parking a task far off the
// end of a list.
inline constexpr std::int64_t kMaxTaskIndex = 1000000;

// Throws unless 1 <= index <= kMaxTaskIndex.
void requireValidTaskIndex(std::int64_t index);

// Validates raw client input into an insertable task.
NewTask buildNewTask(std::int64_t createdById, const TaskInput &input);

// Applies the buildNewTask field rules to the fields the client supplied;
// fields left disengaged stay untouched.
TaskUpdate normalizeTaskUpdate(TaskUpdate update);

// Permission rules (apirequirement.md §4).
// A task may be edited, or have a blocker raised on it, by its creator or any
// of its assignees.
bool canEditTask(const TaskRecord &task, std::int64_t userId);
// Any member may (re)assign any task to anyone, even if they neither created
// it nor are assigned to it. Only covers updates that change assignees alone;
// other fields still need canEditTask.
bool canAssignTask(const TaskRecord &task, std::int64_t userId);
// A task may be deleted only by its creator.
bool canDeleteTask(const TaskRecord &task, std::int64_t userId);

}  // namespace taskmanager::rules
