class TopicGroupsController < ApplicationController
  
  def index
    redirect_to topic_groups_by_letter_url('a')
  end
  
  def show
    group_name = params[:id]
    group_name.gsub!(/_|-/, ' ')
    @topic_group = TopicGroup.find_by_group_name!(params[:id])

    respond_to do |wants|
      wants.html do
        @entries = Entry.find(:all,
            :conditions => {:topics => {:group_name => @topic_group.group_name}},
            :include => :topics,
            :order => "entries.publication_date DESC",
            :limit => 100)
        
        # AGENCIES
        @agencies = Agency.all(:select => 'agencies.*, count(*) AS entries_count',
          :joins => {:entries => :topics},
          :conditions => {:entries => {:topics => {:group_name => group_name}}},
          :group => "agencies.id",
          :order => 'entries_count DESC'
        )
        
        # GRANULE CLASSES
        @granule_classes = Entry.all(
          :select => 'granule_class, count(*) AS count',
          :joins  => :topics,
          :conditions => {:topics => {:group_name => group_name}},
          :group => 'granule_class',
          :order => 'count DESC'
        )
        
        # RELATED TOPICS
        @related_topic_groups = Topic.find_by_sql(["SELECT topics.*, COUNT(*) AS entries_count
        FROM topics AS our_topics
        LEFT JOIN topic_assignments AS our_topic_assignments
          ON our_topic_assignments.topic_id = our_topics.id
        LEFT JOIN topic_assignments
          ON topic_assignments.entry_id = our_topic_assignments.entry_id
        LEFT JOIN topics
          ON topics.id = topic_assignments.topic_id
        WHERE our_topics.group_name = ?
          AND topics.group_name != ?
          AND topics.group_name != ''
        GROUP BY topics.group_name
        ORDER BY entries_count DESC, LENGTH(topics.name)
        LIMIT 100", group_name, group_name])
        
      end
      wants.rss do
        @feed_name = "govpulse: #{@topic_group.name}"
        @feed_description = "Recent Federal Register entries about #{@topic_group.name}."
        @entries = Entry.find(:all,
            :conditions => {:topics => {:group_name => @topic_group.group_name}},
            :joins => [:topics],
            :include => :agency,
            :order => "entries.publication_date DESC",
            :limit => 20)
        render :template => 'entries/index.rss.builder'
      end
    end
  end
  
  def by_letter
    @letter = params[:letter]
    @letters = ('a' .. 'z')
    
    @popular_topic_groups = TopicGroup.find(:all, :order => 'entries_count DESC', :limit => 100).sort_by(&:name)
    
    @topic_groups = TopicGroup.all(:conditions => ["group_name LIKE ?", "#{@letter}%"], :order => "topic_groups.name")
  end
end