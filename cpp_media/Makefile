# cpp_media – HTTP image processing service (libvips + cpp-httplib)
# Requires: libvips-dev (apt) or vips (brew). httplib.h is vendored.

CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra
VIPS_CFLAGS = $(shell pkg-config --cflags vips-cpp 2>/dev/null)
VIPS_LIBS = $(shell pkg-config --libs vips-cpp 2>/dev/null)
TARGET = cpp_media
SRC = main.cpp profiles.cpp request_parser.cpp

ifeq ($(VIPS_CFLAGS),)
$(error libvips not found. Install libvips-dev (apt) or vips (brew), then run make again.)
endif

all: $(TARGET)

$(TARGET): $(SRC) httplib.h profiles.hpp request_parser.hpp
	$(CXX) $(CXXFLAGS) $(VIPS_CFLAGS) -o $(TARGET) $(SRC) $(VIPS_LIBS)

clean:
	rm -f $(TARGET) *.o

.PHONY: all clean
