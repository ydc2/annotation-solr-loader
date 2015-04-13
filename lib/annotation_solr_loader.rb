  require 'rubygems'
  require 'json'
  require 'rsolr'
  require 'open-uri'
  require 'set'
  require_relative 'annotation_solr_loader/manifest_parser.rb'
  require_relative 'annotation_solr_loader/config/solr_connect_config.rb'

  class AnnotationSolrLoader

    def initialize
      @project_map = { 'hours' => 'Books of Hours', 'yaleCS' => 'Machine analysis', 'creatingEnglish' => 'Creating English Literature'}
      @project_map = { 'hours' => 'Books of Hours', 'yaleCS' => 'Machine analysis', 'creatingEnglish' => 'Creating English Literature', 'gratian' => 'Gratian\'s Decretum'}
      @valid_groups = ['hours', 'creatingEnglish', 'yaleCS', 'gratian']
      @solrUrl = SolrConnectConfig.get("solrUrl")
      puts 'connection made for add/update to: ' + @solrUrl.to_s
      @tagUrl = SolrConnectConfig.get("tagUrl")
    end

    def load_all_annotations()
      exported_manifests_path = ENV['DESMM_MANIFESTS_PATH']
      manifest_lookup = ManifestParser.new
      manifest_lookup.manifests_from_array("#{exported_manifests_path}/manifests.json")
      manifest_lookup.manifest_from_file("#{exported_manifests_path}/WaltersMS34.json")
      manifest_lookup.manifest_from_file("#{exported_manifests_path}/WaltersMS102.json")

      @jsonTagCat = JSON.parse(open("http://desmmtags.ydc2.yale.edu/services/getTagsSolrMappings.json").read)
      getTagsSolrMappingsUrl = @tagUrl + "/services/getTagsSolrMappings.json"
      @jsonTagCat = JSON.parse(open( getTagsSolrMappingsUrl).read)
      @all_tags = Set.new
      solr_data = Array.new
      data = File.read("#{exported_manifests_path}/annotations.json")

      begin
        json = JSON.parse(data)
      rescue Exception => e
        puts e.to_s
        exit(-1)
      end
      annotations = load_annotations(json)
      #puts 'annotations loaded: count = ' + annotations.count().to_s

      i=0
      annotations.each do |id, annotation|
        unless !annotation['active']
          i += 1
          record = create_solr_record(annotation, manifest_lookup)
          solr_data.push(record) unless record.nil?
        end
      end
      add_to_solr(solr_data)
    end

    def load_single_annotation(annotation)
      #Delayed::Worker.logger.debug("Log Entry: " + 'async_update: annotated by: ' + annotation.annotatedBy.to_s)
      if !annotation.active
        delete_from_solr annotation
        return
      end
      solr_data = Array.new
      # get the manifest info for this annotation into manifest_lookup
      manifest_lookup = ManifestParser.new
      manifest_lookup.manifest_from_annotation annotation
      # Convert Annotation object to JSON
      annotation_attributes=annotation.attributes
      annotation_string = JSON.generate(annotation_attributes)
      annotation = JSON.parse(annotation_string)
      #set @jsonTagCat to hold solr mappings for any tags in resource_chars
      @jsonTagCat = set_jsonTagCat annotation['resource']['chars']
      record = create_solr_record(annotation, manifest_lookup) unless !annotation['active']
      solr_data.push(record)
      add_to_solr(solr_data)
    end

    def create_solr_record(annotation, manifest_lookup)
      record = Hash.new
      #record[:id] = annotation['@id'].gsub(/http:\/\/annotations.ydc2.yale.edu\/annotation\//, "")
      last_index = annotation['@id'].rindex('/')
      record[:id] = annotation['@id'][last_index+1..annotation['@id'].length]
      record[:annotation_id_s] = annotation['@id']
      group = annotation['permissions']['read'] & @valid_groups
      return if group.empty?
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
      record[:canvas_label_t] = manifest_lookup.canvas_label_map[record[:canvas_s]]
      canvas_image = manifest_lookup.canvas_image_map[record[:canvas_s]]
      if !canvas_image.nil?
      if !canvas_image.empty?
        begin
          if canvas_image.index("full/full").nil?
            canvas_image += '/' unless canvas_image.end_with?('/')
            canvas_image += 'full/full/0/native.jpg'
            canvas_image.gsub!('native', 'default') if canvas_image.include?('stanford.edu')
          end
          rescue
            puts 'no canvas_image.index: canvas_image is nil: ' + canvas_image.nil?.to_s + "  and canvas_image.empty?: " + canvas_image.empty?.to_s
          end
        end
      end
      record[:iiif_canvas_image_s] = canvas_image
      anno_img = annotation_area_image(canvas_image, record[:on_s], record)
      record[:iiif_annotation_image_s] = anno_img unless anno_img.nil?
      # Process data from Manifest
      manifest = manifest_lookup.manifests[manifest_uri]
      manifest_label = manifest_lookup.manifest_label_map[manifest_uri]
      record[:manifest_s] = manifest_uri
      record[:manifest_label_t] = manifest_label
      record[:manifest_label_s] = manifest_label
      unless manifest.nil?
        record[:attribution_t] = manifest['attribution']
        record[:logo_s] = manifest['logo']
        record[:license_t] = manifest['license']
        add_related_items record, manifest
        add_metadata record, manifest
      end
      #*********************************************************************************************
      # parse tags
      tags = Array.new
      if (record[:text_t])
        record[:text_t].scan(/\#\w*/).each { |m|
          unless record[:project_id_t] == 'gratian'
            tag = m.gsub!(/\#/, '')
            # find the correct category/solr field based on the tag id
            thisTag = '#' + m
            if @jsonTagCat[thisTag].nil?
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
            end
          end   # unless project_id_t == 'gratian'

          record[:tags_t] = tags
        }
      end
      record[:text] = record.keys.join(' ')
      record = map_facet_fields(record)
      record
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

    def annotation_area_image(canvas_image, on, record)
      return nil if on.nil? or canvas_image.nil?
      url, fragment = on.split(/\#xywh=/)
      return nil if fragment.nil?
      coords = fragment.split(',')
      record[:iiif_x1_i] = coords[0]
      record[:iiif_y1_i] = coords[1]
      record[:iiif_x2_i] = coords[0].to_i + coords[2].to_i
      record[:iiif_y2_i] = coords[1].to_i + coords[3].to_i
      record[:iiif_w_i] = coords[2]
      record[:iiif_h_i] = coords[3]
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

      #url.gsub!('native', 'default') if url.include?('stanford.edu')

      return url
    end

    def getSolrValueForGratian (text_t)
      return if text_t.nil?
      if text_t.start_with?('#')
        text_t = text_t[1..-1]
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
      solrValueArray.each do |solrValueSeg|
        #puts 'solrValueSeg = ' + solrValueSeg
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

    def set_jsonTagCat recordText
      tagsIn = recordText.split(' ')
      tagSet = ""
      tagsIn.each do |tag|
        tagSet.concat(tag + " ") if tag.start_with?("#")
      end
      tagSet.rstrip!.gsub!(/#/,'').gsub!(/\s/,"%20") unless tagSet.empty?
      tagUrl = @tagUrl + '/services/getSolrMappingsForTagSet.json?tags=' + tagSet
      @jsonTagCat = JSON.parse(open(tagUrl).read)
    end


    def load_annotations(json)
      annotations = Hash.new
      json.each do |annotation|
        annotations[annotation['@id']] = annotation
      end
      annotations
    end

    def add_to_solr(annotations)
      puts 'connection made for add/update to: ' + @solrUrl.to_s
      solr = RSolr.connect :url => @solrUrl
      #puts 'annotations count = ' + annotations.count().to_s
      x = 0
      annotations.each_slice(1000) { |annotations|
        solr.add annotations
        solr.commit
        x += 1
        p x
      }
    end

    def delete_from_solr(annotation)
      solr = RSolr.connect :url => @solrUrl
      puts 'connection made for deletion by query'
      #response = solr.delete_by_id annotation['@id']
      response = solr.delete_by_query 'annotation_id_s:"' + annotation['@id'] + '"'
      puts 'response = ' + response.to_s
      solr.commit
    end
  end
