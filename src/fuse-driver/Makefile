CC = gcc
CFLAGS = -Wall -g -D_FILE_OFFSET_BITS=64
LDFLAGS = -lfuse

SRC_DIR = src
BUILD_DIR = build
TARGET = nas-emu-fuse

SOURCES = $(wildcard $(SRC_DIR)/*.c)
OBJECTS = $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(SOURCES))

.PHONY: all clean test

all: $(BUILD_DIR) $(TARGET)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET): $(OBJECTS)
	$(CC) $^ -o $@ $(LDFLAGS)

clean:
	rm -rf $(BUILD_DIR) $(TARGET)

test:
	@echo "Running unit tests..."
	@echo "No tests defined yet"
