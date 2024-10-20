require 'uri'
require 'net/http'
require 'nokogiri'

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
    raise "Error: #{codes[code] || code} [#{err_message}]"
  end
end

def get_token
  uri = URI(@base_uri + '/webserver/SesTokInfo')
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
    raise "Get session token failed"
  end
end


def sms_count
  uri = URI("#{@base_uri}/sms/sms-count")
  params = get_token
  uri.query = URI.encode_www_form(params)

  res = Net::HTTP.get_response(uri)
  if res.is_a?(Net::HTTPSuccess)
    doc = Nokogiri::XML(res.body)
    error_codes(doc)
    doc
  else
    raise "Get sms count failed"
  end
end


def fetch_sms
  uri = URI("#{@base_uri}/sms/sms-list")

  body =  %Q(<?xml version = "1.0" encoding = "UTF-8"?>\n)
  body += %Q(<request><PageIndex>1</PageIndex><ReadCount>20</ReadCount><BoxType>1</BoxType><SortType>0</SortType><Ascending>0</Ascending><UnreadPreferred>1</UnreadPreferred></request>\n)
  
  body = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
    xml.request {
      xml.PageIndex_ "1"
      xml.ReadCount_ "20"
      xml.BoxType_ "1"
      xml.SortType_ "0"
      xml.Ascending_ "0"
      xml.UnreadPreferred_ "1"
    }
  end
  body = body.to_xml(:save_with => Nokogiri::XML::Node::SaveOptions::AS_XML)

  http = Net::HTTP.new(uri.host, uri.port)
  res = http.post(uri.path, body, get_token)

  if res.is_a?(Net::HTTPSuccess)
    doc = Nokogiri::XML(res.body.gsub(/\n|\t/, ''))
    error_codes(doc)
    count = doc.xpath('//response/Count').text.to_i
    messages = []
    for i in count.times do
      messages << {
        'date'    => doc.xpath("//response/Messages/Message[#{i+1}]/Date").text,
        'phone'   => doc.xpath("//response/Messages/Message[#{i+1}]/Phone").text,
        'index'   => doc.xpath("//response/Messages/Message[#{i+1}]/Index").text,
        'content' => doc.xpath("//response/Messages/Message[#{i+1}]/Content").text,
      }
    end
    messages
  else
    raise "Readind sms failed"
  end
end


def send_sms(phones, content)
  phones.is_a?(String) && phones = [phones]

  body = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
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
  body = body.to_xml(:save_with => Nokogiri::XML::Node::SaveOptions::AS_XML)
  
  # double sending protection 
  messages = read_outbox
  new_message = {'date' => Time.new.strftime("%Y-%m-%d"), 'content' => content}
  unless messages.include?(new_message)
  
    uri = URI("#{@base_uri}/sms/send-sms")
    http = Net::HTTP.new(uri.host, uri.port)
    res = http.post(uri.path, body, get_token)

    if res.is_a?(Net::HTTPSuccess)
      doc = Nokogiri::XML(res.body.gsub(/\n|\t/, ''))
      error_codes(doc)
    else
      raise "Sending sms failed"
    end
    write_outbox(messages << new_message) # double sending protection
  end
end

def dry_send_sms(phones, content)
  phones.is_a?(String) && phones = [phones]
  
  # double sending protection
  messages = read_outbox
  new_message = {'date' => Time.new.strftime("%Y-%m-%d"), 'content' => content}
  unless messages.include?(new_message)
  
    puts "Phones: #{phones.join(', ')}\n#{content}"
    write_outbox(messages << new_message) # double sending protection
  end
end


def delete_sms(messages)
  uri = URI("#{@base_uri}/sms/delete-sms")

  messages.each do |message|
    message_id = message['index']
    body =  %Q(<?xml version => "1.0" encoding="UTF-8"?><request><Index>#{message_id}</Index></request>\n)

    http = Net::HTTP.new(uri.host, uri.port)
    res = http.post(uri.path, body, get_token)

    if res.is_a?(Net::HTTPSuccess)
      doc = Nokogiri::XML(res.body.gsub(/\n|\t/, ''))
      error_codes(doc)
    else
      raise "Deleting sms #{message_id} failed"
    end
  end
end

