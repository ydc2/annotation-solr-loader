require 'rubygems'
require 'json'

class ManifestParser

  attr_accessor :manifest_label_map, :canvas_label_map, :canvas_image_map, :manifests

  def initialize
    @manifests = Hash.new
    @manifest_label_map = Hash.new
    @canvas_label_map = Hash.new
    @canvas_image_map = Hash.new

    @manifest_label_map['https://s3.amazonaws.com/tempmanifests/Walters/xq443wf4818/manifest.json'] = 'Walters MS 102'
    @manifest_label_map['https://s3.amazonaws.com/tempmanifests/Walters/zw200wd8767/manifest.json'] = 'Walters MS 34'
  end

  def manifests_from_array(path)
    data = File.read(path)
    json = JSON.parse(data)
    json.each do |manifest|
      @manifests[manifest['manifest_json']['@id']] = manifest['manifest_json']
    end
    @manifests.each do |id, manifest|
      map_manifest(manifest, 'array')
    end
  end

  def manifest_from_file(path)
    data = File.read(path)
    manifest = JSON.parse(data)
    @manifests[manifest['@id']] = manifest
    map_manifest(manifest, 'file')
    puts
  end

  def manifest_from_annotation(annotation)
    puts 'in manifest_from_annotation'
    manifest_id = annotation.manifest.gsub(/http:\/\/manifests.ydc2.yale.edu\/manifest\//, "")
    manifest_id.gsub!(/.json/,"")
    #puts 'manifest_id = ' + manifest_id
    manifest = Manifest.find(manifest_id)
    #puts '**manifest = '+ manifest.to_s
    #@manifests[manifest['@id']] = manifest
    @manifests[manifest['manifest_json']['@id']] = manifest.manifest_json

    manifest_hash_string = manifest.attributes
  #puts "new annotation's manifest ==> " + JSON.generate(manifest_hash_string)
    map_manifest(manifest.manifest_json, 'annotation')
    puts 'done with manifest_from_annotation'
  end

  protected

  def map_manifest(manifest, from)
    #puts manifest.to_s
   # puts 'label: ' +  manifest['label']
    @manifest_label_map[ manifest['@id'] ] = manifest['label']
    sequences = manifest['sequences'] || Array.new
    sequences.each do |sequence|
      sequence['canvases'].each do |canvas|
        @canvas_label_map[ canvas['@id'] ] = canvas['label']
        @canvas_image_map[ canvas['@id'] ] = primary_image_url(canvas)
      end
    end
  end

  def primary_image_url(canvas)
    url = nil
    if canvas['images'] and canvas['images'][0]
      resources = canvas['images'][0]['resource']
      return if resources.nil? || resources.empty? || resources['@type'].nil?
      annotation_type = resources['@type']
      if annotation_type == 'dctypes:Image'
        url = resources['service']['@id']
      elsif annotation_type == 'oa:Choice'
        url = resources['default']['service']['@id'] if resources['default']
      else
        p "No image for #{canvas}"
      end
    elsif canvas['resources'] and canvas['resources'][0]
      url = canvas['resources'][0]['resource']['service']['@id']
    end
    return url
  end

end