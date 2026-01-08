#!/bin/bash
# watch_test.sh - Verify auto-reload and IPC refresh

set -e

# 1. Prepare a temporary test file
TEST_FILE="watch_test_temp.md"
echo "# Initial Content" > "$TEST_FILE"

# 2. Start mdview in debug mode in background
# We use --debug to see file watching logs
# We use --no-activate to avoid GUI focus stealing
echo "Starting mdview in background..."
./mdview --debug --no-activate "$TEST_FILE" &
MDVIEW_PID=$!

# Give it a moment to start and set up file watching
sleep 2

# 3. Modify the file content and see if it reloads
echo "Modifying file content..."
echo "# Modified Content" > "$TEST_FILE"
sleep 1

# 4. Try to open the same file again via CLI (IPC)
echo "Running mdview again for the same file (IPC test)..."
./mdview --no-activate "$TEST_FILE"
sleep 1

# 5. Cleanup
kill $MDVIEW_PID
rm "$TEST_FILE"

echo "Test script finished. Check the output above for 'Started watching file' and reload messages."
