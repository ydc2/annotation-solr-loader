require "bundler/gem_tasks"
namespace :solrLoader do
  task :SolrLoadAll do
    require 'annotation_solr_loader'
    AnnotationSolrLoader.new.load_all_annotations()
  end
end
