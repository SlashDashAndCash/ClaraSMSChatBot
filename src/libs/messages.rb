require 'json'

@inbox_file      = "#{@data_dir}/inbox.json"
@outbox_file     = "#{@data_dir}/outbox.json"
@recipients_file = "#{@data_dir}/recipients.json"


def drop_messages(messages)
  count = messages.size
  count > 100 && messages = messages.drop(count - 100)
  messages
end


def puts_messages(messages, lines=10, banner=false)
  puts '---------- Messages ----------' if banner
  messages.last(lines).each do |message|
    puts [message['date'], recipient_name(message['phone']), message['content'][0,70]].join('; ')
  end
end


def read_inbox
  if File.exist? @inbox_file
    messages = JSON.parse(File.read @inbox_file)
    return messages unless messages.empty?
  end
  []
end

def write_inbox(messages)
  File.write(@inbox_file, JSON.pretty_generate(messages))
end


def read_outbox
  if File.exist? @outbox_file
    messages = JSON.parse(File.read @outbox_file)
    return messages unless messages.empty?
  end
  []
end

def write_outbox(messages)
  messages = drop_messages(messages)
  File.write(@outbox_file, JSON.pretty_generate(messages))
end

