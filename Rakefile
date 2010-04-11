require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "mysql_mirror" 
    gemspec.summary = "Helps mirror MySql Databases"
    gemspec.description = "Will mirror tables / databases between mysql databases and across hosts"
    gemspec.email = "peterleonhardt@gmail.com"
    gemspec.homepage = "http://github.com/pjleonhardt/mysql_mirror"
    gemspec.authors = ["Peter Leonhardt", "Joe Goggins"]      
    gemspec.files = FileList["[A-Z]*", "lib/mysql_mirror.rb"]
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Please install the jeweler gem."
end

Dir["#{File.dirname(__FILE__)}/tasks/*.rake"].sort.each { |ext| load ext }


desc 'Run the demo/test cases'
task :demo do
  require 'lib/mysql_mirror'
  puts 'MySqlMirror Demo'
  # Basic usage, copy production db to development
  #     @m = MysqlMirror.new({
  #      :source => :production,
  #      :target => :development
  #    })
  # 
  # Choose what tables you want to bring over and how you want to scope them...
  #    @m = MysqlMirror.new({
  #      :source => :production,
  #      :target => :development,
  #      :tables => [:users, :widgets],
  #      :where => {:users => "is_admin NOT NULL"},
  #    })
  # 
  # Database information not in your database.yml file? (Or Not Running Rails?) No Problem!
  #    @m = MysqlMirror.new({
  #      :source => { :database => "app_production", :user => ..., :password => ..., :hostname => ...},
  #      :target => {:database => "app_development", :hostname => 'localhost'}
  #    })
  # 
  # Want to use everything in :production environment (user, pass, host) but need to change the database?
  #    @m = MysqlMirror.new({
  #      :source => :production,
  #      :override => {:source => {:database => "heavy_calculations_database"}},
  #      :target => :production
  #    })
  require 'ostruct'
  @demos = []
  @demos << OpenStruct.new(:name => "Basic usage, copy production db to development",
                           :code => Proc.new {
                            @m = MysqlMirror.new({
                              :source => :production,
                              :target => :development
                            })
                          })
  @demos.each do |demo|
    demo.code.call(binding)
    puts @m.inspect
  end
    
end