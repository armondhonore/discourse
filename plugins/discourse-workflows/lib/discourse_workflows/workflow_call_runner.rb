# frozen_string_literal: true

module DiscourseWorkflows
  class WorkflowCallRunner
    MAX_WORKFLOW_CALL_DEPTH = 10

    Result = Data.define(:execution, :items)

    def initialize(exec_ctx:, workflow_id:, trigger_data:, return_mode:, return_node_id: nil)
      @exec_ctx = exec_ctx
      @workflow_id = workflow_id.to_s
      @trigger_data = trigger_data
      @return_mode = return_mode.to_s
      @return_node_id = return_node_id.presence&.to_s
    end

    def call
      validate_workflow_id!
      @exec_ctx.ensure_workflow_call_access!(@workflow_id)
      ensure_stack_allows_call!

      workflow = target_workflow
      workflow_version = workflow&.active_version
      ensure_callable_workflow!(workflow, workflow_version)

      snapshot = WorkflowSnapshot.from_version(workflow, workflow_version)
      trigger_node = workflow_call_trigger(snapshot)
      ensure_no_waiting_nodes!(snapshot)
      ensure_return_node_exists!(snapshot)

      executor = build_executor(workflow, workflow_version, trigger_node)
      executor.run

      execution = executor.execution
      ensure_successful_execution!(execution)

      Result.new(execution:, items: output_items(executor, execution, workflow))
    end

    private

    def validate_workflow_id!
      if @workflow_id.blank?
        raise_node_error!(I18n.t("discourse_workflows.errors.workflow_call.workflow_required"))
      end
    end

    def ensure_stack_allows_call!
      stack = @exec_ctx.workflow_call_stack.map(&:to_s)

      if stack.include?(@workflow_id)
        raise_node_error!(I18n.t("discourse_workflows.errors.workflow_call.recursive_call"))
      end

      if stack.length >= MAX_WORKFLOW_CALL_DEPTH
        raise_node_error!(
          I18n.t(
            "discourse_workflows.errors.workflow_call.max_depth_exceeded",
            max: MAX_WORKFLOW_CALL_DEPTH,
          ),
        )
      end
    end

    def target_workflow
      @target_workflow ||= Workflow.includes(:active_version).find_by(id: @workflow_id)
    end

    def ensure_callable_workflow!(workflow, workflow_version)
      if workflow.nil?
        raise_node_error!(I18n.t("discourse_workflows.errors.workflow_call.target_not_found"))
      end

      unless workflow.published? && workflow_version && workflow_call_trigger(workflow_version)
        raise_node_error!(I18n.t("discourse_workflows.errors.workflow_call.target_not_callable"))
      end
    end

    def workflow_call_trigger(source)
      nodes = source.respond_to?(:nodes) ? source.nodes : []
      nodes.find do |node|
        if node.respond_to?(:type)
          node.type == Nodes::WorkflowCallTrigger::V1.identifier
        else
          node["type"] == Nodes::WorkflowCallTrigger::V1.identifier
        end
      end
    end

    def ensure_no_waiting_nodes!(snapshot)
      waiting_identifiers = NodeType.waiting_identifiers.to_set
      waiting_nodes = snapshot.nodes.select { |node| waiting_identifiers.include?(node.type) }
      return if waiting_nodes.empty?

      raise_node_error!(
        I18n.t(
          "discourse_workflows.errors.workflow_call.waiting_nodes_not_supported",
          nodes: waiting_nodes.map(&:name).join(", "),
        ),
      )
    end

    def ensure_return_node_exists!(snapshot)
      return unless @return_mode == Nodes::WorkflowCall::V1::RETURN_SELECTED_NODE
      return if @return_node_id.present? && snapshot.find_node(@return_node_id)

      raise_node_error!(I18n.t("discourse_workflows.errors.workflow_call.return_node_not_found"))
    end

    def build_executor(workflow, workflow_version, trigger_node)
      options =
        Executor::ExecutionOptions.new(
          user: @exec_ctx.user,
          workflow_version: workflow_version,
          workflow_call_stack: @exec_ctx.workflow_call_stack,
          workflow_call_caller: caller_metadata,
        )

      Executor.new(workflow, trigger_node.id, @trigger_data, options)
    end

    def caller_metadata
      workflow = @exec_ctx.get_workflow
      node = @exec_ctx.get_node
      execution_id = @exec_ctx.execution_id

      {
        "workflow_id" => integer_or_string_id(workflow.id),
        "workflow_name" => workflow.name,
        "execution_id" => execution_id,
        "execution_url" => caller_execution_url(workflow.id, execution_id),
        "node_id" => node.id,
        "node_name" => node.name,
        "node_type" => node.type,
      }.compact
    end

    def caller_execution_url(workflow_id, execution_id)
      return if workflow_id.blank? || execution_id.blank?

      "#{Discourse.base_url}/admin/plugins/discourse-workflows/workflows/" \
        "#{workflow_id}/executions/#{execution_id}"
    end

    def integer_or_string_id(id)
      id.to_s.match?(/\A\d+\z/) ? id.to_i : id
    end

    def ensure_successful_execution!(execution)
      return if execution&.success?

      status = execution&.status || "unknown"
      error = execution&.error.presence
      message =
        if error.present?
          I18n.t(
            "discourse_workflows.errors.workflow_call.execution_failed_with_error",
            status:,
            error:,
          )
        else
          I18n.t("discourse_workflows.errors.workflow_call.execution_failed", status:)
        end

      raise_node_error!(message)
    end

    def output_items(executor, execution, workflow)
      case @return_mode
      when Nodes::WorkflowCall::V1::RETURN_EXECUTION_METADATA
        [Item.wrap(execution_metadata(execution, workflow))]
      when Nodes::WorkflowCall::V1::RETURN_SELECTED_NODE
        executor.output_items_for_node_id(@return_node_id) || []
      else
        executor.last_output_items || []
      end
    end

    def execution_metadata(execution, workflow)
      {
        workflow: {
          id: workflow.id,
          name: workflow.name,
        },
        execution: {
          id: execution.id,
          status: execution.status,
          url:
            "#{Discourse.base_url}/admin/plugins/discourse-workflows/workflows/" \
              "#{workflow.id}/executions/#{execution.id}",
        },
      }
    end

    def raise_node_error!(message)
      raise DiscourseWorkflows::NodeError, message
    end
  end
end
