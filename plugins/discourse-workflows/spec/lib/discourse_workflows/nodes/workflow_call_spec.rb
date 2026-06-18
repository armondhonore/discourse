# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::WorkflowCall::V1 do
  fab!(:admin)

  def assignment(name, value, type: "string")
    { "name" => name, "type" => type, "value" => value }
  end

  def execute_workflow(workflow, trigger_node_id: "trigger-1", trigger_data: { "name" => "Ada" })
    executor =
      DiscourseWorkflows::Executor.new(
        workflow,
        trigger_node_id,
        trigger_data,
        DiscourseWorkflows::Executor::ExecutionOptions.new(
          user: admin,
          workflow_version: workflow.active_version,
        ),
      )
    executor.run
    executor.execution
  end

  def expected_called_by(caller, execution, node_id: "call-1", node_name: "Call workflow")
    {
      "workflow_id" => caller.id,
      "workflow_name" => caller.name,
      "execution_id" => execution.id,
      "execution_url" =>
        "#{Discourse.base_url}/admin/plugins/discourse-workflows/workflows/" \
          "#{caller.id}/executions/#{execution.id}",
      "node_id" => node_id,
      "node_name" => node_name,
      "node_type" => "action:workflow_call",
    }
  end

  def callable_workflow_with_set_fields(assignments, trigger_id: "call-trigger")
    graph =
      build_workflow_graph do |workflow_graph|
        workflow_graph.node trigger_id, "trigger:workflow_call", name: "Workflow call"
        workflow_graph.node "set-fields",
                            "action:set_fields",
                            name: "Set fields",
                            configuration: {
                              "assignments" => {
                                "assignments" => assignments,
                              },
                            }
        workflow_graph.chain trigger_id, "set-fields"
      end

    Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **graph)
  end

  describe "#execute" do
    it "calls a published callable workflow and returns its output" do
      target = callable_workflow_with_set_fields([assignment("called", "yes")])
      caller_graph =
        build_workflow_graph do |workflow_graph|
          workflow_graph.node "trigger-1", "trigger:manual", name: "Manual"
          workflow_graph.node "call-1",
                              "action:workflow_call",
                              name: "Call workflow",
                              configuration: {
                                "workflow_id" => target.id,
                              }
          workflow_graph.chain "trigger-1", "call-1"
        end
      caller =
        Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **caller_graph)

      execution = execute_workflow(caller)
      call_step = execution.execution_data.find_step(node_id: "call-1")

      expect(execution).to be_success
      expect(call_step["output"].map { |item| item["json"] }).to eq(
        [{ "name" => "Ada", "called" => "yes" }],
      )
      expect(call_step.dig("output", 0, "json")).not_to have_key("workflow_call")
      expect(call_step.dig("metadata", "workflow_call", "executions").first).to include(
        "workflow_id" => target.id,
        "status" => "success",
      )
    end

    it "records caller details on the called workflow trigger" do
      target =
        callable_workflow_with_set_fields(
          [assignment("called_by", "={{ $execution.called_by }}", type: "object")],
        )
      caller_graph =
        build_workflow_graph do |workflow_graph|
          workflow_graph.node "trigger-1", "trigger:manual", name: "Manual"
          workflow_graph.node "call-1",
                              "action:workflow_call",
                              name: "Call workflow",
                              configuration: {
                                "workflow_id" => target.id,
                              }
          workflow_graph.chain "trigger-1", "call-1"
        end
      caller =
        Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **caller_graph)

      execution = execute_workflow(caller)
      call_step = execution.execution_data.find_step(node_id: "call-1")
      child_execution_id = call_step.dig("metadata", "workflow_call", "executions", 0, "id")
      child_execution = DiscourseWorkflows::Execution.find(child_execution_id)
      trigger_step = child_execution.execution_data.find_step(node_id: "call-trigger")
      expected_caller = expected_called_by(caller, execution)

      expect(execution).to be_success
      expect(call_step.dig("output", 0, "json", "called_by")).to eq(expected_caller)
      expect(call_step.dig("output", 0, "json")).not_to have_key("workflow_call")
      expect(trigger_step.dig("metadata", "workflow_call", "called_by")).to eq(expected_caller)
      expect(trigger_step.dig("output", 0, "json", "workflow_call", "called_by")).to eq(
        expected_caller,
      )
      expect(trigger_step.dig("output", 0, "json")).not_to have_key("__workflow_call")
      expect(trigger_step.dig("output", 0, "json", "name")).to eq("Ada")
    end

    it "can call once for each input item" do
      target = callable_workflow_with_set_fields([assignment("called", "yes")])
      caller_graph =
        build_workflow_graph do |workflow_graph|
          workflow_graph.node "trigger-1", "trigger:manual", name: "Manual"
          workflow_graph.node "call-1",
                              "action:workflow_call",
                              name: "Call workflow",
                              configuration: {
                                "workflow_id" => target.id,
                                "run_mode" => "once_for_each_item",
                              }
          workflow_graph.chain "trigger-1", "call-1"
        end
      caller =
        Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **caller_graph)

      execution =
        execute_workflow(caller, trigger_data: [{ "name" => "Ada" }, { "name" => "Grace" }])
      call_step = execution.execution_data.find_step(node_id: "call-1")

      expect(execution).to be_success
      expect(call_step["output"].map { |item| item["json"] }).to eq(
        [{ "name" => "Ada", "called" => "yes" }, { "name" => "Grace", "called" => "yes" }],
      )
      expect(call_step["output"].map { |item| item["pairedItem"] }).to eq(
        [{ "item" => 0 }, { "item" => 1 }],
      )
      expect(call_step.dig("metadata", "workflow_call", "count")).to eq(2)

      child_execution_ids =
        call_step.dig("metadata", "workflow_call", "executions").map { |child| child["id"] }
      expect(child_execution_ids.length).to eq(2)

      expected_caller = expected_called_by(caller, execution)
      child_execution_ids.each do |child_execution_id|
        child_execution = DiscourseWorkflows::Execution.find(child_execution_id)
        trigger_step = child_execution.execution_data.find_step(node_id: "call-trigger")

        expect(trigger_step.dig("metadata", "workflow_call", "called_by")).to eq(expected_caller)
        expect(trigger_step.dig("output", 0, "json", "workflow_call", "called_by")).to eq(
          expected_caller,
        )
      end
    end

    it "returns a selected node output" do
      target_graph =
        build_workflow_graph do |workflow_graph|
          workflow_graph.node "call-trigger", "trigger:workflow_call", name: "Workflow call"
          workflow_graph.node "first",
                              "action:set_fields",
                              name: "First",
                              configuration: {
                                "assignments" => {
                                  "assignments" => [assignment("first", "yes")],
                                },
                              }
          workflow_graph.node "second",
                              "action:set_fields",
                              name: "Second",
                              configuration: {
                                "assignments" => {
                                  "assignments" => [assignment("second", "yes")],
                                },
                              }
          workflow_graph.chain "call-trigger", "first", "second"
        end
      target =
        Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **target_graph)
      caller_graph =
        build_workflow_graph do |workflow_graph|
          workflow_graph.node "trigger-1", "trigger:manual", name: "Manual"
          workflow_graph.node "call-1",
                              "action:workflow_call",
                              name: "Call workflow",
                              configuration: {
                                "workflow_id" => target.id,
                                "return_mode" => "selected_node",
                                "return_node_id" => "first",
                              }
          workflow_graph.chain "trigger-1", "call-1"
        end
      caller =
        Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **caller_graph)

      execution = execute_workflow(caller)
      call_step = execution.execution_data.find_step(node_id: "call-1")

      expect(execution).to be_success
      expect(call_step["output"].map { |item| item["json"] }).to eq(
        [{ "name" => "Ada", "first" => "yes" }],
      )
    end

    it "fails before executing target workflows with waiting nodes" do
      target_graph =
        build_workflow_graph do |workflow_graph|
          workflow_graph.node "call-trigger", "trigger:workflow_call", name: "Workflow call"
          workflow_graph.node "wait-1", "flow:wait", name: "Wait"
          workflow_graph.chain "call-trigger", "wait-1"
        end
      target =
        Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **target_graph)
      caller_graph =
        build_workflow_graph do |workflow_graph|
          workflow_graph.node "trigger-1", "trigger:manual", name: "Manual"
          workflow_graph.node "call-1",
                              "action:workflow_call",
                              name: "Call workflow",
                              configuration: {
                                "workflow_id" => target.id,
                              }
          workflow_graph.chain "trigger-1", "call-1"
        end
      caller =
        Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **caller_graph)

      execution = execute_workflow(caller)

      expect(execution).to be_error
      expect(execution.error).to eq(
        I18n.t(
          "discourse_workflows.errors.workflow_call.waiting_nodes_not_supported",
          nodes: "Wait",
        ),
      )
    end

    it "detects recursive workflow calls at runtime" do
      caller_graph =
        build_workflow_graph do |workflow_graph|
          workflow_graph.node "trigger-1", "trigger:workflow_call"
        end
      caller =
        Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **caller_graph)
      target_graph =
        build_workflow_graph do |workflow_graph|
          workflow_graph.node "target-trigger", "trigger:workflow_call", name: "Target trigger"
          workflow_graph.node "target-call",
                              "action:workflow_call",
                              name: "Target call",
                              configuration: {
                                "workflow_id" => caller.id,
                              }
          workflow_graph.chain "target-trigger", "target-call"
        end
      target =
        Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **target_graph)
      updated_caller_graph =
        build_workflow_graph do |workflow_graph|
          workflow_graph.node "trigger-1", "trigger:workflow_call", name: "Caller trigger"
          workflow_graph.node "caller-call",
                              "action:workflow_call",
                              name: "Caller call",
                              configuration: {
                                "workflow_id" => target.id,
                              }
          workflow_graph.chain "trigger-1", "caller-call"
        end
      caller.update!(
        nodes: updated_caller_graph[:nodes],
        connections: updated_caller_graph[:connections],
      )
      version = caller.snapshot!(user: admin)
      caller.publish!(user: admin)
      DiscourseWorkflows::WorkflowDependencyIndexer.call(caller, version: version)

      execution = execute_workflow(caller)

      expect(execution).to be_error
      expect(execution.error).to include("Workflow call loop detected")
    end
  end
end
