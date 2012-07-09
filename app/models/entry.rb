# == Schema Information
#
# Table name: entries
#
#  id                            :integer(4)      not null, primary key
#  title                         :text
#  abstract                      :text
#  contact                       :text
#  dates                         :text
#  action                        :text
#  type                          :string(255)
#  link                          :string(255)
#  genre                         :string(255)
#  part_name                     :string(255)
#  citation                      :string(255)
#  granule_class                 :string(255)
#  document_number               :string(255)
#  toc_subject                   :string(255)
#  toc_doc                       :string(255)
#  length                        :integer(4)
#  start_page                    :integer(4)
#  end_page                      :integer(4)
#  publication_date              :date
#  places_determined_at          :datetime
#  created_at                    :datetime
#  updated_at                    :datetime
#  slug                          :text
#  delta                         :boolean(1)      default(TRUE), not null
#  source_text_url               :string(255)
#  regulationsdotgov_url         :string(255)
#  comment_url                   :string(255)
#  checked_regulationsdotgov_at  :datetime
#  volume                        :integer(4)
#  full_xml_updated_at           :datetime
#  citing_entries_count          :integer(4)      default(0)
#  document_file_path            :string(255)
#  full_text_updated_at          :datetime
#  curated_title                 :string(255)
#  curated_abstract              :string(500)
#  lede_photo_id                 :integer(4)
#  lede_photo_candidates         :text
#  raw_text_updated_at           :datetime
#  significant                   :boolean(1)
#  presidential_document_type_id :integer(4)
#  signing_date                  :date
#  executive_order_number        :integer(4)
#  action_name_id                :integer(4)
#  correction_of_id              :integer(4)
#  regulations_dot_gov_docket_id :string(255)
#  executive_order_notes         :text
#  fr_index_subject              :string(255)
#  fr_index_doc                  :string(255)
#

# require 'flickr'
class Entry < ApplicationModel
  
  DESCRIPTIONS = {
    :notice => 'This section of the Federal Register contains documents other than rules 
                or proposed rules that are applicable to the public. Notices of hearings 
                and investigations, committee meetings, agency decisions and rulings, 
                delegations of authority, filing of petitions and applications and agency 
                statements of organization and functions are examples of documents 
                appearing in this section.'
  }
  
  ENTRY_TYPES = {
    'RULE'     => 'Rule', 
    'PRORULE'  => 'Proposed Rule', 
    'NOTICE'   => 'Notice', 
    'PRESDOCU' => 'Presidential Document', 
    'CORRECT'  => 'Correction',
    'UNKNOWN'  => 'Document of Unknown Type',
    'SUNSHINE' => 'Sunshine Act Document'
  }
  
  belongs_to :issue, :foreign_key => :publication_date, :primary_key => :publication_date
  belongs_to :presidential_document_type
  belongs_to :action_name
  belongs_to :correction_of, :class_name => "Entry"
  belongs_to :docket, :foreign_key => :regulations_dot_gov_docket_id

  has_one :public_inspection_document

  has_many :corrections, :foreign_key => "correction_of_id", :class_name => "Entry"
  has_many :topic_name_assignments, :dependent => :destroy
  has_many :topic_names, :through => :topic_name_assignments
  
  has_many :topic_assignments, :dependent => :destroy
  has_many :topics, :through => :topic_assignments, :order => 'topics.name'
  
  has_many :url_references, :dependent => :destroy
  has_many :urls, :through => :url_references
  
  has_many :place_determinations,
           :conditions => "place_determinations.confidence >= #{PlaceDetermination::MIN_CONFIDENCE}",
           :dependent => :destroy
  has_many :places, :through => :place_determinations
  
  has_many :citations,
           :foreign_key => :source_entry_id,
           :dependent => :destroy
  has_many :cited_entries,
           :class_name => 'Entry',
           :through => :citations,
           :source => :cited_entry
  
  has_many :references, :class_name => 'Citation',
           :foreign_key => :cited_entry_id,
           :dependent => :nullify
  has_many :referencing_entries,
           :class_name => 'Entry',
           :through => :references,
           :source => :source_entry
  has_many :graphic_usages
  has_many :graphics,
           :through => :graphic_usages
  
  acts_as_mappable :through => :places
 
  has_many :docket_numbers, :as => :assignable, :order => "docket_numbers.position", :dependent => :destroy
 
  has_many :agency_name_assignments, :as => :assignable, :order => "agency_name_assignments.position", :dependent => :destroy
  has_many :agency_names, :through => :agency_name_assignments
  has_many :agency_assignments, :as => :assignable, :order => "agency_assignments.position", :dependent => :destroy
  has_many :agencies, :through => :agency_assignments, :order => "agency_assignments.position", :extend => Agency::AssociationExtensions
  
  has_many :events, :dependent => :destroy
  has_one :comments_close_date, :class_name => "Event", :conditions => {:event_type => 'CommentsClose'}
  has_one :effective_date, :class_name => "Event", :conditions => {:event_type => 'EffectiveDate'}
  has_one :regulations_dot_gov_comments_close_date, :class_name => "Event", :conditions => {:event_type => 'RegulationsDotGovCommentsClose'}
  
  before_save :set_document_file_path
  
  has_many :section_assignments
  has_many :sections, :through => :section_assignments
  
  has_many :section_highlights
  belongs_to :lede_photo
  
  has_many :entry_page_views
  has_many :entry_emails
  
  has_one :agency_highlight
  
  has_many :events, :dependent => :destroy
  
  accepts_nested_attributes_for :lede_photo, :reject_if => Proc.new{|attr| attr["url"].blank? }
  
  file_attribute(:full_xml)  {"#{RAILS_ROOT}/data/xml/#{document_file_path}.xml"}
  file_attribute(:full_text) {"#{RAILS_ROOT}/data/text/#{document_file_path}.txt"}
  file_attribute(:raw_text)  {"#{RAILS_ROOT}/data/raw/#{document_file_path}.txt"}
  
  has_many :entry_regulation_id_numbers
  has_many :regulatory_plans, :through => :entry_regulation_id_numbers
  has_many :small_entities_for_thinking_sphinx,
           :class_name => 'EntryRegulationIdNumber',
           :conditions => "1 = 1
              LEFT OUTER JOIN regulatory_plans
                ON regulatory_plans.regulation_id_number = entry_regulation_id_numbers.regulation_id_number
                AND regulatory_plans.current = 1
              LEFT OUTER JOIN regulatory_plans_small_entities
                ON regulatory_plans_small_entities.regulatory_plan_id = regulatory_plans.id"
  has_many :entry_cfr_references, :dependent => :delete_all
  has_many :entry_cfr_affected_parts, :class_name => "EntryCfrReference", :conditions => "entry_cfr_references.part IS NOT NULL"

  does 'shared/document_number_normalization'

  validate :curated_attributes_are_not_too_long
  
  def self.published_today
    Issue.current.entries
  end

  def self.with_lede_photo
    scoped(:joins => :lede_photo)
  end
 
  def self.published_in(date_range)
    scoped(:conditions => {:entries => {:publication_date => date_range}})
  end
  
  def self.published_on(publication_date)
    scoped(:conditions => {:entries => {:publication_date => publication_date}})
  end

  def self.published_since(time)
    scoped(:conditions => {:entries => {:publication_date => time .. Time.now}})
  end
  
  def self.comments_closing(range = (Time.current.to_date .. Time.current.to_date + 127.days))
    scoped(
      :joins => :comments_close_date,
      :conditions => {:events => {:date => range}},
      :order => "events.date"
    )
  end
  
  def self.comments_opening(range = (Time.current.to_date - 7.days .. Time.current.to_date))
    scoped(
      :joins => :comments_close_date,
      # :conditions => {:entries => {:publication_date => range}},
      :conditions => {:events => {:date => range}},
      :order => "events.date"
    )
  end
  
  def self.most_recent(n = 10)
    scoped(:order => "publication_date DESC", :limit => n)
  end
  
  def self.popular(since = 1.week.ago)
    scoped(
      :select => "entries.id, entries.title, entries.document_number, entries.publication_date, entries.abstract, count(distinct(remote_ip)) AS num_views",
      :joins => :entry_page_views,
      :conditions => ["entry_page_views.created_at > ?", since],
      :group => "entries.id",
      :having => "num_views > 0",
      :order => "num_views DESC"
    )
  end
  
  def self.most_emailed(since = 1.week.ago)
    scoped(
      :select => "entries.id, entries.title, entries.document_number, entries.publication_date, entries.abstract, count(distinct(remote_ip)) AS num_emails",
      :joins => :entry_emails,
      :conditions => ["entry_emails.created_at > ?", since],
      :group => "entries.id",
      :having => "num_emails > 0",
      :order => "num_emails DESC"
    )
  end
  
  def self.highlighted(date = IssueApproval.latest_publication_date)
    scoped(:joins => :section_highlights, :conditions => {:section_highlights => {:publication_date => date}})
  end
  
  def self.most_recent(n)
    scoped(:order => "entries.publication_date DESC", :limit => n.to_i)
  end
  
  def self.most_cited(n)
    scoped(:conditions => "entries.citing_entries_count > 0",
           :order => "citing_entries_count DESC, publication_date DESC",
           :limit => n.to_i)
  end
  
  def self.of_type(type)
    scoped(:conditions => {:granule_class => type})
  end
  
  def self.with_regulation_id_number(rin)
    scoped(:conditions => {:entry_regulation_id_numbers => {:regulation_id_number => rin}}, :joins => :entry_regulation_id_numbers)
  end

  def self.executive_order
    scoped(:conditions => {:presidential_document_type_id => PresidentialDocumentType::EXECUTIVE_ORDER})
  end

  def entry_type 
    ENTRY_TYPES[granule_class]
  end
  
  define_index do
    # fields
    indexes title
    indexes abstract
    indexes "LOAD_FILE(CONCAT('#{RAILS_ROOT}/data/raw/', document_file_path, '.txt'))", :as => :full_text
    indexes "GROUP_CONCAT(DISTINCT IFNULL(`entry_regulation_id_numbers`.`regulation_id_number`, '0') SEPARATOR ' ')", :as =>  :regulation_id_number
    indexes "GROUP_CONCAT(DISTINCT docket_numbers.number SEPARATOR ' ')", :as => :docket_id
    
    # attributes
    has "SUM(IF(regulatory_plans.priority_category IN (#{RegulatoryPlan::SIGNIFICANT_PRIORITY_CATEGORIES.map{|c| "'#{c}'"}.join(',')}),1,0)) > 0", :as => :significant, :type => :boolean
    has "CRC32(IF(granule_class = 'SUNSHINE', 'NOTICE', granule_class))", :as => :type, :type => :integer
    has presidential_document_type_id
    has "IF(granule_class = 'PRESDOCU', INTERVAL(DATE_FORMAT(IFNULL(signing_date,DATE_SUB(publication_date, INTERVAL 3 DAY)), '%Y%m%d'),#{President.all.map{|p| p.starts_on.strftime("%Y%m%d")}.join(', ')}), NULL)", :as => :president_id, :type => :integer
    has "GROUP_CONCAT(DISTINCT entry_cfr_references.title * #{EntrySearch::CFR::TITLE_MULTIPLIER} + entry_cfr_references.part)", :as => :cfr_affected_parts, :type => :multi
    has agency_assignments(:agency_id), :as => :agency_ids
    has topic_assignments(:topic_id),   :as => :topic_ids
    has section_assignments(:section_id), :as => :section_ids
    has place_determinations(:place_id), :as => :place_ids
    has "GROUP_CONCAT(DISTINCT IFNULL(regulatory_plans_small_entities.small_entity_id,0) SEPARATOR ',')", :as => :small_entity_ids, :type => :multi
    has publication_date
    has effective_date(:date), :as => :effective_date
    has comments_close_date(:date), :as => :comment_date
    has "IF(granule_class = 'CORRECT' OR correction_of_id IS NOT NULL OR (presidential_document_type_id = 2 AND (executive_order_number = 0 or executive_order_number IS NULL)), 1, 0)", :as => :correction, :type => :boolean
    has start_page
    has executive_order_number
    
    join entry_cfr_affected_parts
    join docket_numbers
    join small_entities_for_thinking_sphinx
    set_property :field_weights => {
      "title" => 100,
      "abstract" => 50,
      "full_text" => 25,
      "agency_name" => 10
    }
    
    set_property :delta => ThinkingSphinx::Deltas::ManualDelta
  end
  # this line must appear after the define_index block
  include ThinkingSphinx::Deltas::ManualDelta::ActiveRecord
  
  def title
    if self[:title].present? && self[:title] =~ /[A-Za-z]/
      self[:title]
    else
      '[No title available]'
    end
  end
  
  def toc_doc
    if self[:toc_doc].present?
      self[:toc_doc].sub(/\s*,\s*$/,'')
    else
      nil
    end
  end
  
  def curated_title
    self[:curated_title] || title
  end
  
  def curated_abstract
    self[:curated_abstract] || abstract
  end
  
  def day
    publication_date.strftime('%d')
  end

  def active
    response_code == '200' ? true : false
  end
  
  def human_length
    if length.blank? && end_page && start_page
      end_page - start_page + 1
    else
      length
    end
  end
  
  def slug
    clean_title = title.downcase.gsub(/[^a-z0-9& -]+/,'').gsub(/&/, 'and')
    slug = view_helper.truncate_words(clean_title, :length => 100, :omission => '')
    slug.gsub(/ /,'-')
  end
  
  def comments_close_on
    comments_close_date.try(:date)
  end
  
  def effective_on
    effective_date.try(:date)
  end

  def regulations_dot_gov_comments_close_on
    regulations_dot_gov_comments_close_date.try(:date)
  end

  def regulations_dot_gov_comments_close_on=(date)
    if date
      event = regulations_dot_gov_comments_close_date || events.build(:event_type => 'RegulationsDotGovCommentsClose')
      event.date = date
    else
      regulations_dot_gov_comments_close_date.try(:delete)
    end
  end

  def source_url(format)
    case format.to_sym
    when :mods
      "http://www.gpo.gov/fdsys/granule/FR-#{publication_date.to_s(:iso)}/#{document_number}/mods.xml"
    when :html
      "http://www.gpo.gov/fdsys/granule/FR-#{publication_date.to_s(:db)}/#{document_number}"
    when :text
      "http://www.gpo.gov/fdsys/pkg/FR-#{publication_date.to_s(:db)}/html/#{document_number}.htm"
    when :pdf
      "http://www.gpo.gov/fdsys/pkg/FR-#{publication_date.to_s(:db)}/pdf/#{document_number}.pdf"
    end
  end
  
  def entries_within(distance, options={})
    limit = options.delete(:limit) || 10
    count = options.delete(:count) || false
    
    if count
      entry_count = 0
      places.each do |place|
        entry_count = entry_count + Entry.count_within(distance, :origin => place.location)
      end
      entry_count
    else
      entries = []
      places.each do |place|
        entries += Entry.find_within(distance, :origin => place.location, :limit => limit, :order => 'distance')
      end
      entries.uniq.sort_by{|e| e.publication_date}[0..9].flatten
    end
  end
  
  def self.find_near(loc, dist = 100)
    places  = Place.find_places_near(loc, dist)
    entries = []
    places.each do |place|
      entries << place.entry
    end
    entries
  end
  
  def self.earliest_publication_date
    with_exclusive_scope do
      Entry.find(:first, :select => "publication_date", :order => "publication_date").publication_date
    end
  end
  
  def self.latest_publication_dates(n)
    find(:all,
         :select => "publication_date",
         :conditions => ["publication_date <= ?", Issue.current.publication_date],
         :group => "publication_date",
         :order => "publication_date DESC",
         :limit => n
    ).map &:publication_date
  end
  
  def self.find_all_by_citation(volume, page)
    scoped(:conditions => ["volume = ? AND start_page <= ? AND end_page >= ?", volume.to_i, page.to_i, page.to_i], :order => "entries.end_page")
  end
  
  def self.first_publication_date_before(date)
    Entry.find(:first,
        :select => 'publication_date',
        :conditions => ["publication_date < ?", date],
        :order => 'publication_date DESC'
    ).try(:publication_date)
  end
  
  def self.first_publication_date_after(date)
    Entry.find(:first,
        :select => 'publication_date',
        :conditions => ["publication_date > ?", date],
        :order => 'publication_date'
    ).try(:publication_date)
  end
  
  # TODO: remove this method when no longer called
  def agency
    ActiveSupport::Deprecation.warn("Entry#agency is deprecated. Entries are now associated with multiple agencies.")
    agencies.first
  end
  
  def has_type?
    entry_type != 'Unknown'
  end
  
  def recalculate_agencies!
    agency_name_assignments.map do |agency_name_assignment|
      agency_name_assignment.create_agency_assignment
    end
  end
  
  def lede_photo_candidates
    self[:lede_photo_candidates] ? YAML::load(self[:lede_photo_candidates]) : []
  end
  
  def regulation_id_numbers=(rins)
    @regulation_id_numbers = rins
    self.entry_regulation_id_numbers = rins.map do |rin|
      entry_regulation_id_numbers.to_a.find{|erin| erin.regulation_id_number == rin} || EntryRegulationIdNumber.new(:regulation_id_number => rin)
    end
    rins
  end
  
  def regulation_id_numbers
    @rins || self.entry_regulation_id_numbers.map(&:regulation_id_number)
  end
  
  def current_regulatory_plans
    RegulatoryPlan.current.all(:conditions => {:regulation_id_number => regulation_id_numbers})
  end

  def significant?
    current_regulatory_plans.any?(&:significant?)
  end
  
  def previous_entry
    @previous_entry ||= Entry.first(
      :conditions => ["entries.volume <= ? AND entries.start_page <= ? AND entries.id < ?", volume, start_page, id],
      :order => "entries.volume DESC, entries.start_page DESC, entries.id DESC"
    )
  end
  
  def next_entry
    @next_entry ||= Entry.first(
      :conditions => ["entries.volume >= ? AND entries.start_page >= ? AND entries.id > ?", volume, start_page, id],
      :order => "entries.volume, entries.start_page, entries.id"
    )
  end

  def should_have_full_xml?
    full_xml_updated_at.present?
  end

  def republication?
    document_number =~ /^R/
  end

  def president
    date = signing_date || (publication_date - 3)
    President.in_office_on(date)
  end
 
  private
  
  def set_document_file_path
    self.document_file_path = document_number.sub(/-/,'').scan(/.{0,3}/).reject(&:blank?).join('/') if document_number.present?
    
    true
  end
  
  def curated_attributes_are_not_too_long
    if self[:curated_title].present? && self[:curated_title].size > 255
      errors.add(:curated_title, "exceeds 255 characters")
    end
    
    if self[:curated_abstract].present? && self[:curated_abstract].size > 500
      errors.add(:curated_abstract, "exceeds 500 characters")
    end
  end
  
end
