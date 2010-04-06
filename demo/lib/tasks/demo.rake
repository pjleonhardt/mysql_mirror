namespace :demo do
  desc "requirements for the basic demo"
  task :instructions do
    s =<<-EOS
---
Setup privileged MySql user accounts and add this to database.yml
	demo_local:
		adapter: mysql
		database: mm_demo_local_source
		username: root
		password: 
		socket: /tmp/mysql.sock

	demo_remote:
		adapter: mysql
		database: mm_demo_remote_source
		username: <SOME_PRIVILEGED_ACCOUNT>
		password: 
		host: <SOME_HOST>

---

These users will need root privileges
EOS
  end

	desc "Setup the demo"
	task :setup => ["demo:instructions", "environment"] do
      		
	end
	desc "Run the demo"
	task :run => :environment do
		
	end
end
