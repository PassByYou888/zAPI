cmake_minimum_required(VERSION 3.10)
project(Client1)

add_executable(Client1
    Client1.cpp
    ../API_HubTool.c
    ../API_HubTool.h
)
target_include_directories(Client1 PRIVATE ..)
if(WIN32)
    target_link_libraries(Client1 kernel32)
endif()
