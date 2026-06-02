# Plan: Push to GitHub and add macOS build CI

**Description:** Initialize git repo at F:\mac-athlon-work, push to https://github.com/karsonto/athlon-work-mac, and add GitHub Actions workflow to build the macOS SwiftUI app.
**Expected outcome:** Project is on GitHub with a working CI pipeline that builds AthlonAgent.app on every push.

## Subtasks

### 0. - [ ] [WIP] Initialize git repo and configure .gitignore
- Description: git init at F:\mac-athlon-work, create root .gitignore covering both .NET and Swift/Xcode artifacts, and make initial commit
- Expected outcome: Initial commit with all project files committed to local git repo
- State: InProgress

### 1. - [ ] Push to GitHub remote
- Description: Add remote origin https://github.com/karsonto/athlon-work-mac.git and push main branch
- Expected outcome: All code pushed to GitHub repository
- State: Todo

### 2. - [ ] Create GitHub Actions workflow for macOS build
- Description: Create .github/workflows/build-mac.yml that uses swift build via Package.swift to compile the AthlonAgent macOS app on macos-14 runner
- Expected outcome: CI workflow file in repo that builds the SwiftUI macOS app on push
- State: Todo
