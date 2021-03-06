module Api
  module V1
    class DataController < ActionController::Base

      include ApplicationHelper

      def index

        if params[:id].present?
          project = Project.find(params[:id])
          resource = DatapackageResource.where(datapackage_id: project.datapackage.id,table_ref: "#{params[:table_ref]}").first
          table_with_scopes = get_mira_ar_table("#{resource.db_table_name}")
        elsif params[:db_table].present?
          table_with_scopes = get_mira_ar_table(params[:db_table])
        else
          raise "Unexpected url reaching data#index action"
        end

        query_params = request.query_parameters

        # create active record table with scopes
        scope = table_with_scopes.unscoped

        # extract the sort order column
        order_columns = query_params.delete(:order)
        # extract select columns
        select_columns = query_params.delete(:select_columns)
        # extract the 'echo_params' parameter
        echo_params = query_params.delete(:echo_params)
        # get the per page, taking account default and maximum
        per_page_num = query_params.delete(:per_page).to_i || Rails.configuration.x.api_default_per_page
        per_page_num = [Rails.configuration.x.api_max_per_page, per_page_num].min

        (order_columns || "").split(",").each do |column|
          sort_column, sort_direction = (column || "").split(":")
          sort_direction = sort_direction == "desc" ? "desc" : "asc"
          scope = scope.order(sort_column.to_sym => sort_direction.to_sym) unless sort_column.nil?
        end

        if !select_columns.nil?
          sc = (select_columns.split(",") + ["id"]).uniq # always return id
          scope = scope.select(sc) # seems can't use pluck here as it does not return a relation. Had intended using below:
          # apply select (pluck faster than select - http://stackoverflow.com/a/27995494/1002140)
          # scope = scope.pluck(*sc).map{|a| Hash[*sc.zip(a).flatten]} unless select_columns.nil?
        end

        # apply each scope
        query_params.each do |key,value|
          scope = scope.send(key,value)
        end

        results = {}
        if !echo_params.nil?
          results[:params] = request.env["rack.request.query_hash"] if echo_params.upcase == "TRUE"
        end

        results[:data] = paginate scope, per_page: per_page_num
        render json: results


      end



      def datatables

        project = Project.find(params[:id])
        resource = DatapackageResource.where(datapackage_id: project.datapackage.id,table_ref: "#{params[:table_ref]}").first

        # create active record table with scopes
        table_with_scopes = get_mira_ar_table("#{resource.db_table_name}")
        scope = table_with_scopes.unscoped

        per_page_num = @_params["length"].to_i
        # Datatables sends a start observations rather than a page number so
        # we infer the page number
        dt_draw = @_params["draw"]
        dt_start = @_params["start"].to_i
        # the api-pagination gem accesses the param[:page] parameter. As
        # datatables doesn't use the same parameter we add it in manually.
        params[:page] = 1 + (dt_start.to_i)/per_page_num


        range_filter_columns = @_params["lower_range_values"].nil? ? [] : @_params["lower_range_values"].keys

        # column search strings (we exclude those columns where we do column range filtering
        # as we get this information from the 'lower_range_values' and 'upper_range_values')
        contains_filters = {} # hash with column names => search strings
        @_params["columns"].each do |k,v|
          if !range_filter_columns.include?(v["data"]) && v["search"]["value"].length > 0
            contains_filters[v["data"]] = v["search"]["value"]
          end
        end

        # apply each scope from query string
        query_params = get_query_string_params(@_params)
        query_params.each do |key,value|
          scope = scope.send(key,value)
        end

        # apply simple contains search scopes
        contains_filters.each do |k,v|
          scope = scope.send(k + "_contains", v)
        end

        # column range filter: greater than or equal to
        lrv_hash = @_params["lower_range_values"] || {}
        lrv_hash.each do |k,v|
          if is_number? v
            scope = scope.send(k + "_ge", v)
          elsif v.length > 0
            scope = scope.none
          end
        end

        # column range filter: less than or equal to
        urv_hash = @_params["upper_range_values"] || {}
        urv_hash.each do |k,v|
          if is_number? v
            scope = scope.send(k + "_le", v)
          elsif v.length > 0
            scope = scope.none
          end
        end

        # column ordering
        @_params["order"].each do |k,v| # e.g. {"0"=>{"column"=>"0", "dir"=>"asc"}}
          sort_column_key = v["column"]
          sort_column = @_params["columns"][sort_column_key]["data"]
          sort_direction = v["dir"]
          scope = scope.order(sort_column => sort_direction) unless sort_column.nil?
        end

        # see the Datatables server processing documention => it expects a response
        # which includes "data", "recordsTotal", "recordsFiltered" and "draw"
        results = {}
        results[:data] = paginate scope, per_page: per_page_num
        results[:recordsTotal] = response.headers[ApiPagination.config.total_header]
        results[:recordsFiltered] = results[:recordsTotal] # don't yet know exactly what this is for
        results[:draw] = dt_draw
        render json: results
      end



      def distinct
        project = Project.find(params[:id])
        resource = DatapackageResource.where(datapackage_id: project.datapackage.id,table_ref: "#{params[:table_ref]}").first

        query_params = request.query_parameters
        per_page_num = query_params.delete(:per_page).to_i || Rails.configuration.x.api_default_per_page
        per_page_num = [Rails.configuration.x.api_max_per_page, per_page_num].min

        # extract the sort order (in this case it is either order=asc or order=desc)
        o = query_params.delete(:order)
        order = (["asc", "desc"].include? o) ? o : "asc"

        column = params[:col_ref].parameterize
        uniq_method = "#{column}_uniq".to_sym
        table_const = get_mira_ar_table("#{resource.db_table_name}")

        if table_const.respond_to? uniq_method
          distinct_values = paginate table_const.order(column.to_sym => order.to_sym).send(uniq_method), per_page: per_page_num
          render json: distinct_values
        else
          render json: {"Message" => "The API does not support getting distinct '#{column}' values from the '#{params[:table_ref]}' table"}
        end

      end


      private

        def get_query_string_params(params)
          query_params = params.select do |k,v|
            ksplit = k.split("_")
            if ksplit.length > 1
              true if ["eq", "ne", "contains", "ends", "begins", "le", "lt", "ge", "gt"].include? ksplit.last
            end
          end
        end


    end
  end
end
