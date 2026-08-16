cmake_minimum_required(VERSION 3.10)
project(FuncClient)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(FuncClient
    func_client.cpp
    ../API_HubTool.c
    ../API_HubTool.h
)
target_include_directories(FuncClient PRIVATE ..)

if(WIN32)
    target_link_libraries(FuncClient kernel32)
else()
    target_link_libraries(FuncClient dl)
endif()