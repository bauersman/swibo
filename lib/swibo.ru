#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__))

require 'rubygems'
require 'rack'

require 'swibo/server'

use Rack::CommonLogger
use Rack::ShowExceptions
run Rack::Reloader.new(Swibo::Server.new)
