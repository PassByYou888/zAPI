cmake_minimum_required(VERSION 3.10)
project(Service)

add_executable(Service
    Service.cpp
    ../API_HubTool.c
    ../API_HubTool.h
)
target_include_directories(Service PRIVATE ..)
if(WIN32)
    target_link_libraries(Service kernel32)
endif()
