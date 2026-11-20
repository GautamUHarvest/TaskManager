#include <drogon/drogon_test.h>

#include "services/TaskRules.h"

#include <stdexcept>

using namespace taskmanager;

DROGON_TEST(TaskRulesEnums)
{
    CHECK(rules::resolveStatus(std::nullopt) == "todo");
    CHECK(rules::resolveStatus(std::string(" done ")) == "done");
    CHECK_THROWS_AS(rules::resolveStatus(std::string("finished")),
                    std::invalid_argument);
    // Unlike type/discipline, a blank status is rejected, not defaulted.
    CHECK_THROWS_AS(rules::resolveStatus(std::string("  ")),
                    std::invalid_argument);

    CHECK(rules::resolveType(std::nullopt) == "decide");
    CHECK(rules::resolveType(std::string("  ")) == "decide");
    CHECK(rules::resolveType(std::string("code")) == "code");
    CHECK_THROWS_AS(rules::resolveType(std::string("CODE")),
                    std::invalid_argument);

    CHECK(rules::resolveDiscipline(std::string("frontend")) == "frontend");
    CHECK_THROWS_AS(rules::resolveDiscipline(std::string("marketing")),
                    std::invalid_argument);
}

DROGON_TEST(TaskRulesTextAndIds)
{
    CHECK(!rules::normalizeOptionalText(std::nullopt, 10, "f"));
    CHECK(!rules::normalizeOptionalText(std::string(" \t "), 10, "f"));
    CHECK(*rules::normalizeOptionalText(std::string(" hi "), 10, "f") == "hi");
    CHECK_THROWS_AS(
        rules::normalizeOptionalText(std::string(11, 'x'), 10, "f"),
        std::invalid_argument);

    CHECK(rules::normalizeBody("  note ") == "note");
    CHECK_THROWS_AS(rules::normalizeBody("   "), std::invalid_argument);
    CHECK_THROWS_AS(rules::normalizeBody(std::string(4001, 'x')),
                    std::invalid_argument);

    const auto ids = rules::normalizeAssigneeIds({3, 1, 3, 2, 1});
    CHECK((ids == std::vector<std::int64_t>{3, 1, 2}));
    CHECK_THROWS_AS(rules::normalizeAssigneeIds({1, 0}), std::invalid_argument);

    CHECK_NOTHROW(rules::requirePositiveId(1, "task_id"));
    CHECK_THROWS_AS(rules::requirePositiveId(0, "task_id"),
                    std::invalid_argument);
}

DROGON_TEST(TaskRulesBuildNewTask)
{
    TaskInput input;
    input.title = "  Wire the motor  ";
    input.assigneeIds = {5, 5};
    const auto task = rules::buildNewTask(7, input);
    CHECK(task.createdById == 7);
    CHECK(task.title == "Wire the motor");
    CHECK(task.status == "todo");
    CHECK(task.type == "decide");
    CHECK(task.discipline == "decide");
    CHECK(task.projectId == rules::kDefaultProjectId);
    CHECK(!task.description);
    CHECK(task.assigneeIds.size() == 1);

    TaskInput blank;
    blank.title = "   ";
    CHECK_THROWS_AS(rules::buildNewTask(7, blank), std::invalid_argument);

    TaskInput longTitle;
    longTitle.title = std::string(201, 't');
    CHECK_THROWS_AS(rules::buildNewTask(7, longTitle), std::invalid_argument);

    TaskInput badProject;
    badProject.title = "x";
    badProject.projectId = 0;
    CHECK_THROWS_AS(rules::buildNewTask(7, badProject), std::invalid_argument);
}

DROGON_TEST(TaskRulesNormalizeUpdate)
{
    TaskUpdate update;
    update.taskId = 1;
    CHECK(update.empty());

    // Explicit null description: outer engaged, inner cleared.
    update.description.emplace(std::nullopt);
    update.title = "  New title ";
    CHECK(!update.empty());
    auto normalized = rules::normalizeTaskUpdate(update);
    CHECK(*normalized.title == "New title");
    REQUIRE(normalized.description.has_value());
    CHECK(!normalized.description->has_value());
    // Untouched fields stay disengaged.
    CHECK(!normalized.status);
    CHECK(!normalized.assigneeIds);

    // A blank description is also a clear, not an empty string.
    TaskUpdate blankDescription;
    blankDescription.description.emplace(std::string("   "));
    normalized = rules::normalizeTaskUpdate(blankDescription);
    REQUIRE(normalized.description.has_value());
    CHECK(!normalized.description->has_value());

    TaskUpdate blankTitle;
    blankTitle.title = " ";
    CHECK_THROWS_AS(rules::normalizeTaskUpdate(blankTitle),
                    std::invalid_argument);
}

DROGON_TEST(TaskRulesPermissions)
{
    TaskRecord task{};
    task.createdById = 1;
    task.assigneeIds = {2, 3};

    CHECK(rules::canEditTask(task, 1));   // creator
    CHECK(rules::canEditTask(task, 3));   // assignee
    CHECK(!rules::canEditTask(task, 4));  // neither

    CHECK(rules::canDeleteTask(task, 1));
    CHECK(!rules::canDeleteTask(task, 2));  // assignees cannot delete
}
