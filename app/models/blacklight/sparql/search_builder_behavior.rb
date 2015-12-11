module Blacklight::Sparql
  module SearchBuilderBehavior
    extend ActiveSupport::Concern

    included do
      self.default_processor_chain = [
        :add_query_to_sparql,
        :add_facetting_to_sparql, :add_sparql_fields_to_query, :add_paging_to_sparql,
        :add_sorting_to_sparql, :add_group_config_to_sparql,
        :add_facet_paging_to_sparql
      ]
    end

    ##
    # Take the user-entered query, and put it in the SPARQL params,
    # including config's "search field" params for current search field.
    # also include setting spellcheck.q.
    def add_query_to_sparql(sparql_parameters)
      ###
      # Merge in search field configured values, if present, over-writing general defaults

      if search_field
        sparql_parameters.merge!( search_field.sparql_parameters) if search_field.sparql_parameters
      end

      ##
      # Create XXX 'q' including the user-entered q
      ##
      if blacklight_params[:q].is_a? Hash
        q = blacklight_params[:q]
        raise "FIXME, translation of Solr search for SPARQL"
      elsif blacklight_params[:q]
        sparql_parameters[:q] = blacklight_params[:q]
      end
    end

    ##
    # Add appropriate SPARQL facetting filters.
    def add_facetting_to_sparql sparql_parameters
      facet_fields_to_include_in_request.each do |field_name, facet|
        sparql_parameters[:facet] ||= true

        case
          when facet.pivot
            raise "FIXME: SPARQL pivot?"
            #sparql_parameters.append_facet_pivot facet.pivot.join(",")
          when facet.query
            sparql_parameters.append_facet_query facet.query.map { |k, x| x[:fq] }
          else
            sparql_parameters.append_facet_fields facet.field
        end

        if facet.sort
          sparql_parameters[:sort] = facet.sort
        end

        # Support facet paging and 'more'
        # links, by sending a facet.limit one more than what we
        # want to page at, according to configured facet limits.
        sparql_parameters[:limit] = (facet_limit_for(field_name) + 1) if facet_limit_for(field_name)
      end
    end

    def add_sparql_fields_to_query sparql_parameters
      sparql_parameters[:show_fields] = blacklight_config.show_fields.select(&method(:should_add_field_to_request?)).values
    end

    ###
    # copy paging params from BL app over to SPARQL, changing
    # app level per_page and page to Solr rows and start.
    def add_paging_to_sparql sparql_parameters
      rows(sparql_parameters[:rows] || 10) if rows.nil?

      sparql_parameters[:rows] = rows

      if start != 0
        sparql_parameters[:rows] = start
      end
    end

    ###
    # copy sorting params from BL app over to solr
    def add_sorting_to_sparql sparql_parameters
      sparql_parameters[:sort] = sort unless sort.blank?
    end

    # Remove the group parameter if we've faceted on the group field (e.g. for the full results for a group)
    def add_group_config_to_sparql sparql_parameters
      if blacklight_params[:f] && blacklight_params[:f][blacklight_config.index.group]
        sparql_parameters[:group] = false
      end
    end

    def add_facet_paging_to_sparql sparql_parameters
      return unless facet.present?

      facet_config = blacklight_config.facet_fields[facet]

      # Now override with our specific things for fetching facet values
      sparql_parameters[:"facet.field"] = facet

      limit = if scope.respond_to?(:facet_list_limit)
                scope.facet_list_limit.to_s.to_i
              elsif sparql_parameters["facet.limit"]
                sparql_parameters["facet.limit"].to_i
              else
                20
              end

      page = blacklight_params.fetch(request_keys[:page], 1).to_i
      offset = (page - 1) * (limit)

      sort = blacklight_params[request_keys[:sort]]
      prefix = blacklight_params[request_keys[:prefix]]

      # Need to set as f.facet_field.facet.*  to make sure we
      # override any field-specific default in the solr request handler.
      sparql_parameters[:"f.#{facet}.facet.limit"] = limit + 1
      sparql_parameters[:"f.#{facet}.facet.offset"] = offset
      if blacklight_params[request_keys[:sort]]
        sparql_parameters[:"f.#{facet}.facet.sort"] = sort
      end
      if blacklight_params[request_keys[:prefix]]
        sparql_parameters[:"f.#{facet}.facet.prefix"] = prefix
      end
      sparql_parameters[:rows] = 0
    end

    def facet_fields_to_include_in_request
      blacklight_config.facet_fields.select do |field_name,facet|
        facet.include_in_request || (facet.include_in_request.nil? && blacklight_config.add_facet_fields_to_sparql_request)
      end
    end

    def request_keys
      blacklight_config.facet_paginator_class.request_keys
    end
  end
end