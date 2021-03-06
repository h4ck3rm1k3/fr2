class EntryApiRepresentation < ApiRepresentation
  self.default_index_fields_json = [:title, :type, :abstract, :document_number, :html_url, :pdf_url, :public_inspection_pdf_url, :publication_date, :agencies, :excerpts]
  self.default_index_fields_csv = [:title, :type, :agency_names, :abstract, :document_number, :html_url, :pdf_url, :publication_date]

  def self.default_show_fields_json
    all_fields - [:excerpts, :agency_names, :docket_id, :president]
  end

  field(:abstract)
  field(:abstract_html_url, :select => :document_file_path) {|e| entry_abstract_url(e)}
  field(:action)
  field(:agencies, :select => :id) do |entry|
    entry.agency_names.map do |agency_name|
      agency = agency_name.agency
      if agency
        {
          :raw_name => agency_name.name,
          :name     => agency.name,
          :id       => agency.id,
          :url      => agency_url(agency),
          :json_url => api_v1_agency_url(agency.id, :format => :json),
          :parent_id => agency.parent_id
        }
      else
        {
          :raw_name => agency_name.name
        }
      end
    end
  end
  field(:agency_names, :select => :id) {|e| e.agency_names.map{|a| a.agency.try(:name) || a.name}}
  field(:body_html_url, :select => :document_file_path) {|e| entry_full_text_url(e)}
  field(:cfr_references, :include => :entry_cfr_references) do |entry|
    entry.entry_cfr_references.map do |cfr_reference|
      {:title => cfr_reference.title, :part => cfr_reference.part}
    end
  end
  field(:citation)
  field(:comments_close_on, :include => :events){|e| e.comments_close_on}
  field(:corrections, :include => :corrections){|e| e.corrections.map{|c| api_v1_entry_url(c.document_number, :format => :json)}}
  field(:correction_of, :include => :correction_of, :select => :correction_of_id){|e| api_v1_entry_url(e.correction_of.document_number, :format => :json) if e.correction_of}
  field(:dates)
  field(:docket_id, :include => :docket_numbers){|e| e.docket_numbers.first.try(:number)} # backwards compatible for now
  field(:docket_ids, :include => :docket_numbers){|e| e.docket_numbers.map(&:number)}
  field(:document_number)
  field(:effective_on, :include => :events)
  field(:end_page)
  field(:excerpts, :select => [:document_file_path, :abstract]) {|e| (e.excerpts.raw_text || e.excerpts.abstract) if e.respond_to?(:excerpts) && e.excerpts}
  field(:executive_order_notes) 
  field(:executive_order_number)
  field(:full_text_xml_url, :select => [:document_file_path, :full_xml_updated_at]){|e| entry_xml_url(e) if e.should_have_full_xml?}
  field(:html_url, :select => [:publication_date, :document_number, :slug]){|e| entry_url(e)}
  field(:json_url, :select => :document_number) {|e| api_v1_entry_url(e.document_number, :format => :json)}
  field(:mods_url, :select => [:publication_date, :document_number]){|e| e.source_url(:mods)}
  field(:pdf_url, :select => [:publication_date, :document_number]){|e| e.source_url('pdf')}
  field(:public_inspection_pdf_url, :select => :document_number) {|e| e.public_inspection_document.try(:pdf).try(:url)}
  field(:president, :select => [:granule_class, :signing_date, :publication_date]) do |entry|
    president = entry.president
    if president
      {:name => president.full_name, :identifier => president.identifier}
    end
  end
  field(:publication_date)
  field(:regulation_id_number_info, :include => :entry_regulation_id_numbers) do |entry|
    values = entry.entry_regulation_id_numbers.map(&:regulation_id_number).map do |rin|
      regulatory_plan = entry.current_regulatory_plans.detect{|r| r.regulation_id_number == rin}

      if regulatory_plan
        regulatory_plan_info = {
          :xml_url => regulatory_plan.source_url(:xml),
          :issue => regulatory_plan.issue,
          :title => regulatory_plan.title,
          :priority_category => regulatory_plan.priority_category
        }
      end
      [rin, regulatory_plan_info]
    end
    
    Hash[*values.flatten]
  end
  field(:regulation_id_numbers, :include => :entry_regulation_id_numbers) {|e| e.entry_regulation_id_numbers.map{|r| r.regulation_id_number}}
  field(:regulations_dot_gov_url, :select => :regulationsdotgov_url) {|e| e.regulationsdotgov_url}
  field(:start_page)
  field(:signing_date)
  field(:subtype, :select => :presidential_document_type_id){|e| e.presidential_document_type.try(:name)}
  field(:title)
  field(:type, :select => :granule_class){|e| e.entry_type}
  field(:volume)
end
