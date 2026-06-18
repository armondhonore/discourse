# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module WorkflowCall
      class V1 < NodeType
        RUN_ONCE_FOR_ALL_ITEMS = "once_for_all_items"
        RUN_ONCE_FOR_EACH_ITEM = "once_for_each_item"
        INPUT_ITEMS = "input_items"
        CUSTOM_JSON = "custom_json"
        RETURN_LAST_NODE = "last_node"
        RETURN_SELECTED_NODE = "selected_node"
        RETURN_EXECUTION_METADATA = "execution_metadata"

        description(
          name: "action:workflow_call",
          version: "1.0",
          defaults: {
            icon: "arrows-turn-to-dots",
            color: "teal",
          },
          group: "flow",
          capabilities: {
            run_scope: {
              parameter: "run_mode",
              values: {
                RUN_ONCE_FOR_ALL_ITEMS => "all_items",
                RUN_ONCE_FOR_EACH_ITEM => "per_item",
              },
            },
          },
          properties: {
            workflow_id: {
              type: :integer,
              required: true,
              no_data_expression: true,
              type_options: {
                load_options_method: "callable_workflows",
              },
              ui: {
                control: :combo_box,
              },
              control_options: {
                value_property: "id",
                name_property: "name",
                filterable: true,
                none: "discourse_workflows.workflow_call.workflow_id_placeholder",
              },
            },
            run_mode: {
              type: :options,
              required: true,
              default: RUN_ONCE_FOR_ALL_ITEMS,
              options: [RUN_ONCE_FOR_ALL_ITEMS, RUN_ONCE_FOR_EACH_ITEM],
              no_data_expression: true,
            },
            input_mode: {
              type: :options,
              required: true,
              default: INPUT_ITEMS,
              options: [INPUT_ITEMS, CUSTOM_JSON],
              no_data_expression: true,
            },
            payload_json: {
              type: :string,
              required: true,
              display_options: {
                show: {
                  input_mode: [CUSTOM_JSON],
                },
              },
              ui: {
                control: :textarea,
              },
            },
            return_mode: {
              type: :options,
              required: true,
              default: RETURN_LAST_NODE,
              options: [RETURN_LAST_NODE, RETURN_SELECTED_NODE, RETURN_EXECUTION_METADATA],
              no_data_expression: true,
            },
            return_node_id: {
              type: :string,
              required: true,
              no_data_expression: true,
              type_options: {
                load_options_method: "return_nodes",
                load_options_depends_on: %w[workflow_id return_mode],
              },
              display_options: {
                show: {
                  return_mode: [RETURN_SELECTED_NODE],
                },
              },
              ui: {
                control: :combo_box,
              },
              control_options: {
                value_property: "id",
                name_property: "name",
                filterable: true,
                none: "discourse_workflows.workflow_call.return_node_id_placeholder",
              },
            },
          },
          i18n_scope: "workflow_call",
        )

        def self.load_options_context(context)
          case context.method_name
          when "callable_workflows"
            callable_workflow_options(context)
          when "return_nodes"
            return_node_options(context)
          end
        end

        def self.callable_workflow_options(context)
          scope =
            DiscourseWorkflows::Workflow
              .published
              .joins(:workflow_dependencies)
              .where(
                discourse_workflows_workflow_dependencies: {
                  dependency_type: "node_type",
                  dependency_key: DiscourseWorkflows::Nodes::WorkflowCallTrigger::V1.identifier,
                },
              )
              .where(
                "discourse_workflows_workflows.active_version_id = " \
                  "discourse_workflows_workflow_dependencies.workflow_version_id",
              )
          scope = scope.where.not(id: context.workflow_id) if context.workflow_id.present?
          scope = scope.filter_by_name(context.filter) if context.filter.present?

          scope.distinct.order(:name).pluck(:id, :name).map { |id, name| { id:, name: } }
        end
        private_class_method :callable_workflow_options

        def self.return_node_options(context)
          workflow_id = context.get_current_node_parameter("workflow_id").presence
          return [] if workflow_id.blank?

          workflow = DiscourseWorkflows::Workflow.includes(:active_version).find_by(id: workflow_id)
          return [] unless workflow&.active_version

          workflow.active_version.nodes.filter_map do |node|
            next if node["type"] == DiscourseWorkflows::WorkflowGraphValidator::STICKY_NOTE_TYPE
            next if context.filter.present? && !context.matches_filter?(node["name"].to_s)

            { id: node["id"], name: node["name"] }
          end
        end
        private_class_method :return_node_options

        def execute(exec_ctx)
          run_mode = exec_ctx.get_node_parameter("run_mode", 0, default: RUN_ONCE_FOR_ALL_ITEMS)
          input_mode = exec_ctx.get_node_parameter("input_mode", 0, default: INPUT_ITEMS)

          executions = []
          items = []

          if run_mode == RUN_ONCE_FOR_EACH_ITEM
            exec_ctx.input_items.each_with_index do |input_item, item_index|
              result = execute_call(exec_ctx, item_index:, input_items: [input_item], input_mode:)
              executions << result.execution
              items.concat(pair_to_parent_item(result.items, item_index))
            end
          else
            result =
              execute_call(exec_ctx, item_index: 0, input_items: exec_ctx.input_items, input_mode:)
            executions << result.execution
            items.concat(strip_child_pairing(result.items))
          end

          exec_ctx.set_metadata("workflow_call" => execution_metadata(executions))
          [items]
        end

        private

        def execute_call(exec_ctx, item_index:, input_items:, input_mode:)
          workflow_id = exec_ctx.get_node_parameter("workflow_id", item_index)
          return_mode =
            exec_ctx.get_node_parameter("return_mode", item_index, default: RETURN_LAST_NODE)
          return_node_id = exec_ctx.get_node_parameter("return_node_id", item_index)

          WorkflowCallRunner.new(
            exec_ctx:,
            workflow_id:,
            trigger_data: trigger_data(exec_ctx, item_index, input_items, input_mode),
            return_mode:,
            return_node_id:,
          ).call
        end

        def trigger_data(exec_ctx, item_index, input_items, input_mode)
          if input_mode == CUSTOM_JSON
            return normalize_custom_payload(exec_ctx.get_node_parameter("payload_json", item_index))
          end

          input_items.map { |item| item.fetch("json") { {} } }
        end

        def normalize_custom_payload(value)
          value = JSON.parse(value) if value.is_a?(String)

          case value
          when Hash
            value
          when Array
            unless value.all? { |entry| entry.is_a?(Hash) }
              raise_node_error!(
                I18n.t("discourse_workflows.errors.workflow_call.payload_must_be_object"),
              )
            end

            value
          else
            raise_node_error!(
              I18n.t("discourse_workflows.errors.workflow_call.payload_must_be_object"),
            )
          end
        rescue JSON::ParserError => e
          raise_node_error!(
            I18n.t("discourse_workflows.errors.workflow_call.payload_invalid_json"),
            description: e.message,
          )
        end

        def pair_to_parent_item(items, item_index)
          items.map do |item|
            with_paired_item(item.except(Item::PAIRED_ITEM_KEY), { item: item_index })
          end
        end

        def strip_child_pairing(items)
          items.map { |item| item.except(Item::PAIRED_ITEM_KEY) }
        end

        def execution_metadata(executions)
          execution_entries =
            executions.compact.map do |execution|
              {
                "id" => execution.id,
                "workflow_id" => execution.workflow_id,
                "status" => execution.status,
                "url" => execution_url(execution),
              }
            end

          { "executions" => execution_entries, "count" => execution_entries.length }
        end

        def execution_url(execution)
          "#{Discourse.base_url}/admin/plugins/discourse-workflows/workflows/" \
            "#{execution.workflow_id}/executions/#{execution.id}"
        end
      end
    end
  end
end
