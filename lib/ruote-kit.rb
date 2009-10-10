# Your starting point for daemon specific classes. This directory is
# already included in your load path, so no need to specify it.

module RuoteKit

  VERSION = "0.0.0"

  autoload :Configuration, "ruote-kit/configuration"
  autoload :Application,   "ruote-kit/application"

  class << self
    # The instance of ruote
    attr_accessor :engine

    # Instance of our sinatra app
    attr_accessor :sinatra

    # Instance of server handler
    attr_accessor :server

    # Instance of our server thread
    attr_accessor :server_thread

    # Configure and run the engine in a RESTful container
    def run!(&block)
      yield if block_given?

      configure_engine
      configure_sinatra
      running!
    end

    def shutdown!( purge_engine = false )
      shutdown_sinatra
      shutdown_engine( purge_engine )
    end

    def configuration
      unless @configuration
        @configuration = Configuration.new
        config = @configuration
        eval( IO.read( @configuration.user_file ), binding, @configuration.user_file ) if File.exist?( @configuration.user_file )
      end

      @configuration
    end

    def access_logger
      if configuration.access_log
        return DaemonKit::AbstractLogger.new( configuration.access_log )
      end
    end

    private

    def configure_engine
      DaemonKit.logger.debug "Configuring engine"

      engine_context = {
        :work_directory => configuration.work_directory
      }
      self.engine = configuration.engine_class.new( engine_context )

      self.engine.register_participant('.*', configuration.catchall_participant)
    end

    def shutdown_engine( purge = false )
      DaemonKit.logger.debug "Shutting down engine"

      self.engine.shutdown

      if purge
        self.engine.context.values.each do |s|
          s.purge if s.respond_to?(:purge)
        end
      end

      self.engine = nil
    end

    def configure_sinatra
      DaemonKit.logger.debug "Configuring Sinatra"

      self.sinatra = RuoteKit::Application

      return if %w(test cucumber).include? DaemonKit.env

      self.server_thread = Thread.new {
        configuration.rack_handler_class.run( self.sinatra, configuration.rack_options ) do |server|
          self.server = server
        end
      }
    end

    def running!
      DaemonKit.at_shutdown do
        RuoteKit.shutdown!
      end

      self.server_thread.join if self.server_thread
    end

    def shutdown_sinatra
      DaemonKit.logger.debug "Shutting down Sinatra"

      return if %w( test cucumber ).include? DaemonKit.env

      self.server.respond_to?(:stop!) ? self.server.stop! : self.server.stop
      self.server_thread.join
    end
  end
end