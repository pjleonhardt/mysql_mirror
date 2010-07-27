require 'active_record'
require 'fileutils'

class MysqlMirror
  class MysqlMirrorException < Exception; end
  
  class Source < ActiveRecord::Base
  end
  
  class Target < ActiveRecord::Base
  end
  
  attr_accessor :tables, :where, :mysqldump_options
  
  def initialize(options = {})
    unless ([:source, :target] - options.keys).blank?
      # Need to specify a Source and Target database
      raise MysqlMirrorException.new("You must specify both Source and Target connections")
    end
    
    self.tables = options.delete(:tables)
    self.where  = options.delete(:where)
    
    overrides = options.delete(:override)       || {}
    source_override = overrides.delete(:source) || {}
    target_override = overrides.delete(:target) || {}
    
    # set default mysqldump options
    self.mysqldump_options = {
      "compact" => "TRUE",
      "max_allowed_packet" => 100553296,
      "extended-insert" => "TRUE",
      "lock-tables" => "FALSE",
      "add-locks" => "FALSE",
      "add-drop-table" => "FALSE"      
    }
        
    @source_config = get_configuration(options.delete(:source))
    @target_config = get_configuration(options.delete(:target))
    
    @source_config.merge!(source_override)
    @target_config.merge!(target_override)    
    
    # @commands is an array of methods to call
    if mirroring_same_host?
      @commands = commands_for_local_mirror
    else
      @commands = commands_for_remote_mirror
    end
  end
  
  def commands_for_local_mirror
    [:local_copy]
  end
  
  def commands_for_remote_mirror
    [ 
      :remote_mysqldump,
      :remote_tmp_file_table_rename,
      :remote_insert_command,
      :remote_rename_tmp_tables,
      :remote_remove_tmp_file 
    ]
  end
  
  def mirroring_same_host?
    @source_config[:host] == @target_config[:host]
  end
  
  def execute!
    @start_time = Time.now
    @source = connect_to(:source)
    @target = connect_to(:target)
    
    @commands.each do |c|
      self.send(c)
    end
  end
  
  def to_s
    "Mirroring #{self.tables.join(', ')} from #{@source_config[:host]}.#{@source_config[:database]} to #{@target_config[:host]}.#{@target_config[:database]}"
  end
  
private
  #   e.g, connect_to(:source)
  #      => MysqlMirror::Source.establish_connection(@source_config).connection
  #
  def connect_to(which)
    "MysqlMirror::#{which.to_s.classify}".constantize.establish_connection(self.instance_variable_get("@#{which}_config")).connection
  end

  def local_copy
    get_tables.each do |table|
      target_db = @target_config[:database]
      source_db = @source_config[:database]
      target_table     = "`#{target_db}`.`#{table}`"
      target_tmp_table = "`#{target_db}`.`#{table}_MirrorTmp`"
      target_old_table = "`#{target_db}`.`#{table}_OldMarkedToDelete`"
      source_table     = "`#{source_db}`.`#{table}`"
      
      
      prime_statement_1  = "DROP TABLE IF EXISTS #{target_tmp_table}"
      prime_statement_2  = "CREATE TABLE IF NOT EXISTS #{target_table} LIKE #{source_table}"
      
      create_statement = "CREATE TABLE #{target_tmp_table} LIKE #{source_table}"
      
        select_clause = "SELECT * FROM #{source_table}"
        select_clause << " WHERE #{self.where[table]}" unless (self.where.blank? or self.where[table].blank?)
      
      insert_statement  = "INSERT INTO #{target_tmp_table} #{select_clause}"
      rename_statement  = "RENAME TABLE #{target_table} TO #{target_old_table}, #{target_tmp_table} TO #{target_table}"
      cleanup_statement = "DROP TABLE IF EXISTS #{target_old_table}"
      
      staments_to_run = [prime_statement_1, prime_statement_2, create_statement, insert_statement, rename_statement, cleanup_statement]
      
      staments_to_run.each do |statement|
        @target.execute(statement)
      end
    end    
  end
  
  def mysqldump_command_prefix
    "mysqldump " << self.mysqldump_options.map {|x| "--#{x[0]}=#{x[1]}" }.join(" ")
  end
  
  def remote_mysqldump
    @tmp_file_name = "mysql_mirror_#{@start_time.to_i}.sql"
    tables = get_tables.map(&:to_s).join(" ")
    
    if self.where.blank?
      where = ""
    else
      where_statement = self.where.values.first
      where = "--where=\"#{where_statement}\""
    end

    config = "-u#{@source_config[:username]} -p'#{@source_config[:password]}' -h #{@source_config[:host]} #{@source_config[:database]}"
    
    the_cmd = "#{mysqldump_command_prefix} #{where} #{config} #{tables} > #{@tmp_file_name}"
    puts the_cmd
    `#{the_cmd}`
  end
  
  def remote_tmp_file_table_rename
    create_or_insert_regex = Regexp.new('(^CREATE TABLE|^INSERT INTO)( `)(.+?)(`)(.+)')
    new_file_name = @tmp_file_name + ".replaced.sql"
    
    new_file = File.new(new_file_name, "w")
    IO.foreach(@tmp_file_name) do |line|
      if match_data = line.match(create_or_insert_regex)
        table_name = match_data[3]
        new_table_name = "#{table_name}_#{@start_time.to_i}"
        new_file.puts match_data[1] + match_data[2] + new_table_name + match_data[4]+ match_data[5]
      else
        new_file.puts line
      end
    end
    new_file.close
    # replace dump'd sql file with this gsub'd one
    FileUtils.move(new_file_name, @tmp_file_name)
  end
  
  def remote_insert_command
    config = "-u#{@target_config[:username]} -p'#{@target_config[:password]}' -h #{@target_config[:host]} #{@target_config[:database]}"
    the_cmd = "mysql #{config} < #{@tmp_file_name}"
    `#{the_cmd}`
  end
  
  def remote_rename_tmp_tables
    get_tables.each do |table|
      tmp_table_name = "#{table}_#{@start_time.to_i}"
      old_table_name = "#{table}_OldMarkedToDelete"
      
      @target.transaction do 
        @target.execute("DROP TABLE IF EXISTS #{old_table_name}")
        @target.execute("RENAME TABLE #{table} TO #{old_table_name}, #{tmp_table_name} TO #{table}")
        @target.execute("DROP TABLE IF EXISTS #{old_table_name}")        
      end
    end 
  end
  
  def remote_remove_tmp_file
    FileUtils.rm(@tmp_file_name)
  end
  
  def get_tables
    the_tables = self.tables.blank? ? @source.select_values("SHOW TABLES").map!(&:to_sym) : self.tables
  end


  def get_configuration(env_or_hash)
    config = env_or_hash
    
    if(env_or_hash.is_a? Symbol)
      config = ActiveRecord::Base.configurations[env_or_hash.to_s]
    end
    
    config.symbolize_keys
  end
  
end









