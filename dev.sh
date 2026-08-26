#!/bin/bash

# MindVault Development Helper
# Simplified script for managing the app

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}➜ $1${NC}"
}

# Command handlers
case "${1:-help}" in
    setup)
        print_header "Setting up MindVault"
        
        # Check Python
        if ! command -v python3 &> /dev/null; then
            print_error "Python 3 not found. Please install Python 3.9+"
            exit 1
        fi
        print_success "Python found"
        
        # Setup backend
        cd backend
        print_info "Installing Python dependencies..."
        pip3 install -r requirements-dev.txt
        print_success "Backend dependencies installed"
        cd ..
        
        print_success "Setup complete!"
        echo ""
        print_info "Next steps:"
        echo "  1. Run: ./dev.sh start"
        echo "  2. Open MindVault.xcodeproj in Xcode"
        echo "  3. Build and run the app"
        ;;
        
    start)
        print_header "Starting MindVault Backend"
        cd backend
        print_info "Starting FastAPI server on http://localhost:8000"
        python3 -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
        ;;
        
    test)
        print_header "Testing Backend"
        cd backend
        python3 -m pytest "${@:2}"
        ;;

    lint)
        print_header "Linting Backend"
        cd backend
        python3 -m ruff check .
        ;;
        
    clean)
        print_header "Cleaning project"
        print_info "Removing __pycache__ directories..."
        find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
        print_info "Removing .DS_Store files..."
        find . -name ".DS_Store" -delete 2>/dev/null || true
        print_success "Project cleaned"
        ;;
        
    help|*)
        print_header "MindVault Development Helper"
        echo ""
        echo "Usage: ./dev.sh [command]"
        echo ""
        echo "Commands:"
        echo "  setup     - Install dependencies and setup project"
        echo "  start     - Start the backend server"
        echo "  test      - Run backend tests (pytest)"
        echo "  lint      - Run ruff on the backend"
        echo "  clean     - Clean temporary files"
        echo "  help      - Show this help message"
        echo ""
        echo "Example:"
        echo "  ./dev.sh setup     # First time setup"
        echo "  ./dev.sh start     # Start backend server"
        ;;
esac
