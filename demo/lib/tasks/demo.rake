namespace :demo do
  desc "requirements for the basic demo"
  task :instructions do
    s =<<-EOS
---
Setup privileged MySql user accounts and add this to database.yml
	development:
		adapter: mysql
		database: mm_demo_local_source
		username: root
		password: 
		socket: /tmp/mysql.sock

	production:
		adapter: mysql
		database: mm_demo_remote_target
		username: <SOME_PRIVILEGED_ACCOUNT>
		password: 
		host: <SOME_HOST>

---

These users will need root privileges
EOS
  end

	desc "Setup the demo"
	task :setup => ["demo:instructions", "environment", "db:create","db:migrate","db:fixtures:load"] do
    puts "mkay, you should be able do rake demo:run now"
	end
	desc "Run the demo"
	task :run => ['environment'] do
		require '../lib/mysql_mirror'
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
end
