module WorkflowEnhancements
  module Patches
    module WorkflowsControllerPatch
      def self.included(base) # :nodoc
        base.extend(ClassMethods)
        base.send(:prepend, InstanceMethods)
        base.class_eval do
          unloadable
        end
      end

      module ClassMethods; end

      module InstanceMethods
        def find_statuses
          super
          if @trackers && @used_statuses_only
            @statuses |= IssueStatus.where(
              id: TrackerStatus.where(tracker_id: @trackers.map(&:id)).pluck(:issue_status_id).flatten.uniq
            ).to_a
          end
        end
      end
    end
  end
end
