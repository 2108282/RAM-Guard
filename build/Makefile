CXX ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -pthread
LDFLAGS ?= -pthread -static

SRCS = ../src/main.cpp \
       ../src/config.cpp \
       ../src/logger.cpp \
       ../src/memory.cpp \
       ../src/process_manager.cpp \
       ../src/notification.cpp \
       ../src/cleaner.cpp \
       ../src/event_listener.cpp

TARGET = ram.sh

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CXX) $(CXXFLAGS) $(SRCS) $(LDFLAGS) -o $(TARGET)
	strip $(TARGET) 2>/dev/null || true

clean:
	rm -f $(TARGET)
