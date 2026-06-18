# frozen_string_literal: true

module DiscourseWorkflows
  class Executor
    ExecutionOptions =
      Data.define(
        :user,
        :execution_mode,
        :draft_execution,
        :workflow_version,
        :workflow_snapshot,
        :existing_execution,
        :webhook_context,
        :workflow_call_stack,
        :workflow_call_caller,
      ) do
        def initialize(
          user: nil,
          execution_mode: :normal,
          draft_execution: false,
          workflow_version: nil,
          workflow_snapshot: nil,
          existing_execution: nil,
          webhook_context: nil,
          workflow_call_stack: [],
          workflow_call_caller: nil
        )
          super
        end
      end
  end
end
