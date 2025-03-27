#!/bin/bash
# A very simple test that just creates a file and checks if it exists

# Exit on any error
set -e

echo "Starting simple functional test..."

# Define test file path
TEST_FILE="/mnt/fs-fault/test_file.txt"
TEST_CONTENT="Hello, this is a test file."

# Remove test file if it already exists
rm -f "$TEST_FILE"

echo "Creating test file..."
echo "$TEST_CONTENT" > "$TEST_FILE"

# Check if file exists
if [ -f "$TEST_FILE" ]; then
    echo "✅ SUCCESS: File was created successfully."
else
    echo "❌ ERROR: File was not created."
    exit 1
fi

# Check file content
CONTENT=$(cat "$TEST_FILE")
if [ "$CONTENT" = "$TEST_CONTENT" ]; then
    echo "✅ SUCCESS: File content is correct."
else
    echo "❌ ERROR: File content is incorrect."
    echo "Expected: $TEST_CONTENT"
    echo "Actual: $CONTENT"
    exit 1
fi

echo "Simple functional test completed successfully!"
exit 0
