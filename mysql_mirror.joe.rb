
class MysqlMirror
  class Source < ActiveRecord::Base
  end

  class Target < ActiveRecord::Base
  end
  attr_accessor :source_config, :target_config, :commands, :source_connection, :target_connection, :strategy
  def initialize(options={})

    @timestamp = Time.now.to_i
    @temp_file_name = "mysql_mirror_#{@timestamp.to_s}.sql"
    @strategy = options[:strategy] || :bomb_and_rebuild
    @commands = []
   
    unless ([:source, :target] - options.keys).empty?
      raise "Must specify a source and target"
    end
    @source_config = ActiveRecord::Base.configurations[options[:source]]
    @target_config = ActiveRecord::Base.configurations[options[:target]]
    if @source_config == @target_config # needed when on same host, otherwise later changes to one happen to the other
      @target_config = @source_config.clone
    end
    if (not @source_config.kind_of? Hash)
      raise "source_config must be valid config hashes like found in database.yml"
    end
    if (not @target_config.kind_of? Hash)
      raise "target_config must be valid config hashes like found in database.yml"
    end
    
    if options[:source_override].kind_of? Hash
      @source_config.merge! options[:source_override]
    end
    if options[:target_override].kind_of? Hash
      @target_config.merge! options[:target_override]
    end
    if options[:source_tables].kind_of? Array and (not options[:source_tables].empty?)
      @source_config[:tables] = options[:source_tables]
    end

    if options[:source_where].kind_of? String and (not options[:source_where].blank?)
      @source_config[:where] = options[:source_where]
    end

    Source.establish_connection @source_config
    @source_connection = Source.connection
    Target.establish_connection @target_config
    @target_connection = Target.connection


    # going to set 'host' key to 'localhost' for mysqldump and mysql binary usage
    # MUST be done after establish_connection
    if @source_config['host'].blank? and (not @source_config['socket'].blank?)
      @source_config['host'] = 'localhost' 
    end
    
    if @target_config['host'].blank? and (not @target_config['socket'].blank?)
      @target_config['host'] = 'localhost' 
    end

    case @strategy
    # This is designed to be runnable on production systems as the target without any
    # disruption, IT CURRENTLY HAS SOME BUGS...#Mysql::Error: Can't find file: './warehouse/ps_person.frm' (errno: 2): RENAME TABLE ps_person TO ps_person_OLD_marked_to_delete, ps_person_1265222838 TO ps_person;
    #
    when :atomic_rename
      @commands << mysqldump_command
      @commands << {:method => :rename_tables_in_temp_file}
      @commands << insert_command 
      @commands << {:method => :rename_temp_tables_on_target}
      @commands << remove_temp_file_command
    # Adds a drop-table clause to the mysqldump output, any tables that exist on the target
    # are NOT destroyed
    #
    when :bomb_and_rebuild
      @commands << mysqldump_command
      @commands << insert_command 
      @commands << remove_temp_file_command
    # Just like above except, also destroyes any tables on the
    # target as well (those tables not-mentioned in the mysqldump are dropped as well)
    #
    when :bomb_everything_first_then_rebuild
      @commands << {:method => :destroy_all_tables_on_target}
      @commands << mysqldump_command
      @commands << insert_command 
      @commands << remove_temp_file_command
    else
      raise "Invalid strategy #{@strategy}"
    end
  end

  def rename_tables_in_temp_file
    create_or_insert_into_table_regex = Regexp.new('(^CREATE TABLE|^INSERT INTO)( `)(.+?)(`)(.+)')
    new_file_name = @temp_file_name + ".replaced.sql"
    new_file = File.new(new_file_name, 'w')
		IO.foreach(@temp_file_name) do |line|
			if match_data = line.match(create_or_insert_into_table_regex)
				table_name = match_data[3]
        new_table_name = "#{table_name}_#{@timestamp}"
        new_file.puts match_data[1] + match_data[2] + new_table_name + match_data[4] + match_data[5]
      else
        new_file.puts line
			end
		end
    new_file.close
    # Replace the dump file with the gsubbed one
    puts "Replacing dump file with gsubbed table names..."
    require 'fileutils'
    FileUtils.move(new_file_name, @temp_file_name)
  end

  # WARNING: This is designed to be invoked from a rake task,
  # you could get unpredictable results if you invoke this from a passenger or mongrel rails production env
  # due to the default connection for other active record classes potentially being changed
  def rename_temp_tables_on_target
    if @source_config[:tables].blank? || @source_config[:tables].empty?
      the_tables_to_rename = @source_connection.select_values "show tables"
    else
      the_tables_to_rename = @source_config[:tables]
    end
    the_tables_to_rename.each do |table_name|
      temp_table_name = "#{table_name}_#{@timestamp}"
      old_table_name  = "#{table_name}_OLD_marked_to_delete"
      # Rename old table to #{old_table_name}, rename new table to table_name
      # Then Drop the old table
      @target_connection.transaction do
        #remove any stale OLD tables
        @target_connection.execute("DROP TABLE IF EXISTS #{old_table_name}")
        @target_connection.execute("RENAME TABLE #{table_name} TO #{old_table_name}, #{temp_table_name} TO #{table_name};")
        # remove the old data
        @target_connection.execute("DROP TABLE IF EXISTS #{old_table_name}")
      end
#      @target_connection.transaction do
#        @target_connection.execute("DROP TABLE IF EXISTS #{table_name}")
#        @target_connection.rename_table(temp_table_name, table_name)
#      end
    end
  end

  def remove_temp_file_command
    "rm #{@temp_file_name}"
  end

  # Helper method nothing more
  def password_clause
   @target_config['password'].blank? ? "" : "-p'#{@target_config['password']}'"
  end
  
  def insert_command
    "mysql -u#{@target_config['username']} #{password_clause} -h #{@target_config['host']} #{@target_config['database']} < #{@temp_file_name}"
  end

  def destroy_all_tables_on_target
    Target.connection.select_values('show tables').each do |t|
      Target.connection.execute "DROP TABLE #{t}"
    end
  end
  
  # Default invocation syntax
  #
  def mysqldump_command_prefix
    base = "mysqldump --compact=TRUE --max_allowed_packet=100663296 --extended-insert=TRUE --lock-tables=FALSE --add-locks=FALSE "
    case @strategy
    when :atomic_rename
      base + "--add-drop-table=FALSE"
    when :bomb_and_rebuild, :bomb_everything_first_then_rebuild
      base + "--add-drop-table=TRUE"
    else
      raise "invalid strategy."
    end
  end

  def mysqldump_command
    tables_string = @source_config[:tables].nil? ? "" : @source_config[:tables].join(" ")
    where_string = @source_config[:where].nil? ? "" : "--where=\"#{@source_config[:where]}\""
    password_clause = @source_config['password'].blank? ? "" : "-p'#{@source_config['password']}'"
    "#{mysqldump_command_prefix} #{where_string} -u#{@source_config['username']} #{password_clause} -h #{@source_config['host']} #{@source_config['database']} #{tables_string} > #{@temp_file_name}"
  end

  def to_s(mode=:short_obfuscated)
    case mode
    when :short_obfuscated
          source_temp = @source_config
          source_temp['password'] ='XXXXXXXX'
          target_temp = @target_config
          target_temp['password'] = 'YYYYYYYYYYYYYY'
          @source_config_string = @sourc
          s = <<-EOS
      SOURCE CONFIG:
      #{source_temp.inspect}

      TARGET CONFIG:
      #{target_temp.inspect}

          EOS
    when :long
      s = <<-EOS
Mirror Stategy: #{@strategy}

Source Config:  #{@source_config.inspect}

Target Config:  #{@target_config.inspect}

COMMANDS:
     EOS
     @commands.each do |c|
       if c.kind_of? Hash
         s << "[Ruby method]: #{c[:method].to_s}"
       else
         s << "[Shell Command]: #{c}"
       end
       s << "\n\n"
     end
     s
    end
  end
  def execute
    @global_start_time = Time.now
    puts "Starting MysqlMirror from #{@source_config['database']} to #{@target_config['database']} at #{@global_start_time}..."
    @commands.each do |c|
      start_time = Time.now
      if c.kind_of? String
        puts "Executing Shell Command..."
        puts c
        `#{c}`
      elsif c.kind_of? Hash and c[:method].kind_of? Symbol
        if self.respond_to? c[:method]
          self.send c[:method]
        else
          raise "Undefined :method \"#{c[:method].to_s}\""
        end
      else
        raise "Something is amis with your command #{c}"
      end
      puts "Took #{Time.now.to_i - start_time.to_i} seconds."
    end 
    @global_end_time = Time.now
    puts "Finished MysqlMirror at #{@global_end_time}, took #{@global_end_time.to_i - @global_start_time.to_i} seconds."
  end
end
