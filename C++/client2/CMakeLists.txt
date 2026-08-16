cmake_minimum_required(VERSION 3.10)
project(Client2)

add_executable(Client2
    Client2.cpp
    ../API_HubTool.c
    ../API_HubTool.h
)
target_include_directories(Client2 PRIVATE ..)
if(WIN32)
    target_link_libraries(Client2 kernel32)
endif()
