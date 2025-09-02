cmake_minimum_required(VERSION 3.21)
project(immutable_audit CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Tell CMake we’re using vcpkg
find_package(libpqxx CONFIG REQUIRED)


add_executable(immutable_audit main.cpp)

# Link against libpqxx and libpq
target_link_libraries(immutable_audit PRIVATE libpqxx::pqxx)
