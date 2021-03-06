class ApplicationSearch
  extend ActiveSupport::Memoizable
  class InputError < StandardError; end

  attr_accessor :order
  attr_reader :filters, :term, :per_page, :page, :conditions, :valid_conditions
  
  def per_page=(count)
    per_page = count.to_s.to_i
    if per_page > 1 && per_page <= 1000
      @per_page = per_page
    else
      @per_page = 20
    end
    
    @per_page
  end
  
  def term=(term)
    @term = term.to_s
  end
  
  def validation_errors
    @errors
  end
  
  def self.define_filter(filter_name, options = {}, &name_definer)
    attr_reader filter_name
    # refactor to partials...
    
    define_method "#{filter_name}=" do |val|
      if (val.present? && (val.is_a?(String) || val.is_a?(Fixnum))) || (val.is_a?(Array) && !val.all?(&:blank?))
        instance_variable_set("@#{filter_name}", val)
        if val.is_a?(Array)
          val.reject!(&:blank?)
        end
        
        begin
          add_filter options.merge(:value => val, :condition => filter_name, :name_definer => name_definer)
        rescue ApplicationSearch::InputError => e
          @errors[filter_name] = e.message
        end
      end
    end
  end
  
  def self.define_date_filter(filter_name, options = {})
    attr_reader filter_name
    condition = filter_name
    
    define_method "#{filter_name}=" do |hsh|
      if hsh.is_a?(Hash) && hsh.values.any?(&:present?)
        selector = DateSelector.new(hsh)
        instance_variable_set("@#{filter_name}", selector)
        
        label = options[:label]
        
        if selector.valid?
          add_filter(
            :value => selector.sphinx_value,
            :name => selector.filter_name,
            :condition => condition,
            :label => label,
            :sphinx_type => :with,
            :sphinx_attribute => options[:sphinx_attribute] || filter_name
          )
        else
          @errors[filter_name.to_sym] = "#{label} is not a valid date."
        end
      end
    end
  end
  
  def self.define_place_filter(filter_name, options = {})
    attr_reader filter_name
    
    define_method "#{filter_name}=" do |hsh|
      if hsh.present? && hsh.values.any?(&:present?)
        place_selector = PlaceSelector.new(hsh[:location], hsh[:within])
        instance_variable_set("@#{filter_name}", place_selector)
        if place_selector.valid? && place_selector.location.present?
          add_filter(
            :value => [place_selector.place_ids], # deeply nested array keeps places together to avoid duplicate filters
            :name => "within #{place_selector.within} miles of #{place_selector.location}",
            :condition => filter_name,
            :sphinx_attribute => options[:sphinx_attribute],
            :label => "Located",
            :sphinx_type => :with
          )
        else
          unless place_selector.valid?
            @errors[filter_name] = place_selector.validation_errors
          end
        end
      end
    end
  end
  
  def initialize(options = {})
    options.symbolize_keys!
    @errors = {}
    @filters = []
    
    # Set some defaults...
    @page = options[:page].to_i
    if @page < 1 || @page > 50
      @page = 1
    end
    
    set_defaults(options)
    
    @skip_results = options[:skip_results] || false
    self.per_page = options[:per_page]
    self.conditions = (options[:conditions] || {}).reject{|key,val| ! self.respond_to?("#{key}=")}
  end
  
  def conditions=(conditions)
    @conditions = conditions
    @valid_conditions = {}
    conditions.to_a.reverse.each do |attr, val|
      response = self.send("#{attr}=", val)
      @valid_conditions[attr] = val if response.present?
    end
  end
  
  def add_filter(options)
    # vals = (options[:value].is_a?(Array) ? options[:value] : [options[:value]])
    # vals.each do |val|
      @filters << Filter.new(options)#.merge(:value => val))
    # end
  end
  
  def valid?
    @errors.empty?
  end
  
  def blank?
    [with, with_all, sphinx_conditions, term].all?(&:blank?) || skip_results?
  end
  
  def skip_results?
    @skip_results
  end
  
  def sphinx_conditions
    sphinx_conditions = {}
    @filters.select{|f| f.sphinx_type == :conditions }.each do |filter|
      sphinx_conditions[filter.sphinx_attribute] = TermPreprocessor.process_term(filter.sphinx_value)
    end
    
    sphinx_conditions
  end
  
  def with
    with = {}
    @filters.select{|f| f.sphinx_type == :with }.each do |filter|
      with[filter.sphinx_attribute] = filter.sphinx_value
    end
    with
  end
  
  def with_all
    with = {}
    @filters.select{|f| f.sphinx_type == :with_all }.each do |filter|
      with[filter.sphinx_attribute] ||= []
      with[filter.sphinx_attribute] << filter.sphinx_value
    end
    with
  end
  
  def results(args = {})
    result_array = model.search(sphinx_term,
      {
        :page => @page,
        :per_page => @per_page,
        :order => order_clause,
        :with => with,
        :with_all => with_all,
        :conditions => sphinx_conditions,
        :match_mode => :extended,
        :sort_mode => sort_mode
      }.merge(find_options).recursive_merge(args)
    )

    if result_array
      result_array.each do |result|
        result.excerpts = ApplicationSearch::FileExcerpter.new result_array, result
      end
    end

    # TODO: FIXME: Ugly hack to get total pages to be within bounds
    if result_array && result_array.total_pages > 50
      def result_array.total_pages
        50
      end
    end
    
    result_array
  end
  memoize :results
  
  def order_clause
    "@relevance DESC"
  end

  def sort_mode
    :extended
  end
  
  def find_options
    {}
  end
  
  def to_hash
    {
      :page => @page,
      :per_page => @per_page,
      :order => order_clause,
      :conditions => conditions
    }
  end
  
  def count
    @count ||= model.search_count(sphinx_term,
      {
        :page => @page,
        :per_page => @per_page,
        :order => order_clause,
        :with => with,
        :with_all => with_all,
        :conditions => sphinx_conditions,
        :match_mode => :extended,
        :sort_mode => sort_mode
      }.merge(find_options)
    )
  end
  
  def term_count
    model.search_count(sphinx_term, :match_mode => :extended)
  end
  
  def entry_count
    EntrySearch.new(:conditions => {:term => @term}).term_count
  end
  
  def public_inspection_document_count
    PublicInspectionDocumentSearch.new(:conditions => {:term => @term}).term_count
  end

  def event_count
    EventSearch.new(:conditions => {:term => @term}).term_count
  end
  
  def regulatory_plan_count
    RegulatoryPlanSearch.new(:conditions => {:term => @term}).term_count
  end
  
  def to_json
    @conditions.to_json
  end

  def sphinx_term
    @sphinx_term ||= TermPreprocessor.process_term(@term)
  end
  
  private
  
  def set_defaults(options)
  end
end
