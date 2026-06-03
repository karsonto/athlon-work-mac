import Foundation

struct SubTaskInput {
    let name: String
    let description: String?
    let expectedOutcome: String?
    let files: [String]
}

struct CreatePlanRequest {
    let name: String
    let description: String
    let expectedOutcome: String
    let overview: String
    let subtasks: [SubTaskInput]
    let architecture: String?
    let mermaid: String?
    let testingStrategy: String?
    let outOfScope: String?
}
