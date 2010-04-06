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