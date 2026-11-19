cmake_minimum_required(VERSION 3.5)
project(TaskManagerBackend CXX)
enable_testing()

# Emit build/compile_commands.json so editors/IntelliSense (VS Code C/C++,
# clangd) use the exact include paths and flags as the real build. Without
# this, IntelliSense misses non-standard include dirs (e.g. jsoncpp under
# /usr/include/jsoncpp) and reports phantom "undefined type" errors even
# though the compiler build is clean.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Custom file extension configuration
if(NOT DEFINED DEFAULT_SOURCE_EXTENSION)
    set(DEFAULT_SOURCE_EXTENSION "cc" CACHE STRING "Default source file extension (e.g., cc, cpp, cxx)")
endif()
if(NOT DEFINED DEFAULT_HEADER_EXTENSION)
    set(DEFAULT_HEADER_EXTENSION "h" CACHE STRING "Default header file extension (e.g., h, hpp, hxx)")
endif()

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

add_executable(${PROJECT_NAME} main.${DEFAULT_SOURCE_EXTENSION})

# ##############################################################################
# If you include the drogon source code locally in your project, use this method
# to add drogon
# add_subdirectory(drogon)
# target_link_libraries(${PROJECT_NAME} PRIVATE drogon)
#
# and comment out the following lines
find_package(Drogon CONFIG REQUIRED)
find_package(CURL REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(SQLite3 REQUIRED)
target_link_libraries(${PROJECT_NAME}
                      PRIVATE Drogon::Drogon ${CURL_LIBRARIES}
                              OpenSSL::Crypto SQLite3_lib)

file(GLOB AUTH_MIGRATIONS CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/migrations/*.sql")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/migrations")
foreach(MIGRATION_FILE IN LISTS AUTH_MIGRATIONS)
    get_filename_component(MIGRATION_NAME "${MIGRATION_FILE}" NAME)
    configure_file("${MIGRATION_FILE}"
                   "${CMAKE_CURRENT_BINARY_DIR}/migrations/${MIGRATION_NAME}"
                   COPYONLY)
endforeach()

# ##############################################################################

if (CMAKE_CXX_STANDARD LESS 17)
    message(FATAL_ERROR "c++17 or higher is required")
elseif (CMAKE_CXX_STANDARD LESS 20)
    message(STATUS "use c++17")
else ()
    message(STATUS "use c++20")
endif ()

aux_source_directory(controllers CTL_SRC)
aux_source_directory(routes ROUTE_SRC)
aux_source_directory(filters FILTER_SRC)
aux_source_directory(plugins PLUGIN_SRC)
aux_source_directory(models MODEL_SRC)
aux_source_directory(services SERVICE_SRC)
aux_source_directory(repositories REPOSITORY_SRC)
aux_source_directory(security SECURITY_SRC)
aux_source_directory(error_middleware ERROR_MIDDLEWARE_SRC)

drogon_create_views(${PROJECT_NAME} ${CMAKE_CURRENT_SOURCE_DIR}/views
                    ${CMAKE_CURRENT_BINARY_DIR})
# use the following line to create views with namespaces.
# drogon_create_views(${PROJECT_NAME} ${CMAKE_CURRENT_SOURCE_DIR}/views
#                     ${CMAKE_CURRENT_BINARY_DIR} TRUE)
# use the following line to create views with namespace CHANGE_ME prefixed
# and path namespaces.
# drogon_create_views(${PROJECT_NAME} ${CMAKE_CURRENT_SOURCE_DIR}/views
#                     ${CMAKE_CURRENT_BINARY_DIR} TRUE CHANGE_ME)

target_include_directories(${PROJECT_NAME}
                           PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}
                                   ${CURL_INCLUDE_DIRS}
                                   ${CMAKE_CURRENT_SOURCE_DIR}/models
                                   ${CMAKE_CURRENT_SOURCE_DIR}/security
                                   ${CMAKE_CURRENT_SOURCE_DIR}/services
                                   ${CMAKE_CURRENT_SOURCE_DIR}/repositories
                                   ${CMAKE_CURRENT_SOURCE_DIR}/routes
                                   ${CMAKE_CURRENT_SOURCE_DIR}/error_middleware)
target_compile_definitions(
    ${PROJECT_NAME}
    PRIVATE TASK_MANAGER_MIGRATIONS_DIR="${CMAKE_CURRENT_BINARY_DIR}/migrations")
target_sources(${PROJECT_NAME}
               PRIVATE
               ${SRC_DIR}
               ${CTL_SRC}
               ${ROUTE_SRC}
               ${FILTER_SRC}
               ${PLUGIN_SRC}
               ${MODEL_SRC}
               ${SERVICE_SRC}
               ${REPOSITORY_SRC}
               ${SECURITY_SRC}
               ${ERROR_MIDDLEWARE_SRC})
# ##############################################################################
# uncomment the following line for dynamically loading views
# set_property(TARGET ${PROJECT_NAME} PROPERTY ENABLE_EXPORTS ON)

# ##############################################################################

add_subdirectory(test)
