ActionController::Routing::Routes.draw do |map|
  map.with_options(:path_prefix => "api/v1", :name_prefix => "api_v1_") do |api|
    api.with_options(:path_prefix => "api/v1/doc", :controller => "api/v1/documentation", :conditions => {:method => :get}) do |doc|
      doc.entries_attributes ':type/attributes', :action => :attributes, :quiet => true
    end

    api.resources :entries,
                  :as => :articles,
                  :only => [:index, :show],
                  :controller => 'api/v1/entries'
  
    api.resources :agencies,
                  :only => [:index, :show],
                  :controller => 'api/v1/agencies'

    api.resources :public_inspection_documents,
                  :as => 'public-inspection-documents',
                  :only => [:index, :show],
                  :controller => 'api/v1/public_inspection_documents',
                  :collection => {:current => :get}
  end
end
