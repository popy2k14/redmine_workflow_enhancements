module WorkflowEnhancements
  module Patches
    module TrackerPatch
      def self.apply
        unless Tracker < self
          Tracker.prepend self
          Tracker.class_eval do
            safe_attributes :predef_issue_status_ids
            has_many :tracker_statuses, dependent: :destroy
            has_many :predef_issue_statuses, :through => :tracker_statuses
          end
        end
      end

      def issue_statuses
        if @issue_statuses
          return @issue_statuses
        elsif new_record?
          return []
        end

        ids = (WorkflowTransition.where(tracker_id: id).distinct.map{|w| [w.old_status_id, w.new_status_id]} +
               TrackerStatus.where(tracker_id: id).pluck(:issue_status_id)).flatten.uniq
        @issue_statuses = IssueStatus.where(:id => ids).all.sort
      end
    end
  end
end
