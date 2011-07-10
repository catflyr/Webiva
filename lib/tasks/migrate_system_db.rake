namespace "cms" do 
	desc "Migrate the system database"
	task :migrate_system_db => [:environment] do |t|
	
    require 'active_record/schema_dumper'
    require 'logger'
    
    version = ENV["VERSION"] ? ENV["VERSION"].to_i : nil
    
    main_db = YAML.load_file("#{Rails.root}/config/cms_migrator.yml")

    ActiveRecord::Base.logger = Logger.new(STDOUT)
    ActiveRecord::Base.establish_connection(main_db[Rails.env])
    ActiveRecord::Migrator.migrate("#{Rails.root}/db/system_migrate/",version)
	
	
  end
end
