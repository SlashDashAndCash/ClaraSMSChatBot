
def recipient_name(recipient)
  if @recipients.has_key?(recipient)
    @recipients[recipient]['name']
  else
    recipient
  end
end

def recipient_active?(recipient)
  @recipients.has_key?(recipient) && @recipients[recipient]['role'] =~ /admin|user/
end

def recipient_admin?(recipient)
  recipient_active?(recipient) && @recipients[recipient]['role'] == 'admin'
end

def read_recipients
  if File.exist? @recipients_file
    @recipients = JSON.parse(File.read @recipients_file)
  end
  
  @recipients.is_a?(Hash) || @recipients = {}
end

def write_recipients
  File.write(@recipients_file, JSON.pretty_generate(@recipients))
end

