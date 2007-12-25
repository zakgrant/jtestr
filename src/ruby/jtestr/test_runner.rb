
module JtestR
  class TestRunner
    include TestUnitTestRunning
    include RSpecTestRunning
    include JUnitTestRunning
    
    def run(dirname = nil, log_level = JtestR::SimpleLogger::WARN, outp_level = JtestR::GenericResultHandler::QUIET, output = STDOUT)
      @logger = JtestR::SimpleLogger.new(output, log_level)
      @output_level = outp_level
      @output = output
      @dirname = dirname
      
      @result = true
      load_configuration
      setup_classpath
      find_tests

      load_helpers
      load_factories
      
      [["Unit", {:directory => /unit/}],
       ["Functional", {:directory => /functional/}],
       ["Integration", {:directory => /integration/}],
       ["Other", {:not_directory => /unit|functional|integration/}]
      ].each do |name, pattern|
        run_test_unit("#{name} tests", pattern)
        run_rspec("#{name} specs", pattern)
        run_junit("JUnit #{name} tests", name)
      end
      
      @result && (!@errors || @errors.empty?)
    rescue Exception => e
      log.err e.inspect
      e.backtrace.each do |bline|
        log.err bline
      end
      false
    end

    def report
      @errors && @errors.each do |errdesc, e|
        log.err "#{errdesc}" if errdesc
        log.err e.inspect
        e.backtrace.each do |bline|
          log.err bline
        end
      end
    end
    
    private
    def log
      @logger
    end
    
    def load_configuration
      log.debug { "loading configuration" }

      @test_directories = @dirname ? [@dirname.strip] : ["test","src/test"]
      
      @config_files = @test_directories.map {|dir| File.join(dir, "jtestr_config.rb") }.select {|file| File.exist?(file)}
      
      @configuration = Configuration.new
      @config_files.each do |file|
        @configuration.evaluate(File.read(file))
      end
    end

    def setup_classpath
      @paths ||= find_existing_common_paths

      @paths.each do |p|
        $CLASSPATH << File.expand_path(p)
      end
    end
    
    def find_existing_common_paths
      Dir["{build,target}/{classes,test_classes}"] + Dir['{lib,build_lib}/**/*.jar']
    end
    
    def find_tests
      log.debug { "finding tests" }

      lib_files = Dir["{#{@test_directories.map{ |td| "#{td}/lib"}.join(',')}}/**/*.rb"]
      work_files = (Dir["{#{@test_directories.join(',')}}/**/*.rb"] - lib_files) - @config_files

      lib_files.each do |lib_file|
        guard("Loading #{lib_file}") { load lib_file }
      end
      
      # here all places enumerated in configuration should be removed first
      
      @helpers, work_files = work_files.partition { |filename| filename =~ /_helper\.rb$/ }
      @factories, work_files = work_files.partition { |filename| filename =~ /_factory\.rb$/ }
      @specs, work_files = work_files.partition { |filename| filename =~ /_spec\.rb$/ }
      @test_units = work_files
    end

    def load_helpers
      log.debug { "loading helpers" }

      @helpers.each do |helper|
        guard("Loading #{helper}") { load helper }
      end
    end

    def load_factories
      log.debug { "loading factories" }

      @factories.each do |factory|
        guard("Loading #{factory}") { load factory }
      end
    end
    
    def choose_files(files, match_info)
      discriminator = match_info.has_key?(:directory) ? 
                        proc { |name| File.dirname(name) =~ match_info[:directory] } :
                          match_info.has_key?(:not_directory) ? 
                            proc { |name| File.dirname(name) !~ match_info[:not_directory] } :
                            proc { |name| true }
      files.select(&discriminator)
    end
    
    def guard(desc=nil)
      begin 
        yield
      rescue Exception => e
        add_error(desc, e)
      end
    end

    def add_error(description, exception)
      (@errors ||= []) << [description, exception]
    end
  end
end