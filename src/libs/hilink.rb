require 'uri'
require 'net/http'
require 'nokogiri'

class HiLink
end

class HiLink::Request
  attr_writer :log_failure
  attr_writer :body
  
  def initialize(base_uri, logger, uri)
    @base_uri = base_uri
    @uri = set_uri(uri)
    @logger = logger
    @log_failure = ''
  end

  def error_codes(doc)
    codes = {
      -1     => "system not available",
      100002 => "not supported by firmware or incorrect API path",
      100003 => "unauthorized",
      100004 => "system busy",
      100005 => "unknown error",
      100006 => "invalid parameter",
      100009 => "write error",
      103002 => "unknown error",
      103015 => "unknown error",
      108001 => "invalid username",
      108002 => "invalid password",
      108003 => "user already logged in",
      108006 => "invalid username or password",
      108007 => "invalid username, password, or session timeout",
      110024 => "battery charge less than 50%",
      111019 => "no network response",
      111020 => "network timeout",
      111022 => "network not supported",
      113018 => "system busy",
      114001 => "file already exists",
      114002 => "file already exists",
      114003 => "SD card currently in use",
      114004 => "path does not exist",
      114005 => "path too long",
      114006 => "no permission for specified file or directory",
      115001 => "unknown error",
      117001 => "incorrect WiFi password",
      117004 => "incorrect WISPr password",
      120001 => "voice busy",
      125001 => "invalid token",
    }

    code = doc.xpath('//error/code').text.to_i
    err_message = doc.xpath('//error/message').text
    
    unless code == 0
      raise SystemCallError, "Error: #{codes[code] || code} [#{err_message}]"
    end
    
    doc
  end
  
  def set_uri(uri)
    @uri = URI(@base_uri + '/' + uri)
  end
  
  def body_xml
    @body.to_xml(:save_with => Nokogiri::XML::Node::SaveOptions::AS_XML)
  end
  
  def get_token
    uri = set_uri('webserver/SesTokInfo')
    params = {}
    uri.query = URI.encode_www_form(params)

    res = Net::HTTP.get_response(uri)
    if res.is_a?(Net::HTTPSuccess)
      doc = Nokogiri::XML(res.body)
      error_codes(doc)
      {
        'Cookie' => doc.at_xpath('//response/SesInfo').text,
        '__RequestVerificationToken' => doc.at_xpath('//response/TokInfo').text,
      }
    else
      raise SystemCallError, "Get session token failed"
    end
  end
  
  def post
    begin
      retries ||= 0
      http = Net::HTTP.start(@uri.host, @uri.port, :read_timeout => 20)
      res = http.post(@uri.path, body_xml, get_token)

      if res.is_a?(Net::HTTPSuccess)
        doc = Nokogiri::XML(res.body.gsub(/\n|\t/, ''))
        error_codes(doc)
      else
        raise SystemCallError, "HTTP POST #{@uri.path} failed with {res.class}"
      end
    rescue SystemCallError => e
      @logger.error @log_failure + " ErrMessage #{e.message}"
      sleep 2  # wait for processing previous requests
      retry if (retries += 1) < 2
    end
  end
end


def set_control(mode)
  control_modes = {
    'REBOOT'    => 1,
    'RESET'     => 2,  #Resets device into factory settings
  }

  req = HiLink::Request.new(@base_uri, @logger, 'device/control')
  req.log_failure = %Q(Failed to set control mode to #{mode}.)
  req.body = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
    xml.request {
      xml.Control_ control_modes[mode]
    }
  end
  res = req.post
  
  @logger.info %Q(Set control mode to #{mode})
end


def sms_count
  begin
    uri = URI("#{@base_uri}/sms/sms-count")
    params = get_token
    uri.query = URI.encode_www_form(params)

    res = Net::HTTP.get_response(uri)
    if res.is_a?(Net::HTTPSuccess)
      doc = Nokogiri::XML(res.body)
      error_codes(doc)
      doc
    else
      raise SystemCallError, "Get sms count failed"
    end
  rescue SystemCallError => e
    @logger.error %Q(Failed to get SMS count with ErrMessage #{e.message})
    sleep 4  # wait for processing previous requests
    retry if (retries += 1) < 2
  end
end


def fetch_sms
  req = HiLink::Request.new(@base_uri, @logger, 'sms/sms-list')
  req.log_failure = %Q(Failed to fetch SMS.)
  req.body = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
    xml.request {
      xml.PageIndex_ "1"
      xml.ReadCount_ "20"
      xml.BoxType_ "1"
      xml.SortType_ "0"
      xml.Ascending_ "0"
      xml.UnreadPreferred_ "1"
    }
  end
  res = req.post
  
  count = res.xpath('//response/Count').text.to_i
  messages = []
  for i in count.times do
    messages << {
      'date'    => res.xpath("//response/Messages/Message[#{i+1}]/Date").text,
      'phone'   => res.xpath("//response/Messages/Message[#{i+1}]/Phone").text,
      'index'   => res.xpath("//response/Messages/Message[#{i+1}]/Index").text,
      'content' => res.xpath("//response/Messages/Message[#{i+1}]/Content").text,
    }
    @logger.debug %Q(Received new message from #{messages.last['phone']} with content "#{messages.last['content']}")
  end
  messages
end


def send_sms(phones, content)
  phones.is_a?(String) && phones = [phones]
  
  req = HiLink::Request.new(@base_uri, @logger, 'sms/send-sms')
  req.log_failure = %Q(Failed to fetch SMS.)
  req.body = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
    xml.request {
      xml.Index_ "-1"
      xml.Phones {
        phones.each do |phone|
          xml.Phone_ phone
        end
      }
      xml.Sca_
      xml.Content_ content
      xml.Length_ content.length
      xml.Reserved_ "1"
      xml.Date_ Time.new.strftime("%Y-%m-%d %H:%M:%S")
    }
  end
  
  # double sending protection 
  messages = read_outbox
  new_message = {'date' => Time.new.strftime("%Y-%m-%d"), 'content' => content}
  unless messages.include?(new_message)  
    res = req.post 
    write_outbox(messages << new_message) # double sending protection
    @logger.debug %Q(Sent out "#{content[0,30]}" to #{phones.join(', ')})
    sleep 10  # LTE modem get's busy be sending SMS
  else
    @logger.warn %Q(Prevent double sending of "#{content[0,30]}" to #{phones.join(', ')})
  end
end

def dry_send_sms(phones, content)
  phones.is_a?(String) && phones = [phones]
  
  # double sending protection
  messages = read_outbox
  new_message = {'date' => Time.new.strftime("%Y-%m-%d"), 'content' => content}
  unless messages.include?(new_message)
  
    write_outbox(messages << new_message) # double sending protection
    @logger.debug %Q(DRY Sent out "#{content[0,30]}" to #{phones.join(', ')})
  else
    @logger.warn %Q(DRY Prevent double sending of "#{content[0,30]}" to #{phones.join(', ')})
  end
end


def delete_sms(message)
  req = HiLink::Request.new(@base_uri, @logger, 'sms/delete-sms')
  req.log_failure = %Q(Failed to delete "#{message['content'][0,20]}" from #{message['phone']}.)
  req.body = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
    xml.request {
      xml.Index_ message['index']
    }
  end
  res = req.post
  
  @logger.debug %Q(Deleted SMS "#{message['content'][0,20]}" from #{message['phone']}.)
end

