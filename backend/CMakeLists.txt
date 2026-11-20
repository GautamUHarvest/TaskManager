cmake_minimum_required(VERSION 3.13)
project(TaskManagerBackend CXX)
enable_testing()

# Emit build/compile_commands.json so editors/IntelliSense (VS Code C/C++,
# clangd) use the exact include paths and flags as the real build. Without
# this, IntelliSense misses non-standard include dirs (e.g. jsoncpp under
# /usr/include/jsoncpp) and reports phantom "undefined type" errors even
# though the compiler build is clean.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(CheckIncludeFileCXX)

check_include_file_cxx(any HAS_ANY)
check_include_file_cxx(string_view HAS_STRING_VIEW)
check_include_file_cxx(coroutine HAS_COROUTINE)
if (NOT "${CMAKE_CXX_STANDARD}" STREQUAL "")
    # Do nothing
elseif (HAS_ANY AND HAS_STRING_VIEW AND HAS_COROUTINE)
    set(CMAKE_CXX_STANDARD 20)
elseif (HAS_ANY AND HAS_STRING_VIEW)
    set(CMAKE_CXX_STANDARD 17)
else ()
    set(CMAKE_CXX_STANDARD 14)
endif ()

set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if (CMAKE_CXX_STANDARD LESS 17)
    message(FATAL_ERROR "c++17 or higher is required")
elseif (CMAKE_CXX_STANDARD LESS 20)
    message(STATUS "use c++17")
else ()
    message(STATUS "use c++20")
endif ()

# System-installed Drogon. To build against the vendored copy instead, replace
# find_package(Drogon) with add_subdirectory(<path to drogon>) and link
# `drogon` in place of Drogon::Drogon below.
find_package(Drogon CONFIG REQUIRED)
find_package(CURL REQUIRED)  # only for the dormant SmtpMailer
find_package(OpenSSL REQUIRED)
find_package(SQLite3 REQUIRED)

# ##############################################################################
# Migrations: copied next to the binary and the path baked in as the default
# for TASK_MANAGER_MIGRATIONS_DIR.
file(GLOB MIGRATION_FILES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/migrations/*.sql")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/migrations")
foreach(MIGRATION_FILE IN LISTS MIGRATION_FILES)
    get_filename_component(MIGRATION_NAME "${MIGRATION_FILE}" NAME)
    configure_file("${MIGRATION_FILE}"
                   "${CMAKE_CURRENT_BINARY_DIR}/migrations/${MIGRATION_NAME}"
                   COPYONLY)
endforeach()

# ##############################################################################
# Application code, shared by the server and the tests.
#
# CONFIGURE_DEPENDS re-globs on every build, so a new .cc in any of these
# directories is picked up without re-running cmake by hand.
#
# An OBJECT library rather than STATIC on purpose: BlockerSocketController
# registers its WebSocket route from a static initializer and nothing calls
# into it, so a static archive would let the linker drop it silently.
set(SOURCE_DIRS
    common config controllers db error_middleware http models repositories
    routes security services)
set(CORE_SOURCES)
foreach(SOURCE_DIR IN LISTS SOURCE_DIRS)
    file(GLOB DIR_SOURCES CONFIGURE_DEPENDS
         "${CMAKE_CURRENT_SOURCE_DIR}/${SOURCE_DIR}/*.cc")
    list(APPEND CORE_SOURCES ${DIR_SOURCES})
endforeach()

add_library(taskmanager_core OBJECT ${CORE_SOURCES})
target_include_directories(taskmanager_core
                           PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}
                                  ${CURL_INCLUDE_DIRS})
target_link_libraries(taskmanager_core
                      PUBLIC Drogon::Drogon ${CURL_LIBRARIES}
                             OpenSSL::Crypto SQLite3_lib)
target_compile_definitions(
    taskmanager_core
    PUBLIC TASK_MANAGER_MIGRATIONS_DIR="${CMAKE_CURRENT_BINARY_DIR}/migrations")

add_executable(${PROJECT_NAME} main.cc)
target_link_libraries(${PROJECT_NAME} PRIVATE taskmanager_core)

add_subdirectory(test)
