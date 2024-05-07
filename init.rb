require File.expand_path('../lib/workflow_enhancements/hooks', __FILE__)
require File.expand_path('../lib/workflow_enhancements/patches/workflows_controller_patch', __FILE__)

Redmine::Plugin.register :redmine_workflow_enhancements do
  name 'Redmine Workflow Enhancements'
  author 'Daniel Ritz'
  description 'Enhancements for Workflow'
  version '0.5.1'
  url 'https://github.com/dr-itz/redmine_workflow_enhancements'
  author_url 'https://github.com/dr-itz/'

  requires_redmine '2.2.0'
  if Redmine::VERSION::MAJOR > 3 || Redmine::VERSION::MAJOR == 3 && Redmine::VERSION::MINOR >= 4
    Rails.configuration.to_prepare do
      WorkflowsController.send(:include, WorkflowEnhancements::Patches::WorkflowsControllerPatch)
    end
  end

  project_module :issue_tracking do
    permission :workflow_graph_view, :workflow_enhancements => :show
  end
end

# Patches to the Redmine core.
patched_classes = %w(tracker)
patched_classes.each do |core_class|
   require core_class
   "WorkflowEnhancements::#{core_class.camelize}Patch".constantize.perform
end
