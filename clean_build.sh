#!/bin/bash

# Clean Xcode build artifacts
echo "Cleaning Xcode build cache..."

# Remove DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/MindVault-*

# Clean the project
cd "$(dirname "$0")"

echo "✅ Build cache cleaned!"
echo ""
echo "Next steps:"
echo "1. Open Xcode"
echo "2. Product → Clean Build Folder (⌘⇧K)"
echo "3. Build the project (⌘B)"
