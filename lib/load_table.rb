require 'csv'
require 'tempfile'
require 'load_dynamic_AR_class_with_scopes'

class LoadTable

  include ApplicationHelper

  attr_reader :table_name, :column_list, :column_type_hash


  def initialize(datasource, datapackage_resource, upload_method)
    @ds = datasource
    # @datapackage_resources = DatapackageResource.where(datapackage_id: @ds.datapackage_id)
    @datapackage_resource = datapackage_resource
    load_logger.info("Initialising load of #{@datapackage_resource.table_ref}")
    @column_metadata = DatapackageResourceField.where(datapackage_resource_id: @datapackage_resource.id)
    @csv_file = convert_to_utf8_encoding(File.open(@ds.datafile.path))
    @upload_method = upload_method

    upload_to_db_table

  end


  private

  def convert_to_utf8_encoding(original_file)
    original_string = original_file.read
    final_string = original_string.encode(invalid: :replace, undef: :replace, replace: '') #If you'd rather invalid characters be replaced with something else, do so here.
    final_file = Tempfile.new('import') #No need to save a real File
    final_file.write(final_string)
    final_file.close #Don't forget me
    final_file
  end

  def load_logger
    log_dir = Project.find(@ds.project_id).job_log_path
    Dir.mkdir(log_dir) unless File.directory?(log_dir)
    @load_logger ||= Logger.new("#{log_dir}/#{@ds.datafile_file_name}.log")
  end


  def new_col_name(name)
    # NOTE: better not to try maintaining case of variables as uppercase column names
    # leads to problems later when creating scopes dynamically (ruby starts looking for constants).
    name.parameterize.underscore
  end


  def upload_to_db_table
    if @upload_method == "quick"
      quick_upload_to_db_table
    else
      slow_upload_to_db_table
    end
  end


  def slow_upload_to_db_table
    ar_table_klass = get_mira_ar_table(@datapackage_resource.db_table_name)
    uploaded_row_count = 0
    CSV.foreach(@csv_file,
                :headers => true,
                :header_converters => lambda { |h| new_col_name(h) }) do |row|
      next if row.to_s.strip.size == 0
      if ar_table_klass.create!(row.to_hash)
        uploaded_row_count += 1
      else
        load_logger.error("Failed to upload row " + (uploaded_row_count + 1).to_s )
      end
    end
    save_row_count(uploaded_row_count)
  end


  def quick_upload_to_db_table
    # columns in correct order
    column_names = @column_metadata.sort{ |a,b| a.order <=> b.order }.map{ |c| new_col_name(c.name) }
    column_string = "\"#{column_names.join('","')}\""
    csv_options = "DELIMITER '#{@datapackage_resource.delimiter}' CSV"
    skip_header_line = @csv_file.gets
    uploaded_row_count = 0
    # https://github.com/theSteveMitchell/postgres_upsert
    ActiveRecord::Base.connection.raw_connection.copy_data "COPY #{@datapackage_resource.db_table_name} (#{column_string}) FROM STDIN #{csv_options} QUOTE '#{@datapackage_resource.quote_character}'" do
      while line = @csv_file.gets do
        next if line.strip.size == 0
        ActiveRecord::Base.connection.raw_connection.put_copy_data line
        uploaded_row_count += 1
      end
    end
    save_row_count(uploaded_row_count)
  end

  def save_row_count(uploaded_row_count)
    @datapackage_resource.imported_rows = uploaded_row_count
    @datapackage_resource.save
    load_logger.info("Imported " + uploaded_row_count.to_s + " rows of data.")
  end
end
