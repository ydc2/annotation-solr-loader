  require 'rubygems'
  require 'json'
  #require './manifest_parser.rb'
  require 'rsolr'
  require 'open-uri'
  require 'set'

  class AnnotationSolrLoader
    def initialize
      @project_map = { 'hours' => 'Books of Hours', 'yaleCS' => 'Machine analysis', 'creatingEnglish' => 'Creating English Literature'}
      @project_map = { 'hours' => 'Books of Hours', 'yaleCS' => 'Machine analysis', 'creatingEnglish' => 'Creating English Literature', 'gratian' => 'Gratian\'s Decretum'}
      @valid_groups = ['hours', 'creatingEnglish', 'yaleCS', 'gratian']
    end

    def load_all_annotations(path, manifest_lookup)
      exported_manifests_path = ENV['DESMM_MANIFESTS_PATH']
      manifest_lookup = ManifestParser.new
      manifest_lookup.manifests_from_array("#{exported_manifests_path}/manifests.json")
      #manifest_lookup.manifest_from_file("./manifests/WaltersMS34.json")
      #manifest_lookup.manifest_from_file("./manifests/WaltersMS102.json")
      # 2 params above need to be set here
      @jsonTagCat = JSON.parse(open("http://desmmtags.ydc2.yale.edu/services/getTagsSolrMappings.json").read)
      @all_tags = Set.new
      solr_data = Array.new
      data = File.read(path)
      begin
        json = JSON.parse(data)
      rescue Exception => e
        puts e.to_s
        exit(-1)
      end
      annotations = load_annotations(json)
      annotations.each do |id, annotation|
        record = create_solr_record(annotation, manifest_lookup) unless !annotation['active']
        solr_data.push(record)
      end
      add_to_solr(solr_data)
    end

    def load_single_annotation(annotation)
      @all_tags = Set.new
      puts 'In load_single_annotation'
      #Delayed::Worker.logger.debug("Log Entry: " + 'async_update: annotated by: ' + annotation.annotatedBy.to_s)
      solr_data = Array.new
      # get the manifest info for this annotation into manifest_lookup
      manifest_lookup = ManifestParser.new
      manifest_lookup.manifest_from_annotation annotation
      # Convert Annotation object to JSON
      annotation_attributes=annotation.attributes
      annotation_string = JSON.generate(annotation_attributes)
      annotation = JSON.parse(annotation_string)
      #set  @jsonTagCat to hold solr mappings for any tags in resource_chars
      @jsonTagCat = set_jsonTagCat annotation['resource']['chars']
      puts '@jsonTagCat after call = ' + JSON.generate(@jsonTagCat)
      record = create_solr_record(annotation, manifest_lookup) unless !annotation['active']
      puts 'back fron create_solr_record'
      solr_data.push(record)
      puts 'solr_record: ' + record.to_s
      add_to_solr(solr_data)
    end

    def create_solr_record(annotation, manifest_lookup)
      puts 'start of first record section'
      record = Hash.new
      record[:id] = annotation['@id'].gsub(/http:\/\/annotations.ydc2.yale.edu\/annotation\//, "")
      record[:annotation_id_s] = annotation['@id']
      group = annotation['permissions']['read'] & @valid_groups
      exit if group.empty?
      record[:project_t] = @project_map[group[0]]
      record[:project_id_t] =  group[0]
      record[:text_t] = annotation['resource']['chars']
      record[:creator_t] = annotation['annotatedBy']['name']
      on = annotation['on']
      on.gsub!(/-3128/, "3128")
      record[:on_s] = annotation['on']
      record[:motivation_t] = annotation['motivation']
      record[:manifest_s] = annotation['manifest'].gsub!(/.json/, '')
      record[:canvas_s] = annotation['canvas']
      manifest_uri = annotation['manifest']
      if manifest_uri.include?('ydc2')
        #manifest_uri.gsub!(/.json/, '')
      end

      record[:manifest_label_t] = manifest_lookup.manifest_label_map[annotation['manifest']]
      record[:manifest_label_s] = manifest_lookup.manifest_label_map[annotation['manifest']]
      puts 'manifest 1'
      record[:canvas_label_t] = manifest_lookup.canvas_label_map[record[:canvas_s]]
      canvas_image = manifest_lookup.canvas_image_map[record[:canvas_s]]
      if canvas_image.index("full/full").nil?
        canvas_image += '/' unless canvas_image.end_with?('/')
        canvas_image += 'full/full/0/native.jpg'
      end
      record[:iiif_canvas_image_s] = canvas_image
      anno_img = annotation_area_image(canvas_image, record[:on_s])
      record[:iiif_annotation_image_s] = anno_img unless anno_img.nil?
      puts 'manifest 2'
      # Process data from Manifest
      puts 'manifest2.5 manifiest_uri = ' + manifest_uri
      manifest = manifest_lookup.manifests[manifest_uri]
      manifest_label = manifest_lookup.manifest_label_map[manifest_uri]
      record[:manifest_s] = manifest_uri
      record[:manifest_label_t] = manifest_label
      record[:manifest_label_s] = manifest_label
      unless manifest.nil?
        #record[:attribution_t] = manifest['attribution']
        #record[:logo_s] = manifest['logo']
        #record[:license_t] = manifest['license']
        #test above for bulk load
        record[:attribution_t] = manifest['manifest_json']['attribution']
        record[:logo_s] = manifest['manifest_json']['logo']
        record[:license_t] = manifest['manifest_json']['license']
        add_related_items record, manifest
        add_metadata record, manifest
        add_related_items record, manifest['manifest_json']
        add_metadata record,manifest['manifest_json']
      end
      puts 'manifest 3'
      #*********************************************************************************************
      # parse tags
      tags = Array.new
      if (record[:text_t])
        record[:text_t].scan(/\#\w*/).each { |m|
          @all_tags.add(m)

          unless record[:project_id_t] == 'gratian'
            tag = m.gsub!(/\#/, '')
            # find the correct category/solr field based on the tag id
            thisTag = '#' + m
            if @jsonTagCat[thisTag].nil?
              #@tagsNotManaged.push(thisTag)
              record['unclassified_t'] = tag
            end
            if !@jsonTagCat[thisTag].nil?
              tagMap = @jsonTagCat[thisTag]
              tagMap.each do |element|
                hash = Hash[*element.flatten]
                solrField = hash['solrfield'].to_s
                solrValue = hash['solrvalue'].to_s
                writeSolrFields(solrField, solrValue, record)
              end
            end
          else
            # handle Gratian TOC tag
            # first qualify that it is a TOC tag
            if gratianTagIsTOC record[:text_t]
              solrValue = getSolrValueForGratian record [:text_t]
              writeSolrFields  'project_t', solrValue, record
              i += 1
            end
          end   # unless project_id_t == 'gratian'

          record[:tags_t] = tags
        }
      end
      record[:text] = record.keys.join(' ')
      record = map_facet_fields(record)
      record
      #@solr_data.push(record)

    end
    protected

    def add_metadata(record,manifest)
      metadata = manifest['metadata']
      if (metadata)
        record['metadata_keys_t'] = Array.new
        record['metadata_values_t'] = Array.new
        metadata.each { |item|
          record['metadata_keys_t'].push(item['label'])
          record['metadata_values_t'].push(item['value'])
        }
      end
    end

    def add_related_items(record, manifest)
      record[:related_item_uri_t] = []
      record[:related_item_label_t] = []
      related_items = manifest['related']
      return if related_items.nil?
      if related_items.is_a?Array
        related_items.each { |related_item|
          add_single_related_item record, related_item
        }
      elsif related_items.is_a?Hash
        add_single_related_item record, related_items
      end
    end

    def add_single_related_item(record, related_item)
      uri = related_item['@id']
      return if uri.nil?
      label = related_item['label'] || uri
      record[:related_item_uri_t].push uri
      record[:related_item_label_t].push label
    end

    def annotation_area_image(canvas_image, on)
      return nil if on.nil? or canvas_image.nil?
      url, fragment = on.split(/\#xywh=/)
      return nil if fragment.nil?
      canvas_image.sub(/full\/full/, "#{fragment}/full")
    end

    def map_facet_fields(record)
      new_fields = Hash.new
      record.each { |k,v|
        if k.match(/_[st]$/)
          new_key = k.to_s.gsub(/_[st]$/, '_facet')
          new_fields[new_key] = v
        end
      }
      record.merge new_fields
    end

    def map_manifest(manifest)
      @manifest_label_map[ manifest['@id'] ] = manifest['label']
      manifest['sequences'].each do |sequence|
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
          url = resources['@id']
        elsif annotation_type == 'oa:Choice'
          url = resources['default']['@id'] if resources['default']
        end
      end
      return url
    end

    def getSolrValueForGratian (text_t)
      puts 'Gratian tag = ' + text_t
      if text_t.start_with?('#')
        text_t = text_t[1..-1]
        #puts "stripped #: " + text_t
      end
      text_t.gsub! '.', ':.'
      text_t = 'Gratian\'s Decretum:' + text_t
      return text_t
    end

    def gratianTagIsTOC(text_t)
      if text_t .start_with?(*('0'..'9')) || text_t.start_with?('#')
        return true
      else
        return false;
      end
    end

    def writeSolrFields(solrField, solrValue, record)
      workMap = ''
      solrValueArray = solrValue.split(":")
      # begin iteration for solrfield
      solrValueArray.each do |solrValueSeg|
        record[solrField] = Array.new unless record[solrField]
        begin
          if workMap.empty?
            workMap = solrValueSeg
          else
            workMap = workMap +  ':' + solrValueSeg
          end
          record[solrField].push workMap
        rescue Exception => e
          puts 'solr mapping error: ' + e.to_s
          puts ''
        end
      end
    end

    def set_jsonTagCatSingle recordTextS
      tagHash = Hash.new
      puts 'recordText = ' + recordText
      @jsonTagCat = ''
      recordText.scan(/\#\w*/).each { |tag|
        tag.gsub!(/#/, "")
        puts 'tag = ' + tag
        #tagURI = "http://desmmtags.ydc2.yale.edu/services/getSolrMappingsForSingleTag.json?tag=" + tag
        tagURI = "http://localhost:3000/services/getSolrMappingsForSingleTag.json?tag=" + tag
        puts 'tagURI = ' + tagURI
        @jsonTagCat = JSON.parse(open(tagURI).read)
        puts 'solrMappings = ' + JSON.generate(@jsonTagCat)
      }
    end

    def set_jsonTagCat recordText
      tagSet = recordText.gsub(/#/,'')
      tagSet.rstrip!.gsub!(/\s/,"%20")
      #tagURI = "http://desmmtags.ydc2.yale.edu/services/getSolrMappingsForTagSet.json?tags=" + tagSet
      tagURI = "http://localhost:3000/services/getSolrMappingsForTagSet.json?tags=" + tagSet

      @jsonTagCat = JSON.parse(open(tagURI).read)
      @jsonTagCat
    end

    def load_annotations(json)
      annotations = Hash.new
      json.each do |annotation|
        annotations[annotation['@id']] = annotation
      end
      annotations
    end

    def add_to_solr(annotations)
      url = 'http://vm-ydc2dev-01.its.yale.edu:8080/solr/desm-hours-blacklight'
      #url = 'http://solr:desmm@ec2-54-91-21-213.compute-1.amazonaws.com:8983/solr/desmm-hours-blacklight'

      puts "Loading #{url}"
      solr = RSolr.connect :url => url
      puts 'connection made'
      x = 0

      annotations.each_slice(1000) { |annotations|
        solr.add annotations
        solr.commit
        x += 1
        p x
      }
    end
  end
