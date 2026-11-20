cmake_minimum_required(VERSION 3.13)
project(TaskManagerBackend_test CXX)

# Every *.cc here is a test translation unit; test_main.cc holds main().
file(GLOB TEST_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.cc")
add_executable(${PROJECT_NAME} ${TEST_SOURCES})
target_link_libraries(${PROJECT_NAME} PRIVATE taskmanager_core)
add_test(NAME TaskManagerBackend_tests COMMAND ${PROJECT_NAME})

ParseAndAddDrogonTests(${PROJECT_NAME})
