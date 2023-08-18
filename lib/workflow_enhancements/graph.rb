module WorkflowEnhancements::Graph

  def self.load_data(roles, trackers, issue=nil, project_roles=nil, workspace_id=nil)
    tracker = nil
    if trackers.is_a?(Array)
      tracker = trackers.length == 1 ? trackers.first : nil
    else
      tracker = trackers
    end
    unless tracker
      return { :nodes => [], :edges => [] }
    end

    current_status = nil
    possible_statuses = {}
    if issue
      current_status = issue.status_id
      issue.new_statuses_allowed_to().each {|x| possible_statuses[x.id] = true }
    end

    role_map = {}
    Array(roles).each {|x| role_map[x.id] = x } if roles

    new_issue_status_map = {}
    edges_map = {}
    loops_map = {}
    WorkflowTransition.where(:tracker_id => tracker, :workspace_id => workspace_id).each do |t|
      next unless project_roles.nil? || project_roles.include?(t.role_id)
      if t.old_status_id != 0
        key = t.old_status_id.to_s + '-' + t.new_status_id.to_s
        own = role_map.include?(t.role_id)
        author = own && t.author
        assignee = own && t.assignee
        always = own && !author && !assignee

        if t.old_status_id == t.new_status_id
          loops_map[t.old_status_id] = [] unless loops_map.include?(t.old_status_id)
          loops_map[t.old_status_id] |= [t.role_id]
        else
          if edges_map.include?(key)
            edges_map[key][:own] ||= own
            edges_map[key][:author] ||= author
            edges_map[key][:assignee] ||= assignee
            edges_map[key][:always] ||= always
            edges_map[key][:roles] |= [t.role_id]
          else
            edges_map[key] = { :u => t.old_status_id, :v => t.new_status_id,
               :own => own, :author => author, :assignee => assignee, :always => always, :roles => [t.role_id] }
          end
        end
      else
        new_issue_status_map[t.new_status_id] = 1
      end
    end
    edges_array = []
    statuses_list = []
    edges_map.each_value do |e|
      cls = role_map.empty? ? '' : 'transOther'
      if e[:own]
        cls = 'transOwn'
        unless e[:always]
          cls += ' transOwn-author' if e[:author]
          cls += ' transOwn-assignee' if e[:assignee]
        end
      end
      if e[:roles]
        e[:roles].each do |r|
          cls += " role#{r}"
        end
      end
      edges_array << { :u => e[:u], :v => e[:v], :value => { :edgeclass => cls } }
      statuses_list |= [e[:u], e[:v]]
    end

    statuses_array = tracker.issue_statuses.select{ |s| statuses_list.include?(s.id) }.map do |s|
      cls = ''
      if is_default_status(tracker, s)
        cls = 'state-new'
      elsif new_issue_status_map.include?(s.id)
        cls = 'state-new-possible'
      elsif s.is_closed
        cls = 'state-closed'
      end
      if s.id == current_status
        cls += ' state-current'
      elsif possible_statuses.include?(s.id)
        cls += ' state-possible'
      end
      label = '<div style="margin: 10px;">'
      label += '<text class="' + loops_map[s.id].map{|r| "role" + r.to_s}.join(" ") + '"><span style="' +
        ((loops_map[s.id] & roles.pluck(:id)).any? ? 'font-weight: bold;' : 'color: lightgray;') +
        '">⟳</span></text>&nbsp;' if loops_map.include?(s.id)
      label += '<text class="' + cls + '" style="white-space: nowrap;">' + s.name + '</text></div>'
      { :id => s.id, :value => { :label => label, :nodeclass => cls } }
    end

    { :nodes => statuses_array, :edges => edges_array }
	end

  private

  def self.is_default_status(tracker, status)
    if Redmine::VERSION::MAJOR >= 3
      tracker.default_status == status
    else
      status.is_default
    end
  end
end
