# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CapiCar for YOS is a fulfillment management system consisting of:
- **iOS App** (`CapiCarForYOS/`): SwiftUI-based mobile app for task management
- **Node.js API** (`capicar-for-yos-api/`): Express.js backend with Airtable integration

## Development Commands

### iOS App
- **Build**: Open `CapiCarForYOS.xcodeproj` in Xcode and use Cmd+B
- **Run**: Use Xcode's Run button or Cmd+R
- **Test**: Run tests from Xcode Test Navigator or Cmd+U

### Node.js API
- **Install dependencies**: `cd capicar-for-yos-api && npm install`
- **Development server**: `npm run dev` (uses nodemon + ts-node)
- **Build**: `npm run build` (compiles TypeScript to `dist/`)
- **Production start**: `npm start`
- **Type check**: `npm run type-check`

## Architecture

### iOS App Structure
- **MVVM Pattern**: ViewModels handle business logic, Views handle UI
- **SwiftData**: Used for local persistence (Item model)
- **SwiftUI**: Declarative UI framework
- **APIService**: Singleton for all HTTP requests to backend
- **Models**: Centralized data models in `Models/TaskModels.swift`

### Key iOS Components
- `Features/`: Feature-based organization (Dashboard, Tasks, Staff, Auth)
- `Components/`: Reusable UI components (Task/, Shared/)
- `Services/APIService.swift`: HTTP client with proper error handling
- `Models/TaskModels.swift`: All data models and enums

### Node.js API Structure
- **Express.js** with TypeScript
- **Airtable Integration**: Backend data source
- **Route-based organization**: `routes/` (dashboard, tasks, staff)
- **Middleware**: Error handling, CORS, Helmet security
- **Type definitions**: Centralized in `types/index.ts`

### Data Flow
1. iOS app makes HTTP requests via `APIService.shared`
2. Express API processes requests and interacts with Airtable
3. API returns JSON responses with consistent structure:
   ```typescript
   { success: boolean, data: T }
   ```

### Key Models
- **FulfillmentTask**: Main task entity with status workflow
- **TaskStatus**: Enum (pending → picking → packed → inspecting → completed. Exception: paused, cancelled)
- **ChecklistItem**: Individual items within tasks
- **StaffMember**: User management
- **GroupedTasks**: Dashboard organization by status

### API Configuration
- **Base URL**: Hardcoded to `http://192.168.1.143:3000/api` in APIService
- **JSON Strategy**: snake_case ↔ camelCase conversion
- **Date Format**: ISO8601
- **Error Handling**: Custom `APIError` enum with specific error types

## Testing
- **iOS**: XCTest framework, test files in `CapiCarForYOSTests/` and `CapiCarForYOSUITests/`
- **API**: No specific test framework configured yet

## Important Notes
- The iOS app uses hardcoded IP address for API base URL
- API requires environment variables for Airtable configuration
- SwiftData models currently only include basic `Item` - may need expansion
- Task workflow follows specific status transitions enforced by backend
