#!/usr/local/bin/ruby

@base_uri      = ENV["CLARA_BASE_URI"]       || 'http://192.168.8.1/api'
@data_dir      = ENV["CLARA_DATA_DIR"]       || 'data'
@log_level     = ENV['CLARA_LOG_LEVEL']      || 'info'
fetch_interval = ENV["CLARA_FETCH_INTERVAL"] || 10

require_relative 'libs/logging.rb'
require_relative 'libs/hilink.rb'
require_relative 'libs/messages.rb'
require_relative 'libs/recipients.rb'

def updates_messages(messages)
  new_messages = fetch_sms
  unless new_messages.empty?
    messages = messages.concat(new_messages).sort_by{|m| m['date']}.uniq
    write_inbox(messages)
  end
  return messages, new_messages
end

def join_recipient(message)
  phone = message['phone']
  name  = message['content'].split(/\s+/)[1]
  unless @recipients.has_key?(phone) || name.nil?
    @recipients[phone] = {'name' => name[0,10], 'role' => 'nobody'}
    write_recipients
  end
end

def activate_recipient(message)
  admin_phone = message['phone']
  recipient_name = message['content'].split(/\s+/)[1] || ''
  recipient_phone = @recipients.select{|p, r| r['name'].downcase == recipient_name[0,10].downcase}.keys.first
  
  if recipient_admin?(admin_phone)
    if recipient_phone
      unless recipient_active?(recipient_phone)
        @recipients[recipient_phone]['role'] = 'user'
        write_recipients
        send_sms([admin_phone, recipient_phone], %Q(Clara: recipient "#{recipient_name}" with phone number #{recipient_phone} has been activated.))
      else
        send_sms(admin_phone, %Q(Clara: recipient "#{recipient_name}" is already activated.))        
      end
    else
      send_sms(admin_phone, %Q(Clara: recipient not joined or invalid name "#{recipient_name}".))
    end
  end
end

def leave_recipient(message)
  phone = message['phone']
  if @recipients.has_key?(phone) && recipient_active?(phone)
    @recipients[phone]['role'] = 'nobody'
    write_recipients
    send_sms(phone, %Q(Clara: you have left the group chat.))
  end
end

def bulk_message(message)
  sender_phone = message['phone']
  sender_name = recipient_name(sender_phone)
  phones = @recipients.keys.select{ |r| r != sender_phone && recipient_active?(r) }
  content = sender_name + ': ' + message['content']

  if phones.any? && recipient_active?(sender_phone)
    send_sms(phones, content[0,139])
  end
end


# Handle command line arguments
case
when ARGV.include?('reboot-modem')
  set_control 'REBOOT'
  exit
end


read_recipients
messages = read_inbox
puts_messages(messages, lines=10, banner=true); puts

begin
  loop do
    messages, new_messages = updates_messages(messages)

    new_messages.each do |message|
      @logger.info ('New message ' + log_message(message))
    
      case message['content'].downcase
      when /^#join/
        join_recipient(message)
      when /^#activate/
        activate_recipient(message)
      when /^\s*#leave/
        leave_recipient(message)
      when /^\s*#/
        # ignore unknown chat bot commands
      else
        bulk_message(message)
      end
      
      delete_sms(message)
    end

    sleep(fetch_interval)
  end
ensure
  @logger.fatal("Something went wrong. Rebooting LTE modem in 30 sec. and exit.")
  sleep 30
  set_control 'REBOOT'
end

