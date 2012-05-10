module FrIndexPresenter
  class AgencyPresenter
    attr_reader :agency, :total_count
    attr_accessor :children

    delegate :id,
             :name,
             :parent_id,
             :slug,
             :to_param,
             :to => :agency

    def initialize(agency, total_count)
      @agency = agency
      @total_count = total_count
    end

    def entries_count
      @total_count
    end
  end

  def self.agencies_in_year(year)
    facets = EntrySearch.new(
      :conditions => {:publication_date => {:year => year}}
    ).agency_facets

    agencies = Agency.all(:conditions => {:id => facets.map(&:value)}, :include => :children).to_a

    agency_presenters = facets.map do |facet|
      agency = agencies.detect{|a| a.id == facet.value}
      if agency.children.present?
        count = EntrySearch.new(:conditions => {
          :publication_date => {:year => year},
          :agency_ids => [agency.id],
          :without_agency_ids => agency.children.map(&:id)
        }).count
      else
        count = facet.count
      end
      AgencyPresenter.new(agency, count)
    end

    agency_presenters.each do |p|
      p.children = agency_presenters.select{|c| c.parent_id == p.id}.sort_by{|c| c.name.downcase}
    end
    
    agency_presenters.sort_by{|a| a.name.downcase}
  end

  def self.entries_for_year_and_agency(year,agency)
    first = Date.parse('1900-01-01')

    entries = agency.entries.scoped(
      :select => "entries.id, entries.document_number, entries.publication_date, entries.title, entries.toc_subject, entries.toc_doc, entries.fr_index_subject, entries.fr_index_doc",
      :conditions => {:publication_date => Date.parse("#{year}-01-01")..Date.parse("#{year}-12-31")})
    
    if agency.children.present?
      entries = entries.scoped(
        :joins => "LEFT OUTER JOIN agency_assignments AS child_agency_assignments
                     ON child_agency_assignments.agency_id IN (#{agency.children.map(&:id).join(',')})
                     AND child_agency_assignments.assignable_type = 'Entry'
                     AND child_agency_assignments.assignable_id = entries.id",
        :conditions => "child_agency_assignments.id IS NULL"
      )
    end
    entries
  end

  def self.grouped_entries_for_year_and_agency(year, agency)
    entries = entries_for_year_and_agency(year,agency)

    entries.group_by(&:granule_class).sort_by{|type,entries| type}.reverse.map do |type, entries_by_type|

      entries_with_subject, entries_without_subject = entries_by_type.partition{|e| e.fr_index_subject.present?}

      grouped_entries = entries_with_subject.group_by(&:fr_index_subject).map do |subject, entries_by_subject|
        [subject] << entries_by_subject.group_by do |e|
          (e.fr_index_doc || e.title)
        end.sort_by{|a,b| a.downcase}.map{|a,b| [a,b.sort_by(&:publication_date)]}
      end

      grouped_entries += entries_without_subject.group_by(&:title).map{|g_e| [nil, [[g_e.first, g_e.second.sort_by(&:publication_date)]]]}

      sorted_grouped_entries = grouped_entries.sort_by{|a,b| [a || b.first.first]}
      [type, sorted_grouped_entries]
    end
  end
end