require 'active_record'
require 'action_mailer'
require 'yaml'

class Mailer < ActionMailer::Base
  def email(to, from, subject)
    mail(:to      => to,
         :from    => from,
         :subject => subject)
  end
end

class WatchGou
  def row_count_query(table)
    "SELECT COUNT(*) FROM #{table}"
  end
  
  def row_count(table)
    ActiveRecord::Base.connection.select_value(row_count_query table).to_i
  end
  
  def current_mode
    @mode ||= ENV["WATCH_GOU_MODE"] || "development"
  end
  
  def parse_config(file_name)
    puts "loading config/#{file_name}.yml"
    config_file = YAML.load_file("config/#{file_name}.yml")
    config_file[current_mode]
  end
  
  def load_mail_config
    mail = parse_config "mail"

    ActionMailer::Base.raise_delivery_errors = mail["raise_delivery_errors"]
    ActionMailer::Base.delivery_method       = mail["delivery_method"].to_sym
    ActionMailer::Base.smtp_settings = {
       :address              => mail["address"],
       :port                 => mail["port"],
       :domain               => mail["domain"],
       :authentication       => mail["authentication"].to_sym,
       :user_name            => mail["user_name"],
       :password             => mail["password"],
       :enable_starttls_auto => mail["enable_starttls_auto"]
    }

    @email = Mailer.email(mail["to"], mail["from"], mail["subject"])
  end
  
  def load_db_config
    db = parse_config "database"
  
    ActiveRecord::Base.establish_connection(
      :adapter  => db["adapter"],
      :host     => db["host"],
      :database => db["database"],
      :username => db["username"],
      :password => db["password"]
    )
  end
  
  def load_config
    puts "Current mode: #{current_mode}"
    config     = parse_config "config"
    @frequency = config["frequency"] 
    @max_tries = config["max_tries"] 

    load_db_config 
    load_mail_config
  end
  
  def init
    load_config
  
    ActiveRecord::Base.connection.tables.map do |t|
      puts "Initializing table: #{t}"
      count = row_count(t)
      {
        :table_name  => t,
        :row_count   => count
      }
    end
  end
  
  def run
    tables = init
  
    puts "\nStarting up watch dog in #{current_mode} mode.... Ctrl-C to exit"
    puts "Checking all the tables every #{@frequency} minutes"
    
    retries = 0
    while true
      sleep(@frequency * 60) 
    
      db_active = false
    
      tables.each do |t|
        current_count = row_count(t[:table_name])
        if current_count != t[:row_count]
          db_active = true
          retries   = 0
        end
    
        t[:row_count] = current_count
      end
    
      if not db_active
        if retries < @max_tries
          puts "DB doesn't appear to be active... sending notification..."
          @email.deliver
          retries += 1
        else
          puts "Max tries reached, exiting..."
          exit
        end
      else
        puts "Looks like there's some activities going on in your DB..."
      end
    end
  end
end

WatchGou.new.run
