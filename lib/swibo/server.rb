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

class ListenerList
  def initialize
    @listeners = Array.new
  end

  def send(msg)
    @listeners.each {|l| l << msg}
  end
  
  def add(obj)
    @listeners << obj
  end

  def <<(obj)
    add obj
  end

  def remove(obj)
    obj.finish
    cleanup
  end

  private
  def cleanup
    @listeners.reject! {|x| x.finished?}
  end
end

class Server
  def initialize
    @ping_list = Array.new
    @timer_started = false
    @current_env
    @listeners = ListenerList.new 
  end

  def call(env)
    @current_env = env
    case env['PATH_INFO']
    when %r(^/ping)
      start_timer
      body = ChunkedPingBody.new(5)

      EventMachine::next_tick do
        env['async.callback'].call [200, chunked_header("text/html"), body]
      end

      body.callback do
        STDERR.puts "callback: #{env['REMOTE_ADDR']}"
        debug_callback(body, env)
      end

      body.errback do
        STDERR.puts "errback: #{env['REMOTE_ADDR']}"
        debug_callback(body, env)
      end
    
      add_to_timer(body)
    when %r(^/listen)
      body = ChunkedBody.new

      EventMachine::next_tick do
        env['async.callback'].call [200, chunked_header("text/plain"), body]
      end

      body.callback do
        @listeners.remove body
      end

      body.errback do
        @listeners.remove body
      end
      
      @listeners << body
    when %r(^/send/(.*))
      msg = $1+"\n"
      body = "Message Sent: #{msg.inspect}\n"
      EventMachine::next_tick do
        @listeners.send msg
        env['async.callback'].call [200, default_header(body.length), body]
      end
    else
      EventMachine::next_tick do
        body = "Not found: #{env['PATH_INFO']}\n"
        env['async.callback'].call [404, default_header(body.size), body]
      end
    end
    return Swibo::AsyncResponse
  ensure
    @current_env = nil
  end

  private
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

  def add_to_timer(body)
    @ping_list << body
    STDERR.puts "client #{body.object_id} from #{@current_env['REMOTE_ADDR']} connected, ping list has #{@ping_list.length} clients"
  end

  def start_timer
    return if @timer_started
    STDERR.puts "starting timer"
    EventMachine::add_periodic_timer(1) do
      @ping_list = @ping_list.reject {|body| body.finished?}
      @ping_list.each do |body|
        body.send_chunk_or_succeed
      end
    end
    @timer_started = true
  end
end
end
