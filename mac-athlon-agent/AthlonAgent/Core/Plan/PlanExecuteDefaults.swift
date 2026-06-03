import Foundation

enum PlanExecuteDefaults {
    static let executeUserMessage = """
    Execute the approved plan. Call get_plan first. Work through subtasks in order; call finish_subtask with concrete measurable outcomes when each step is done.
    """
}
