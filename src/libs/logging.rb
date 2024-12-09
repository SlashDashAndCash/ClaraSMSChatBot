require 'logger'

LOG_LEVELS = {
  "debug" => Logger::DEBUG,
  "info"  => Logger::INFO,
  "warn"  => Logger::WARN,
  "error" => Logger::ERROR,
  "fatal" => Logger::FATAL,
}

STDOUT.sync = true
STDERR.sync = true

@logger = Logger.new(STDOUT)
@logger.level = LOG_LEVELS[@log_level]

@logger.formatter = proc do |severity, datetime, _progname, msg|
  datefmt = datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')
  "[#{datefmt}] #{severity.ljust(5)}: #{msg}\n"
end

