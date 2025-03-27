CC = gcc
CFLAGS = -Wall -Wextra -g -D_FILE_OFFSET_BITS=64
LDFLAGS = -lfuse -lpthread

TARGET = nas-emu-fuse
SRCDIR = src
OBJDIR = obj

SOURCES = $(SRCDIR)/fs_fault_injector.c \
          $(SRCDIR)/fs_operations.c \
          $(SRCDIR)/fault_injector.c \
          $(SRCDIR)/log.c

OBJECTS = $(patsubst $(SRCDIR)/%.c, $(OBJDIR)/%.o, $(SOURCES))

.PHONY: all clean

all: directories $(TARGET)

directories:
	@mkdir -p $(OBJDIR)

$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(OBJDIR)/%.o: $(SRCDIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(OBJDIR) $(TARGET)

# Testing targets
.PHONY: test test-docker

test:
	@echo "Running functional tests..."
	@cd tests/functional && ./run_all_tests.sh

test-docker:
	@echo "Running tests in Docker container..."
	@../scripts/run_tests.sh