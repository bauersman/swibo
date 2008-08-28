require 'date'

module Swibo
  AsyncResponse = [-1, {}, []].freeze

class DeferrableBody
  include EventMachine::Deferrable

  def initialize
    @finished = false
  end

  def finished?
    @finished
  end

  def finish
    succeed
    @finished = true
  end

  def call(body)
    return unless @body_callback
    body.each do |chunk|
      @body_callback.call(chunk)
    end
  end

  def each(&blk)
    @body_callback = blk
  end
end

class ChunkedBody < DeferrableBody
  def send(msg)
    return if finished?
    call [chunk(msg)]
  end

  def <<(msg)
    send msg
  end

  def finish
    call [last_chunk]
    succeed
    super
  end

  protected
  def chunk(str)
    str.length.to_s(16)+"\r\n"+str+"\r\n"
  end

  def last_chunk
    "0\r\n\r\n"
  end
end

class ChunkedPingBody < ChunkedBody
  attr_reader :ping_max

  def initialize(ping_max)
    @ping_count = 0
    @ping_max = ping_max
    super()
  end

  def send_chunk_or_succeed
    call [chunk("Test #{@ping_count}\n")]
    if((@ping_count += 1) > ping_max)
      finish
    end
  end
end

class DocManager
  def initialize
    @doclist = Array.new
  end
end

class ListenerList
  def initialize
    @listeners = Array.new
  end

  def send(msg)
    @listeners.each {|l| l << msg}
  end
  
  def add(obj)
    @listeners << obj
    STDERR.puts "[Listener] adding listener, list has now #{@listeners.size} bodies"
  end

  def <<(obj)
    add obj
  end

  def remove(obj)
    obj.finish
    cleanup
    STDERR.puts "[Listener] removing listener, list has now #{@listeners.size} bodies"
  end

  private
  def cleanup
    @listeners.reject! {|x| x.finished?}
  end
end

class Server
  def initialize
    @listeners = ListenerList.new
    @approot = File.expand_path(File.dirname(__FILE__)+"/../..")
  end

  def call(env)
    @env = env
      case env['PATH_INFO']
      when %r(^/$)
        response = redirect_to("/index.html")
      when %r(^/doc/?$)
        response = doclist
      when %r(^/static/(.*))
        response = static(path)
      when %r(^/listen)
        response = listen
      when %r(^/send/?$)
        env["QUERY_STRING"] =~ /t=(.*)/
        response = send($1+"\n")
      else
        response = static(env["PATH_INFO"])
      end
    return response
  end

  private

  def redirect_to(path)
    header = {
      "Location" => path
    }
    [301, header, []]
  end

  def notfound(path)
    body = "Not found: #{path}\n"
    [404, default_header(body.size), [body]]
  end

  def static(path)
    static_dir = @approot+"/static"
    
    if(File::exists? static_dir+path)
      readfile(static_dir+path)
    else
      notfound(path)
    end
  end

  def readfile(path)
    stat = File::stat(path)
    header = {
      "Date" => Time.now.to_s,
      "Content-Type" => content_type_from_filename(path),
      "Last-Modified" => stat.mtime.to_s
    }

    mod_since = @env["HTTP_IF_MODIFIED_SINCE"]
    if false and mod_since and stat.mtime.to_datetime <= DateTime.parse(mod_since)
      result = [304, header, []]
    else
      header.merge!({
        "Content-Length" => stat.size.to_s
      })
      f = open(path, "r")
      result = [200, header, [f.read]]
      f.close
    end
    return result
  end

  def content_type_from_filename(fname)
    md = fname.match(/.+\.(.+)$/)
    return "application/octet-stream" unless md
    return case md
    when "html"
      "text/html"
    when "css"
      "text/css"
    when "js"
      "text/javascript"
    end
  end

  def listen
    body = ChunkedBody.new
    body.callback do
      STDERR.puts "callback"
      @listeners.remove body
    end
    body.errback do
      STDERR.puts "errback"
      @listeners.remove body
    end
    @listeners << body
    EventMachine::next_tick do
      @env['async.callback'].call [200, chunked_header("text/plain"), body]
    end
    return Swibo::AsyncResponse
  end

  def send(msg)
    @listeners.send msg
    body = "Message Sent: #{msg.inspect}\n"
    [200, default_header(body.length), body]
  end

  def chunked_header(ctype)
    {"Content-Type"=>ctype, "Transfer-Encoding"=>"chunked"}
  end

  def default_header(size)
    {"Content-Type" => "text/plain", "Content-Length" => size.to_s}
  end

  def debug_callback(body, env)
    return unless @debug
    STDERR.puts "--------------------------------------------------------" 
    STDERR.puts body.inspect
    STDERR.puts env.inspect
    STDERR.puts "--------------------------------------------------------" 
  end
end
end
