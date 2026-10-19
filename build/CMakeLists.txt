cmake_minimum_required(VERSION 3.10)
project(RAMGuard CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SOURCES
    ../src/main.cpp
    ../src/config.cpp
    ../src/logger.cpp
    ../src/memory.cpp
    ../src/process_manager.cpp
    ../src/notification.cpp
    ../src/cleaner.cpp
    ../src/event_listener.cpp
)

add_executable(ram.sh ${SOURCES})
target_link_libraries(ram.sh -pthread)

option(STATIC_BUILD "Build statically" ON)
if(STATIC_BUILD)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static")
endif()
