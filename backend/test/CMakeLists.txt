cmake_minimum_required(VERSION 3.5)
project(TaskManagerBackend_test CXX)

add_executable(${PROJECT_NAME} test_main.cc)

# ##############################################################################
# If you include the drogon source code locally in your project, use this method
# to add drogon 
# target_link_libraries(${PROJECT_NAME} PRIVATE drogon)
#
# and comment out the following lines
target_link_libraries(${PROJECT_NAME} PRIVATE Drogon::Drogon)
find_package(OpenSSL REQUIRED)
target_link_libraries(${PROJECT_NAME} PRIVATE OpenSSL::Crypto)
target_sources(${PROJECT_NAME} PRIVATE ../security/AuthCrypto.cc)
target_include_directories(${PROJECT_NAME} PRIVATE .. ../security)
add_test(NAME TaskManagerBackend_auth_tests COMMAND ${PROJECT_NAME})

ParseAndAddDrogonTests(${PROJECT_NAME})
